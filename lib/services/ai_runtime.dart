import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'ai_contracts.dart';
import 'ai_service.dart';
import 'chat_tool_registry.dart';
import 'memory_extraction.dart';
import 'prompt_context.dart';

class StructuredAiService {
  final AiTransport _client;
  const StructuredAiService(this._client);

  String? get lastError => _client.lastApiError;

  Future<SplitResult?> splitTodo(String text) => _client.splitTodo(text);
  Future<String?> polishTodo(String text) => _client.polishTodo(text);
  Future<InputClassification?> classifyInput(String text, {String? draft}) =>
      _client.classifyInput(text, draft: draft);
  Future<MilestoneRecognition?> recognizeMilestone({
    required String message,
    required List<TodoItem> candidates,
  }) => _client.recognizeMilestone(message: message, candidates: candidates);

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
    if (onProgress != null) {
      return _client.generatePlanEnhancedStreaming(
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
    return _client.generatePlanEnhanced(
      goal: goal,
      level: level,
      cycleMonths: cycleMonths,
      timeConstraint: timeConstraint,
      startDate: startDate,
      assessmentReport: assessmentReport,
      domainKnowledge: domainKnowledge,
    );
  }

  Future<DailyTodoResult?> generateDailyTodos({
    required String monthPlanTitle,
    required String monthPlanSummary,
    required String date,
    required int timeConstraint,
    required int scheduledHours,
  }) => _client.generateDailyTodos(
    monthPlanTitle: monthPlanTitle,
    monthPlanSummary: monthPlanSummary,
    date: date,
    timeConstraint: timeConstraint,
    scheduledHours: scheduledHours,
  );

  Future<DailyReflectionResult?> generateDailyReflection({
    required String date,
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> signals,
  }) => _client.generateDailyReflection(
    date: date,
    messages: messages,
    signals: signals,
  );

  Future<WeeklyTodoResult?> generateWeeklyTodos({
    required String monthPlanTitle,
    required String monthPlanSummary,
    required List<String> dates,
    required int timeConstraint,
    required int scheduledHours,
  }) => _client.generateWeeklyTodos(
    monthPlanTitle: monthPlanTitle,
    monthPlanSummary: monthPlanSummary,
    dates: dates,
    timeConstraint: timeConstraint,
    scheduledHours: scheduledHours,
  );

  Future<TodayLoadAnalysis?> analyzeTodayLoad({
    required String date,
    required List<Map<String, Object?>> todos,
    required List<Map<String, Object?>> futureDays,
  }) => _client.analyzeTodayLoad(
    date: date,
    todos: todos,
    futureDays: futureDays,
  );

  Future<TodayLoadScreening?> screenTodayLoad({
    required String date,
    required List<Map<String, Object?>> todos,
  }) => _client.screenTodayLoad(date: date, todos: todos);

  Future<GoalAssessment?> assessGoal({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String domainContext,
  }) => _client.assessGoal(
    goal: goal,
    level: level,
    cycleMonths: cycleMonths,
    timeConstraint: timeConstraint,
    domainContext: domainContext,
  );
}

class SuggestionQuestionAiService {
  final AiTransport _client;
  const SuggestionQuestionAiService(this._client);

  String? get lastError => _client.lastApiError;

  Future<List<SuggestionQuestion>?> recommend({
    required Map<String, Object?> context,
    required List<SuggestionQuestion> existing,
    required Set<String> validTodoIds,
    required Set<String> validProjectIds,
    required Set<String> forbiddenIntents,
  }) => _client.recommendSuggestionQuestions(
    context: context,
    existing: existing,
    validTodoIds: validTodoIds,
    validProjectIds: validProjectIds,
    forbiddenIntents: forbiddenIntents,
  );
}

class ChatAgentService {
  final AiTransport _client;
  const ChatAgentService(this._client);

  Stream<StreamEvent> sendAgentLoop({
    required List<Map<String, Object?>> messages,
    required Future<String> Function(ToolCall call) executeTool,
    void Function(ToolCall call)? onToolCall,
    int maxTurns = 8,
    Set<String> validProjectIds = const {},
    Set<String>? enabledTools,
  }) async* {
    final allowedTools = (enabledTools ?? ChatToolRegistry.allNames.toSet())
        .where((name) => name != 'write_todo')
        .toSet();
    for (var turn = 0; turn < maxTurns; turn++) {
      List<ToolCall>? pendingCalls;
      final contentBuf = StringBuffer();
      var failed = false;

      yield AgentActivityEvent('正在生成回复');
      await for (final event in _client.streamChatMessages(
        messages,
        tools: ChatToolRegistry.schemasFor(allowedTools),
      )) {
        switch (event) {
          case ContentDelta(text: final text):
            contentBuf.write(text);
            yield event;
          case ReasoningDelta():
            // 原始推理不进入下一轮工具上下文。
            continue;
          case ToolCallsComplete(calls: final calls):
            pendingCalls = calls;
          case AgentErrorEvent():
            failed = true;
            yield event;
          case AgentActivityEvent():
            yield event;
          case StreamDone():
            break;
        }
      }
      if (failed) return;

      if (pendingCalls != null && pendingCalls.isNotEmpty) {
        pendingCalls = pendingCalls
            .map((call) => _normalizeTimerCall(call, messages))
            .toList(growable: false);
      }

      final assistantMessage = <String, Object?>{
        'role': 'assistant',
        'content': contentBuf.toString(),
        if (pendingCalls != null && pendingCalls.isNotEmpty)
          'tool_calls': pendingCalls
              .map(
                (call) => {
                  'id': call.id,
                  'type': 'function',
                  'function': {
                    'name': call.name,
                    'arguments': jsonEncode(call.arguments),
                  },
                },
              )
              .toList(),
      };
      messages.add(assistantMessage);
      if (pendingCalls == null || pendingCalls.isEmpty) return;

      for (final call in pendingCalls) {
        onToolCall?.call(call);
        yield AgentActivityEvent(_activityForTool(call.name));
        final validation = ToolCallValidator.validate(
          call.id,
          call.name,
          call.arguments,
          validProjectIds: validProjectIds,
          enabledTools: allowedTools,
        );
        final validatedCall = validation.isValid
            ? ToolCall(
                id: call.id,
                name: call.name,
                arguments: validation.value!,
              )
            : null;
        final result = validatedCall == null
            ? '工具参数错误：${validation.errors.join('；')}'
            : await executeTool(validatedCall);
        messages.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'content': PromptContext.toolResult(
            toolName: call.name,
            content: result,
          ),
        });
      }
    }

    yield ContentDelta('\n\n（本次工具步骤较多，以上是已完成的部分。）');
    yield StreamDone();
  }

  static ToolCall _normalizeTimerCall(
    ToolCall call,
    List<Map<String, Object?>> messages,
  ) {
    if (call.name != 'create_study_timer') return call;
    final userText = messages.reversed
        .where((message) => message['role'] == 'user')
        .map((message) => message['content'])
        .whereType<String>()
        .firstOrNull;
    if (userText == null || !_prefersRelativeTimer(userText)) return call;

    final minutes =
        _relativeMinutes(userText) ?? _integer(call.arguments['minutes']);
    if (minutes == null || minutes < 1 || minutes > 480) return call;
    return ToolCall(
      id: call.id,
      name: call.name,
      arguments: {
        ...call.arguments,
        'kind': 'timer',
        'minutes': minutes,
        'startImmediately': _startsImmediately(userText),
      }..remove('alertAt'),
    );
  }

  static bool _prefersRelativeTimer(String text) {
    if (text.contains('闹钟') &&
        !text.contains('计时器') &&
        !text.contains('倒计时') &&
        !text.contains('开始计时')) {
      return false;
    }
    return RegExp(r'计时器|倒计时|开始计时').hasMatch(text) ||
        RegExp(
          r'(?:\d+|[一二两三四五六七八九十半]+)(?:秒钟?|分钟|小时)后.{0,12}提醒|提醒.{0,12}(?:\d+|[一二两三四五六七八九十半]+)(?:秒钟?|分钟|小时)后',
        ).hasMatch(text);
  }

  static bool _startsImmediately(String text) =>
      RegExp(r'开始|立刻|立即|现在|马上').hasMatch(text) ||
      RegExp(r'(?:\d+|[一二两三四五六七八九十半]+)(?:秒钟?|分钟|小时)后.{0,12}提醒').hasMatch(text);

  static int? _relativeMinutes(String text) {
    final match = RegExp(r'(\d+|[一二两三四五六七八九十半]+)(秒钟?|分钟|小时)').firstMatch(text);
    if (match == null) return null;
    final amountText = match.group(1)!;
    final unit = match.group(2)!;
    if (amountText == '半') return unit == '小时' ? 30 : 1;
    final amount = int.tryParse(amountText) ?? _chineseInteger(amountText);
    if (amount == null) return null;
    if (unit.startsWith('秒')) return (amount / 60).ceil().clamp(1, 480);
    return unit == '小时' ? amount * 60 : amount;
  }

  static int? _chineseInteger(String text) {
    const digits = {
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (text == '十') return 10;
    final tenAt = text.indexOf('十');
    if (tenAt < 0) return digits[text];
    final tens = tenAt == 0 ? 1 : digits[text.substring(0, tenAt)];
    final ones = tenAt == text.length - 1
        ? 0
        : digits[text.substring(tenAt + 1)];
    if (tens == null || ones == null) return null;
    return tens * 10 + ones;
  }

  static int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    return null;
  }

  static String _activityForTool(String name) {
    return switch (name) {
      'search_web' => '正在搜索',
      'read_memory' => '正在读取记忆',
      'read_todos' => '正在读取事项',
      'write_todo' => '正在创建事项',
      'read_signals' => '正在分析行为记录',
      'create_study_timer' => '正在创建学习计时器',
      'start_project_generation' => '正在准备项目生成',
      _ => '正在使用工具',
    };
  }
}

class WebSearchService {
  final AiTransport _client;
  const WebSearchService(this._client);

  bool get isConfigured =>
      _client.tavilyApiKey != null && _client.tavilyApiKey!.isNotEmpty;

  Future<List<Map<String, String>>> search(String query) =>
      _client.searchWeb(query);
}

class MemoryExtractionAiService {
  final AiTransport _client;
  const MemoryExtractionAiService(this._client);

  Future<MemoryExtractionDecision?> extractMemory({
    required String message,
    required List<MemoryExtractionCandidate> candidates,
  }) => _client.extractMemory(message: message, candidates: candidates);
}

class AiRuntime {
  final AiTransport transport;
  late final StructuredAiService structured;
  late final ChatAgentService chat;
  late final WebSearchService search;
  late final MemoryExtractionAiService memoryExtraction;
  late final SuggestionQuestionAiService suggestionQuestions;

  AiRuntime({
    required String apiKey,
    String? tavilyApiKey,
    http.Client? httpClient,
  }) : transport = AiTransport(
         apiKey: apiKey,
         tavilyApiKey: tavilyApiKey,
         client: httpClient,
       ) {
    _bindServices();
  }

  AiRuntime.fromClient(AiTransport client) : transport = client {
    _bindServices();
  }

  void _bindServices() {
    structured = StructuredAiService(transport);
    chat = ChatAgentService(transport);
    search = WebSearchService(transport);
    memoryExtraction = MemoryExtractionAiService(transport);
    suggestionQuestions = SuggestionQuestionAiService(transport);
  }

  void close() => transport.close();
}
