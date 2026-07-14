import 'dart:convert';

import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// 结果类型
// ---------------------------------------------------------------------------

/// SplitResult —— AI 拆分判断结果。
class SplitResult {
  final bool split;
  final List<String> items;

  const SplitResult({required this.split, required this.items});

  factory SplitResult.fromJson(Map<String, Object?> json) {
    final items = (json['items'] as List<Object?>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    return SplitResult(
      split: (json['split'] as bool?) ?? false,
      items: items,
    );
  }

  factory SplitResult.single(String text) =>
      SplitResult(split: false, items: [text]);
}

// ---------------------------------------------------------------------------
// 规划相关结果类型
// ---------------------------------------------------------------------------

class MonthPlanItem {
  final int monthIndex;
  final String title;
  final String summary;

  const MonthPlanItem({
    required this.monthIndex,
    required this.title,
    required this.summary,
  });

  factory MonthPlanItem.fromJson(Map<String, Object?> json) => MonthPlanItem(
        monthIndex: (json['monthIndex'] as num?)?.toInt() ?? 0,
        title: (json['title'] as String?) ?? '',
        summary: (json['summary'] as String?) ?? '',
      );
}

class TodoSeed {
  final String title;
  final String? body;
  final String date; // "YYYY-MM-DD"

  const TodoSeed({
    required this.title,
    this.body,
    required this.date,
  });

  factory TodoSeed.fromJson(Map<String, Object?> json) => TodoSeed(
        title: (json['title'] as String?) ?? '',
        body: json['body'] as String?,
        date: (json['date'] as String?) ?? '',
      );
}

class PlanResult {
  final List<MonthPlanItem> monthPlans;
  final List<TodoSeed> todayTodos;

  const PlanResult({
    required this.monthPlans,
    required this.todayTodos,
  });

  factory PlanResult.fromJson(Map<String, Object?> json) {
    final monthPlansRaw = json['monthPlans'] as List<Object?>?;
    final todayTodosRaw = json['todayTodos'] as List<Object?>?;
    return PlanResult(
      monthPlans: monthPlansRaw
              ?.map(
                  (e) => MonthPlanItem.fromJson(e as Map<String, Object?>))
              .toList() ??
          [],
      todayTodos: todayTodosRaw
              ?.map((e) => TodoSeed.fromJson(e as Map<String, Object?>))
              .toList() ??
          [],
    );
  }
}

class DailyTodoResult {
  final List<TodoSeed> todos;

  const DailyTodoResult({required this.todos});

  factory DailyTodoResult.fromJson(Map<String, Object?> json) {
    final todosRaw = json['todos'] as List<Object?>?;
    return DailyTodoResult(
      todos: todosRaw
              ?.map((e) => TodoSeed.fromJson(e as Map<String, Object?>))
              .toList() ??
          [],
    );
  }
}

// ---------------------------------------------------------------------------
// Stream 事件类型（05 轮新增）
// ---------------------------------------------------------------------------

sealed class StreamEvent {}

class ContentDelta extends StreamEvent {
  final String text;
  ContentDelta(this.text);
}

class ReasoningDelta extends StreamEvent {
  final String text;
  ReasoningDelta(this.text);
}

class ToolCallsComplete extends StreamEvent {
  final List<ToolCall> calls;
  ToolCallsComplete(this.calls);
}

class StreamDone extends StreamEvent {}

// ---------------------------------------------------------------------------
// ToolCall
// ---------------------------------------------------------------------------

class ToolCall {
  final String id;
  final String name;
  final Map<String, Object?> arguments;

  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  factory ToolCall.fromMap(Map<String, Object?> map) {
    final func = map['function'] as Map<String, Object?>?;
    Object? rawArgs = func?['arguments'];
    Map<String, Object?> args;
    if (rawArgs is String) {
      try {
        args = (jsonDecode(rawArgs) as Map<String, Object?>)
            .map((k, v) => MapEntry(k, v));
      } catch (_) {
        args = {};
      }
    } else if (rawArgs is Map<String, Object?>) {
      args = rawArgs;
    } else {
      args = {};
    }
    return ToolCall(
      id: (map['id'] as String?) ?? '',
      name: (func?['name'] as String?) ?? '',
      arguments: args,
    );
  }
}

// ---------------------------------------------------------------------------
// AiService
// ---------------------------------------------------------------------------

class AiService {
  static const _baseUrl = 'https://api.deepseek.com/v1/chat/completions';

  // V4 系列模型
  static const _modelFlash = 'deepseek-v4-flash';
  static const _modelPro = 'deepseek-v4-pro';

  // ---------------------------------------------------------------------------
  // System prompts
  // ---------------------------------------------------------------------------

  static const _splitSystemPrompt = '你是 Sumi，一个自学个人助手的 AI 引擎。\n'
      '你的任务是将用户输入的长文本智能拆分为独立可执行的 todo 事项。\n'
      '\n'
      '规则：\n'
      '1. 如果文本描述的是单一事项（尽管很长），不要拆分，在 items 中返回一条凝练后的文本。\n'
      '2. 如果包含多个独立步骤或事项，拆分为独立 todo。\n'
      '3. 每条 todo 保留完整的语义，可脱离上下文理解。\n'
      '4. 每条 todo 凝练到 2-18 字。\n'
      '5. 以 JSON 格式回复，不要带任何额外文字。\n'
      '\n'
      '回复格式：\n'
      '{"split": true/false, "items": ["事项1", "事项2"]}';

  static const _planningSystemPrompt =
      '你是 Sumi，一个专业的自学规划师。\n'
          '\n'
          '用户正在创建一个自学项目，你需要根据项目信息为其生成完整的学习计划。\n'
          '\n'
          '## 要求\n'
          '\n'
          '### 月计划\n'
          '- 为每个月生成一个月计划卡\n'
          '- 每月有一个凝练的主题（5-15 字）和详细摘要（30-100 字）\n'
          '- 摘要要高维度、战略性，不要过于具体（具体步骤留给每日 todo）\n'
          '- 内容量匹配当月实际天数：如果起始月份剩余天数少（如只剩 6 天），计划应紧凑\n'
          '- 各月之间应有递进关系（基础 → 进阶 → 综合）\n'
          '\n'
          '### 每日 Todo（仅生成第一天的）\n'
          '- 基于第一个月计划拆解为具体的可执行 todo\n'
          '- 标题 2-20 字，可附带更详细的 body\n'
          '- 数量：1 条（默认）\n'
          '- 考虑每周投入时间约束，不要超出用户能力\n'
          '\n'
          '## 输出格式\n'
          '严格按以下 JSON 格式输出，不要带任何额外文字：\n'
          '\n'
          '{\n'
          '  "monthPlans": [\n'
          '    {"monthIndex": 0, "title": "月主题", "summary": "月计划摘要..."},\n'
          '    ...\n'
          '  ],\n'
          '  "todayTodos": [\n'
          '    {"title": "todo 标题", "body": "更详细的说明（可选）", "date": "YYYY-MM-DD"}\n'
          '  ]\n'
          '}';

  static const _dailyTodoSystemPrompt =
      '你是 Sumi。根据当前月计划，为指定日期生成 1 条系统 todo。\n'
          '\n'
          '要求：todo 标题 2-20 字，可附带 body。\n'
          '输出 JSON：{"todos": [{"title": "...", "body": "...", "date": "YYYY-MM-DD"}]}';

  // ---------------------------------------------------------------------------
  // 工具定义（05 轮新增）
  // ---------------------------------------------------------------------------

  static const _chatTools = [
    {
      'type': 'function',
      'function': {
        'name': 'search_web',
        'description': '搜索网络获取实时信息。当你需要了解最新信息、事实核查、查找资料时使用。',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': '搜索关键词',
            },
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_memory',
        'description': '读取 Sumi 自己的持久记忆（MEMORY.md）。MEMORY.md 记录的是 Sumi 的自我认知、从对话中学到的经验、以及对用户的理解。除非内容明确标注"用户："前缀，否则所有内容描述的都是 Sumi 自己。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'write_memory',
        'description': '将重要信息写入 Sumi 自己的记忆（MEMORY.md）。用于记录学到的经验、用户偏好、重要决策等。注意：MEMORY.md 默认记录的是 Sumi 自己的事；如果要记录关于用户的信息，请用"用户："前缀标注，例如"用户：偏好中文交流"。',
        'parameters': {
          'type': 'object',
          'properties': {
            'content': {
              'type': 'string',
              'description': '要写入的记忆内容。简洁、独立、可检索的事实陈述。不要写对话流水账。',
            },
          },
          'required': ['content'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_todos',
        'description': '查询当前的待办事项列表。',
        'parameters': {
          'type': 'object',
          'properties': {
            'filter': {
              'type': 'string',
              'description': '筛选条件：today（今日）、all（全部）、或 project:xxx（指定项目）',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'write_todo',
        'description': '创建一个新的待办事项。',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': '事项标题（2-20 字）',
            },
            'date': {
              'type': 'string',
              'description': '日期，格式 YYYY-MM-DD，可选',
            },
            'projectId': {
              'type': 'string',
              'description': '归属项目 ID，可选',
            },
            'body': {
              'type': 'string',
              'description': '详细说明，可选',
            },
          },
          'required': ['title'],
        },
      },
    },
  ];

  final String apiKey;
  final String? tavilyApiKey;
  final http.Client _client;

  AiService({
    required this.apiKey,
    this.tavilyApiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  // ---------------------------------------------------------------------------
  // 底层调用
  // ---------------------------------------------------------------------------

  /// 构建请求体参数。
  Map<String, Object?> _buildRequestParams({
    required String model,
    required List<Map<String, Object?>> messages,
    bool thinking = false,
    bool stream = false,
    List<Map<String, Object?>>? tools,
    String? responseFormat, // 'json_object' 或 null
    int maxTokens = 1000,
  }) {
    final body = <String, Object?>{
      'model': model,
      'messages': messages,
      'temperature': 1.0,
      'top_p': 1.0,
      'max_tokens': maxTokens,
    };
    if (stream) {
      body['stream'] = true;
    }
    if (thinking) {
      body['thinking_mode'] = 'thinking';
    }
    if (tools != null) {
      body['tools'] = tools;
    }
    if (responseFormat != null) {
      body['response_format'] = {'type': responseFormat};
    }
    return body;
  }

  /// 非流式 JSON 调用（通用）。
  Future<Map<String, Object?>?> _callJsonApi({
    required String systemPrompt,
    required String userPrompt,
    required String model,
    bool thinking = false,
    int maxTokens = 2000,
    int timeoutSeconds = 60,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(_buildRequestParams(
              model: model,
              messages: [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userPrompt},
              ],
              thinking: thinking,
              responseFormat: 'json_object',
              maxTokens: maxTokens,
            )),
          )
          .timeout(Duration(seconds: timeoutSeconds));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, Object?>;
      final choices = body['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) return null;

      final message = (choices.first as Map<String, Object?>?)?['message']
          as Map<String, Object?>?;
      if (message == null) return null;

      final content = message['content'] as String?;
      if (content == null) return null;

      return jsonDecode(content) as Map<String, Object?>;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Todo 拆分
  // ---------------------------------------------------------------------------

  Future<SplitResult?> splitTodo(String text) async {
    final result = await _callJsonApi(
      systemPrompt: _splitSystemPrompt,
      userPrompt: text,
      model: _modelFlash,
      thinking: false,
      maxTokens: 500,
      timeoutSeconds: 15,
    );
    if (result == null) return null;
    return SplitResult.fromJson(result);
  }

  // ---------------------------------------------------------------------------
  // 润色
  // ---------------------------------------------------------------------------

  Future<String?> polishTodo(String text) async {
    final result = await _callJsonApi(
      systemPrompt: '你是 Sumi，一个个人助手。你的任务是优化用户提供的 todo 标题。\n'
          '要求：凝练清晰、保留原意、2-18 字。\n'
          '以 JSON 格式回复：{"result": "优化后的文本"}',
      userPrompt: text,
      model: _modelFlash,
      thinking: false,
      maxTokens: 100,
      timeoutSeconds: 10,
    );
    if (result == null) return null;
    return (result['result'] as String?)?.trim();
  }

  // ---------------------------------------------------------------------------
  // 项目规划（05 轮：切到 pro + thinking）
  // ---------------------------------------------------------------------------

  Future<PlanResult?> generateProjectPlan({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String startDate,
  }) async {
    final userPrompt = '''
## 输入信息
- 项目目标：$goal
- 当前水平：$level
- 规划周期：$cycleMonths 个月
- 每周投入时间：$timeConstraint 小时
- 起始日期：$startDate

请生成 $cycleMonths 个月的月计划卡和第一天的 todo。''';

    final result = await _callJsonApi(
      systemPrompt: _planningSystemPrompt,
      userPrompt: userPrompt,
      model: _modelPro,
      thinking: true,
      maxTokens: 3000,
      timeoutSeconds: 60,
    );
    if (result == null) return null;
    return PlanResult.fromJson(result);
  }

  // ---------------------------------------------------------------------------
  // 每日 todo 生成
  // ---------------------------------------------------------------------------

  Future<DailyTodoResult?> generateDailyTodos({
    required String monthPlanTitle,
    required String monthPlanSummary,
    required String date,
    required int timeConstraint,
    required int scheduledHours,
  }) async {
    final userPrompt = '''
月计划：$monthPlanTitle — $monthPlanSummary
日期：$date
本周已安排的小时数：$scheduledHours / $timeConstraint''';

    final result = await _callJsonApi(
      systemPrompt: _dailyTodoSystemPrompt,
      userPrompt: userPrompt,
      model: _modelFlash,
      thinking: false,
      maxTokens: 500,
      timeoutSeconds: 30,
    );
    if (result == null) return null;
    return DailyTodoResult.fromJson(result);
  }

  // ---------------------------------------------------------------------------
  // Tavily 搜索（05 轮新增）
  // ---------------------------------------------------------------------------

  /// 调用 Tavily Search API，返回格式化结果列表。
  Future<List<Map<String, String>>> searchWeb(String query) async {
    if (tavilyApiKey == null || tavilyApiKey!.isEmpty) {
      return [{'error': 'Tavily API Key 未配置'}];
    }
    try {
      final response = await _client
          .post(
            Uri.parse('https://api.tavily.com/search'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'api_key': tavilyApiKey,
              'query': query,
              'search_depth': 'basic',
              'max_results': 5,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return [{'error': '搜索失败（${response.statusCode}）'}];
      }

      final body = jsonDecode(response.body) as Map<String, Object?>;
      final results = body['results'] as List<Object?>?;
      if (results == null || results.isEmpty) {
        return [{'info': '未找到相关结果'}];
      }

      return results.take(5).map((r) {
        final m = r as Map<String, Object?>;
        return {
          'title': (m['title'] as String?) ?? '',
          'url': (m['url'] as String?) ?? '',
          'content': (m['content'] as String?) ?? '',
        };
      }).toList();
    } catch (_) {
      return [{'error': '搜索请求超时或网络错误'}];
    }
  }

  // ---------------------------------------------------------------------------
  // 流式对话（05 轮重写：Stream<StreamEvent> + thinking + tools）
  // ---------------------------------------------------------------------------

  /// Streaming 对话，返回 [StreamEvent]。
  /// [messages] 为完整消息历史（含 system prompt + 历史对话 + 当前用户消息）。
  /// 每条 assistant 消息应包含 `reasoning_content` 字段（如果有）。
  Stream<StreamEvent> streamChatMessages(
    List<Map<String, Object?>> messages, {
    bool thinkingEnabled = true,
  }) async* {
    try {
      final request = http.Request('POST', Uri.parse(_baseUrl));
      request.headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      });
      request.body = jsonEncode(_buildRequestParams(
        model: _modelFlash,
        messages: messages,
        thinking: thinkingEnabled,
        stream: true,
        tools: _chatTools,
        maxTokens: 2000,
      ));

      final streamedResponse =
          await _client.send(request).timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) return;

      // tool_calls 增量解析状态
      final toolCallBufs = <int, _ToolCallBuf>{};

      await for (final chunk in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final trimmed = chunk.trim();
        if (!trimmed.startsWith('data: ')) continue;

        final data = trimmed.substring(6);
        if (data == '[DONE]') break;

        try {
          final json = jsonDecode(data) as Map<String, Object?>;
          final choices = json['choices'] as List<Object?>?;
          if (choices == null || choices.isEmpty) continue;

          final delta = (choices.first as Map<String, Object?>?)?['delta']
              as Map<String, Object?>?;
          if (delta == null) continue;

          // 文本内容
          final content = delta['content'] as String?;
          if (content != null && content.isNotEmpty) {
            yield ContentDelta(content);
          }

          // 思考过程
          final reasoning =
              delta['reasoning_content'] as String?;
          if (reasoning != null && reasoning.isNotEmpty) {
            yield ReasoningDelta(reasoning);
          }

          // 工具调用
          final toolCalls = delta['tool_calls'] as List<Object?>?;
          if (toolCalls != null) {
            for (final tc in toolCalls) {
              if (tc is! Map<String, Object?>) continue;
              final index = (tc['index'] as num?)?.toInt() ?? 0;
              final buf = toolCallBufs.putIfAbsent(
                index,
                () => _ToolCallBuf(),
              );

              final id = tc['id'] as String?;
              if (id != null) buf.id = id;

              final func = tc['function'] as Map<String, Object?>?;
              if (func != null) {
                final name = func['name'] as String?;
                if (name != null) buf.name = name;
                final args = func['arguments'] as String?;
                if (args != null) buf.arguments.write(args);
              }
            }
          }
        } catch (_) {
          // 跳过无法解析的 chunk
        }
      }

      // 流结束后：检查是否有完成拼接的 tool_calls
      if (toolCallBufs.isNotEmpty) {
        final calls = <ToolCall>[];
        // 按 index 排序
        final sortedKeys = toolCallBufs.keys.toList()..sort();
        for (final key in sortedKeys) {
          final buf = toolCallBufs[key]!;
          if (buf.name.isNotEmpty) {
            calls.add(ToolCall(
              id: buf.id,
              name: buf.name,
              arguments: ToolCall.fromMap({
                'function': {
                  'arguments': buf.arguments.toString(),
                },
              }).arguments,
            ));
          }
        }
        if (calls.isNotEmpty) {
          yield ToolCallsComplete(calls);
        }
      }

      yield StreamDone();
    } catch (_) {
      // stream 异常时静默结束
    }
  }

  /// 简化版流式对话（单条 prompt，兼容旧接口）。
  Stream<StreamEvent> streamChat(String prompt) async* {
    yield* streamChatMessages([
      {'role': 'user', 'content': prompt},
    ]);
  }

  // ---------------------------------------------------------------------------
  // Agent Loop（05 轮新增）
  // ---------------------------------------------------------------------------

  /// 执行 Agent Loop：多轮 tool calling 直到 AI 给出最终回复或达到上限。
  Stream<StreamEvent> sendAgentLoop({
    required List<Map<String, Object?>> messages,
    required Future<String> Function(ToolCall call) executeTool,
    bool thinkingEnabled = true,
    int maxTurns = 5,
  }) async* {
    for (var turn = 0; turn < maxTurns; turn++) {
      List<ToolCall>? pendingCalls;
      final contentBuf = StringBuffer();
      final reasoningBuf = StringBuffer();

      await for (final event in streamChatMessages(messages,
          thinkingEnabled: thinkingEnabled)) {
        switch (event) {
          case ContentDelta(text: final t):
            contentBuf.write(t);
            yield event;
          case ReasoningDelta(text: final t):
            reasoningBuf.write(t);
            yield event;
          case ToolCallsComplete(calls: final calls):
            pendingCalls = calls;
          case StreamDone():
            break;
        }
      }

      // 将 assistant 消息（含 content + reasoning_content + tool_calls）加入历史
      // 必须在 tool 结果之前添加，否则 API 会因消息序列非法而报错
      final assistantMsg = <String, Object?>{
        'role': 'assistant',
        'content': contentBuf.toString(),
      };
      if (reasoningBuf.isNotEmpty) {
        assistantMsg['reasoning_content'] = reasoningBuf.toString();
      }
      if (pendingCalls != null && pendingCalls.isNotEmpty) {
        assistantMsg['tool_calls'] = pendingCalls.map((c) => {
          'id': c.id,
          'type': 'function',
          'function': {
            'name': c.name,
            'arguments': jsonEncode(c.arguments),
          },
        }).toList();
      }
      messages.add(assistantMsg);

      // 无 tool_calls → 结束
      if (pendingCalls == null || pendingCalls.isEmpty) return;

      // 执行工具并追加 tool 结果消息
      for (final call in pendingCalls) {
        final result = await executeTool(call);
        messages.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'content': result,
        });
      }
    }

    // 达到最大轮数：发送总结请求
    yield ContentDelta('\n\n（已达最大轮数，以上为我能获取的信息。）');
    yield StreamDone();
  }

  // ---------------------------------------------------------------------------
  // 预留：非流式对话
  // ---------------------------------------------------------------------------

  Future<String?> chat(String prompt) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(_buildRequestParams(
              model: _modelFlash,
              messages: [
                {'role': 'user', 'content': prompt},
              ],
              thinking: false,
              maxTokens: 1000,
            )),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, Object?>;
      final choices = body['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) return null;

      final message = (choices.first as Map<String, Object?>?)?['message']
          as Map<String, Object?>?;
      return message?['content'] as String?;
    } catch (_) {
      return null;
    }
  }
}

/// tool_calls 增量解析缓冲。
class _ToolCallBuf {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}
