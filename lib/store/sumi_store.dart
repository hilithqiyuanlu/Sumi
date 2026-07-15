import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/chat_database.dart';
import '../data/local_database.dart';
import '../data/signal_database.dart';
import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/ai_runtime.dart';
import '../services/chat_prompt_builder.dart';
import '../services/daily_planning_policy.dart';
import '../services/project_generation.dart';
import '../services/secure_settings_store.dart';
import '../services/signal_service.dart';
import '../services/snapshot_write_queue.dart';
import '../services/tool_executor.dart';
import '../services/user_model_service.dart';
import '../services/voice_input_service.dart';
import '../utils/utils.dart';
part 'domain_controllers.dart';
part 'sumi_store_persist.dart';
part 'sumi_store_todos.dart';
part 'sumi_store_projects.dart';
part 'sumi_store_chat.dart';

/// 应用协调器。可变状态由分域控制器持有，AppStore 本身不广播 UI 更新。
class AppStore
    with SumiStorePersist, SumiStoreTodos, SumiStoreProjects, SumiStoreChat {
  @override
  final SumiLocalDatabase? _database;
  final SecureSettingsStore _secureSettings;
  AiRuntime? _aiRuntime;
  ChatDatabase? _chatDatabase;
  ToolExecutor? _toolExecutor;
  VoiceInputService? _voiceService;
  final DateTime Function() _now;
  late final SnapshotWriteQueue _snapshotWrites;
  bool _closed = false;

  // 07 轮新增
  SignalDatabase? _signalDb;
  UserModelService? _userModelService;
  SignalService? _signalService;

  /// 信号数据库（供 mixin 使用）。
  @override
  SignalDatabase? get signalDb => _signalDb;

  /// 用户模型服务。
  @override
  UserModelService? get userModelService => _userModelService;

  /// 信号发射服务（供 mixin 使用）。
  @override
  SignalService? get signalService => _signalService;

  // 07 轮：建议缓存状态
  List<String> cachedSuggestions = [];
  bool _suggestionsDirty = true;
  bool get suggestionsDirty => _suggestionsDirty;
  DateTime? lastForegroundTime;
  DateTime? lastSuggestionTime;

  // 07 轮：周度反思状态
  @override
  DateTime? lastWeeklyReflection;

  /// todo 标题最大字数，超过触发 AI 凝练。
  static const todoTitleMaxLength = 16;

  /// 按职责暴露 AI Runtime 服务。
  AiRuntime? get aiRuntime => _aiRuntime;
  @override
  StructuredAiService? get structuredAi => _aiRuntime?.structured;
  @override
  ChatAgentService? get chatAgent => _aiRuntime?.chat;

  /// 对话数据库。
  @override
  ChatDatabase? get chatDatabase => _chatDatabase;

  /// 工具执行器（仅 sumi_store_chat 的 agent loop 使用）。
  @override
  ToolExecutor? get toolExecutor => _toolExecutor;

  /// 语音输入服务。
  VoiceInputService? get voiceService => _voiceService;

  /// Thinking 模式开关。
  @override
  bool get thinkingEnabled => appSettings.thinkingEnabled;

  final TodoController todoController = TodoController();
  final ProjectController projectController = ProjectController();
  final SettingsController settingsController = SettingsController();
  @override
  final ChatController chatController = ChatController();
  final SelectionController selection = SelectionController();

  @override
  DateTime get selectedDate => todoController._selectedDate;
  @override
  set selectedDate(DateTime value) => todoController._selectedDate = value;
  @override
  String? get currentProjectId => projectController._currentProjectId;
  @override
  set currentProjectId(String? value) =>
      projectController._currentProjectId = value;
  // --- 导航信号（不持久化） ---
  int get navigateToTodaySignal => selection.navigateToTodaySequence;

  @override
  void triggerNavigateToToday() {
    selection.navigateToTodaySequence++;
    selection.markChanged();
  }

  // --- 数据变更版本号（不持久化，触发建议刷新等副作用） ---
  int dataVersion = 0;

  // --- 数据列表（mixin 需要访问，不可私有） ---
  @override
  List<TodoItem> get todoItems => todoController._items;
  @override
  List<Project> get projectList => projectController._projects;
  @override
  List<MonthCard> get monthCardList => projectController._monthCards;

  // --- 设置 ---
  @override
  AppSettings get appSettings => settingsController._value;
  @override
  set appSettings(AppSettings value) => settingsController._value = value;

  AppStore._({
    required this._database,
    required this._secureSettings,
    required this._now,
  });

  void dispose() {
    unawaited(close());
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await flushPersistence();
    disposeChatView();
    _voiceService?.dispose();
    _aiRuntime?.close();
    todoController.dispose();
    projectController.dispose();
    settingsController.dispose();
    chatController.dispose();
    selection.dispose();
    await _database?.close();
  }

  /// 工厂：创建并加载持久化数据。
  static Future<AppStore> create({
    SumiLocalDatabase? database,
    SecureSettingsStore? secureSettings,
    AiTransport? aiServiceOverride,
    UserModelService? userModelServiceOverride,
    SignalDatabase? signalDatabaseOverride,
    DateTime Function()? now,
  }) async {
    final db = database ?? createSnapshotStore();
    final ss = secureSettings ?? SecureSettingsStore();
    final store = AppStore._(
      database: db,
      secureSettings: ss,
      now: now ?? DateTime.now,
    );
    store._snapshotWrites = SnapshotWriteQueue(db.writeSnapshot);

    // 初始化对话数据库
    store._chatDatabase = ChatDatabase(db);

    // 07 轮：初始化信号数据库和用户模型服务
    store._signalDb = signalDatabaseOverride ?? SignalDatabase(db);
    store._userModelService =
        userModelServiceOverride ?? UserModelService(store._signalDb!);
    store._signalService = SignalService(
      store._signalDb!,
      projectForId: (projectId) {
        for (final project in store.projectList) {
          if (project.id == projectId) return project;
        }
        return null;
      },
    );

    // 07 轮：迁移旧 MEMORY.md → USER_MODEL.md
    await store._migrateLegacyMemory();

    // 从安全存储读取 API Key（并行读取，减少启动延迟）
    final keyResults = await Future.wait([
      ss.readDeepseekApiKey(),
      ss.readTavilyApiKey(),
    ]);
    final deepseekKey = keyResults[0];
    final tavilyKey = keyResults[1];

    // 从快照恢复数据
    await store.loadFromDb();

    // 回填安全存储中的 API Key（快照中不存明文）
    store.appSettings = store.appSettings.copyWith(
      deepseekApiKey: deepseekKey,
      tavilyApiKey: tavilyKey,
    );

    store._initAiService(override: aiServiceOverride);

    // 加载今天的会话
    await store._getOrCreateConversationForDate(dateKey(store.selectedDate));

    // 检测并生成每日 todo —— 不阻塞启动，后台静默执行
    store.checkAndGenerateDaily();

    return store;
  }

  // ---------------------------------------------------------------------------
  // AI
  // ---------------------------------------------------------------------------

  void _initAiService({AiTransport? override}) {
    final previousRuntime = _aiRuntime;
    final key = appSettings.deepseekApiKey;
    if (override != null || key.isNotEmpty) {
      _aiRuntime = override != null
          ? AiRuntime.fromClient(override)
          : AiRuntime(
              apiKey: key,
              tavilyApiKey: appSettings.tavilyApiKey,
            );
      _toolExecutor = ToolExecutor(
        searchService: _aiRuntime!.search,
        userModelService: _userModelService!,
        signalDatabase: _signalDb!,
        readTodos: ({String? filter}) => _readTodosForTool(filter: filter),
        writeTodo:
            ({
              required String title,
              String? date,
              String? projectId,
              String? body,
            }) => _writeTodoForTool(
              title: title,
              date: date,
              projectId: projectId,
              body: body,
            ),
      );
    } else {
      _aiRuntime = null;
      _toolExecutor = null;
    }

    if (previousRuntime != null && !identical(previousRuntime, _aiRuntime)) {
      previousRuntime.close();
    }

    // 语音输入服务（不依赖 API key）
    _voiceService ??= VoiceInputService();
  }

  /// AI todo 拆分入口。
  /// 返回 null 表示已降级直接创建（调用方无需再处理）。
  /// 返回 SplitResult(split: false) 表示 AI 判断无需拆分，已直接创建。
  /// 返回 SplitResult(split: true) 表示需要拆分确认。
  Future<SplitResult?> splitAndAddTodo(String text) async {
    final ai = structuredAi;
    if (ai == null) {
      addUserTodo(text);
      return null;
    }

    final result = await ai.splitTodo(text);
    if (result == null) {
      // AI 调用失败 → 若超长尝试凝练，否则直接创建
      if (text.length > todoTitleMaxLength) {
        final condensed = await polishText(text);
        addUserTodo(condensed ?? text, condensedFrom: text);
      } else {
        addUserTodo(text);
      }
      return null;
    }

    if (!result.split) {
      // AI 判断无需拆分 → 用 AI 凝练结果或直接创建
      final single = result.items.isNotEmpty ? result.items.first : text;
      if (single.length > todoTitleMaxLength) {
        final condensed = await polishText(single);
        addUserTodo(condensed ?? single, condensedFrom: text);
      } else {
        addUserTodo(single, condensedFrom: text);
      }
      return null;
    }

    // 需要拆分 → 确保每项不超长
    final polishedItems = <String>[];
    for (final item in result.items) {
      if (item.length > todoTitleMaxLength) {
        final condensed = await polishText(item);
        polishedItems.add(condensed ?? item);
      } else {
        polishedItems.add(item);
      }
    }

    return SplitResult(split: true, items: polishedItems);
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  Future<void> updateDeepseekApiKey(String key) async {
    await _secureSettings.writeDeepseekApiKey(key);
    appSettings = appSettings.copyWith(deepseekApiKey: key);
    _initAiService();
    afterSettingsMutation();
  }

  Future<void> updateTavilyApiKey(String key) async {
    await _secureSettings.writeTavilyApiKey(key);
    appSettings = appSettings.copyWith(tavilyApiKey: key);
    _initAiService(); // 重新创建 AiService（携带新的 tavily key）
    afterSettingsMutation();
  }

  /// 切换 thinking 模式。
  void setThinkingEnabled(bool v) {
    appSettings = appSettings.copyWith(thinkingEnabled: v);
    afterSettingsMutation();
  }

  /// 切换开发者开关：披露全部月卡。
  void setShowAllMonthCards(bool v) {
    appSettings = appSettings.copyWith(showAllMonthCards: v);
    afterSettingsMutation();
  }

  /// 更新用户昵称。
  void updateUserName(String name) {
    appSettings = appSettings.copyWith(userName: name.trim());
    afterSettingsMutation();
  }

  // ---------------------------------------------------------------------------
  // 核心方法
  // ---------------------------------------------------------------------------

  Future<void> selectDate(DateTime date) async {
    selectedDate = dateOnly(date);
    afterSelectionMutation();
    // 切换到该日期的会话
    await _getOrCreateConversationForDate(dateKey(selectedDate));
  }

  // ---------------------------------------------------------------------------
  // 内部
  // ---------------------------------------------------------------------------

  void _persist() {
    dataVersion++;
    _snapshotWrites.schedule(snapshotMap());
  }

  @override
  Future<void> persistSnapshotNow(Map<String, Object?> snapshot) =>
      _snapshotWrites.write(snapshot);

  Future<void> flushPersistence() => _snapshotWrites.flush();

  @override
  void afterTodoMutation() {
    _persist();
    todoController.markChanged();
  }

  @override
  void afterProjectMutation() {
    _persist();
    projectController.markChanged();
    todoController.markChanged();
  }

  void afterSettingsMutation() {
    _persist();
    settingsController.markChanged();
  }

  void afterSelectionMutation() {
    _persist();
    todoController.markChanged();
    selection.markChanged();
  }

  @override
  void notifyAllDomains() {
    todoController.markChanged();
    projectController.markChanged();
    settingsController.markChanged();
    selection.markChanged();
  }

  // ---------------------------------------------------------------------------
  // USER_MODEL.md（07 轮：替代旧 MEMORY.md）
  // ---------------------------------------------------------------------------

  /// 迁移旧 MEMORY.md → USER_MODEL.md（仅运行一次）。
  Future<void> _migrateLegacyMemory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final legacyFile = io.File('${dir.path}/sumi/MEMORY.md');
      final newFile = io.File('${dir.path}/sumi/USER_MODEL.md');

      // 如果 USER_MODEL.md 已存在，跳过
      if (await newFile.exists()) return;

      if (await legacyFile.exists()) {
        final legacyContent = await legacyFile.readAsString();
        final migrated = await _userModelService!.migrateFromLegacyMemory(
          legacyContent,
        );
        await _userModelService!.writeUserModel(migrated);
        // 不删除旧文件，保留备份
      }
    } catch (_) {
      // 静默失败
    }
  }

  /// 周期性检查并触发周度反思（由 HomePage 在回前台时调用）。
  Future<void> checkAndRunWeeklyReflection() async {
    final ai = structuredAi;
    if (ai == null) return;

    final now = _now();
    final isSunday = now.weekday == DateTime.sunday;
    final isMondayMorning = now.weekday == DateTime.monday && now.hour < 12;
    if (!isSunday && !isMondayMorning) return;

    if (lastWeeklyReflection != null) {
      final daysSince = now.difference(lastWeeklyReflection!).inDays;
      if (daysSince < 6) return;
    }

    try {
      final model = await _userModelService!.readUserModel();
      final stats = await _userModelService!.computeRealtimeStats();
      final modelWithStats = _userModelService!.injectRealtimeStats(
        model,
        stats,
      );
      final hotPrompt = _userModelService!.buildHotPrompt(modelWithStats);
      final warmPrefs = _userModelService!.buildWarmPrefsPrompt(modelWithStats);
      final weekSignals = await _signalDb!.query(range: '7d', limit: 200);
      final signalsText = SignalDatabase.formatForPrompt(weekSignals);

      final result = await ai.generateWeeklyReflection(
        hotPrompt: hotPrompt,
        warmPrefs: warmPrefs,
        weeklySignals: signalsText,
      );
      if (result == null) {
        throw Exception('AI 返回空结果');
      }

      // 校验 AI 返回的模型结构，防止截断或格式错误覆盖掉完整模型。
      if (!_userModelService!.isValidUserModel(result.updatedUserModel)) {
        throw Exception('AI 返回的 USER_MODEL.md 缺少必要区段，拒绝覆盖');
      }

      // 覆盖前先备份，保留恢复可能。
      await _userModelService!.backupUserModel();
      await _userModelService!.writeUserModel(result.updatedUserModel);

      // 只有成功写入后才记录本次反思时间，失败时下次仍可重试。
      lastWeeklyReflection = now;
      _persist();
    } catch (e) {
      debugPrint('Weekly reflection failed (non-blocking): $e');
    }
  }

  /// 设置建议脏标记。true = 下次回前台时刷新，false = 已是最新。
  void setSuggestionsDirty(bool v) {
    _suggestionsDirty = v;
  }

  // ---------------------------------------------------------------------------
  // Tool helpers（供 ToolExecutor 使用）
  // ---------------------------------------------------------------------------

  /// 供工具调用的 todo 查询，返回格式化文本。
  String _readTodosForTool({String? filter}) {
    List<TodoItem> source;
    if (filter == 'today') {
      final today = dateKey(DateTime.now());
      source = todoItems
          .where((t) => t.date == today || t.date == null)
          .toList();
    } else if (filter != null && filter.startsWith('project:')) {
      final pid = filter.substring(8);
      source = todoItems.where((t) => t.projectId == pid).toList();
    } else {
      source = List.of(todoItems);
    }

    if (source.isEmpty) return '暂无待办事项。';

    final buf = StringBuffer();
    for (final t in source.take(20)) {
      final status = t.done ? '[✓]' : '[ ]';
      buf.writeln('$status ${t.title}');
      if (t.date != null) buf.writeln('   日期：${t.date}');
      if (t.body != null && t.body!.isNotEmpty) {
        buf.writeln('   备注：${t.body}');
      }
    }
    if (source.length > 20) {
      buf.writeln('... 还有 ${source.length - 20} 条事项');
    }
    return buf.toString();
  }

  /// 供工具调用的 todo 创建。
  Future<void> _writeTodoForTool({
    required String title,
    String? date,
    String? projectId,
    String? body,
  }) {
    if (projectId == null || projectId.isEmpty) {
      return addUserTodo(title, date: date, body: body);
    }
    return addSystemTodo(title, projectId, date: date, body: body);
  }
}

typedef SumiStore = AppStore;
