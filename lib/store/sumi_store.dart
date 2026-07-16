import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../data/chat_database.dart';
import '../data/embedding_document_store.dart';
import '../data/local_database.dart';
import '../data/signal_database.dart';
import '../data/schedule_proposal_database.dart';
import '../data/study_timer_database.dart';
import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/ai_runtime.dart';
import '../services/chat_prompt_builder.dart';
import '../services/chat_tool_registry.dart';
import '../services/prompt_context.dart';
import '../services/daily_planning_policy.dart';
import '../services/embedding_indexer.dart';
import '../services/hybrid_retriever.dart';
import '../services/local_embedding_runtime.dart';
import '../services/local_embedding_service.dart';
import '../services/local_retrieval_coordinator.dart';
import '../services/local_retrieval_service.dart';
import '../services/local_text_generation_coordinator.dart';
import '../services/local_text_generation_runtime.dart';
import '../services/local_text_model_package.dart';
import '../services/local_structured_generation.dart';
import '../services/model_package_manager.dart';
import '../services/model_router_metrics.dart';
import '../services/model_router.dart';
import '../services/project_generation.dart';
import '../services/project_generation_controller.dart';
import '../services/secure_settings_store.dart';
import '../services/signal_service.dart';
import '../services/study_timer_service.dart';
import '../services/system_reminder_service.dart';
import '../services/timer_controller.dart';
import '../services/snapshot_write_queue.dart';
import '../services/schedule_load_service.dart';
import '../services/tool_executor.dart';
import '../services/user_model_service.dart';
import '../services/memory_service.dart';
import '../services/memory_extraction.dart';
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
  ModelRouter? _modelRouter;
  late final EmbeddingDocumentStore _embeddingDocuments;
  late final LocalEmbeddingRuntime _localEmbeddingRuntime;
  late final LocalEmbeddingService _localEmbedding;
  late final LocalRetrievalService _localRetrieval;
  late final LocalRetrievalCoordinator _localRetrievalCoordinator;
  late final LocalTextGenerationRuntime _localTextRuntime;
  late final LocalTextGenerationCoordinator _localTextCoordinator;
  late final TimerController timerController;
  late final StudyTimerService _studyTimers;
  late final ScheduleProposalDatabase _scheduleProposals;
  final ScheduleLoadAssessor _scheduleLoadAssessor = ScheduleLoadAssessor();
  ScheduleRebalanceProposal? _pendingScheduleProposal;
  bool _scheduleAssessmentRunning = false;
  bool _rollingPlanningRunning = false;
  bool _appInForeground = true;
  String? _scheduleNotificationSentProposalId;
  final ProjectGenerationController projectGenerationController =
      ProjectGenerationController();
  ChatDatabase? _chatDatabase;
  ToolExecutor? _toolExecutor;
  VoiceInputService? _voiceService;
  final DateTime Function() _now;
  late final SnapshotWriteQueue _snapshotWrites;
  @override
  late final ModelRouterMetricsStore modelRouterMetrics;
  bool _closed = false;

  // 07 轮新增
  SignalDatabase? _signalDb;
  UserModelService? _legacyUserModelService;
  MemoryService? _memoryService;
  MemoryExtractionService? _memoryExtractionService;
  SignalService? _signalService;

  /// 信号数据库（供 mixin 使用）。
  @override
  SignalDatabase? get signalDb => _signalDb;

  /// 用户模型服务。
  @override
  MemoryService? get memoryService => _memoryService;
  @override
  MemoryService? get memoryServiceForStore => _memoryService;
  @override
  MemoryExtractionService? get memoryExtractionService =>
      _memoryExtractionService;

  /// 首页建议可使用本地计数选模板，但这些统计不进入 Agent 记忆上下文。
  Future<Map<String, String>> legacyRealtimeStats() async =>
      _legacyUserModelService?.computeRealtimeStats() ?? const {};

  /// 信号发射服务（供 mixin 使用）。
  @override
  SignalService? get signalService => _signalService;

  // 07 轮：建议缓存状态
  List<MemorySuggestion> cachedSuggestions = [];
  bool _suggestionsDirty = true;
  bool get suggestionsDirty => _suggestionsDirty;
  DateTime? lastForegroundTime;
  DateTime? lastSuggestionTime;

  /// todo 标题最大字数，超过触发 AI 凝练。
  static const todoTitleMaxLength = 16;

  /// 按职责暴露 AI Runtime 服务。
  AiRuntime? get aiRuntime => _aiRuntime;
  ModelRouter? get modelRouter => _modelRouter;
  @override
  LocalRetrievalService get localRetrieval => _localRetrieval;
  LocalRetrievalState get localRetrievalState =>
      _localRetrievalCoordinator.state;
  LocalTextModelState get localTextModelState => _localTextCoordinator.state;
  @override
  StructuredGenerationCapability? get structuredAi => _modelRouter == null
      ? null
      : LocalFirstStructuredGeneration(
          cloud: _modelRouter!.structured,
          local: _localTextRuntime,
        );
  @override
  ChatCapability? get chatAgent => _modelRouter?.chat;

  void recordAiDegraded(ModelCapability capability) {
    _modelRouter?.recordDegraded(capability: capability);
  }

  void _recordLocalEmbeddingMetric({
    required bool succeeded,
    required Duration elapsed,
    required Object? error,
  }) {
    modelRouterMetrics.record(
      ModelRouterMetric(
        occurredAt: _now(),
        capability: ModelCapability.embedding,
        provider: 'local-bge-small-zh-v1.5',
        outcome: succeeded
            ? ModelRouteOutcome.success
            : ModelRouteOutcome.failure,
        elapsed: elapsed,
        errorCategory: error == null
            ? ModelRouterErrorCategory.none
            : ModelRouterErrorClassifier.fromException(error),
      ),
    );
  }

  /// 对话数据库。
  @override
  ChatDatabase? get chatDatabase => _chatDatabase;

  /// 工具执行器（仅 sumi_store_chat 的 agent loop 使用）。
  @override
  ToolExecutor? get toolExecutor => _toolExecutor;

  /// 语音输入服务。
  VoiceInputService? get voiceService => _voiceService;
  List<String> get enabledTools => appSettings.enabledTools;
  bool isToolEnabled(String name) => enabledTools.contains(name);

  void updateEnabledTools(Iterable<String> names) {
    final values = names
        .where(ChatToolRegistry.allNames.contains)
        .toSet()
        .toList(growable: false);
    appSettings = appSettings.copyWith(enabledTools: values);
    afterSettingsMutation();
  }

  StudyTimer? timerForToolCall(String toolCallId) =>
      timerController.byToolCallId(toolCallId);
  Future<void> startStudyTimer(String id) => _studyTimers.start(id);
  Future<void> pauseStudyTimer(String id) => _studyTimers.pause(id);
  Future<void> finishStudyTimer(String id) => _studyTimers.finish(id);
  Future<void> cancelStudyTimer(String id) => _studyTimers.cancel(id);
  @override
  Future<void> clearStudyTimers() => _studyTimers.clearAll();
  ScheduleRebalanceProposal? get pendingScheduleProposal =>
      _pendingScheduleProposal;

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
    await _localRetrievalCoordinator.close();
    await _localTextCoordinator.close();
    _studyTimers.dispose();
    timerController.dispose();
    projectGenerationController.dispose();
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
    store.modelRouterMetrics = ModelRouterMetricsStore(
      onChanged: store._persist,
    );

    // 初始化对话数据库
    store._chatDatabase = ChatDatabase(db);
    store.timerController = TimerController();
    store._studyTimers = StudyTimerService(
      database: StudyTimerDatabase(db),
      controller: store.timerController,
      now: store._now,
    );
    store._scheduleProposals = ScheduleProposalDatabase(db);

    // 07 轮：初始化信号数据库和用户模型服务
    store._signalDb = signalDatabaseOverride ?? SignalDatabase(db);
    store._legacyUserModelService =
        userModelServiceOverride ?? UserModelService(store._signalDb!);
    store._memoryService = MemoryService(db, now: store._now);
    await store._memoryService!.ensureTables();
    store._signalService = SignalService(
      store._signalDb!,
      projectForId: (projectId) {
        for (final project in store.projectList) {
          if (project.id == projectId) return project;
        }
        return null;
      },
    );
    store._embeddingDocuments = EmbeddingDocumentStore(db);
    store._localEmbeddingRuntime = LocalEmbeddingRuntime();
    store._localEmbedding = LocalEmbeddingService(
      store._localEmbeddingRuntime,
      onMetric: store._recordLocalEmbeddingMetric,
    );
    final indexer = EmbeddingIndexer(
      documents: store._embeddingDocuments,
      embedding: store._localEmbedding,
      chatDatabase: store._chatDatabase!,
      signalDatabase: store._signalDb!,
      memoryService: store._memoryService!,
      projects: () => store.projectList,
      todos: () => store.todoItems,
      embeddingVersion: () => store._localEmbedding.embeddingVersion ?? '',
    );
    store._localRetrieval = LocalRetrievalService(
      embedding: store._localEmbedding,
      retriever: HybridRetriever(store._embeddingDocuments),
    );
    store._localRetrievalCoordinator = LocalRetrievalCoordinator(
      packages: ModelPackageManager(),
      runtime: store._localEmbeddingRuntime,
      embedding: store._localEmbedding,
      documents: store._embeddingDocuments,
      indexer: indexer,
      stateListener: (_) => store.settingsController.markChanged(),
    );
    store._localTextRuntime = LocalTextGenerationRuntime();
    store._localTextCoordinator = LocalTextGenerationCoordinator(
      packages: LocalTextModelPackage(),
      runtime: store._localTextRuntime,
      onState: (_) => store.settingsController.markChanged(),
    );

    // Import legacy files once, then generate USER_MODEL.md only as export.
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
    await store._studyTimers.restore();
    store._pendingScheduleProposal = await store._scheduleProposals
        .latestPending();

    // 回填安全存储中的 API Key（快照中不存明文）
    store.appSettings = store.appSettings.copyWith(
      deepseekApiKey: deepseekKey,
      tavilyApiKey: tavilyKey,
    );

    store._initAiService(override: aiServiceOverride);
    unawaited(store._localRetrievalCoordinator.restore());
    unawaited(store._localTextCoordinator.restore());

    // 加载今天的会话
    await store._getOrCreateConversationForDate(dateKey(store.selectedDate));

    // 检测并生成每日 todo —— 不阻塞启动，后台静默执行
    unawaited(store._runRollingPlanAndScheduleAssessment());

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
          : AiRuntime(apiKey: key, tavilyApiKey: appSettings.tavilyApiKey);
      _modelRouter = ModelRouter.fromRuntime(
        _aiRuntime!,
        metrics: modelRouterMetrics,
        embedding: _localEmbedding,
      );
      _memoryExtractionService = MemoryExtractionService(
        memory: _memoryService!,
        capability: _modelRouter!.memoryExtraction,
        onMemoryChanged: _scheduleLocalIndex,
        currentProjectId: () => currentProjectId,
      );
      _toolExecutor = ToolExecutor(
        searchService: _modelRouter!.search,
        memoryService: _memoryService!,
        signalDatabase: _signalDb!,
        currentUserMessage: () {
          for (final message in currentMessages.reversed) {
            if (message.role == 'user') return message.content;
          }
          return '';
        },
        currentConversationId: () => currentConversationId,
        isToolEnabled: isToolEnabled,
        defaultTodoDate: () => activeToolDefaultDate ?? dateKey(selectedDate),
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
        createStudyTimer: _createStudyTimerForTool,
        startProjectGeneration: _startProjectGenerationForTool,
      );
    } else {
      _aiRuntime = null;
      _modelRouter = null;
      _memoryExtractionService = null;
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
      recordAiDegraded(ModelCapability.structured);
      addUserTodo(text);
      return null;
    }

    final result = await ai.splitTodo(text);
    if (result == null) {
      recordAiDegraded(ModelCapability.structured);
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

  /// 月历可浏览范围：当前系统月前后各 30 个月。
  DateTime get firstNavigableMonth {
    final now = _now();
    return DateTime(now.year, now.month - 30);
  }

  DateTime get lastNavigableMonth {
    final now = _now();
    return DateTime(now.year, now.month + 30);
  }

  /// 判断当前选中月份能否继续向左或向右浏览。
  bool canNavigateMonth({required bool forward}) {
    final target = DateTime(
      selectedDate.year,
      selectedDate.month + (forward ? 1 : -1),
    );
    return !target.isBefore(firstNavigableMonth) &&
        !target.isAfter(lastNavigableMonth);
  }

  /// 切换月份并复用日期选择流程加载目标日期的会话。
  ///
  /// 向右进入下个月 1 日；向左进入上个月最后一天。
  Future<void> navigateMonth({required bool forward}) async {
    if (!canNavigateMonth(forward: forward)) return;
    final target = forward
        ? DateTime(selectedDate.year, selectedDate.month + 1, 1)
        : DateTime(selectedDate.year, selectedDate.month, 0);
    await selectDate(target);
  }

  /// Loads all persisted messages for one calendar month.
  Future<List<MonthChatMessage>> loadMonthChatMessages({
    required DateTime month,
  }) async {
    final db = chatDatabase;
    if (db == null) return const [];
    return db.loadMessagesForMonth(month);
  }

  /// Searches persisted user messages across all calendar months.
  Future<List<ChatSearchResult>> searchUserMessages({
    required String query,
  }) async {
    final db = chatDatabase;
    if (db == null) return const [];
    return db.searchUserMessages(query: query);
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
    _scheduleLocalIndex();
    unawaited(_assessScheduleAfterChange());
  }

  @override
  void afterProjectMutation() {
    _persist();
    projectController.markChanged();
    todoController.markChanged();
    _scheduleLocalIndex();
    if (!_rollingPlanningRunning) {
      unawaited(_runRollingPlanAndScheduleAssessment());
    }
  }

  void afterSettingsMutation() {
    _persist();
    settingsController.markChanged();
  }

  Future<void> handleAppLifecycle(AppLifecycleState state) async {
    await _studyTimers.handleLifecycle(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      await _runRollingPlanAndScheduleAssessment();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _appInForeground = false;
      unawaited(_notifyPendingScheduleProposalIfNeeded());
    }
  }

  Future<void> _runRollingPlanAndScheduleAssessment() async {
    if (_rollingPlanningRunning) return;
    _rollingPlanningRunning = true;
    try {
      await checkAndGenerateDaily();
    } finally {
      _rollingPlanningRunning = false;
    }
    await _assessScheduleAfterChange();
  }

  Future<void> _assessScheduleAfterChange() async {
    if (_scheduleAssessmentRunning) return;
    _scheduleAssessmentRunning = true;
    try {
      final assessment = _scheduleLoadAssessor.assess(
        projects: projectList,
        todos: todoItems,
        today: _now(),
      );
      final lastProposal = await _scheduleProposals.latest();
      if (!assessment.overloaded ||
          _pendingScheduleProposal != null ||
          await _scheduleProposals.hasFingerprint(assessment.fingerprint) ||
          (lastProposal != null &&
              assessment.score <= lastProposal.overloadScore + .5)) {
        return;
      }
      final proposal = _scheduleLoadAssessor.propose(
        assessment: assessment,
        todos: todoItems,
        today: _now(),
      );
      if (proposal == null) return;
      await _scheduleProposals.save(proposal);
      _pendingScheduleProposal = proposal;
      todoController.markChanged();
      unawaited(_notifyPendingScheduleProposalIfNeeded());
    } finally {
      _scheduleAssessmentRunning = false;
    }
  }

  Future<void> acceptScheduleProposal() async {
    final proposal = _pendingScheduleProposal;
    if (proposal == null || proposal.status != ScheduleProposalStatus.pending) {
      return;
    }
    final originalDates = <String, String>{};
    for (final move in proposal.moves) {
      final index = todoItems.indexWhere((todo) => todo.id == move.todoId);
      if (index == -1) continue;
      final todo = todoItems[index];
      if (todo.done ||
          todo.pinned ||
          todo.reminderTime != null ||
          todo.date != move.fromDate ||
          isPastDate(todo.date)) {
        continue;
      }
      originalDates[todo.id] = todo.date!;
      todoItems[index] = todo.copyWith(date: move.toDate);
    }
    if (originalDates.isNotEmpty) {
      for (final entry in originalDates.entries) {
        final todo = todoItems.firstWhere((item) => item.id == entry.key);
        await _signalService?.emitTodoMovedDate(todo, entry.value, todo.date!);
      }
      _persist();
      _scheduleLocalIndex();
    }
    await _scheduleProposals.updateStatus(
      proposal.id,
      ScheduleProposalStatus.accepted,
    );
    _pendingScheduleProposal = null;
    todoController.markChanged();
  }

  Future<void> _notifyPendingScheduleProposalIfNeeded() async {
    final proposal = _pendingScheduleProposal;
    if (_appInForeground ||
        proposal == null ||
        proposal.status != ScheduleProposalStatus.pending ||
        proposal.notificationSent ||
        _scheduleNotificationSentProposalId == proposal.id) {
      return;
    }
    _scheduleNotificationSentProposalId = proposal.id;
    final updated = await _scheduleProposals.markNotificationSent(proposal.id);
    if (updated == null || !updated.notificationSent) return;
    if (_pendingScheduleProposal?.id == updated.id) {
      _pendingScheduleProposal = updated;
    }
    await SystemReminderService().showScheduleRebalanceAlert(
      moveCount: proposal.moves.length,
    );
  }

  Future<void> dismissScheduleProposal() async {
    final proposal = _pendingScheduleProposal;
    if (proposal == null) return;
    await _scheduleProposals.updateStatus(
      proposal.id,
      ScheduleProposalStatus.dismissed,
    );
    _pendingScheduleProposal = null;
    todoController.markChanged();
  }

  @override
  Future<void> clearScheduleProposals() async {
    _pendingScheduleProposal = null;
    await _scheduleProposals.clearAll();
  }

  Future<void> downloadLocalRetrievalModel() =>
      _localRetrievalCoordinator.download();
  Future<void> recheckLocalRetrievalModel() =>
      _localRetrievalCoordinator.recheck();
  @override
  Future<void> deleteLocalRetrievalModel() =>
      _localRetrievalCoordinator.deleteModel();
  Future<void> downloadLocalTextModel() => _localTextCoordinator.download();
  Future<void> deleteLocalTextModel() => _localTextCoordinator.delete();
  void cancelLocalRetrievalWork() => _localRetrievalCoordinator.cancel();

  Timer? _localIndexTimer;
  @override
  void scheduleLocalIndex() => _scheduleLocalIndex();

  void _scheduleLocalIndex() {
    if (!_localEmbedding.isAvailable) return;
    _localIndexTimer?.cancel();
    _localIndexTimer = Timer(const Duration(seconds: 1), () {
      unawaited(_localRetrievalCoordinator.rebuildIndex());
    });
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
      String? content;
      if (await legacyFile.exists()) {
        content = await legacyFile.readAsString();
      } else if (await newFile.exists()) {
        content = await newFile.readAsString();
      }
      if (content != null) await _memoryService!.importLegacyMarkdown(content);
      await _memoryService!.importLegacyHypotheses();
      await _memoryService!.exportUserModel();
    } catch (_) {
      // 静默失败
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
  }) async {
    if (projectId == null || projectId.isEmpty) {
      await addUserTodo(title, date: date, body: body);
      return;
    }
    await addSystemTodo(title, projectId, date: date, body: body);
  }

  Future<String> _createStudyTimerForTool({
    required String toolCallId,
    required String conversationId,
    required String title,
    required String kind,
    int? minutes,
    String? alertAt,
    required bool startImmediately,
  }) async {
    final timerKind = StudyTimerKind.values.firstWhere(
      (value) => value.name == kind,
      orElse: () => StudyTimerKind.timer,
    );
    final alarmAt = alertAt == null ? null : DateTime.tryParse(alertAt);
    final timer = await _studyTimers.create(
      id: newSumiId('timer'),
      toolCallId: toolCallId,
      conversationId: conversationId,
      title: title,
      kind: timerKind,
      minutes: minutes,
      alertAt: alarmAt,
      startImmediately: startImmediately,
    );
    if (timer.kind == StudyTimerKind.alarm) {
      final alert = timer.alertAt!.toLocal();
      final time =
          '${alert.month}月${alert.day}日 ${alert.hour.toString().padLeft(2, '0')}:${alert.minute.toString().padLeft(2, '0')}';
      return '已创建闹钟「${timer.title}」，会在 $time 通过系统声音和震动提醒。';
    }
    return startImmediately
        ? '已开始学习计时「${timer.title}」，$minutes 分钟后会通过系统声音和震动提醒。'
        : '已创建学习计时器「${timer.title}」，时长 $minutes 分钟；点击卡片开始后会通过系统声音和震动提醒。';
  }

  ProjectGenerationSession createProjectGenerationSession(
    ProjectGenerationRequest request, {
    String? toolCallId,
    String? conversationId,
  }) {
    final router = _modelRouter;
    if (router == null) throw StateError('请先配置 DeepSeek API Key');
    return ProjectGenerationSession(
      request: request,
      router: router,
      commit: commitProjectPlan,
      toolCallId: toolCallId,
      conversationId: conversationId,
    );
  }

  Future<String> _startProjectGenerationForTool({
    required String toolCallId,
    required String conversationId,
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
  }) async {
    final session = createProjectGenerationSession(
      ProjectGenerationRequest(
        projectId: newSumiId('proj'),
        goal: goal,
        level: level,
        cycleMonths: cycleMonths,
        timeConstraint: timeConstraint,
        color: nextAvailableColor(),
      ),
      toolCallId: toolCallId,
      conversationId: conversationId,
    );
    projectGenerationController.add(session);
    await session.start();
    return switch (session.state.stage) {
      ProjectGenerationStage.awaitingConfirmation => '目标评估完成，已打开项目生成页面等待用户确认。',
      ProjectGenerationStage.cancelled => '项目生成已取消。',
      ProjectGenerationStage.failed => '项目生成失败：${session.state.error ?? '请重试'}',
      _ => '项目生成仍在处理。',
    };
  }
}

typedef SumiStore = AppStore;
