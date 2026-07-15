import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'ai_contracts.dart';
import 'memory_extraction.dart';
import 'prompt_context.dart';

// ---------------------------------------------------------------------------
// 结果类型
// ---------------------------------------------------------------------------

/// SplitResult —— AI 拆分判断结果。
class SplitResult {
  final bool split;
  final List<String> items;

  const SplitResult({required this.split, required this.items});

  factory SplitResult.fromJson(Map<String, Object?> json) {
    final items =
        (json['items'] as List<Object?>?)?.map((e) => e.toString()).toList() ??
        [];
    return SplitResult(split: (json['split'] as bool?) ?? false, items: items);
  }
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

  const TodoSeed({required this.title, this.body, required this.date});

  factory TodoSeed.fromJson(Map<String, Object?> json) => TodoSeed(
    title: (json['title'] as String?) ?? '',
    body: json['body'] as String?,
    date: (json['date'] as String?) ?? '',
  );
}

class PlanResult {
  final String projectTitle;
  final List<MonthPlanItem> monthPlans;
  final List<TodoSeed> todayTodos;

  const PlanResult({
    this.projectTitle = '',
    required this.monthPlans,
    required this.todayTodos,
  });

  factory PlanResult.fromJson(Map<String, Object?> json) {
    final monthPlansRaw = json['monthPlans'] as List<Object?>?;
    final todayTodosRaw = json['todayTodos'] as List<Object?>?;
    final monthPlans =
        monthPlansRaw
            ?.map((e) => MonthPlanItem.fromJson(e as Map<String, Object?>))
            .toList() ??
        [];
    return PlanResult(
      projectTitle:
          (json['projectTitle'] as String?) ??
          (monthPlans.isEmpty ? '' : monthPlans.first.title),
      monthPlans: monthPlans,
      todayTodos:
          todayTodosRaw
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
      todos:
          todosRaw
              ?.map((e) => TodoSeed.fromJson(e as Map<String, Object?>))
              .toList() ??
          [],
    );
  }
}

class _MemoryExtractionPrompt {
  static const system = '''你只负责判断一条用户消息是否值得保存为长期记忆。
只输出 JSON，不要解释。每条消息最多选择一条。

允许：用户明确说出的长期 preference、goal、constraint，或对已有长期记忆的明确纠正。
忽略：一次性问题、临时计划、阶段性事项、情绪、闲聊、行为描述、他人信息、模糊陈述。
不得根据推断补充信息。quotedText 必须逐字摘自用户消息。

格式：
{"action":"ignore"}
或 {"action":"save","category":"preference|goal|constraint","content":"简短长期事实","quotedText":"用户原话"}
或 {"action":"replace","category":"preference|goal|constraint","content":"简短长期事实","quotedText":"用户原话","replacesId":"候选 ID"}。
replace 只能使用输入候选的 ID。''';
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

enum AiStructuredStage { validating, repairing }

class ToolCallsComplete extends StreamEvent {
  final List<ToolCall> calls;
  ToolCallsComplete(this.calls);
}

class StreamDone extends StreamEvent {}

class AgentActivityEvent extends StreamEvent {
  final String label;
  AgentActivityEvent(this.label);
}

class AgentErrorEvent extends StreamEvent {
  final String message;
  AgentErrorEvent(this.message);
}

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
        args = (jsonDecode(rawArgs) as Map<String, Object?>).map(
          (k, v) => MapEntry(k, v),
        );
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

class AiTransport {
  static const _baseUrl = 'https://api.deepseek.com/v1/chat/completions';

  // V4 系列模型
  static const _modelFlash = 'deepseek-v4-flash';
  static const _modelPro = 'deepseek-v4-pro';

  // ---------------------------------------------------------------------------
  // System prompts
  // ---------------------------------------------------------------------------

  static const _splitSystemPrompt =
      '你是 Sumi，一个自学个人助手的 AI 引擎。\n'
      '你的任务是将用户输入的长文本智能拆分为独立可执行的 todo 事项。\n'
      '\n'
      '规则：\n'
      '1. 如果文本描述的是单一事项（尽管很长），不要拆分，在 items 中返回一条凝练后的文本。\n'
      '2. 如果包含多个独立步骤或事项，拆分为独立 todo。\n'
      '3. 每条 todo 保留完整的语义，可脱离上下文理解。\n'
      '4. 每条 todo 凝练到 2-16 字。\n'
      '5. 以 JSON 格式回复，不要带任何额外文字。\n'
      '\n'
      '回复格式：\n'
      '{"split": true/false, "items": ["事项1", "事项2"]}';

  /// 构建规划 system prompt，通过 [hasAssessment] 控制是否包含评估反馈段落。
  static String _buildPlanningPrompt({bool hasAssessment = false}) {
    final assessmentLine = hasAssessment
        ? '5. **评估反馈**：如果评估报告指出了问题（如周期偏短），在计划中给出缓解策略\n'
        : '';
    return '你是 Sumi，一个专业的自学规划师。\n'
        '\n'
        '用户正在创建一个自学项目，请根据提供的项目信息${hasAssessment ? '、评估报告和领域调研数据' : '和搜索结果'}为其生成完整的学习计划。\n'
        '\n'
        '## 核心约束\n'
        '\n'
        '### 认知科学原则\n'
        '1. **难度递进**：每月难度递进 10-20%，内容应比用户当前水平稍难但通过努力可以完成\n'
        '2. **刻意练习**：每月必须有明确的核心技能目标 + 检验标准\n'
        '3. **时间约束**：∑每月预估小时 ≤ 周期月数 × 每周小时 × 4.3\n'
        '$assessmentLine'
        '\n'
        '### 领域对齐\n'
        '- 月计划内容必须与提供的${hasAssessment ? '领域知识' : '搜索结果'}中的真实学习路径一致\n'
        '- 引用搜索到的具体资源和方法，不要凭空编造\n'
        '- 如果搜索结果中有推荐的时间线，优先参考\n'
        '\n'
        '## 要求\n'
        '\n'
        '### 月计划\n'
        '- 为每个月生成一个月计划卡\n'
        '- 每月有一个凝练的主题（2-10 字）和详细摘要（30-120 字）\n'
        '- 摘要要高维度、战略性，具体步骤留给每日 todo\n'
        '- 内容量匹配当月实际天数\n'
        '- 各月之间递进关系清晰（基础 → 进阶 → 综合）\n'
        '\n'
        '### 每日 Todo（仅第一天）\n'
        '- 基于第一个月计划拆解为可执行 todo\n'
        '- 标题 2-16 字，可附带 body\n'
        '- 数量：1-2 条，考虑时间约束不超出用户能力\n'
        '\n'
        '## 输出格式\n'
        '严格 JSON，不要带任何额外文字：\n'
        '{\n'
        '  "projectTitle": "2-16字项目标题",\n'
        '  "monthPlans": [\n'
        '    {"monthIndex": 0, "title": "月主题", "summary": "月计划摘要..."},\n'
        '    ...\n'
        '  ],\n'
        '  "todayTodos": [\n'
        '    {"title": "todo 标题", "body": "详细说明（可选）", "date": "YYYY-MM-DD"}\n'
        '  ]\n'
        '}';
  }

  static const _dailyTodoSystemPrompt =
      '你是 Sumi。根据月计划为指定日期生成 1-3 条待办。\n'
      '\n'
      '要求：\n'
      '- 标题 2-16 字，是可执行的具体动作（不是抽象描述）\n'
      '- 如果当天已有足够的待办，可以返回空列表\n'
      '- 可附带 body 作为补充说明\n'
      '- 输出 JSON：{"todos": [{"title": "...", "body": "...", "date": "YYYY-MM-DD"}]}';

  static const _assessmentSystemPrompt =
      '你是 Sumi，一个专业的自学规划评估师。基于搜索结果对用户的学习目标进行多维度评估，给出 A/B/C/D 综合评定。\n'
      '\n'
      '## 维度（每项 0.0-1.0）\n'
      '1. clarity 清晰度：0-0.3=模糊/0.4-0.6=有方向/0.7-1.0=具体可衡量\n'
      '2. feasibility 可行性：物理/逻辑上是否可能，D 级红线\n'
      '3. challengeFit 挑战匹配：略高于能力最优(0.7-0.9)，过大→焦虑区，过小→厌倦区\n'
      '4. decomposability 可分解性：有清晰知识体系→高分，模糊目标→低分\n'
      '5. timeRealism 时间合理：用行业共识作基准，可用小时<最低20%→D级\n'
      '6. motivationPotential 动机可持续：与用户身份/长期发展关联，无线索给0.5\n'
      '7. resourceAccess 资源可达：仅需电脑网络→高分，需特殊设备→低分\n'
      '8. measurability 可测性：有证书/作品/量化指标→高分\n'
      '\n'
      '## 判定\n'
      'D 级（任一命中→d）：impossible（物理不可能）/ meaningless（无学习价值）/ extreme（能力极弱+目标极高+时间极短）/ too_uncertain（不可预测）\n'
      'C 级：≥3 个维度<0.4 或 timeRealism<0.3\n'
      '\n'
      '## 输出\n'
      '{"clarity":0.8,"feasibility":0.7,"challengeFit":0.6,"decomposability":0.8,"timeRealism":0.5,"motivationPotential":0.5,"resourceAccess":0.9,"measurability":0.7,"verdict":"a","concerns":["问题"],"suggestions":["建议"],"estimatedHours":"约200-300小时","domainSummary":"领域概述","goalSummary":"2-16字目标凝练"}';

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
            'query': {'type': 'string', 'description': '搜索关键词'},
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_memory',
        'description': '按当前问题查询少量相关的用户记忆。历史行为请使用 read_signals。',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
            'projectId': {'type': 'string'},
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_todos',
        'description':
            '查询待办事项列表。默认优先查今天的待办；当用户明确提到"所有待办""全部事项""之前的任务""历史待办""某个项目"等跨日期/跨范围语义时，再查全部或指定项目。',
        'parameters': {
          'type': 'object',
          'properties': {
            'filter': {
              'type': 'string',
              'description':
                  '筛选条件：today（今天的待办，默认首选）、all（全部待办，用户明确提及时才用）、或 project:xxx（指定项目的待办）',
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
            'title': {'type': 'string', 'description': '事项标题（2-16 字）'},
            'date': {'type': 'string', 'description': '日期，格式 YYYY-MM-DD，可选'},
            'projectId': {'type': 'string', 'description': '归属项目 ID，可选'},
            'body': {'type': 'string', 'description': '详细说明，可选'},
          },
          'required': ['title'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_signals',
        'description':
            '查询用户的历史行为信号（操作日志）。用于发现用户的行为模式、偏好变化、学习节奏等。当你需要理解用户长期行为模式时，优先调用此工具。',
        'parameters': {
          'type': 'object',
          'properties': {
            'type': {
              'type': 'string',
              'description':
                  '信号类型筛选。可选值：todoCreated, todoCompleted, todoUncompleted, todoDeleted, todoEdited, todoMovedDate, projectGoalSet, projectLevelSet, projectCycleSet, projectTimeSet',
            },
            'projectId': {'type': 'string', 'description': '按项目ID筛选，可选'},
            'range': {
              'type': 'string',
              'description': '时间范围：7d（最近7天）、30d（最近30天）、all（全部），默认7d',
            },
            'limit': {'type': 'integer', 'description': '最多返回条数，默认20'},
          },
        },
      },
    },
  ];

  final String apiKey;
  final String? tavilyApiKey;
  final http.Client _client;
  final bool _ownsClient;

  /// 最近一次 API 调用的错误详情（用于 UI 诊断）。
  String? lastApiError;
  bool _lastFailureWasInvalidResponse = false;

  AiTransport({required this.apiKey, this.tavilyApiKey, http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

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
    int maxTokens = 2000,
    double temperature = 0.7,
  }) {
    final body = <String, Object?>{
      'model': model,
      'messages': messages,
      'temperature': temperature,
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
    int maxTokens = 4000,
    int timeoutSeconds = 60,
    double temperature = 0.2,
    bool useResponseFormat = true,
  }) async {
    _lastFailureWasInvalidResponse = false;
    lastApiError = null;
    try {
      final response = await _client
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(
              _buildRequestParams(
                model: model,
                messages: [
                  {'role': 'system', 'content': systemPrompt},
                  {'role': 'user', 'content': userPrompt},
                ],
                thinking: thinking,
                responseFormat: useResponseFormat ? 'json_object' : null,
                maxTokens: maxTokens,
                temperature: temperature,
              ),
            ),
          )
          .timeout(Duration(seconds: timeoutSeconds));

      if (response.statusCode != 200) {
        String apiMsg = response.body;
        try {
          final errJson = jsonDecode(response.body) as Map<String, Object?>;
          final err = errJson['error'] as Map<String, Object?>?;
          if (err != null && err['message'] != null) {
            apiMsg = err['message'].toString();
          }
        } catch (_) {}
        lastApiError = 'HTTP ${response.statusCode}: $apiMsg';
        debugPrint('[callJsonApi] $lastApiError');
        return null;
      }

      late final Map<String, Object?> body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, Object?>) {
          throw const FormatException('响应顶层必须是 JSON 对象');
        }
        body = decoded;
      } catch (e) {
        _lastFailureWasInvalidResponse = true;
        lastApiError = '响应 JSON 解析失败: $e';
        debugPrint('[callJsonApi] $lastApiError');
        return null;
      }
      final choices = body['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) {
        _lastFailureWasInvalidResponse = true;
        lastApiError = '响应无 choices';
        debugPrint('[callJsonApi] $lastApiError');
        return null;
      }

      final message =
          (choices.first as Map<String, Object?>?)?['message']
              as Map<String, Object?>?;
      if (message == null) {
        _lastFailureWasInvalidResponse = true;
        lastApiError = '响应无 message';
        debugPrint('[callJsonApi] $lastApiError');
        return null;
      }

      final content = message['content'] as String?;
      if (content == null) {
        _lastFailureWasInvalidResponse = true;
        lastApiError = 'message 无 content';
        debugPrint('[callJsonApi] $lastApiError');
        return null;
      }

      try {
        String cleaned = content.trim();
        if (cleaned.startsWith('```')) {
          cleaned = cleaned.replaceFirst(RegExp(r'^```\w*\n?'), '');
          cleaned = cleaned.replaceFirst(RegExp(r'\n?```$'), '');
        }
        return jsonDecode(cleaned) as Map<String, Object?>;
      } catch (e) {
        _lastFailureWasInvalidResponse = true;
        lastApiError = 'JSON 解析失败: $e';
        debugPrint('[callJsonApi] $lastApiError: $content');
        return null;
      }
    } catch (e) {
      lastApiError = '网络/超时异常: $e';
      debugPrint('[callJsonApi] $lastApiError');
      return null;
    }
  }

  Future<Map<String, Object?>?> _callValidatedJsonApi({
    required String systemPrompt,
    required String userPrompt,
    required String model,
    required AiMapValidator validator,
    bool thinking = false,
    int maxTokens = 4000,
    int timeoutSeconds = 60,
    int maxAttempts = 2,
    bool useResponseFormat = true,
  }) async {
    var prompt = userPrompt;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final result = await _callJsonApi(
        systemPrompt: systemPrompt,
        userPrompt: prompt,
        model: model,
        thinking: thinking,
        maxTokens: maxTokens,
        timeoutSeconds: timeoutSeconds,
        temperature: 0.2,
        useResponseFormat: useResponseFormat,
      );
      if (result == null) {
        if (!_lastFailureWasInvalidResponse || attempt == maxAttempts - 1) {
          return null;
        }
        prompt = '$userPrompt\n\n上一次输出不是有效 JSON。请严格按要求重新输出。';
        continue;
      }
      final validation = validator(result);
      if (validation.isValid) return validation.value;
      lastApiError = '结构校验失败: ${validation.errors.join('；')}';
      if (attempt == maxAttempts - 1) return null;
      prompt =
          '$userPrompt\n\n上一次输出未通过校验：'
          '${validation.errors.join('；')}。请修正后重新输出完整 JSON。';
    }
    return null;
  }

  Future<MemoryExtractionDecision?> extractMemory({
    required String message,
    required List<MemoryExtractionCandidate> candidates,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return null;
    // Keep this background request small. Truncation deliberately fails closed:
    // a fact outside the supplied excerpt is not extracted this round.
    final boundedMessage = trimmed.length > 240
        ? trimmed.substring(0, 240)
        : trimmed;
    final boundedCandidates = [
      for (final item in candidates.take(3))
        MemoryExtractionCandidate(
          id: item.id,
          category: item.category,
          content: item.content.length > 40
              ? item.content.substring(0, 40)
              : item.content,
        ),
    ];
    final result = await _callValidatedJsonApi(
      systemPrompt: _MemoryExtractionPrompt.system,
      userPrompt: jsonEncode({
        'message': boundedMessage,
        'candidates': boundedCandidates.map((item) => item.toJson()).toList(),
      }),
      model: _modelFlash,
      validator: AiContracts.memoryExtraction,
      thinking: false,
      maxTokens: 120,
      timeoutSeconds: 20,
      maxAttempts: 1,
    );
    if (result == null) return null;
    return MemoryExtractionDecision(
      action: MemoryExtractionAction.values.firstWhere(
        (item) => item.name == result['action'],
      ),
      category: result['category'] as String?,
      content: result['content'] as String?,
      quotedText: result['quotedText'] as String?,
      replacesId: result['replacesId'] as String?,
    );
  }

  /// 流式 JSON 调用 —— SSE 解析，累积内容，流结束后 parse JSON。
  /// [onProgress] 每收到内容片段时回调，用于实时弹幕等。
  Future<Map<String, Object?>?> _callStreamingJsonApi({
    required String systemPrompt,
    required String userPrompt,
    required String model,
    bool thinking = false,
    int maxTokens = 8192,
    int timeoutSeconds = 120,
    void Function(String chunk)? onProgress,
  }) async {
    _lastFailureWasInvalidResponse = false;
    lastApiError = null;
    try {
      // 在 system prompt 末尾追加 JSON 输出要求（streaming 不能使用 response_format）
      // 如果 prompt 已包含 JSON 输出约束则跳过，避免重复
      final hasJsonHint =
          systemPrompt.contains('只输出 JSON') ||
          systemPrompt.contains('严格 JSON') ||
          systemPrompt.contains('不要任何额外文字');
      final augmentedSystem = hasJsonHint
          ? systemPrompt
          : '$systemPrompt\n\n[重要] 只输出 JSON，不要 markdown 代码块，不要任何额外文字。';

      final request = http.Request('POST', Uri.parse(_baseUrl));
      request.headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      });
      request.body = jsonEncode(
        _buildRequestParams(
          model: model,
          messages: [
            {'role': 'system', 'content': augmentedSystem},
            {'role': 'user', 'content': userPrompt},
          ],
          thinking: thinking,
          stream: true,
          maxTokens: maxTokens,
          temperature: 0.2,
        ),
      );

      final streamedResponse = await _client
          .send(request)
          .timeout(Duration(seconds: timeoutSeconds));

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        debugPrint(
          '[_callStreamingJsonApi] HTTP ${streamedResponse.statusCode}: $errorBody',
        );
        return null;
      }

      final contentBuf = StringBuffer();
      await for (final chunk
          in streamedResponse.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final trimmed = chunk.trim();
        if (!trimmed.startsWith('data:')) continue;

        final data = trimmed.substring(5).trimLeft();
        if (data == '[DONE]') break;

        try {
          final json = jsonDecode(data) as Map<String, Object?>;
          final choices = json['choices'] as List<Object?>?;
          if (choices == null || choices.isEmpty) continue;

          final delta =
              (choices.first as Map<String, Object?>?)?['delta']
                  as Map<String, Object?>?;
          if (delta == null) continue;

          final content = delta['content'] as String?;
          if (content != null && content.isNotEmpty) {
            contentBuf.write(content);
            onProgress?.call(content);
          }
        } catch (_) {
          // 跳过无法解析的 chunk
        }
      }

      final fullContent = contentBuf.toString().trim();
      if (fullContent.isEmpty) {
        _lastFailureWasInvalidResponse = true;
        lastApiError = '流式响应无内容';
        debugPrint('[_callStreamingJsonApi] $lastApiError');
        return null;
      }

      // 清洗 markdown fence 后解析 JSON
      String cleaned = fullContent;
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceFirst(RegExp(r'^```\w*\n?'), '');
        cleaned = cleaned.replaceFirst(RegExp(r'\n?```$'), '');
      }
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('响应顶层必须是 JSON 对象');
      }
      return decoded;
    } on FormatException catch (e) {
      _lastFailureWasInvalidResponse = true;
      lastApiError = '流式 JSON 解析失败: $e';
      debugPrint('[_callStreamingJsonApi] $lastApiError');
      return null;
    } catch (e) {
      lastApiError = '流式调用异常: $e';
      debugPrint('[_callStreamingJsonApi] $lastApiError');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Todo 拆分
  // ---------------------------------------------------------------------------

  Future<SplitResult?> splitTodo(String text) async {
    var result = await _callValidatedJsonApi(
      systemPrompt: _splitSystemPrompt,
      userPrompt: text,
      model: _modelFlash,
      validator: AiContracts.split,
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
    var userPrompt = text;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client
            .post(
              Uri.parse(_baseUrl),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(
                _buildRequestParams(
                  model: _modelFlash,
                  messages: [
                    {
                      'role': 'system',
                      'content':
                          '优化用户提供的 todo 标题。保留原意，输出 2-16 字的单行纯文本，不加引号或解释。',
                    },
                    {'role': 'user', 'content': userPrompt},
                  ],
                  maxTokens: 200,
                  temperature: 0.2,
                ),
              ),
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) return null;
        final body = jsonDecode(response.body) as Map<String, Object?>;
        final choices = body['choices'] as List<Object?>?;
        if (choices == null || choices.isEmpty) return null;
        final firstChoice = choices.first as Map<String, Object?>?;
        final message = firstChoice?['message'] as Map<String, Object?>?;
        final content = message?['content'] as String?;
        if (content == null) return null;
        final validation = AiContracts.polishedText(content);
        if (validation.isValid) return validation.value;
        if (attempt == 1) {
          lastApiError = '润色结果校验失败: ${validation.errors.join('；')}';
          return null;
        }
        userPrompt = '$text\n\n上一次结果不合格：${validation.errors.join('；')}。请重新输出。';
      } catch (e) {
        lastApiError = '润色调用失败: $e';
        return null;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 项目规划（05 轮：切到 pro + thinking）
  // ---------------------------------------------------------------------------

  /// 增强版项目规划（06 轮新增）—— 结合评估报告 + 领域知识。
  Future<PlanResult?> generatePlanEnhanced({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String startDate,
    required String assessmentReport,
    required String domainKnowledge,
  }) async {
    final userPrompt =
        '''
## 项目信息
- 目标：$goal
- 当前水平：$level
- 规划周期：$cycleMonths 个月
- 每周投入：$timeConstraint 小时
- 起始日期：$startDate

## 评估报告数据
${PromptContext.dataBlock(kind: 'assessment', source: 'sumi_assessor', data: assessmentReport)}

## 领域知识数据
${PromptContext.dataBlock(kind: 'domain_knowledge', source: 'tavily', data: PromptContext.truncate(domainKnowledge, 4000))}

请基于以上全部信息，生成 $cycleMonths 个月的月计划卡和第一天的 todo。''';

    // 注意：thinking 与 response_format: json_object 冲突，不可同时使用
    final result = await _callValidatedJsonApi(
      systemPrompt: _buildPlanningPrompt(hasAssessment: true),
      userPrompt: userPrompt,
      model: _modelPro,
      validator: (value) => AiContracts.plan(
        value,
        cycleMonths: cycleMonths,
        startDate: startDate,
      ),
      thinking: false,
      maxTokens: 8192,
      timeoutSeconds: 120,
    );
    if (result == null) {
      throw Exception(
        'AI 规划 API 无响应${lastApiError != null ? '（$lastApiError）' : ''}',
      );
    }
    return PlanResult.fromJson(result);
  }

  /// 流式版本 —— 实时回调内容片段用于弹幕展示，降级时回退到非流式版本。
  Future<PlanResult?> generatePlanEnhancedStreaming({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String startDate,
    required String assessmentReport,
    required String domainKnowledge,
    void Function(String chunk)? onProgress,
    void Function(AiStructuredStage stage)? onStage,
  }) async {
    final userPrompt =
        '''
## 项目信息
- 目标：$goal
- 当前水平：$level
- 规划周期：$cycleMonths 个月
- 每周投入：$timeConstraint 小时
- 起始日期：$startDate

## 评估报告数据
${PromptContext.dataBlock(kind: 'assessment', source: 'sumi_assessor', data: assessmentReport)}

## 领域知识数据
${PromptContext.dataBlock(kind: 'domain_knowledge', source: 'tavily', data: PromptContext.truncate(domainKnowledge, 4000))}

请基于以上全部信息，生成 $cycleMonths 个月的月计划卡和第一天的 todo。''';

    final result = await _callStreamingJsonApi(
      systemPrompt: _buildPlanningPrompt(hasAssessment: true),
      userPrompt: userPrompt,
      model: _modelPro,
      thinking: false,
      maxTokens: 8192,
      timeoutSeconds: 120,
      onProgress: onProgress,
    );
    if (result == null) {
      if (!_lastFailureWasInvalidResponse) return null;
      onStage?.call(AiStructuredStage.repairing);
      final repaired = await _callValidatedJsonApi(
        systemPrompt: _buildPlanningPrompt(hasAssessment: true),
        userPrompt: '$userPrompt\n\n上一次流式输出不是有效 JSON，请重新输出完整 JSON。',
        model: _modelPro,
        validator: (value) => AiContracts.plan(
          value,
          cycleMonths: cycleMonths,
          startDate: startDate,
        ),
        maxTokens: 8192,
        timeoutSeconds: 120,
        maxAttempts: 1,
      );
      return repaired == null ? null : PlanResult.fromJson(repaired);
    }
    onStage?.call(AiStructuredStage.validating);
    final validation = AiContracts.plan(
      result,
      cycleMonths: cycleMonths,
      startDate: startDate,
    );
    if (!validation.isValid) {
      lastApiError = '流式规划校验失败: ${validation.errors.join('；')}';
      onStage?.call(AiStructuredStage.repairing);
      final repaired = await _callValidatedJsonApi(
        systemPrompt: _buildPlanningPrompt(hasAssessment: true),
        userPrompt:
            '$userPrompt\n\n上一次输出未通过校验：${validation.errors.join('；')}。请重新输出完整 JSON。',
        model: _modelPro,
        validator: (value) => AiContracts.plan(
          value,
          cycleMonths: cycleMonths,
          startDate: startDate,
        ),
        maxTokens: 8192,
        timeoutSeconds: 120,
        maxAttempts: 1,
      );
      return repaired == null ? null : PlanResult.fromJson(repaired);
    }
    return PlanResult.fromJson(validation.value!);
  }

  // ---------------------------------------------------------------------------

  Future<DailyTodoResult?> generateDailyTodos({
    required String monthPlanTitle,
    required String monthPlanSummary,
    required String date,
    required int timeConstraint,
    required int scheduledHours,
  }) async {
    final userPrompt =
        '''
月计划：$monthPlanTitle — $monthPlanSummary
日期：$date
本周已安排的小时数：$scheduledHours / $timeConstraint''';

    final result = await _callValidatedJsonApi(
      systemPrompt: _dailyTodoSystemPrompt,
      userPrompt: userPrompt,
      model: _modelFlash,
      validator: (value) => AiContracts.dailyTodos(value, date: date),
      thinking: false,
      maxTokens: 1000,
      timeoutSeconds: 30,
    );
    if (result == null) return null;
    return DailyTodoResult.fromJson(result);
  }

  // ---------------------------------------------------------------------------
  // 目标评估（06 轮新增）
  // ---------------------------------------------------------------------------

  /// 对用户学习目标进行多维度评估，返回 [GoalAssessment]。
  /// [domainContext] 为搜索获取的领域知识文本，作为评估的"地面实况"。
  Future<GoalAssessment?> assessGoal({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String domainContext,
  }) async {
    final userPrompt =
        '''
## 用户输入
- 目标：$goal
- 当前水平：$level
- 规划周期：$cycleMonths 个月
- 每周投入：$timeConstraint 小时

## 搜索结果数据
${PromptContext.dataBlock(kind: 'search_results', source: 'tavily', data: PromptContext.truncate(domainContext, 4000))}

请基于以上信息进行多维度评估，给出 A/B/C/D 综合评定。''';

    var result = await _callValidatedJsonApi(
      systemPrompt: _assessmentSystemPrompt,
      userPrompt: userPrompt,
      model: _modelFlash,
      validator: AiContracts.assessment,
      thinking: false,
      maxTokens: 8000,
      timeoutSeconds: 60,
    );
    if (result == null && (lastApiError?.startsWith('HTTP 400') ?? false)) {
      result = await _callValidatedJsonApi(
        systemPrompt: _assessmentSystemPrompt,
        userPrompt: userPrompt,
        model: _modelFlash,
        validator: AiContracts.assessment,
        thinking: false,
        maxTokens: 8000,
        timeoutSeconds: 60,
        useResponseFormat: false,
      );
    }
    if (result == null) return null;
    return GoalAssessment.fromJson(result);
  }

  // ---------------------------------------------------------------------------
  // Tavily 搜索（05 轮新增）
  // ---------------------------------------------------------------------------

  /// 调用 Tavily Search API，返回格式化结果列表。
  Future<List<Map<String, String>>> searchWeb(String query) async {
    if (tavilyApiKey == null || tavilyApiKey!.isEmpty) {
      return [
        {'error': 'Tavily API Key 未配置'},
      ];
    }
    try {
      final response = await _client
          .post(
            Uri.parse('https://api.tavily.com/search'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'api_key': tavilyApiKey,
              'query': query,
              'search_depth': 'basic',
              'max_results': 5,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return [
          {'error': '搜索失败（${response.statusCode}）'},
        ];
      }

      final body = jsonDecode(response.body) as Map<String, Object?>;
      final results = body['results'] as List<Object?>?;
      if (results == null || results.isEmpty) {
        return [
          {'info': '未找到相关结果'},
        ];
      }

      return results.take(5).map((r) {
        final m = r as Map<String, Object?>;
        final rawUrl = (m['url'] as String?) ?? '';
        final uri = Uri.tryParse(rawUrl);
        final safeUrl =
            uri != null &&
                (uri.scheme == 'https' || uri.scheme == 'http') &&
                uri.host.isNotEmpty
            ? uri.replace(fragment: '').toString()
            : '';
        return {
          'title': PromptContext.truncate((m['title'] as String?) ?? '', 200),
          'url': safeUrl,
          'content': PromptContext.truncate(
            (m['content'] as String?) ?? '',
            800,
          ),
        };
      }).toList();
    } catch (_) {
      return [
        {'error': '搜索请求超时或网络错误'},
      ];
    }
  }

  // ---------------------------------------------------------------------------
  // 流式对话（05 轮重写：Stream<StreamEvent> + thinking + tools）
  // ---------------------------------------------------------------------------

  /// Streaming 对话，返回 [StreamEvent]。
  /// [messages] 为完整消息历史（含 system prompt + 历史对话 + 当前用户消息）。
  /// `reasoning_content` 仅在当前 Agent Loop 内部使用，不传给 Store。
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
      request.body = jsonEncode(
        _buildRequestParams(
          model: _modelFlash,
          messages: messages,
          thinking: thinkingEnabled,
          stream: true,
          tools: _chatTools,
          maxTokens: 8192,
          temperature: 0.7,
        ),
      );

      final streamedResponse = await _client
          .send(request)
          .timeout(const Duration(seconds: 60));

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        debugPrint(
          '[streamChatMessages] HTTP ${streamedResponse.statusCode}: $errorBody',
        );
        yield AgentErrorEvent(_chatErrorMessage(streamedResponse.statusCode));
        return;
      }

      // tool_calls 增量解析状态
      final toolCallBufs = <int, _ToolCallBuf>{};

      await for (final chunk
          in streamedResponse.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final trimmed = chunk.trim();
        if (!trimmed.startsWith('data:')) continue;

        final data = trimmed.substring(5).trimLeft();
        if (data == '[DONE]') break;

        try {
          final json = jsonDecode(data) as Map<String, Object?>;
          final choices = json['choices'] as List<Object?>?;
          if (choices == null || choices.isEmpty) continue;

          final delta =
              (choices.first as Map<String, Object?>?)?['delta']
                  as Map<String, Object?>?;
          if (delta == null) continue;

          // 文本内容
          final content = delta['content'] as String?;
          if (content != null && content.isNotEmpty) {
            yield ContentDelta(content);
          }

          // 思考过程
          final reasoning = delta['reasoning_content'] as String?;
          if (reasoning != null && reasoning.isNotEmpty) {
            yield ReasoningDelta(reasoning);
          }

          // 工具调用
          final toolCalls = delta['tool_calls'] as List<Object?>?;
          if (toolCalls != null) {
            for (final tc in toolCalls) {
              if (tc is! Map<String, Object?>) continue;
              final index = (tc['index'] as num?)?.toInt() ?? 0;
              final buf = toolCallBufs.putIfAbsent(index, () => _ToolCallBuf());

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
            calls.add(
              ToolCall(
                id: buf.id,
                name: buf.name,
                arguments: ToolCall.fromMap({
                  'function': {'arguments': buf.arguments.toString()},
                }).arguments,
              ),
            );
          }
        }
        if (calls.isNotEmpty) {
          yield ToolCallsComplete(calls);
        }
      }

      yield StreamDone();
    } catch (e) {
      debugPrint('[streamChatMessages] 流异常: $e');
      yield AgentErrorEvent('请求失败，请检查网络后重试。');
    }
  }

  static String _chatErrorMessage(int statusCode) {
    return switch (statusCode) {
      401 || 403 => 'API Key 无效或没有访问权限，请检查设置。',
      429 => '请求过于频繁，请稍后重试。',
      >= 500 => 'AI 服务暂时不可用，请稍后重试。',
      _ => '请求失败（$statusCode），请稍后重试。',
    };
  }
}

/// 旧测试和注入点的兼容名称；运行时直接依赖 [AiTransport]。
class AiService extends AiTransport {
  AiService({required super.apiKey, super.tavilyApiKey, super.client});
}

/// tool_calls 增量解析缓冲。
class _ToolCallBuf {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}
