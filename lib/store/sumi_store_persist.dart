part of 'sumi_store.dart';

// ---------------------------------------------------------------------------
// Persistence mixin
// ---------------------------------------------------------------------------

mixin SumiStorePersist {
  // 声明由 SumiStore 提供的字段（mixin 约束）
  SumiLocalDatabase? get _database;
  List<TodoItem> get todoItems;
  List<Project> get projectList;
  List<MonthCard> get monthCardList;
  DateTime get selectedDate;
  set selectedDate(DateTime v);
  String? get currentProjectId;
  set currentProjectId(String? v);
  AppSettings get appSettings;
  set appSettings(AppSettings v);
  Future<void> clearChatData(); // 由 SumiStoreChat mixin 提供
  // 07 轮新增
  SignalDatabase? get signalDb;
  UserModelService? get userModelService;
  DateTime? get lastWeeklyReflection;
  set lastWeeklyReflection(DateTime? v);
  Future<void> persistSnapshotNow(Map<String, Object?> snapshot);

  Future<void> loadFromDb() async {
    final map = await _database?.readSnapshot();
    if (map == null) return;
    restoreFromMap(map);
  }

  void _restoreList<T>(
    List<Object?>? data,
    List<T> target,
    T Function(Map<String, Object?>) fromJson,
  ) {
    if (data == null) return;
    target.clear();
    for (final item in data) {
      if (item is Map<String, Object?>) {
        target.add(fromJson(item));
      }
    }
  }

  void restoreFromMap(Map<String, Object?> map) {
    // Settings
    final settingsMap = map['settings'] as Map<String, Object?>?;
    if (settingsMap != null) {
      appSettings = AppSettings.fromJson(settingsMap);
    }

    // Thinking 模式
    final thinkEnabled = map['thinkingEnabled'] as bool?;
    if (thinkEnabled != null) {
      appSettings = appSettings.copyWith(thinkingEnabled: thinkEnabled);
    }

    // Projects / MonthCards / Todos
    _restoreList(map['projects'] as List<Object?>?, projectList, Project.fromJson);
    _restoreList(map['monthCards'] as List<Object?>?, monthCardList, MonthCard.fromJson);
    _restoreList(map['todos'] as List<Object?>?, todoItems, TodoItem.fromJson);

    // UI state
    currentProjectId = map['currentProjectId'] as String?;
    final dateStr = map['selectedDate'] as String?;
    if (dateStr != null) {
      final d = DateTime.tryParse(dateStr);
      if (d != null) selectedDate = dateOnly(d);
    }
    // 07 轮：恢复周度反思时间
    final rDateStr = map['lastWeeklyReflection'] as String?;
    if (rDateStr != null) {
      lastWeeklyReflection = DateTime.tryParse(rDateStr);
    }
    // monthViewExpanded 已由 AnimationController 管理，不再持久化
  }

  Map<String, Object?> snapshotMap() {
    return {
      'v': 2,
      'settings': appSettings.toJson(includeSecrets: false),
      'projects': projectList.map((p) => p.toJson()).toList(),
      'monthCards': monthCardList.map((m) => m.toJson()).toList(),
      'todos': todoItems.map((t) => t.toJson()).toList(),
      'currentProjectId': currentProjectId,
      'selectedDate': selectedDate.toIso8601String(),
      'thinkingEnabled': appSettings.thinkingEnabled,
      if (lastWeeklyReflection != null)
        'lastWeeklyReflection': lastWeeklyReflection!.toIso8601String(),
    };
  }

  Future<void> writeToDb() async {
    await persistSnapshotNow(snapshotMap());
  }

  /// 清除所有数据，可选择是否保留 API Key。
  Future<void> clearAllData({bool keepSecrets = true}) async {
    final oldDeepseek = appSettings.deepseekApiKey;
    final oldTavily = appSettings.tavilyApiKey;

    todoItems.clear();
    projectList.clear();
    monthCardList.clear();
    currentProjectId = null;
    selectedDate = dateOnly(DateTime.now());

    appSettings = AppSettings(
      deepseekApiKey: keepSecrets ? oldDeepseek : '',
      tavilyApiKey: keepSecrets ? oldTavily : '',
    );

    // 也清除对话历史
    await clearChatData();

    // 07 轮：清除信号和用户模型
    await signalDb?.clearAll();
    // 重置用户模型时保留模板结构，否则后续 AI 无法定位区段标记。
    await userModelService?.resetUserModel();

    await writeToDb();
    notifyAllDomains();
  }

  void notifyAllDomains();
}
