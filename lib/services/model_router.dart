import '../models/models.dart';
import 'ai_runtime.dart';
import 'ai_service.dart';
import 'local_embedding_service.dart';
import 'memory_extraction.dart';

/// A stable capability name used for routing and anonymous local diagnostics.
enum ModelCapability {
  chat,
  structured,
  memoryExtraction,
  webSearch,
  embedding,
}

enum ModelRouteOutcome { success, failure, degraded }

/// Error categories intentionally omit server responses and user supplied text.
enum ModelRouterErrorCategory {
  none,
  authentication,
  rateLimited,
  timeout,
  network,
  validation,
  unavailable,
  unknown,
}

/// One anonymous completed route. Do not add request, response, prompt, or
/// tool payload fields here: this object is persisted only for local health
/// diagnostics.
class ModelRouterMetric {
  final DateTime occurredAt;
  final ModelCapability capability;
  final String provider;
  final ModelRouteOutcome outcome;
  final Duration elapsed;
  final ModelRouterErrorCategory errorCategory;

  const ModelRouterMetric({
    required this.occurredAt,
    required this.capability,
    required this.provider,
    required this.outcome,
    required this.elapsed,
    this.errorCategory = ModelRouterErrorCategory.none,
  });
}

/// Implemented by the local metrics store. Router metrics are best-effort:
/// recording must never change an AI request's result or error behavior.
abstract interface class ModelRouterMetricsSink {
  void record(ModelRouterMetric metric);
}

/// All chat implementations have the same streaming and tool-loop contract.
abstract interface class ChatCapability {
  Stream<StreamEvent> sendAgentLoop({
    required List<Map<String, Object?>> messages,
    required Future<String> Function(ToolCall call) executeTool,
    void Function(ToolCall call)? onToolCall,
    bool thinkingEnabled = true,
    int maxTurns = 5,
    Set<String> validProjectIds = const {},
    Set<String>? enabledTools,
  });
}

/// Structured operations retain the existing return types and validation flow.
abstract interface class StructuredGenerationCapability {
  String? get lastError;

  Future<SplitResult?> splitTodo(String text);
  Future<String?> polishTodo(String text);
  Future<PlanResult?> generatePlan({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String startDate,
    required String assessmentReport,
    required String domainKnowledge,
    void Function(String chunk)? onProgress,
    void Function(AiStructuredStage stage)? onStage,
  });
  Future<DailyTodoResult?> generateDailyTodos({
    required String monthPlanTitle,
    required String monthPlanSummary,
    required String date,
    required int timeConstraint,
    required int scheduledHours,
  });
  Future<WeeklyTodoResult?> generateWeeklyTodos({
    required String monthPlanTitle,
    required String monthPlanSummary,
    required List<String> dates,
    required int timeConstraint,
    required int scheduledHours,
  });
  Future<GoalAssessment?> assessGoal({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String domainContext,
  });
}

abstract interface class WebSearchCapability {
  bool get isConfigured;
  Future<List<Map<String, String>>> search(String query);
}

/// A provider groups implementations for each capability. New local providers
/// can implement this without changing callers of [ModelRouter].
abstract interface class ModelProvider {
  String get id;
  ChatCapability get chat;
  StructuredGenerationCapability get structured;
  MemoryExtractionCapability get memoryExtraction;
  WebSearchCapability get search;
}

/// Adapter for the current cloud runtime. It deliberately delegates without
/// changing prompts, retry policy, model choice, validation, or stream events.
class CloudModelProvider implements ModelProvider {
  @override
  final String id;
  @override
  final ChatCapability chat;
  @override
  final StructuredGenerationCapability structured;
  @override
  final MemoryExtractionCapability memoryExtraction;
  @override
  final WebSearchCapability search;

  CloudModelProvider({
    required this.id,
    required this.chat,
    required this.structured,
    required this.memoryExtraction,
    required this.search,
  });

  factory CloudModelProvider.fromRuntime(
    AiRuntime runtime, {
    String id = 'cloud',
  }) {
    return CloudModelProvider(
      id: id,
      chat: _CloudChatCapability(runtime.chat),
      structured: _CloudStructuredCapability(runtime.structured),
      memoryExtraction: _CloudMemoryExtractionCapability(
        runtime.memoryExtraction,
      ),
      search: _CloudWebSearchCapability(runtime.search),
    );
  }
}

class _CloudMemoryExtractionCapability implements MemoryExtractionCapability {
  final MemoryExtractionAiService _delegate;
  const _CloudMemoryExtractionCapability(this._delegate);

  @override
  Future<MemoryExtractionDecision?> extractMemory({
    required String message,
    required List<MemoryExtractionCandidate> candidates,
  }) => _delegate.extractMemory(message: message, candidates: candidates);
}

class _CloudChatCapability implements ChatCapability {
  final ChatAgentService _delegate;
  const _CloudChatCapability(this._delegate);

  @override
  Stream<StreamEvent> sendAgentLoop({
    required List<Map<String, Object?>> messages,
    required Future<String> Function(ToolCall call) executeTool,
    void Function(ToolCall call)? onToolCall,
    bool thinkingEnabled = true,
    int maxTurns = 5,
    Set<String> validProjectIds = const {},
    Set<String>? enabledTools,
  }) {
    return _delegate.sendAgentLoop(
      messages: messages,
      executeTool: executeTool,
      onToolCall: onToolCall,
      thinkingEnabled: thinkingEnabled,
      maxTurns: maxTurns,
      validProjectIds: validProjectIds,
      enabledTools: enabledTools,
    );
  }
}

class _CloudStructuredCapability implements StructuredGenerationCapability {
  final StructuredAiService _delegate;
  const _CloudStructuredCapability(this._delegate);

  @override
  String? get lastError => _delegate.lastError;

  @override
  Future<SplitResult?> splitTodo(String text) => _delegate.splitTodo(text);

  @override
  Future<String?> polishTodo(String text) => _delegate.polishTodo(text);

  @override
  Future<PlanResult?> generatePlan({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String startDate,
    required String assessmentReport,
    required String domainKnowledge,
    void Function(String chunk)? onProgress,
    void Function(AiStructuredStage stage)? onStage,
  }) {
    return _delegate.generatePlan(
      goal: goal,
      level: level,
      cycleMonths: cycleMonths,
      timeConstraint: timeConstraint,
      startDate: startDate,
      assessmentReport: assessmentReport,
      domainKnowledge: domainKnowledge,
      onProgress: onProgress,
      onStage: onStage,
    );
  }

  @override
  Future<DailyTodoResult?> generateDailyTodos({
    required String monthPlanTitle,
    required String monthPlanSummary,
    required String date,
    required int timeConstraint,
    required int scheduledHours,
  }) {
    return _delegate.generateDailyTodos(
      monthPlanTitle: monthPlanTitle,
      monthPlanSummary: monthPlanSummary,
      date: date,
      timeConstraint: timeConstraint,
      scheduledHours: scheduledHours,
    );
  }

  @override
  Future<WeeklyTodoResult?> generateWeeklyTodos({
    required String monthPlanTitle,
    required String monthPlanSummary,
    required List<String> dates,
    required int timeConstraint,
    required int scheduledHours,
  }) => _delegate.generateWeeklyTodos(
    monthPlanTitle: monthPlanTitle,
    monthPlanSummary: monthPlanSummary,
    dates: dates,
    timeConstraint: timeConstraint,
    scheduledHours: scheduledHours,
  );

  @override
  Future<GoalAssessment?> assessGoal({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String domainContext,
  }) {
    return _delegate.assessGoal(
      goal: goal,
      level: level,
      cycleMonths: cycleMonths,
      timeConstraint: timeConstraint,
      domainContext: domainContext,
    );
  }
}

class _CloudWebSearchCapability implements WebSearchCapability {
  final WebSearchService _delegate;
  const _CloudWebSearchCapability(this._delegate);

  @override
  bool get isConfigured => _delegate.isConfigured;

  @override
  Future<List<Map<String, String>>> search(String query) =>
      _delegate.search(query);
}

/// Routes every current capability to the cloud provider. Routing is explicit
/// even in this one-provider release so later providers remain an additive
/// change rather than a UI or business-logic rewrite.
class ModelRouter {
  final ModelProvider _cloud;
  final ModelRouterMetricsSink? metrics;
  final DateTime Function() _clock;
  final EmbeddingCapability? _embedding;

  late final ChatCapability chat = _MeasuredChatCapability(
    _cloud.chat,
    _cloud.id,
    _record,
  );
  late final StructuredGenerationCapability structured =
      _MeasuredStructuredCapability(_cloud.structured, _cloud.id, _record);
  late final MemoryExtractionCapability memoryExtraction =
      _MeasuredMemoryExtractionCapability(
        _cloud.memoryExtraction,
        _cloud.id,
        _record,
      );
  late final WebSearchCapability search = _MeasuredWebSearchCapability(
    _cloud.search,
    _cloud.id,
    _record,
  );
  late final EmbeddingCapability? embedding = _embedding;

  ModelRouter({
    required ModelProvider cloudProvider,
    EmbeddingCapability? localEmbedding,
    this.metrics,
    DateTime Function()? clock,
  }) : _cloud = cloudProvider,
       _embedding = localEmbedding,
       _clock = clock ?? DateTime.now;

  factory ModelRouter.fromRuntime(
    AiRuntime runtime, {
    ModelRouterMetricsSink? metrics,
    EmbeddingCapability? embedding,
    DateTime Function()? clock,
  }) {
    return ModelRouter(
      cloudProvider: CloudModelProvider.fromRuntime(runtime),
      localEmbedding: embedding,
      metrics: metrics,
      clock: clock,
    );
  }

  void recordDegraded({
    required ModelCapability capability,
    ModelRouterErrorCategory errorCategory =
        ModelRouterErrorCategory.unavailable,
  }) {
    _record(
      capability: capability,
      provider: _cloud.id,
      outcome: ModelRouteOutcome.degraded,
      elapsed: Duration.zero,
      errorCategory: errorCategory,
    );
  }

  void _record({
    required ModelCapability capability,
    required String provider,
    required ModelRouteOutcome outcome,
    required Duration elapsed,
    ModelRouterErrorCategory errorCategory = ModelRouterErrorCategory.none,
  }) {
    try {
      metrics?.record(
        ModelRouterMetric(
          occurredAt: _clock(),
          capability: capability,
          provider: provider,
          outcome: outcome,
          elapsed: elapsed,
          errorCategory: errorCategory,
        ),
      );
    } catch (_) {
      // Local diagnostics cannot affect an AI request.
    }
  }
}

typedef _MetricRecorder = void Function({
  required ModelCapability capability,
  required String provider,
  required ModelRouteOutcome outcome,
  required Duration elapsed,
  ModelRouterErrorCategory errorCategory,
});

class _MeasuredChatCapability implements ChatCapability {
  final ChatCapability _delegate;
  final String _provider;
  final _MetricRecorder _record;

  const _MeasuredChatCapability(this._delegate, this._provider, this._record);

  @override
  Stream<StreamEvent> sendAgentLoop({
    required List<Map<String, Object?>> messages,
    required Future<String> Function(ToolCall call) executeTool,
    void Function(ToolCall call)? onToolCall,
    bool thinkingEnabled = true,
    int maxTurns = 5,
    Set<String> validProjectIds = const {},
    Set<String>? enabledTools,
  }) async* {
    final watch = Stopwatch()..start();
    ModelRouterErrorCategory? error;
    try {
      await for (final event in _delegate.sendAgentLoop(
        messages: messages,
        executeTool: executeTool,
        onToolCall: onToolCall,
        thinkingEnabled: thinkingEnabled,
        maxTurns: maxTurns,
        validProjectIds: validProjectIds,
        enabledTools: enabledTools,
      )) {
        if (event case AgentErrorEvent(message: final message)) {
          error = ModelRouterErrorClassifier.fromMessage(message);
        }
        yield event;
      }
    } catch (exception) {
      error = ModelRouterErrorClassifier.fromException(exception);
      rethrow;
    } finally {
      watch.stop();
      _record(
        capability: ModelCapability.chat,
        provider: _provider,
        outcome: error == null
            ? ModelRouteOutcome.success
            : ModelRouteOutcome.failure,
        elapsed: watch.elapsed,
        errorCategory: error ?? ModelRouterErrorCategory.none,
      );
    }
  }
}

class _MeasuredStructuredCapability implements StructuredGenerationCapability {
  final StructuredGenerationCapability _delegate;
  final String _provider;
  final _MetricRecorder _record;

  const _MeasuredStructuredCapability(
    this._delegate,
    this._provider,
    this._record,
  );

  @override
  String? get lastError => _delegate.lastError;

  @override
  Future<SplitResult?> splitTodo(String text) =>
      _track(() => _delegate.splitTodo(text));

  @override
  Future<String?> polishTodo(String text) =>
      _track(() => _delegate.polishTodo(text));

  @override
  Future<PlanResult?> generatePlan({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String startDate,
    required String assessmentReport,
    required String domainKnowledge,
    void Function(String chunk)? onProgress,
    void Function(AiStructuredStage stage)? onStage,
  }) => _track(
    () => _delegate.generatePlan(
      goal: goal,
      level: level,
      cycleMonths: cycleMonths,
      timeConstraint: timeConstraint,
      startDate: startDate,
      assessmentReport: assessmentReport,
      domainKnowledge: domainKnowledge,
      onProgress: onProgress,
      onStage: onStage,
    ),
  );

  @override
  Future<DailyTodoResult?> generateDailyTodos({
    required String monthPlanTitle,
    required String monthPlanSummary,
    required String date,
    required int timeConstraint,
    required int scheduledHours,
  }) => _track(
    () => _delegate.generateDailyTodos(
      monthPlanTitle: monthPlanTitle,
      monthPlanSummary: monthPlanSummary,
      date: date,
      timeConstraint: timeConstraint,
      scheduledHours: scheduledHours,
    ),
  );

  @override
  Future<WeeklyTodoResult?> generateWeeklyTodos({
    required String monthPlanTitle,
    required String monthPlanSummary,
    required List<String> dates,
    required int timeConstraint,
    required int scheduledHours,
  }) => _track(
    () => _delegate.generateWeeklyTodos(
      monthPlanTitle: monthPlanTitle,
      monthPlanSummary: monthPlanSummary,
      dates: dates,
      timeConstraint: timeConstraint,
      scheduledHours: scheduledHours,
    ),
  );

  @override
  Future<GoalAssessment?> assessGoal({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String domainContext,
  }) => _track(
    () => _delegate.assessGoal(
      goal: goal,
      level: level,
      cycleMonths: cycleMonths,
      timeConstraint: timeConstraint,
      domainContext: domainContext,
    ),
  );

  Future<T> _track<T>(Future<T> Function() action) async {
    final watch = Stopwatch()..start();
    try {
      final result = await action();
      final failed = result == null;
      _record(
        capability: ModelCapability.structured,
        provider: _provider,
        outcome: failed ? ModelRouteOutcome.failure : ModelRouteOutcome.success,
        elapsed: watch.elapsed,
        errorCategory: failed
            ? ModelRouterErrorClassifier.fromMessage(lastError ?? '')
            : ModelRouterErrorCategory.none,
      );
      return result;
    } catch (exception) {
      _record(
        capability: ModelCapability.structured,
        provider: _provider,
        outcome: ModelRouteOutcome.failure,
        elapsed: watch.elapsed,
        errorCategory: ModelRouterErrorClassifier.fromException(exception),
      );
      rethrow;
    } finally {
      watch.stop();
    }
  }
}

class _MeasuredMemoryExtractionCapability
    implements MemoryExtractionCapability {
  final MemoryExtractionCapability _delegate;
  final String _provider;
  final _MetricRecorder _record;

  const _MeasuredMemoryExtractionCapability(
    this._delegate,
    this._provider,
    this._record,
  );

  @override
  Future<MemoryExtractionDecision?> extractMemory({
    required String message,
    required List<MemoryExtractionCandidate> candidates,
  }) async {
    final watch = Stopwatch()..start();
    try {
      final result = await _delegate.extractMemory(
        message: message,
        candidates: candidates,
      );
      _record(
        capability: ModelCapability.memoryExtraction,
        provider: _provider,
        outcome: result == null
            ? ModelRouteOutcome.failure
            : ModelRouteOutcome.success,
        elapsed: watch.elapsed,
        errorCategory: result == null
            ? ModelRouterErrorCategory.validation
            : ModelRouterErrorCategory.none,
      );
      return result;
    } catch (error) {
      _record(
        capability: ModelCapability.memoryExtraction,
        provider: _provider,
        outcome: ModelRouteOutcome.failure,
        elapsed: watch.elapsed,
        errorCategory: ModelRouterErrorClassifier.fromException(error),
      );
      rethrow;
    } finally {
      watch.stop();
    }
  }
}

class _MeasuredWebSearchCapability implements WebSearchCapability {
  final WebSearchCapability _delegate;
  final String _provider;
  final _MetricRecorder _record;

  const _MeasuredWebSearchCapability(
    this._delegate,
    this._provider,
    this._record,
  );

  @override
  bool get isConfigured => _delegate.isConfigured;

  @override
  Future<List<Map<String, String>>> search(String query) async {
    final watch = Stopwatch()..start();
    try {
      final result = await _delegate.search(query);
      _record(
        capability: ModelCapability.webSearch,
        provider: _provider,
        outcome: ModelRouteOutcome.success,
        elapsed: watch.elapsed,
      );
      return result;
    } catch (exception) {
      _record(
        capability: ModelCapability.webSearch,
        provider: _provider,
        outcome: ModelRouteOutcome.failure,
        elapsed: watch.elapsed,
        errorCategory: ModelRouterErrorClassifier.fromException(exception),
      );
      rethrow;
    } finally {
      watch.stop();
    }
  }
}

class ModelRouterErrorClassifier {
  const ModelRouterErrorClassifier._();

  static ModelRouterErrorCategory fromException(Object error) =>
      fromMessage(error.toString());

  static ModelRouterErrorCategory fromMessage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('401') ||
        normalized.contains('403') ||
        normalized.contains('auth') ||
        normalized.contains('api key')) {
      return ModelRouterErrorCategory.authentication;
    }
    if (normalized.contains('429') ||
        normalized.contains('rate limit') ||
        normalized.contains('请求过于频繁') ||
        normalized.contains('限流')) {
      return ModelRouterErrorCategory.rateLimited;
    }
    if (normalized.contains('timeout') || normalized.contains('timed out')) {
      return ModelRouterErrorCategory.timeout;
    }
    if (normalized.contains('socket') ||
        normalized.contains('network') ||
        normalized.contains('connection')) {
      return ModelRouterErrorCategory.network;
    }
    if (normalized.contains('json') ||
        normalized.contains('format') ||
        normalized.contains('contract') ||
        normalized.contains('validation')) {
      return ModelRouterErrorCategory.validation;
    }
    if (normalized.contains('not configured') ||
        normalized.contains('unavailable')) {
      return ModelRouterErrorCategory.unavailable;
    }
    return ModelRouterErrorCategory.unknown;
  }
}
