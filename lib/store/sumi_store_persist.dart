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
  DateTime get currentTime;
  set selectedDate(DateTime v);
  String? get currentProjectId;
  set currentProjectId(String? v);
  AppSettings get appSettings;
  set appSettings(AppSettings v);
  Future<void> clearChatData(); // 由 SumiStoreChat mixin 提供
  // 07 轮新增
  SignalDatabase? get signalDb;
  MemoryService? get memoryServiceForStore;
  Future<void> persistSnapshotNow(Map<String, Object?> snapshot);
  ModelRouterMetricsStore get modelRouterMetrics;
  List<SuggestionQuestion> get cachedSuggestionQuestions;
  set cachedSuggestionQuestions(List<SuggestionQuestion> value);
  String? get suggestionQuestionsFingerprint;
  set suggestionQuestionsFingerprint(String? value);
  DateTime? get suggestionQuestionsGeneratedAt;
  set suggestionQuestionsGeneratedAt(DateTime? value);
  Set<String> get rejectedSuggestionIntents;
  Set<String> get disabledSuggestionIntents;
  Set<String> get acceptedSuggestionIntents;
  void restoreSuggestionQuestionFeedback(Map<String, Object?>? value);
  void setSuggestionsDirty(bool value);
  Future<void> deleteLocalRetrievalModel();
  Future<void> deleteLocalSpeechModel();
  Future<void> clearStudyTimers();
  Future<void> clearScheduleProposals();
  Future<void> clearMilestones();
  Future<void> clearDailyReflections();
  Future<void> clearUserModels();

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

    // Projects / MonthCards / Todos
    _restoreList(
      map['projects'] as List<Object?>?,
      projectList,
      Project.fromJson,
    );
    _restoreList(
      map['monthCards'] as List<Object?>?,
      monthCardList,
      MonthCard.fromJson,
    );
    _restoreList(map['todos'] as List<Object?>?, todoItems, TodoItem.fromJson);

    // UI state
    currentProjectId = map['currentProjectId'] as String?;
    final dateStr = map['selectedDate'] as String?;
    if (dateStr != null) {
      final d = DateTime.tryParse(dateStr);
      if (d != null) selectedDate = dateOnly(d);
    }
    final metrics = map['modelRouterMetrics'] as Map<String, Object?>?;
    modelRouterMetrics.restore(metrics);
    final cached = map['suggestionQuestions'];
    if (cached is List<Object?>) {
      cachedSuggestionQuestions = cached
          .whereType<Map<String, Object?>>()
          .map(SuggestionQuestion.fromJson)
          .where((item) => item.id.isNotEmpty && item.text.isNotEmpty)
          .toList(growable: false);
      if (cachedSuggestionQuestions.length == 5) {
        setSuggestionsDirty(false);
      }
    }
    suggestionQuestionsFingerprint =
        map['suggestionQuestionsFingerprint'] as String?;
    suggestionQuestionsGeneratedAt = DateTime.tryParse(
      map['suggestionQuestionsGeneratedAt'] as String? ?? '',
    );
    restoreSuggestionQuestionFeedback(
      map['suggestionQuestionFeedback'] as Map<String, Object?>?,
    );
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
      'modelRouterMetrics': modelRouterMetrics.toJson(),
      if (cachedSuggestionQuestions.isNotEmpty)
        'suggestionQuestions': cachedSuggestionQuestions
            .map((item) => item.toJson())
            .toList(),
      if (suggestionQuestionsFingerprint != null)
        'suggestionQuestionsFingerprint': suggestionQuestionsFingerprint,
      if (suggestionQuestionsGeneratedAt != null)
        'suggestionQuestionsGeneratedAt': suggestionQuestionsGeneratedAt!
            .toIso8601String(),
      'suggestionQuestionFeedback': {
        'sentIntents': acceptedSuggestionIntents.toList(growable: false),
        'notSuitableIntents': rejectedSuggestionIntents.toList(growable: false),
        'disabledIntents': disabledSuggestionIntents.toList(growable: false),
      },
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
    selectedDate = dateOnly(currentTime);

    appSettings = AppSettings(
      deepseekApiKey: keepSecrets ? oldDeepseek : '',
      tavilyApiKey: keepSecrets ? oldTavily : '',
    );

    // 也清除对话历史
    await clearChatData();

    // 07 轮：清除信号和用户模型
    await signalDb?.clearAll();
    await memoryServiceForStore?.clearAll();
    modelRouterMetrics.clear();
    await clearStudyTimers();
    await clearScheduleProposals();
    await clearMilestones();
    await clearDailyReflections();
    await clearUserModels();
    // 本地检索是可选组件；平台通道不可用时不应阻断用户数据清除。
    try {
      await deleteLocalRetrievalModel();
    } catch (_) {}
    try {
      await deleteLocalSpeechModel();
    } catch (_) {}

    await writeToDb();
    notifyAllDomains();
  }

  void notifyAllDomains();
}
