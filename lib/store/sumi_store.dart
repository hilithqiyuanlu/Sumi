import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/chat_database.dart';
import '../data/local_database.dart';
import '../data/signal_database.dart';
import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/secure_settings_store.dart';
import '../services/signal_service.dart';
import '../services/tool_executor.dart';
import '../services/user_model_service.dart';
import '../services/voice_input_service.dart';
import '../utils/utils.dart';

part 'sumi_store_persist.dart';
part 'sumi_store_todos.dart';
part 'sumi_store_projects.dart';
part 'sumi_store_chat.dart';

/// 全局状态管理器 —— 单一 ChangeNotifier，通过 SumiScope 注入。
/// 使用 mixin 拆分 persistence / todos / projects / chat 逻辑。
class SumiStore extends ChangeNotifier
    with SumiStorePersist, SumiStoreTodos, SumiStoreProjects, SumiStoreChat {
  final SumiLocalDatabase? _database;
  final SecureSettingsStore _secureSettings;
  AiService? _aiService;
  ChatDatabase? _chatDatabase;
  ToolExecutor? _toolExecutor;
  VoiceInputService? _voiceService;

  // 07 轮新增
  SignalDatabase? _signalDb;
  UserModelService? _userModelService;
  SignalService? _signalService;

  /// 信号数据库（供 mixin 使用）。
  SignalDatabase? get signalDb => _signalDb;
  /// 用户模型服务。
  UserModelService? get userModelService => _userModelService;
  /// 信号发射服务（供 mixin 使用）。
  SignalService? get signalService => _signalService;

  // 07 轮：建议缓存状态
  List<String> cachedSuggestions = [];
  bool _suggestionsDirty = true;
  bool get suggestionsDirty => _suggestionsDirty;
  DateTime? lastForegroundTime;
  DateTime? lastSuggestionTime;

  // 07 轮：周度反思状态
  DateTime? lastWeeklyReflection;

  /// todo 标题最大字数，超过触发 AI 凝练。
  static const todoTitleMaxLength = 16;

  /// 暴露给 mixin 使用。
  AiService? get aiService => _aiService;

  /// 对话数据库。
  ChatDatabase? get chatDatabase => _chatDatabase;

  /// 工具执行器（仅 sumi_store_chat 的 agent loop 使用）。
  ToolExecutor? get toolExecutor => _toolExecutor;

  /// 语音输入服务。
  VoiceInputService? get voiceService => _voiceService;

  /// Thinking 模式开关。
  bool get thinkingEnabled => appSettings.thinkingEnabled;

  // --- 核心 UI 状态 ---
  DateTime selectedDate = dateOnly(DateTime.now());
  String? currentProjectId;

  // --- 导航信号（不持久化） ---
  int _navigateToTodaySignal = 0;
  int get navigateToTodaySignal => _navigateToTodaySignal;

  void triggerNavigateToToday() {
    _navigateToTodaySignal++;
    notifyListeners();
  }

  // --- 消息发送信号（不持久化） ---
  int _messageSentSignal = 0;
  int get messageSentSignal => _messageSentSignal;

  void notifyMessageSent() {
    _messageSentSignal++;
    notifyListeners();
  }

  // --- 数据变更版本号（不持久化，触发建议刷新等副作用） ---
  int dataVersion = 0;

  // --- 数据列表（mixin 需要访问，不可私有） ---
  final List<TodoItem> todoItems = [];
  final List<Project> projectList = [];
  final List<MonthCard> monthCardList = [];

  // --- 设置 ---
  AppSettings appSettings = const AppSettings();

  SumiStore._({
    required SumiLocalDatabase? database,
    required SecureSettingsStore secureSettings,
  })  : _database = database,
        _secureSettings = secureSettings;

  /// 工厂：创建并加载持久化数据。
  static Future<SumiStore> create({
    SumiLocalDatabase? database,
    SecureSettingsStore? secureSettings,
  }) async {
    final db = database ?? createSnapshotStore();
    final ss = secureSettings ?? SecureSettingsStore();
    final store = SumiStore._(database: db, secureSettings: ss);

    // 初始化对话数据库
    store._chatDatabase = ChatDatabase(db);

    // 07 轮：初始化信号数据库和用户模型服务
    store._signalDb = SignalDatabase(db);
    store._userModelService = UserModelService(store._signalDb!);
    store._signalService = SignalService(store._signalDb!);

    // 07 轮：迁移旧 MEMORY.md → USER_MODEL.md
    await store._migrateLegacyMemory();

    // 从安全存储读取 API Key（并行读取，减少启动延迟）
    final keyResults = await Future.wait([
      ss.readDeepseekApiKey(),
      ss.readTavilyApiKey(),
    ]);
    final deepseekKey = keyResults[0] as String;
    final tavilyKey = keyResults[1] as String;

    // 从快照恢复数据
    await store.loadFromDb();

    // 回填安全存储中的 API Key（快照中不存明文）
    store.appSettings = store.appSettings.copyWith(
      deepseekApiKey: deepseekKey,
      tavilyApiKey: tavilyKey,
    );

    store._initAiService();

    // 加载今天的会话
    await store._getOrCreateConversationForDate(dateKey(store.selectedDate));

    // 检测并生成每日 todo —— 不阻塞启动，后台静默执行
    store.checkAndGenerateDaily();

    return store;
  }

  // ---------------------------------------------------------------------------
  // AI
  // ---------------------------------------------------------------------------

  void _initAiService() {
    final key = appSettings.deepseekApiKey;
    if (key.isNotEmpty) {
      _aiService = AiService(
        apiKey: key,
        tavilyApiKey: appSettings.tavilyApiKey,
      );
      _toolExecutor = ToolExecutor(
        aiService: _aiService,
        userModelService: _userModelService!,
        signalDatabase: _signalDb!,
        readTodos: ({String? filter}) => _readTodosForTool(filter: filter),
        writeTodo: ({
          required String title,
          String? date,
          String? projectId,
          String? body,
        }) =>
            _writeTodoForTool(
          title: title,
          date: date,
          projectId: projectId,
          body: body,
        ),
      );
    } else {
      _aiService = null;
      _toolExecutor = null;
    }

    // 语音输入服务（不依赖 API key）
    _voiceService ??= VoiceInputService();
  }

  /// AI todo 拆分入口。
  /// 返回 null 表示已降级直接创建（调用方无需再处理）。
  /// 返回 SplitResult(split: false) 表示 AI 判断无需拆分，已直接创建。
  /// 返回 SplitResult(split: true) 表示需要拆分确认。
  Future<SplitResult?> splitAndAddTodo(String text) async {
    if (_aiService == null) {
      addUserTodo(text);
      return null;
    }

    final result = await _aiService!.splitTodo(text);
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
    afterMutation();
  }

  Future<void> updateTavilyApiKey(String key) async {
    await _secureSettings.writeTavilyApiKey(key);
    appSettings = appSettings.copyWith(tavilyApiKey: key);
    _initAiService(); // 重新创建 AiService（携带新的 tavily key）
    afterMutation();
  }

  /// 切换 thinking 模式。
  void setThinkingEnabled(bool v) {
    appSettings = appSettings.copyWith(thinkingEnabled: v);
    afterMutation();
  }

  /// 切换开发者开关：披露全部月卡。
  void setShowAllMonthCards(bool v) {
    appSettings = appSettings.copyWith(showAllMonthCards: v);
    afterMutation();
  }

  /// 更新用户昵称。
  void updateUserName(String name) {
    appSettings = appSettings.copyWith(userName: name.trim());
    afterMutation();
  }

  // ---------------------------------------------------------------------------
  // 核心方法
  // ---------------------------------------------------------------------------

  Future<void> selectDate(DateTime date) async {
    selectedDate = dateOnly(date);
    afterMutation();
    // 切换到该日期的会话
    await _getOrCreateConversationForDate(dateKey(selectedDate));
  }

  // ---------------------------------------------------------------------------
  // 内部
  // ---------------------------------------------------------------------------

  /// mutation 后自动持久化并通知 UI。
  void afterMutation() {
    dataVersion++;
    writeToDb();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // USER_MODEL.md（07 轮：替代旧 MEMORY.md）
  // ---------------------------------------------------------------------------

  /// 读取 USER_MODEL.md 的完整内容（注入实时统计后）。
  Future<String> readMemory() async {
    if (_userModelService == null) return '';
    final content = await _userModelService!.readUserModel();
    final stats = await _userModelService!.computeRealtimeStats();
    stats['userName'] = appSettings.userName.isNotEmpty ? appSettings.userName : '未设置';
    return _userModelService!.injectRealtimeStats(content, stats);
  }

  /// 追加内容到 USER_MODEL.md 核心记忆区。
  Future<void> appendMemory(String content) async {
    if (_userModelService == null) return;
    await _userModelService!.appendToSection('coreMemory', content);
  }

  /// 覆写整个 USER_MODEL.md（用于编辑器保存）。
  Future<void> writeMemory(String content) async {
    if (_userModelService == null) return;
    await _userModelService!.writeUserModel(content);
  }

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
        final migrated = await _userModelService!.migrateFromLegacyMemory(legacyContent);
        await _userModelService!.writeUserModel(migrated);
        // 不删除旧文件，保留备份
      }
    } catch (_) {
      // 静默失败
    }
  }

  /// 周期性检查并触发周度反思（由 HomePage 在回前台时调用）。
  Future<void> checkAndRunWeeklyReflection() async {
    final ai = _aiService;
    if (ai == null) return;

    final now = DateTime.now();
    final isSunday = now.weekday == DateTime.sunday;
    final isMondayMorning = now.weekday == DateTime.monday && now.hour < 12;
    if (!isSunday && !isMondayMorning) return;

    if (lastWeeklyReflection != null) {
      final daysSince = now.difference(lastWeeklyReflection!).inDays;
      if (daysSince < 6) return;
    }

    lastWeeklyReflection = now;
    afterMutation(); // 持久化

    try {
      final model = await _userModelService!.readUserModel();
      final weekSignals = await _signalDb!.query(range: '7d', limit: 200);
      final signalsText = SignalDatabase.formatForPrompt(weekSignals);

      final result = await ai.generateWeeklyReflection(
        userModel: model,
        weeklySignals: signalsText,
      );
      if (result != null) {
        await _userModelService!.writeUserModel(result.updatedUserModel);
      }
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
    addSystemTodo(
      title,
      projectId ?? '',
      date: date,
      body: body,
    );
    return Future.value();
  }
}
