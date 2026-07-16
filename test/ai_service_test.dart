import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sumi/services/ai_service.dart';
import 'package:sumi/services/ai_runtime.dart';
import 'package:sumi/services/memory_extraction.dart';

http.Response _jsonChatResponse(Object content, {int statusCode = 200}) {
  const headers = {'content-type': 'application/json; charset=utf-8'};
  if (statusCode != 200) {
    return http.Response(
      jsonEncode({
        'error': {'message': 'request failed'},
      }),
      statusCode,
      headers: headers,
    );
  }
  return http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'content': content},
        },
      ],
    }),
    statusCode,
    headers: headers,
  );
}

String _sse(Map<String, Object?> delta) {
  return 'data: ${jsonEncode({
    'choices': [
      {'delta': delta},
    ],
  })}\n\ndata: [DONE]\n\n';
}

void main() {
  test('合法结构化结果只请求一次且温度为 0.2', () async {
    var calls = 0;
    double? temperature;
    final client = MockClient((request) async {
      calls++;
      temperature =
          (jsonDecode(request.body) as Map<String, Object?>)['temperature']
              as double?;
      return _jsonChatResponse('{"split":false,"items":["阅读文档"]}');
    });

    final result = await AiService(
      apiKey: 'key',
      client: client,
    ).splitTodo('阅读文档');
    expect(result?.items, ['阅读文档']);
    expect(calls, 1);
    expect(temperature, 0.2);
  });

  test('错误 JSON 会修复重试一次', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return _jsonChatResponse(
        calls == 1 ? 'not json' : '{"split":false,"items":["阅读文档"]}',
      );
    });

    final result = await AiService(
      apiKey: 'key',
      client: client,
    ).splitTodo('阅读文档');
    expect(result, isNotNull);
    expect(calls, 2);
  });

  test('越界字段会修复重试一次', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return _jsonChatResponse(
        calls == 1
            ? '{"split":false,"items":["过"]}'
            : '{"split":false,"items":["阅读文档"]}',
      );
    });

    final result = await AiService(
      apiKey: 'key',
      client: client,
    ).splitTodo('阅读文档');
    expect(result, isNotNull);
    expect(calls, 2);
  });

  test('401 和限流不做格式重试', () async {
    for (final status in [401, 429]) {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return _jsonChatResponse('', statusCode: status);
      });
      final result = await AiService(
        apiKey: 'key',
        client: client,
      ).splitTodo('阅读文档');
      expect(result, isNull);
      expect(calls, 1, reason: 'HTTP $status 不应重试');
    }
  });

  test('网络或超时异常不做格式重试', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      throw TimeoutException('timeout');
    });
    final result = await AiService(
      apiKey: 'key',
      client: client,
    ).splitTodo('阅读文档');
    expect(result, isNull);
    expect(calls, 1);
  });

  test('今日负荷轻检测只发送当天数据，不生成排期字段', () async {
    Map<String, Object?>? requestBody;
    final client = MockClient((request) async {
      requestBody = jsonDecode(request.body) as Map<String, Object?>;
      return _jsonChatResponse('{"risk":0.75,"reasons":["两个深度任务连续安排，切换成本较高"]}');
    });

    final result = await AiService(apiKey: 'key', client: client)
        .screenTodayLoad(
          date: '2026-07-16',
          todos: const [
            {'id': 'todo-1', 'title': '完成章节练习', 'projectName': '英语阅读'},
          ],
        );

    expect(result?.needsAttention, isTrue);
    expect(requestBody?['temperature'], 0.2);
    expect(requestBody?['max_tokens'], 300);
    final messages = requestBody?['messages'] as List<Object?>;
    final prompt = (messages.last as Map<String, Object?>)['content'] as String;
    expect(prompt, contains('todo-1'));
    expect(prompt, isNot(contains('futureDays')));
    expect(prompt, isNot(contains('movableTodoIds')));
  });

  test('记忆提取只发送当前消息和最多三条候选，且不重试', () async {
    var calls = 0;
    Map<String, Object?>? requestBody;
    final client = MockClient((request) async {
      calls++;
      requestBody = jsonDecode(request.body) as Map<String, Object?>;
      return _jsonChatResponse('''{
        "action":"save","category":"preference",
        "content":"偏好短时练习","quotedText":"我长期偏好短时练习"
      }''');
    });
    final result = await AiService(apiKey: 'key', client: client).extractMemory(
      message: '我长期偏好短时练习。${'x' * 500}',
      candidates: [
        for (var index = 0; index < 4; index++)
          MemoryExtractionCandidate(
            id: 'memory-$index',
            category: 'preference',
            content: '候选内容$index${'y' * 100}',
          ),
      ],
    );
    expect(result?.action, MemoryExtractionAction.save);
    expect(calls, 1);
    expect(requestBody?['model'], 'deepseek-v4-flash');
    expect(requestBody?['max_tokens'], 120);
    final messages = requestBody?['messages'] as List<Object?>;
    final payload = jsonDecode(
      ((messages.last as Map<String, Object?>)['content'] as String),
    ) as Map<String, Object?>;
    expect((payload['message'] as String).length, 240);
    expect((payload['candidates'] as List<Object?>), hasLength(3));
  });

  test('评估接口不支持 response_format 时自动降级一次', () async {
    var calls = 0;
    final bodies = <Map<String, Object?>>[];
    final client = MockClient((request) async {
      calls++;
      bodies.add(jsonDecode(request.body) as Map<String, Object?>);
      if (calls == 1) {
        return _jsonChatResponse('', statusCode: 400);
      }
      return _jsonChatResponse(
        jsonEncode({
          'clarity': 0.8,
          'feasibility': 0.8,
          'challengeFit': 0.7,
          'decomposability': 0.7,
          'timeRealism': 0.6,
          'motivationPotential': 0.5,
          'resourceAccess': 0.9,
          'measurability': 0.8,
          'verdict': 'a',
          'concerns': <String>[],
          'suggestions': <String>[],
          'goalSummary': '学习测试技术',
        }),
      );
    });

    final result = await AiTransport(apiKey: 'key', client: client).assessGoal(
      goal: '学习测试技术',
      level: '零基础',
      cycleMonths: 1,
      timeConstraint: 6,
      domainContext: '测试资料',
    );

    expect(result?.goalSummary, '学习测试技术');
    expect(calls, 2);
    expect(bodies.first.containsKey('response_format'), isTrue);
    expect(bodies.last.containsKey('response_format'), isFalse);
  });

  test('非法工具参数不会执行工具，并作为不可信结果返回模型', () async {
    var requests = 0;
    var executions = 0;
    final requestBodies = <Map<String, Object?>>[];
    final client = MockClient((request) async {
      requests++;
      requestBodies.add(jsonDecode(request.body) as Map<String, Object?>);
      if (requests == 1) {
        return http.Response(
          _sse({
            'tool_calls': [
              {
                'index': 0,
                'id': 'call-1',
                'function': {
                  'name': 'write_todo',
                  'arguments': jsonEncode({
                    'title': '整理学习笔记',
                    'projectId': 'missing',
                  }),
                },
              },
            ],
          }),
          200,
          headers: const {'content-type': 'text/event-stream; charset=utf-8'},
        );
      }
      return http.Response(
        _sse({'content': '已修正。'}),
        200,
        headers: const {'content-type': 'text/event-stream; charset=utf-8'},
      );
    });

    final service = AiRuntime.fromClient(
      AiService(apiKey: 'key', client: client),
    );
    final events = await service.chat
        .sendAgentLoop(
          messages: [
            {'role': 'user', 'content': '创建事项'},
          ],
          validProjectIds: {'project-1'},
          executeTool: (call) async {
            executions++;
            return '不应执行';
          },
        )
        .toList();

    expect(executions, 0);
    expect(requests, 2);
    expect(
      events.whereType<ContentDelta>().map((event) => event.text),
      contains('已修正。'),
    );
    final secondMessages = requestBodies[1]['messages'] as List<Object?>;
    final toolMessage = secondMessages.cast<Map<String, Object?>>().lastWhere(
      (message) => message['role'] == 'tool',
    );
    expect(toolMessage['content'], contains('"trust":"data_only"'));
    expect(toolMessage['content'], contains('projectId 不存在'));
  });

  test('Agent Loop 不向调用方暴露原始推理', () async {
    final client = MockClient((request) async {
      return http.Response(
        _sse({'reasoning_content': '内部推理', 'content': '最终回答'}),
        200,
        headers: const {'content-type': 'text/event-stream; charset=utf-8'},
      );
    });
    final runtime = AiRuntime.fromClient(
      AiService(apiKey: 'key', client: client),
    );
    final events = await runtime.chat
        .sendAgentLoop(
          messages: [
            {'role': 'user', 'content': '问题'},
          ],
          executeTool: (call) async => '',
        )
        .toList();

    expect(events.whereType<ReasoningDelta>(), isEmpty);
    expect(events.whereType<ContentDelta>().single.text, '最终回答');
  });

  test('原始推理不进入下一次工具循环请求', () async {
    var calls = 0;
    final bodies = <Map<String, Object?>>[];
    final client = MockClient((request) async {
      calls++;
      bodies.add(jsonDecode(request.body) as Map<String, Object?>);
      if (calls == 1) {
        return http.Response(
          _sse({
            'reasoning_content': '内部推理',
            'tool_calls': [
              {
                'index': 0,
                'id': 'call-memory',
                'function': {'name': 'read_memory', 'arguments': '{}'},
              },
            ],
          }),
          200,
          headers: const {'content-type': 'text/event-stream; charset=utf-8'},
        );
      }
      return http.Response(
        _sse({'content': '完成'}),
        200,
        headers: const {'content-type': 'text/event-stream; charset=utf-8'},
      );
    });
    final runtime = AiRuntime.fromClient(
      AiService(apiKey: 'key', client: client),
    );

    await runtime.chat
        .sendAgentLoop(
          messages: [
            {'role': 'user', 'content': '读取记忆'},
          ],
          executeTool: (_) async => '记忆数据',
        )
        .toList();

    final messages = bodies[1]['messages'] as List<Object?>;
    final assistant = messages.cast<Map<String, Object?>>().firstWhere(
      (message) => message['role'] == 'assistant',
    );
    expect(assistant.containsKey('reasoning_content'), isFalse);
  });
}
