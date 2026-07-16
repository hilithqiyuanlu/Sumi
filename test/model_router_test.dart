import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sumi/models/models.dart';
import 'package:sumi/services/ai_runtime.dart';
import 'package:sumi/services/ai_service.dart';
import 'package:sumi/services/model_router.dart';
import 'package:sumi/services/model_router_metrics.dart';
import 'package:sumi/services/memory_extraction.dart';

http.Response _jsonResponse(Object content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': content},
      },
    ],
  }),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

http.Response _sseResponse(Map<String, Object?> delta) => http.Response(
  'data: ${jsonEncode({
    'choices': [
      {'delta': delta},
    ],
  })}\n\ndata: [DONE]\n\n',
  200,
  headers: const {'content-type': 'text/event-stream; charset=utf-8'},
);

class _Metrics implements ModelRouterMetricsSink {
  final values = <ModelRouterMetric>[];

  @override
  void record(ModelRouterMetric metric) => values.add(metric);
}

class _Provider implements ModelProvider {
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

  const _Provider({
    required this.id,
    required this.chat,
    required this.structured,
    required this.memoryExtraction,
    required this.search,
  });
}

class _MemoryExtraction implements MemoryExtractionCapability {
  @override
  Future<MemoryExtractionDecision?> extractMemory({
    required String message,
    required List<MemoryExtractionCandidate> candidates,
  }) async => null;
}

class _Chat implements ChatCapability {
  final Stream<StreamEvent> Function() events;
  int calls = 0;

  _Chat(this.events);

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
    calls++;
    return events();
  }
}

class _Structured implements StructuredGenerationCapability {
  String? receivedSplitText;
  final SplitResult? splitResult;

  _Structured({this.splitResult});

  @override
  String? get lastError => null;

  @override
  Future<SplitResult?> splitTodo(String text) async {
    receivedSplitText = text;
    return splitResult;
  }

  @override
  Future<String?> polishTodo(String text) async => text;

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
  }) async => null;

  @override
  Future<DailyTodoResult?> generateDailyTodos({
    required String monthPlanTitle,
    required String monthPlanSummary,
    required String date,
    required int timeConstraint,
    required int scheduledHours,
  }) async => null;

  @override
  Future<WeeklyTodoResult?> generateWeeklyTodos({
    required String monthPlanTitle,
    required String monthPlanSummary,
    required List<String> dates,
    required int timeConstraint,
    required int scheduledHours,
  }) async => null;

  @override
  Future<GoalAssessment?> assessGoal({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String domainContext,
  }) async => null;
}

class _Search implements WebSearchCapability {
  @override
  final bool isConfigured;
  final List<Map<String, String>> result;
  String? query;

  _Search({required this.isConfigured, this.result = const []});

  @override
  Future<List<Map<String, String>>> search(String value) async {
    query = value;
    return result;
  }
}

void main() {
  test('初始路由固定使用云端 Provider，并透传结构化调用', () async {
    final metrics = _Metrics();
    final structured = _Structured(
      splitResult: const SplitResult(split: false, items: ['阅读文档']),
    );
    final router = ModelRouter(
      cloudProvider: _Provider(
        id: 'cloud-primary',
        chat: _Chat(() => Stream.value(StreamDone())),
        structured: structured,
        memoryExtraction: _MemoryExtraction(),
        search: _Search(isConfigured: false),
      ),
      metrics: metrics,
      clock: () => DateTime(2026, 7, 15),
    );

    final result = await router.structured.splitTodo('阅读一篇很长的技术文档');

    expect(result?.items, ['阅读文档']);
    expect(structured.receivedSplitText, '阅读一篇很长的技术文档');
    expect(metrics.values, hasLength(1));
    expect(metrics.values.single.capability, ModelCapability.structured);
    expect(metrics.values.single.provider, 'cloud-primary');
    expect(metrics.values.single.outcome, ModelRouteOutcome.success);
  });

  test('云端结构化格式修复仍只重试一次', () async {
    var requests = 0;
    final runtime = AiRuntime(
      apiKey: 'key',
      httpClient: MockClient((_) async {
        requests++;
        return _jsonResponse(
          requests == 1 ? 'not json' : '{"split":false,"items":["阅读文档"]}',
        );
      }),
    );
    addTearDown(runtime.close);
    final router = ModelRouter.fromRuntime(runtime);

    final result = await router.structured.splitTodo('阅读文档');

    expect(result?.items, ['阅读文档']);
    expect(requests, 2);
  });

  test('非法工具参数不会执行工具，聊天仍能继续生成', () async {
    var requests = 0;
    var executions = 0;
    final client = MockClient((_) async {
      requests++;
      if (requests == 1) {
        return _sseResponse({
          'tool_calls': [
            {
              'index': 0,
              'id': 'invalid-project',
              'function': {
                'name': 'write_todo',
                'arguments': jsonEncode({
                  'title': '整理学习笔记',
                  'projectId': 'missing',
                }),
              },
            },
          ],
        });
      }
      return _sseResponse({'content': '已完成'});
    });
    final runtime = AiRuntime.fromClient(
      AiService(apiKey: 'key', client: client),
    );
    addTearDown(runtime.close);
    final router = ModelRouter.fromRuntime(runtime);

    final events = await router.chat
        .sendAgentLoop(
          messages: [
            {'role': 'user', 'content': '创建事项'},
          ],
          validProjectIds: {'project-1'},
          executeTool: (_) async {
            executions++;
            return '不应执行';
          },
        )
        .toList();

    expect(executions, 0);
    expect(requests, 2);
    expect(
      events.whereType<ContentDelta>().map((event) => event.text),
      contains('已完成'),
    );
  });

  test('聊天 401 和 429 产生可分类的失败指标', () async {
    for (final entry in <(int, ModelRouterErrorCategory)>[
      (401, ModelRouterErrorCategory.authentication),
      (429, ModelRouterErrorCategory.rateLimited),
    ]) {
      final metrics = _Metrics();
      final runtime = AiRuntime(
        apiKey: 'key',
        httpClient: MockClient((_) async => http.Response('failure', entry.$1)),
      );
      addTearDown(runtime.close);
      final router = ModelRouter.fromRuntime(runtime, metrics: metrics);

      final events = await router.chat
          .sendAgentLoop(
            messages: [
              {'role': 'user', 'content': '测试错误'},
            ],
            executeTool: (_) async => '',
          )
          .toList();

      expect(events.whereType<AgentErrorEvent>(), hasLength(1));
      expect(metrics.values, hasLength(1));
      expect(metrics.values.single.outcome, ModelRouteOutcome.failure);
      expect(metrics.values.single.errorCategory, entry.$2);
    }
  });

  test('搜索能力保留已配置和未配置状态，并只记录匿名结果', () async {
    final metrics = _Metrics();
    final configured = _Search(
      isConfigured: true,
      result: const [
        {'title': '来源标题', 'content': '包含用户的检索内容'},
      ],
    );
    final configuredRouter = ModelRouter(
      cloudProvider: _Provider(
        id: 'cloud',
        chat: _Chat(() => Stream.value(StreamDone())),
        structured: _Structured(),
        memoryExtraction: _MemoryExtraction(),
        search: configured,
      ),
      metrics: metrics,
    );
    final unavailable = _Search(isConfigured: false);
    final unavailableRouter = ModelRouter(
      cloudProvider: _Provider(
        id: 'cloud',
        chat: _Chat(() => Stream.value(StreamDone())),
        structured: _Structured(),
        memoryExtraction: _MemoryExtraction(),
        search: unavailable,
      ),
    );

    expect(configuredRouter.search.isConfigured, isTrue);
    expect(await configuredRouter.search.search('用户私密检索词'), hasLength(1));
    expect(configured.query, '用户私密检索词');
    expect(unavailableRouter.search.isConfigured, isFalse);
    expect(metrics.values.single.capability, ModelCapability.webSearch);
    expect(metrics.values.single.provider, 'cloud');
  });

  test('诊断指标仅保存聚合字段，并在第八天清理过期数据', () {
    final now = DateTime(2026, 7, 15, 12);
    final store = ModelRouterMetricsStore(now: () => now);
    store.record(
      ModelRouterMetric(
        occurredAt: now.subtract(const Duration(days: 7)),
        capability: ModelCapability.chat,
        provider: 'cloud',
        outcome: ModelRouteOutcome.success,
        elapsed: const Duration(milliseconds: 20),
      ),
    );
    store.record(
      ModelRouterMetric(
        occurredAt: now.subtract(const Duration(days: 6)),
        capability: ModelCapability.structured,
        provider: 'cloud',
        outcome: ModelRouteOutcome.failure,
        elapsed: const Duration(milliseconds: 30),
        errorCategory: ModelRouterErrorCategory.validation,
      ),
    );

    final json = store.toJson();
    final serialized = jsonEncode(json);
    final buckets = json['buckets'] as List<Object?>;

    expect(store.summaries(), hasLength(1));
    expect(store.summaries().single.capability, ModelCapability.structured);
    expect(buckets.single, isA<Map<String, Object?>>());
    expect(serialized, isNot(contains('prompt')));
    expect(serialized, isNot(contains('response')));
    expect(serialized, isNot(contains('content')));
    expect(serialized, isNot(contains('argument')));
  });
}
