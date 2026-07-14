import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/chat_database.dart';
import '../data/local_database.dart';
import '../data/snapshot_store_base.dart';
import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/secure_settings_store.dart';
import '../services/tool_executor.dart';
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
  final SumiSnapshotStore? _database;
  final SecureSettingsStore _secureSettings;
  AiService? _aiService;
  ChatDatabase? _chatDatabase;
  ToolExecutor? _toolExecutor;
  VoiceInputService? _voiceService;

  /// 暴露给 mixin 使用。
  AiService? get aiService => _aiService;

  /// 对话数据库。
  ChatDatabase? get chatDatabase => _chatDatabase;

  /// 工具执行器（仅 sumi_store_chat 的 agent loop 使用）。
  ToolExecutor? get toolExecutor => _toolExecutor;

  /// 语音输入服务。
  VoiceInputService? get voiceService => _voiceService;

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

  // --- 数据列表（mixin 需要访问，不可私有） ---
  final List<TodoItem> todoItems = [];
  final List<Project> projectList = [];
  final List<MonthCard> monthCardList = [];

  // --- 设置 ---
  AppSettings appSettings = const AppSettings();

  SumiStore._({
    required SumiSnapshotStore? database,
    required SecureSettingsStore secureSettings,
  })  : _database = database,
        _secureSettings = secureSettings;

  /// 工厂：创建并加载持久化数据。
  static Future<SumiStore> create({
    SumiSnapshotStore? database,
    SecureSettingsStore? secureSettings,
  }) async {
    final db = database ?? createSnapshotStore();
    final ss = secureSettings ?? SecureSettingsStore();
    final store = SumiStore._(database: db, secureSettings: ss);

    // 初始化对话数据库
    if (db is SumiLocalDatabase) {
      store._chatDatabase = ChatDatabase(db);
    }

    // 从安全存储读取 API Key
    final deepseekKey = await ss.readDeepseekApiKey();
    final tavilyKey = await ss.readTavilyApiKey();

    // 从快照恢复数据
    await store.loadFromDb();

    // 回填安全存储中的 API Key（快照中不存明文）
    store.appSettings = store.appSettings.copyWith(
      deepseekApiKey: deepseekKey,
      tavilyApiKey: tavilyKey,
    );

    store._initAiService();

    // 加载对话列表
    await store.loadConversations();

    // 检测并生成每日 todo
    await store.checkAndGenerateDaily();

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
        readMemory: () => readMemory(),
        appendMemory: (c) => appendMemory(c),
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
      // AI 调用失败 → 若 >18 字尝试凝练，否则直接创建
      if (text.length > 18) {
        final condensed = await polishText(text);
        addUserTodo(condensed ?? text);
      } else {
        addUserTodo(text);
      }
      return null;
    }

    if (!result.split) {
      // AI 判断无需拆分 → 用 AI 凝练结果或直接创建
      final single = result.items.isNotEmpty ? result.items.first : text;
      if (single.length > 18) {
        final condensed = await polishText(single);
        addUserTodo(condensed ?? single);
      } else {
        addUserTodo(single);
      }
      return null;
    }

    // 需要拆分 → 确保每项 ≤18 字
    final polishedItems = <String>[];
    for (final item in result.items) {
      if (item.length > 18) {
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

  // ---------------------------------------------------------------------------
  // 核心方法
  // ---------------------------------------------------------------------------

  void selectDate(DateTime date) {
    selectedDate = dateOnly(date);
    afterMutation();
  }

  // ---------------------------------------------------------------------------
  // 内部
  // ---------------------------------------------------------------------------

  /// mutation 后自动持久化并通知 UI。
  void afterMutation() {
    writeToDb();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // MEMORY.md
  // ---------------------------------------------------------------------------

  /// 读取 MEMORY.md 的完整内容。
  Future<String> readMemory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = io.File('${dir.path}/sumi/MEMORY.md');
      if (!await file.exists()) {
        return '';
      }
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  /// 追加内容到 MEMORY.md。
  Future<void> appendMemory(String content) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final sumiDir = io.Directory('${dir.path}/sumi');
      if (!await sumiDir.exists()) {
        await sumiDir.create(recursive: true);
      }
      final file = io.File('${sumiDir.path}/MEMORY.md');
      final timestamp = DateTime.now().toIso8601String().substring(0, 16);
      final entry = '\n### 记忆 $timestamp\n$content\n';
      if (await file.exists()) {
        await file.writeAsString(entry, mode: io.FileMode.append);
      } else {
        await file.writeAsString('# Sumi MEMORY.md\n$entry');
      }
    } catch (_) {
      // 静默失败
    }
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
