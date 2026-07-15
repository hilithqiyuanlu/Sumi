import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';

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
      '4. 每条 todo 凝练到 2-20 字。\n'
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
        '- 每月有一个凝练的主题（5-15 字）和详细摘要（30-120 字）\n'
        '- 摘要要高维度、战略性，具体步骤留给每日 todo\n'
        '- 内容量匹配当月实际天数\n'
        '- 各月之间递进关系清晰（基础 → 进阶 → 综合）\n'
        '\n'
        '### 每日 Todo（仅第一天）\n'
        '- 基于第一个月计划拆解为可执行 todo\n'
        '- 标题 2-20 字，可附带 body\n'
        '- 数量：1-2 条，考虑时间约束不超出用户能力\n'
        '\n'
        '## 输出格式\n'
        '严格 JSON，不要带任何额外文字：\n'
        '{\n'
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
          '- 标题 2-20 字，是可执行的具体动作（不是抽象描述）\n'
          '- 如果当天已有足够的待办，可以返回空列表\n'
          '- 可附带 body 作为补充说明\n'
          '- 输出 JSON：{"todos": [{"title": "...", "body": "...", "date": "YYYY-MM-DD"}]}';

  static const _suggestionsSystemPrompt =
      '你是 Sumi。根据用户的待办列表，生成 3 条用户可能想让你执行的操作建议。\n'
          '\n'
          '要求：\n'
          '1. 每条是用户会对助手说的自然指令（如"帮我..."、"建议我..."、"总结..."）。\n'
          '2. 必须基于今日待办的具体内容，不要泛泛而谈。\n'
          '3. 每条 8-20 字。\n'
          '4. 只输出 JSON，不要任何额外文字。\n'
          '\n'
          '输出格式：{"suggestions": ["建议1", "建议2", "建议3"]}';

  static const _assessmentSystemPrompt =
      '你是 Sumi，一个专业的自学规划评估师。\n'
          '\n'
          '你的任务是对用户的学习目标进行多维度评估，给出 A/B/C/D 综合评定。\n'
          '评估必须基于提供的搜索结果，不要凭空判断。\n'
          '\n'
          '## 评估维度（每个 0.0-1.0 评分）\n'
          '\n'
          '1. clarity（清晰度）：目标是否具体、可衡量？\n'
          '   0.0-0.3: 极度模糊（"学好XX"）\n'
          '   0.4-0.6: 有方向但不具体（"提升英语水平"）\n'
          '   0.7-1.0: 具体可衡量（"6个月IELTS从5.5到6.5"）\n'
          '\n'
          '2. feasibility（可行性）：物理/逻辑上是否可能？\n'
          '   D 级红线：物理不可能、无学习价值、极端困难、高度不确定\n'
          '   给出具体理由\n'
          '\n'
          '3. challengeFit（挑战匹配度）：目标难度 vs 当前能力\n'
          '   参考心流理论：挑战略高于能力时最优（0.7-0.9）\n'
          '   差距过大 → 低分（焦虑区），太简单 → 中低分（厌倦区）\n'
          '\n'
          '4. decomposability（可分解性）：能否拆为递进子目标？\n'
          '   有清晰知识体系的学科 → 高分\n'
          '   "提升品味"类模糊目标 → 低分\n'
          '\n'
          '5. timeRealism（时间合理性）：周期 × 投入时间是否足够？\n'
          '   用搜索结果中的行业共识作为基准\n'
          '   可用小时 < 行业共识最低时间的 20% → D 级 extreme\n'
          '\n'
          '6. motivationPotential（动机可持续性）：\n'
          '   目标是否与用户的身份/长期发展关联？\n'
          '   无明确线索时给 0.5\n'
          '\n'
          '7. resourceAccess（资源可达性）：\n'
          '   是否需要特殊设备/导师/环境？\n'
          '   只需要一台电脑和网络 → 高分\n'
          '\n'
          '8. measurability（进展可测性）：\n'
          '   有客观标准判断进度吗？\n'
          '   有证书/作品/量化指标 → 高分\n'
          '\n'
          '## D 级判定（不可通过，verdict: "d"）\n'
          '\n'
          '以下任一命中 → d，给出具体 subType：\n'
          '  impossible: 物理上不可能（"造永动机"）\n'
          '  meaningless: 无学习价值/过于简单（"学好呼吸"）\n'
          '  extreme: 能力极弱 + 目标极高 + 时间极短（小学数学 → 1个月物理竞赛省一）\n'
          '  too_uncertain: 目标不可预测/不可控（"拿诺贝尔奖"）\n'
          '\n'
          '## C 级判定\n'
          '至少 3 个维度 < 0.4，或 timeRealism < 0.3\n'
          '\n'
          '## 输出格式\n'
          '严格 JSON：\n'
          '{\n'
          '  "clarity": 0.8,\n'
          '  "feasibility": 0.7,\n'
          '  "challengeFit": 0.6,\n'
          '  "decomposability": 0.8,\n'
          '  "timeRealism": 0.5,\n'
          '  "motivationPotential": 0.5,\n'
          '  "resourceAccess": 0.9,\n'
          '  "measurability": 0.7,\n'
          '  "verdict": "a",\n'
          '  "concerns": ["具体问题1"],\n'
          '  "suggestions": ["可操作的调整建议"],\n'
          '  "estimatedHours": "约 200-300 小时",\n'
          '  "domainSummary": "该领域的概述"\n'
          '}';

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
        'description': '查询待办事项列表。默认优先查今天的待办；当用户明确提到"所有待办""全部事项""之前的任务""历史待办""某个项目"等跨日期/跨范围语义时，再查全部或指定项目。',
        'parameters': {
          'type': 'object',
          'properties': {
            'filter': {
              'type': 'string',
              'description': '筛选条件：today（今天的待办，默认首选）、all（全部待办，用户明确提及时才用）、或 project:xxx（指定项目的待办）',
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

  /// 最近一次 API 调用的错误详情（用于 UI 诊断）。
  String? lastApiError;

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
    int maxTokens = 2000,
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
    int maxTokens = 4000,
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

      final body = jsonDecode(response.body) as Map<String, Object?>;
      final choices = body['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) {
        lastApiError = '响应无 choices';
        debugPrint('[callJsonApi] $lastApiError');
        return null;
      }

      final message = (choices.first as Map<String, Object?>?)?['message']
          as Map<String, Object?>?;
      if (message == null) {
        lastApiError = '响应无 message';
        debugPrint('[callJsonApi] $lastApiError');
        return null;
      }

      final content = message['content'] as String?;
      if (content == null) {
        lastApiError = 'message 无 content';
        debugPrint('[callJsonApi] $lastApiError');
        return null;
      }

      try {
        return jsonDecode(content) as Map<String, Object?>;
      } catch (e) {
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
    try {
      debugPrint('[polishTodo] 开始润色: "$text"');
      final response = await _client
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _modelFlash,
              'messages': [
                {
                  'role': 'system',
                  'content': '你是 Sumi，一个个人助手。优化用户提供的 todo 标题。\n'
                      '要求：凝练清晰、保留原意、2-20 字。\n'
                      '只返回优化后的文本，不要加引号或额外文字。',
                },
                {'role': 'user', 'content': text},
              ],
              'temperature': 1.0,
              'top_p': 1.0,
              'max_tokens': 200,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('[polishTodo] HTTP ${response.statusCode}: ${response.body}');
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, Object?>;
      final choices = body['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) {
        debugPrint('[polishTodo] 无 choices: ${response.body}');
        return null;
      }

      final message = (choices.first as Map<String, Object?>?)?['message']
          as Map<String, Object?>?;
      final content = message?['content'] as String?;
      final result = content?.trim();
      debugPrint('[polishTodo] 结果: "$result"');
      return (result != null && result.isNotEmpty) ? result : null;
    } catch (e) {
      debugPrint('[polishTodo] 异常: $e');
      return null;
    }
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
    String? searchContext,
  }) async {
    final searchSection = searchContext != null && searchContext.isNotEmpty
        ? '\n## 联网搜索结果（Tavily）\n以下是最新网络信息，请参考其内容来制定更准确的学习计划：\n$searchContext\n'
        : '';
    final userPrompt = '''
## 输入信息
- 项目目标：$goal
- 当前水平：$level
- 规划周期：$cycleMonths 个月
- 每周投入时间：$timeConstraint 小时
- 起始日期：$startDate
$searchSection
请生成 $cycleMonths 个月的月计划卡和第一天的 todo。''';

    // 注意：thinking 与 response_format: json_object 冲突，不可同时使用
    final result = await _callJsonApi(
      systemPrompt: _buildPlanningPrompt(),
      userPrompt: userPrompt,
      model: _modelPro,
      thinking: false,
      maxTokens: 8192,
      timeoutSeconds: 90,
    );
    if (result == null) {
      throw Exception('AI 规划 API 无响应${lastApiError != null ? '（$lastApiError）' : ''}');
    }
    return PlanResult.fromJson(result);
  }

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
    final userPrompt = '''
## 项目信息
- 目标：$goal
- 当前水平：$level
- 规划周期：$cycleMonths 个月
- 每周投入：$timeConstraint 小时
- 起始日期：$startDate

## 评估报告
$assessmentReport

## 领域知识（网络搜索结果）
$domainKnowledge

请基于以上全部信息，生成 $cycleMonths 个月的月计划卡和第一天的 todo。''';

    // 注意：thinking 与 response_format: json_object 冲突，不可同时使用
    final result = await _callJsonApi(
      systemPrompt: _buildPlanningPrompt(hasAssessment: true),
      userPrompt: userPrompt,
      model: _modelPro,
      thinking: false,
      maxTokens: 8192,
      timeoutSeconds: 120,
    );
    if (result == null) {
      throw Exception('AI 规划 API 无响应${lastApiError != null ? '（$lastApiError）' : ''}');
    }
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
      maxTokens: 1000,
      timeoutSeconds: 30,
    );
    if (result == null) return null;
    return DailyTodoResult.fromJson(result);
  }

  /// 基于当前上下文生成建议提问。
  Future<List<String>> generateSuggestions({
    required String todayTodosText,
    required String memory,
  }) async {
    final userPrompt = '''
今日待办：
$todayTodosText

记忆：
${memory.trim().isEmpty ? '（暂无记忆）' : memory}''';

    final result = await _callJsonApi(
      systemPrompt: _suggestionsSystemPrompt,
      userPrompt: userPrompt,
      model: _modelFlash,
      thinking: false,
      maxTokens: 800,
      timeoutSeconds: 20,
    );
    if (result == null) return [];
    final raw = result['suggestions'] as List<Object?>?;
    if (raw == null) return [];
    return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
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
    final userPrompt = '''
## 用户输入
- 目标：$goal
- 当前水平：$level
- 规划周期：$cycleMonths 个月
- 每周投入：$timeConstraint 小时

## 搜索结果（领域知识参考）
$domainContext

请基于以上信息进行多维度评估，给出 A/B/C/D 综合评定。''';

    final result = await _callJsonApi(
      systemPrompt: _assessmentSystemPrompt,
      userPrompt: userPrompt,
      model: _modelFlash,
      thinking: false,
      maxTokens: 8000,
      timeoutSeconds: 60,
    );
    if (result == null) return null;
    return GoalAssessment.fromJson(result);
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
        maxTokens: 8192,
      ));

      final streamedResponse =
          await _client.send(request).timeout(const Duration(seconds: 60));

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        debugPrint(
            '[streamChatMessages] HTTP ${streamedResponse.statusCode}: $errorBody');
        return;
      }

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
    } catch (e) {
      debugPrint('[streamChatMessages] 流异常: $e');
    }
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

}

/// tool_calls 增量解析缓冲。
class _ToolCallBuf {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}
