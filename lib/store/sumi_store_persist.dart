part of 'sumi_store.dart';

// ---------------------------------------------------------------------------
// Persistence mixin
// ---------------------------------------------------------------------------

mixin SumiStorePersist on ChangeNotifier {
  // 声明由 SumiStore 提供的字段（mixin 约束）
  SumiSnapshotStore? get _database;
  List<TodoItem> get todoItems;
  List<Project> get projectList;
  List<MonthCard> get monthCardList;
  DateTime get selectedDate;
  set selectedDate(DateTime v);
  bool get monthViewExpanded;
  set monthViewExpanded(bool v);
  String? get currentProjectId;
  set currentProjectId(String? v);
  AppSettings get appSettings;
  set appSettings(AppSettings v);

  Future<void> loadFromDb() async {
    final map = await _database?.readSnapshot();
    if (map == null) return;
    restoreFromMap(map);
  }

  void restoreFromMap(Map<String, Object?> map) {
    // Settings
    final settingsMap = map['settings'] as Map<String, Object?>?;
    if (settingsMap != null) {
      appSettings = AppSettings.fromJson(settingsMap);
    }

    // Projects
    final projectListData = map['projects'] as List<Object?>?;
    if (projectListData != null) {
      projectList.clear();
      for (final p in projectListData) {
        if (p is Map<String, Object?>) {
          projectList.add(Project.fromJson(p));
        }
      }
    }

    // Month cards
    final monthCardListData = map['monthCards'] as List<Object?>?;
    if (monthCardListData != null) {
      monthCardList.clear();
      for (final m in monthCardListData) {
        if (m is Map<String, Object?>) {
          monthCardList.add(MonthCard.fromJson(m));
        }
      }
    }

    // Todos
    final todoListData = map['todos'] as List<Object?>?;
    if (todoListData != null) {
      todoItems.clear();
      for (final t in todoListData) {
        if (t is Map<String, Object?>) {
          todoItems.add(TodoItem.fromJson(t));
        }
      }
    }

    // UI state
    currentProjectId = map['currentProjectId'] as String?;
    final dateStr = map['selectedDate'] as String?;
    if (dateStr != null) {
      final d = DateTime.tryParse(dateStr);
      if (d != null) selectedDate = dateOnly(d);
    }
    monthViewExpanded = (map['monthViewExpanded'] as bool?) ?? false;
  }

  Map<String, Object?> snapshotMap() {
    return {
      'v': 1,
      'settings': appSettings.toJson(includeSecrets: false),
      'projects': projectList.map((p) => p.toJson()).toList(),
      'monthCards': monthCardList.map((m) => m.toJson()).toList(),
      'todos': todoItems.map((t) => t.toJson()).toList(),
      'currentProjectId': currentProjectId,
      'selectedDate': selectedDate.toIso8601String(),
      'monthViewExpanded': monthViewExpanded,
    };
  }

  Future<void> writeToDb() async {
    await _database?.writeSnapshot(snapshotMap());
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
    monthViewExpanded = false;

    appSettings = AppSettings(
      deepseekApiKey: keepSecrets ? oldDeepseek : '',
      tavilyApiKey: keepSecrets ? oldTavily : '',
    );

    await writeToDb();
    notifyListeners();
  }
}
