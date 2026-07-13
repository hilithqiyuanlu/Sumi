import 'package:flutter/foundation.dart';

import '../data/local_database.dart';
import '../data/snapshot_store_base.dart';
import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/secure_settings_store.dart';
import '../utils/utils.dart';

part 'sumi_store_persist.dart';
part 'sumi_store_todos.dart';
part 'sumi_store_projects.dart';

/// 全局状态管理器 —— 单一 ChangeNotifier，通过 SumiScope 注入。
/// 使用 mixin 拆分 persistence / todos / projects 逻辑。
class SumiStore extends ChangeNotifier
    with SumiStorePersist, SumiStoreTodos, SumiStoreProjects {
  final SumiSnapshotStore? _database;
  final SecureSettingsStore _secureSettings;
  AiService? _aiService;

  /// 暴露给 mixin 使用。
  AiService? get aiService => _aiService;

  // --- 核心 UI 状态 ---
  DateTime selectedDate = dateOnly(DateTime.now());
  bool monthViewExpanded = false;
  String? currentProjectId;

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

    return store;
  }

  // ---------------------------------------------------------------------------
  // AI
  // ---------------------------------------------------------------------------

  void _initAiService() {
    final key = appSettings.deepseekApiKey;
    if (key.isNotEmpty) {
      _aiService = AiService(apiKey: key);
    } else {
      _aiService = null;
    }
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
      // AI 调用失败 → 降级
      addUserTodo(text);
      return null;
    }

    if (!result.split) {
      // AI 判断无需拆分 → 直接创建
      addUserTodo(result.items.isNotEmpty ? result.items.first : text);
      return null;
    }

    // 需要拆分 → 返回给 UI 确认
    return result;
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
    afterMutation();
  }

  // ---------------------------------------------------------------------------
  // 核心方法
  // ---------------------------------------------------------------------------

  void selectDate(DateTime date) {
    selectedDate = dateOnly(date);
    afterMutation();
  }

  void toggleMonthView() {
    monthViewExpanded = !monthViewExpanded;
    afterMutation();
  }

  void setMonthViewExpanded(bool expanded) {
    monthViewExpanded = expanded;
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
}
