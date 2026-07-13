import 'dart:convert';

import 'package:http/http.dart' as http;

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

  /// 单条结果（无需拆分）。
  factory SplitResult.single(String text) =>
      SplitResult(split: false, items: [text]);
}

// ---------------------------------------------------------------------------
// 规划相关结果类型
// ---------------------------------------------------------------------------

/// AI 返回的月计划条目。
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

/// AI 返回的 todo 种子。
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

/// AI 规划完整结果。
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
              ?.map((e) =>
                  MonthPlanItem.fromJson(e as Map<String, Object?>))
              .toList() ??
          [],
      todayTodos: todayTodosRaw
              ?.map(
                  (e) => TodoSeed.fromJson(e as Map<String, Object?>))
              .toList() ??
          [],
    );
  }
}

/// 每日 todo 生成结果。
class DailyTodoResult {
  final List<TodoSeed> todos;

  const DailyTodoResult({required this.todos});

  factory DailyTodoResult.fromJson(Map<String, Object?> json) {
    final todosRaw = json['todos'] as List<Object?>?;
    return DailyTodoResult(
      todos: todosRaw
              ?.map(
                  (e) => TodoSeed.fromJson(e as Map<String, Object?>))
              .toList() ??
          [],
    );
  }
}

// ---------------------------------------------------------------------------
// AiService
// ---------------------------------------------------------------------------

/// DeepSeek API 调用服务。
class AiService {
  static const _baseUrl = 'https://api.deepseek.com/v1/chat/completions';
  static const _model = 'deepseek-chat';

  static const _splitSystemPrompt = '你是 Sumi，一个自学个人助手的 AI 引擎。\n'
      '你的任务是将用户输入的长文本智能拆分为独立可执行的 todo 事项。\n'
      '\n'
      '规则：\n'
      '1. 如果文本描述的是单一事项（尽管很长），不要拆分。\n'
      '2. 如果包含多个独立步骤或事项，拆分为独立 todo。\n'
      '3. 每条 todo 保留完整的语义，可脱离上下文理解。\n'
      '4. 拆分后每条 2-20 字为宜。\n'
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

  final String apiKey;
  final http.Client _client;

  AiService({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  // ---------------------------------------------------------------------------
  // 底层调用
  // ---------------------------------------------------------------------------

  /// 非流式 JSON 调用。
  Future<Map<String, Object?>?> _callJsonApi({
    required String systemPrompt,
    required String userPrompt,
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
            body: jsonEncode({
              'model': _model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userPrompt},
              ],
              'response_format': {'type': 'json_object'},
              'max_tokens': maxTokens,
            }),
          )
          .timeout(Duration(seconds: timeoutSeconds));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, Object?>;
      final choices = body['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) return null;

      final message = (choices.first as Map<String, Object?>)['message']
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
  // Todo 拆分（03 轮）
  // ---------------------------------------------------------------------------

  /// Todo 拆分判断。
  /// 返回 null = 调用失败，调用方应降级为直接创建。
  Future<SplitResult?> splitTodo(String text) async {
    final result = await _callJsonApi(
      systemPrompt: _splitSystemPrompt,
      userPrompt: text,
      maxTokens: 500,
      timeoutSeconds: 15,
    );
    if (result == null) return null;
    return SplitResult.fromJson(result);
  }

  /// 润色 todo 标题 —— 调用 AI 优化表达，返回润色后文本。
  /// 返回 null = 调用失败。
  Future<String?> polishTodo(String text) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      '你是 Sumi，一个个人助手。你的任务是优化用户提供的 todo 标题。\n'
                          '要求：凝练清晰、保留原意、2-20 字、只返回优化后的文本，不要加引号或额外文字。',
                },
                {'role': 'user', 'content': text},
              ],
              'max_tokens': 100,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, Object?>;
      final choices = body['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) return null;

      final message = (choices.first as Map<String, Object?>)['message']
          as Map<String, Object?>?;
      if (message == null) return null;

      final content = message['content'] as String?;
      return content?.trim();
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // 项目规划（04 轮新增）
  // ---------------------------------------------------------------------------

  /// 项目规划：根据项目信息生成全部月计划 + 当天 todo。
  /// 返回 null = 失败。
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
      maxTokens: 3000,
      timeoutSeconds: 60,
    );
    if (result == null) return null;
    return PlanResult.fromJson(result);
  }

  /// 生成指定日期的系统 todo（基于给定月卡）。
  /// 返回 null = 失败。
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
      maxTokens: 500,
      timeoutSeconds: 30,
    );
    if (result == null) return null;
    return DailyTodoResult.fromJson(result);
  }

  // ---------------------------------------------------------------------------
  // 对话（03 轮 reserve，04 轮完善）
  // ---------------------------------------------------------------------------

  /// Streaming 对话 —— 返回逐 chunk 的 delta content。
  /// [messages] 为完整消息历史（含 system prompt + 历史对话 + 当前用户消息）。
  Stream<String> streamChatMessages(
      List<Map<String, String>> messages) async* {
    try {
      final request = http.Request('POST', Uri.parse(_baseUrl));
      request.headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      });
      request.body = jsonEncode({
        'model': _model,
        'messages': messages,
        'stream': true,
        'max_tokens': 1000,
      });

      final streamedResponse =
          await _client.send(request).timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) return;

      await for (final chunk in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final trimmed = chunk.trim();
        if (!trimmed.startsWith('data: ')) continue;

        final data = trimmed.substring(6);
        if (data == '[DONE]') return;

        try {
          final json = jsonDecode(data) as Map<String, Object?>;
          final choices = json['choices'] as List<Object?>?;
          if (choices == null || choices.isEmpty) continue;

          final delta = (choices.first as Map<String, Object?>?)?['delta']
              as Map<String, Object?>?;
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            yield content;
          }
        } catch (_) {
          // 跳过无法解析的 chunk
        }
      }
    } catch (_) {
      // stream 异常时静默结束
    }
  }

  /// 简化版流式对话（单条 prompt，03 轮兼容）。
  Stream<String> streamChat(String prompt) async* {
    yield* streamChatMessages([
      {'role': 'user', 'content': prompt},
    ]);
  }

  /// 预留：通用非流式对话。
  Future<String?> chat(String prompt) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
              'max_tokens': 1000,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, Object?>;
      final choices = body['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) return null;

      final message = (choices.first as Map<String, Object?>)['message']
          as Map<String, Object?>?;
      return message?['content'] as String?;
    } catch (_) {
      return null;
    }
  }
}
