import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'ai_contracts.dart';
import 'ai_service.dart';
import 'prompt_context.dart';

class StructuredAiService {
  final AiTransport _client;
  const StructuredAiService(this._client);

  String? get lastError => _client.lastApiError;

  Future<SplitResult?> splitTodo(String text) => _client.splitTodo(text);
  Future<String?> polishTodo(String text) => _client.polishTodo(text);

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

  Future<List<String>> generateOpeningSuggestions({
    required String realtimeStats,
    required String coreMemory,
  }) => _client.generateOpeningSuggestions(
        realtimeStats: realtimeStats,
        coreMemory: coreMemory,
      );

  Future<WeeklyReflectionResult?> generateWeeklyReflection({
    required String hotPrompt,
    required String warmPrefs,
    required String weeklySignals,
  }) => _client.generateWeeklyReflection(
        hotPrompt: hotPrompt,
        warmPrefs: warmPrefs,
        weeklySignals: weeklySignals,
      );
}

class ChatAgentService {
  final AiTransport _client;
  const ChatAgentService(this._client);

  Stream<StreamEvent> sendAgentLoop({
    required List<Map<String, Object?>> messages,
    required Future<String> Function(ToolCall call) executeTool,
    void Function(ToolCall call)? onToolCall,
    bool thinkingEnabled = true,
    int maxTurns = 5,
    Set<String> validProjectIds = const {},
  }) async* {
    for (var turn = 0; turn < maxTurns; turn++) {
      List<ToolCall>? pendingCalls;
      final contentBuf = StringBuffer();
      var failed = false;

      yield AgentActivityEvent('正在生成回复');
      await for (final event in _client.streamChatMessages(
        messages,
        thinkingEnabled: thinkingEnabled,
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

    yield ContentDelta('\n\n（已达最大轮数，以上为我能获取的信息。）');
    yield StreamDone();
  }

  static String _activityForTool(String name) {
    return switch (name) {
      'search_web' => '正在搜索',
      'read_memory' => '正在读取记忆',
      'write_memory' => '正在更新记忆',
      'read_todos' => '正在读取事项',
      'write_todo' => '正在创建事项',
      'read_signals' => '正在分析行为记录',
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

class AiRuntime {
  final AiTransport transport;
  late final StructuredAiService structured;
  late final ChatAgentService chat;
  late final WebSearchService search;

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
  }

  void close() => transport.close();
}
