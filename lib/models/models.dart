import 'dart:convert';

/// Sumi 数据模型 —— 所有模型集中在一个文件。

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum TodoSource { user, system }

/// 统一输入的判定结果。只有 createTodo 可以直接创建事项。
enum InputIntent { chat, createTodo, clarifyTodo }

class InputClassification {
  final InputIntent intent;
  final double confidence;
  final String? title;
  final String? date;
  final String? reminderTime;
  final List<String> missingFields;
  final String? clarification;

  const InputClassification({
    required this.intent,
    required this.confidence,
    this.title,
    this.date,
    this.reminderTime,
    this.missingFields = const [],
    this.clarification,
  });

  factory InputClassification.fromJson(Map<String, Object?> json) {
    final name = json['intent'] as String? ?? 'chat';
    return InputClassification(
      intent: InputIntent.values.firstWhere(
        (value) => value.name == name,
        orElse: () => InputIntent.chat,
      ),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      title: json['title'] as String?,
      date: json['date'] as String?,
      reminderTime: json['reminderTime'] as String?,
      missingFields:
          (json['missingFields'] as List<Object?>?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
      clarification: json['clarification'] as String?,
    );
  }
}

class MilestoneRecognition {
  final double confidence;
  final String? todoId;
  final String? quotedText;

  const MilestoneRecognition({
    required this.confidence,
    this.todoId,
    this.quotedText,
  });

  factory MilestoneRecognition.fromJson(Map<String, Object?> json) =>
      MilestoneRecognition(
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        todoId: json['todoId'] as String?,
        quotedText: json['quotedText'] as String?,
      );
}

/// 用户行为信号类型（07 轮新增）。
enum SignalType {
  todoCreated,
  todoCompleted,
  todoUncompleted,
  todoDeleted,
  todoEdited,
  todoMovedDate,
  projectGoalSet,
  projectLevelSet,
  projectCycleSet,
  projectTimeSet,
}

enum ProjectColor { lemon, mint, lilac, cherry, sky, peach, sage }

// ---------------------------------------------------------------------------
// AppSettings
// ---------------------------------------------------------------------------

class AppSettings {
  final String deepseekApiKey;
  final String tavilyApiKey;
  final bool localTextGenerationEnabled;
  final bool localSpeechRecognitionEnabled;
  final bool showAllMonthCards; // 开发者开关：披露全部月卡
  final bool suggestionQuestionsEnabled;
  final bool scheduleLoadAnalysisEnabled;
  final String userName; // 用户昵称
  final List<String> enabledTools;

  const AppSettings({
    this.deepseekApiKey = '',
    this.tavilyApiKey = '',
    this.localTextGenerationEnabled = true,
    this.localSpeechRecognitionEnabled = true,
    this.showAllMonthCards = false,
    this.suggestionQuestionsEnabled = true,
    this.scheduleLoadAnalysisEnabled = true,
    this.userName = '',
    this.enabledTools = const [
      'search_web',
      'read_memory',
      'read_todos',
      'read_signals',
      'write_todo',
      'move_todo_date',
      'edit_todo',
      'delete_todo',
      'toggle_todo_completion',
      'create_study_timer',
      'start_project_generation',
    ],
  });

  AppSettings copyWith({
    String? deepseekApiKey,
    String? tavilyApiKey,
    bool? localTextGenerationEnabled,
    bool? localSpeechRecognitionEnabled,
    bool? showAllMonthCards,
    bool? suggestionQuestionsEnabled,
    bool? scheduleLoadAnalysisEnabled,
    String? userName,
    List<String>? enabledTools,
  }) {
    return AppSettings(
      deepseekApiKey: deepseekApiKey ?? this.deepseekApiKey,
      tavilyApiKey: tavilyApiKey ?? this.tavilyApiKey,
      localTextGenerationEnabled:
          localTextGenerationEnabled ?? this.localTextGenerationEnabled,
      localSpeechRecognitionEnabled:
          localSpeechRecognitionEnabled ?? this.localSpeechRecognitionEnabled,
      showAllMonthCards: showAllMonthCards ?? this.showAllMonthCards,
      suggestionQuestionsEnabled:
          suggestionQuestionsEnabled ?? this.suggestionQuestionsEnabled,
      scheduleLoadAnalysisEnabled:
          scheduleLoadAnalysisEnabled ?? this.scheduleLoadAnalysisEnabled,
      userName: userName ?? this.userName,
      enabledTools: enabledTools ?? this.enabledTools,
    );
  }

  Map<String, Object?> toJson({bool includeSecrets = false}) => {
    'deepseekApiKey': includeSecrets ? deepseekApiKey : '',
    'tavilyApiKey': includeSecrets ? tavilyApiKey : '',
    'localTextGenerationEnabled': localTextGenerationEnabled,
    'localSpeechRecognitionEnabled': localSpeechRecognitionEnabled,
    'showAllMonthCards': showAllMonthCards,
    'suggestionQuestionsEnabled': suggestionQuestionsEnabled,
    'scheduleLoadAnalysisEnabled': scheduleLoadAnalysisEnabled,
    'userName': userName,
    'enabledTools': enabledTools,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
    deepseekApiKey: (json['deepseekApiKey'] as String?) ?? '',
    tavilyApiKey: (json['tavilyApiKey'] as String?) ?? '',
    localTextGenerationEnabled:
        (json['localTextGenerationEnabled'] as bool?) ?? true,
    localSpeechRecognitionEnabled:
        (json['localSpeechRecognitionEnabled'] as bool?) ?? true,
    showAllMonthCards: (json['showAllMonthCards'] as bool?) ?? false,
    suggestionQuestionsEnabled:
        (json['suggestionQuestionsEnabled'] as bool?) ?? true,
    scheduleLoadAnalysisEnabled:
        (json['scheduleLoadAnalysisEnabled'] as bool?) ?? true,
    userName: (json['userName'] as String?) ?? '',
    enabledTools: {
      ...(json['enabledTools'] as List<Object?>?)
              ?.whereType<String>()
              .toSet() ??
          const {
            'search_web',
            'read_memory',
            'read_todos',
            'read_signals',
            'create_study_timer',
            'start_project_generation',
          },
      'write_todo',
      'move_todo_date',
      'edit_todo',
      'delete_todo',
      'toggle_todo_completion',
    }.toList(growable: false),
  );
}

enum StudyTimerStatus { ready, running, paused, completed, cancelled }

enum StudyTimerKind { timer, alarm }

class StudyTimer {
  final String id;
  final String toolCallId;
  final String conversationId;
  final String title;
  final StudyTimerKind kind;
  final int totalSeconds;
  final int remainingSeconds;
  final StudyTimerStatus status;
  final DateTime? startedAt;
  final DateTime? alertAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StudyTimer({
    required this.id,
    required this.toolCallId,
    required this.conversationId,
    required this.title,
    this.kind = StudyTimerKind.timer,
    required this.totalSeconds,
    required this.remainingSeconds,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.alertAt,
  });

  DateTime? get triggerAt {
    if (status != StudyTimerStatus.running) return null;
    if (kind == StudyTimerKind.alarm) return alertAt;
    if (startedAt == null) return null;
    return startedAt!.add(Duration(seconds: remainingSeconds));
  }

  int remainingAt(DateTime now) {
    if (status != StudyTimerStatus.running || startedAt == null) {
      return remainingSeconds;
    }
    if (kind == StudyTimerKind.alarm && alertAt != null) {
      return alertAt!.difference(now).inSeconds.clamp(0, totalSeconds);
    }
    return (remainingSeconds - now.difference(startedAt!).inSeconds).clamp(
      0,
      totalSeconds,
    );
  }

  StudyTimer copyWith({
    int? remainingSeconds,
    StudyTimerStatus? status,
    DateTime? startedAt,
    bool clearStartedAt = false,
    DateTime? updatedAt,
  }) => StudyTimer(
    id: id,
    toolCallId: toolCallId,
    conversationId: conversationId,
    title: title,
    kind: kind,
    totalSeconds: totalSeconds,
    remainingSeconds: remainingSeconds ?? this.remainingSeconds,
    status: status ?? this.status,
    startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
    alertAt: alertAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

// ---------------------------------------------------------------------------
// 06 轮新增：评估与规划类型
// ---------------------------------------------------------------------------

enum AssessmentVerdict { a, b, c, d }

class SearchSnippet {
  final String title;
  final String url;
  final String content;

  const SearchSnippet({
    required this.title,
    required this.url,
    required this.content,
  });

  factory SearchSnippet.fromJson(Map<String, Object?> json) => SearchSnippet(
    title: (json['title'] as String?) ?? '',
    url: (json['url'] as String?) ?? '',
    content: (json['content'] as String?) ?? '',
  );

  Map<String, Object?> toJson() => {
    'title': title,
    'url': url,
    'content': content,
  };
}

/// One compact question shown in the homepage suggestion strip.
/// It is a prompt for Sumi, never an instruction that the app executes itself.
class SuggestionQuestion {
  final String id;
  final int slot;
  final String text;
  final String intent;
  final bool isToday;
  final bool keepExisting;
  final String? todoId;
  final String? projectId;

  const SuggestionQuestion({
    required this.id,
    required this.slot,
    required this.text,
    required this.intent,
    required this.isToday,
    this.keepExisting = false,
    this.todoId,
    this.projectId,
  });

  SuggestionQuestion copyWith({
    String? id,
    int? slot,
    String? text,
    String? intent,
    bool? isToday,
    bool? keepExisting,
    Object? todoId = _suggestionQuestionUnset,
    Object? projectId = _suggestionQuestionUnset,
  }) => SuggestionQuestion(
    id: id ?? this.id,
    slot: slot ?? this.slot,
    text: text ?? this.text,
    intent: intent ?? this.intent,
    isToday: isToday ?? this.isToday,
    keepExisting: keepExisting ?? this.keepExisting,
    todoId: identical(todoId, _suggestionQuestionUnset)
        ? this.todoId
        : todoId as String?,
    projectId: identical(projectId, _suggestionQuestionUnset)
        ? this.projectId
        : projectId as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'slot': slot,
    'text': text,
    'intent': intent,
    'isToday': isToday,
    if (keepExisting) 'keepExisting': true,
    if (todoId != null) 'todoId': todoId,
    if (projectId != null) 'projectId': projectId,
  };

  factory SuggestionQuestion.fromJson(Map<String, Object?> json) =>
      SuggestionQuestion(
        id: (json['id'] as String?) ?? '',
        slot: (json['slot'] as num?)?.toInt() ?? 0,
        text: (json['text'] as String?) ?? '',
        intent: (json['intent'] as String?) ?? '',
        isToday: json['isToday'] == true,
        keepExisting: json['keepExisting'] == true,
        todoId: json['todoId'] as String?,
        projectId: json['projectId'] as String?,
      );
}

const _suggestionQuestionUnset = Object();

class GoalAssessment {
  final double clarity;
  final double feasibility;
  final double challengeFit;
  final double decomposability;
  final double timeRealism;
  final double motivationPotential;
  final double resourceAccess;
  final double measurability;
  final AssessmentVerdict verdict;
  final List<String> concerns;
  final List<String> suggestions;
  final String? estimatedHours;
  final String? domainSummary;
  final List<SearchSnippet> sources;
  final String goalSummary; // AI 对目标的凝练（2-16 字），用于项目卡标题

  const GoalAssessment({
    required this.clarity,
    required this.feasibility,
    required this.challengeFit,
    required this.decomposability,
    required this.timeRealism,
    required this.motivationPotential,
    required this.resourceAccess,
    required this.measurability,
    required this.verdict,
    this.concerns = const [],
    this.suggestions = const [],
    this.estimatedHours,
    this.domainSummary,
    this.sources = const [],
    this.goalSummary = '',
  });

  factory GoalAssessment.fromJson(Map<String, Object?> json) {
    final sourcesRaw = json['sources'] as List<Object?>?;
    return GoalAssessment(
      clarity: _parseDouble(json['clarity']),
      feasibility: _parseDouble(json['feasibility']),
      challengeFit: _parseDouble(json['challengeFit']),
      decomposability: _parseDouble(json['decomposability']),
      timeRealism: _parseDouble(json['timeRealism']),
      motivationPotential: _parseDouble(json['motivationPotential']),
      resourceAccess: _parseDouble(json['resourceAccess']),
      measurability: _parseDouble(json['measurability']),
      verdict: _parseVerdict(json['verdict']),
      concerns:
          (json['concerns'] as List<Object?>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      suggestions:
          (json['suggestions'] as List<Object?>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      estimatedHours: json['estimatedHours'] as String?,
      domainSummary: json['domainSummary'] as String?,
      sources:
          sourcesRaw
              ?.map((e) => SearchSnippet.fromJson(e as Map<String, Object?>))
              .toList() ??
          [],
      goalSummary: (json['goalSummary'] as String?) ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'clarity': clarity,
    'feasibility': feasibility,
    'challengeFit': challengeFit,
    'decomposability': decomposability,
    'timeRealism': timeRealism,
    'motivationPotential': motivationPotential,
    'resourceAccess': resourceAccess,
    'measurability': measurability,
    'verdict': verdict.name,
    'concerns': concerns,
    'suggestions': suggestions,
    if (estimatedHours != null) 'estimatedHours': estimatedHours,
    if (domainSummary != null) 'domainSummary': domainSummary,
    'sources': sources.map((s) => s.toJson()).toList(),
    if (goalSummary.isNotEmpty) 'goalSummary': goalSummary,
  };
}

double _parseDouble(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw) ?? 0.5;
  return 0.5;
}

AssessmentVerdict _parseVerdict(Object? raw) {
  final s = raw?.toString() ?? 'c';
  return AssessmentVerdict.values.firstWhere(
    (v) => v.name == s,
    orElse: () => AssessmentVerdict.c,
  );
}

// ---------------------------------------------------------------------------
// Project
// ---------------------------------------------------------------------------

class Project {
  final String id;
  final String name;
  final ProjectColor color;
  final String goal;
  final String level;
  final int cycleMonths;
  final int timeConstraint; // 小时/周，0 表示未设置
  final int currentMonthIndex;
  final DateTime createdAt;
  final String? lastAssessmentJson; // 06 轮：最近一次评估结果 JSON
  final String goalSummary; // AI 对目标的凝练（5-15 字），用于项目卡标题

  const Project({
    required this.id,
    required this.name,
    required this.color,
    this.goal = '',
    this.level = '',
    this.cycleMonths = 3,
    this.timeConstraint = 0,
    this.currentMonthIndex = 0,
    required this.createdAt,
    this.lastAssessmentJson,
    this.goalSummary = '',
  });

  Project copyWith({
    String? name,
    ProjectColor? color,
    String? goal,
    String? level,
    int? cycleMonths,
    int? timeConstraint,
    int? currentMonthIndex,
    String? lastAssessmentJson,
    String? goalSummary,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      goal: goal ?? this.goal,
      level: level ?? this.level,
      cycleMonths: cycleMonths ?? this.cycleMonths,
      timeConstraint: timeConstraint ?? this.timeConstraint,
      currentMonthIndex: currentMonthIndex ?? this.currentMonthIndex,
      createdAt: createdAt,
      lastAssessmentJson: lastAssessmentJson ?? this.lastAssessmentJson,
      goalSummary: goalSummary ?? this.goalSummary,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'color': color.name,
    'goal': goal,
    'level': level,
    'cycleMonths': cycleMonths,
    'timeConstraint': timeConstraint,
    'currentMonthIndex': currentMonthIndex,
    'createdAt': createdAt.toIso8601String(),
    if (lastAssessmentJson != null) 'lastAssessmentJson': lastAssessmentJson,
    if (goalSummary.isNotEmpty) 'goalSummary': goalSummary,
  };

  factory Project.fromJson(Map<String, Object?> json) {
    final colorName = (json['color'] as String?) ?? 'lemon';
    return Project(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      color: ProjectColor.values.firstWhere(
        (c) => c.name == colorName,
        orElse: () => ProjectColor.lemon,
      ),
      goal: (json['goal'] as String?) ?? '',
      level: (json['level'] as String?) ?? '',
      cycleMonths: (json['cycleMonths'] as num?)?.toInt() ?? 3,
      timeConstraint: _parseTimeConstraint(json['timeConstraint']),
      currentMonthIndex: (json['currentMonthIndex'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      lastAssessmentJson: json['lastAssessmentJson'] as String?,
      goalSummary: (json['goalSummary'] as String?) ?? '',
    );
  }
}

/// 兼容迁移：旧版 timeConstraint 为 String，新版为 int（小时/周）。
int _parseTimeConstraint(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? 0;
  return 0;
}

// ---------------------------------------------------------------------------
// MonthCard
// ---------------------------------------------------------------------------

class MonthCard {
  final String id;
  final String projectId;
  final int monthIndex;
  final String title;
  final String? summary;
  final bool aiGenerated; // AI 生成标记

  const MonthCard({
    required this.id,
    required this.projectId,
    required this.monthIndex,
    required this.title,
    this.summary,
    this.aiGenerated = false,
  });

  MonthCard copyWith({String? title, String? summary, bool? aiGenerated}) {
    return MonthCard(
      id: id,
      projectId: projectId,
      monthIndex: monthIndex,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      aiGenerated: aiGenerated ?? this.aiGenerated,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'projectId': projectId,
    'monthIndex': monthIndex,
    'title': title,
    'summary': summary,
    'aiGenerated': aiGenerated,
  };

  factory MonthCard.fromJson(Map<String, Object?> json) => MonthCard(
    id: (json['id'] as String?) ?? '',
    projectId: (json['projectId'] as String?) ?? '',
    monthIndex: (json['monthIndex'] as num?)?.toInt() ?? 0,
    title: (json['title'] as String?) ?? '',
    summary: json['summary'] as String?,
    aiGenerated: (json['aiGenerated'] as bool?) ?? false,
  );
}

/// 可追溯的项目进展节点，不属于普通长期记忆。
class Milestone {
  final String id;
  final String projectId;
  final String todoId;
  final String sourceMessageId;
  final String quote;
  final String todoTitle;
  final int monthIndex;
  final DateTime occurredAt;
  final String? memoryId;

  const Milestone({
    required this.id,
    required this.projectId,
    required this.todoId,
    required this.sourceMessageId,
    required this.quote,
    required this.todoTitle,
    required this.monthIndex,
    required this.occurredAt,
    this.memoryId,
  });
}

// ---------------------------------------------------------------------------
// Conversation
// ---------------------------------------------------------------------------

class Conversation {
  final String id;
  final String dateKey;
  final String title;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Conversation({
    required this.id,
    this.dateKey = '',
    this.title = '',
    this.pinned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Conversation copyWith({
    String? dateKey,
    String? title,
    bool? pinned,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id,
      dateKey: dateKey ?? this.dateKey,
      title: title ?? this.title,
      pinned: pinned ?? this.pinned,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'dateKey': dateKey,
    'title': title,
    'pinned': pinned,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Conversation.fromJson(Map<String, Object?> json) => Conversation(
    id: (json['id'] as String?) ?? '',
    dateKey: (json['dateKey'] as String?) ?? '',
    title: (json['title'] as String?) ?? '',
    pinned: (json['pinned'] as bool?) ?? false,
    createdAt:
        DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
        DateTime.now(),
    updatedAt:
        DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
        DateTime.now(),
  );
}

// ---------------------------------------------------------------------------
// ChatMessage
// ---------------------------------------------------------------------------

/// A persisted user-message match returned by monthly local search.
class ChatSearchResult {
  final String messageId;
  final String conversationId;
  final DateTime date;
  final String content;
  final DateTime createdAt;
  final String role;

  const ChatSearchResult({
    required this.messageId,
    required this.conversationId,
    required this.date,
    required this.content,
    required this.createdAt,
    required this.role,
  });
}

/// A persisted chat message with the calendar date of its conversation.
class MonthChatMessage {
  final DateTime date;
  final ChatMessage message;

  const MonthChatMessage({required this.date, required this.message});
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String role; // 'user' | 'assistant' | 'tool'
  final String content;
  final DateTime createdAt;
  final String? reasoningContent; // AI 思考过程（仅 assistant 消息）
  final String? toolCallsJson; // 工具调用 JSON（仅 assistant 消息，DB 序列化用）
  final String? toolCallId; // tool 消息对应的 tool_call_id（仅 tool 消息）
  final String? todoResultJson;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    this.content = '',
    required this.createdAt,
    this.reasoningContent,
    this.toolCallsJson,
    this.toolCallId,
    this.todoResultJson,
  });

  ChatMessage copyWith({
    String? content,
    String? reasoningContent,
    String? toolCallsJson,
    String? toolCallId,
    String? todoResultJson,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      toolCallsJson: toolCallsJson ?? this.toolCallsJson,
      toolCallId: toolCallId ?? this.toolCallId,
      todoResultJson: todoResultJson ?? this.todoResultJson,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'conversationId': conversationId,
    'role': role,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    if (reasoningContent != null) 'reasoningContent': reasoningContent,
    if (toolCallsJson != null) 'toolCallsJson': toolCallsJson,
    if (toolCallId != null) 'toolCallId': toolCallId,
    if (todoResultJson != null) 'todoResultJson': todoResultJson,
  };

  factory ChatMessage.fromJson(Map<String, Object?> json) => ChatMessage(
    id: (json['id'] as String?) ?? '',
    conversationId: (json['conversationId'] as String?) ?? '',
    role: (json['role'] as String?) ?? 'user',
    content: (json['content'] as String?) ?? '',
    createdAt:
        DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
        DateTime.now(),
    reasoningContent: json['reasoningContent'] as String?,
    toolCallsJson: json['toolCallsJson'] as String?,
    toolCallId: json['toolCallId'] as String?,
    todoResultJson: json['todoResultJson'] as String?,
  );
}

// ---------------------------------------------------------------------------
// TodoItem
// ---------------------------------------------------------------------------

class TodoItem {
  final String id;
  final TodoSource source;
  final String? projectId; // system todo 必填，user todo 为 null
  final String? date; // ISO8601，用户分配日期；null = 未分配（在所有日期显示）
  final String title;
  final String? body;
  final bool done;
  final bool pinned; // 置顶
  final int sortOrder; // 手动排序序号（越大越靠前）
  final DateTime? completedAt;
  final String? reminderTime; // 提醒时间 "HH:mm"
  final DateTime createdAt;
  final String? condensedFrom; // 07 轮：AI 凝练前原始文本，用于凝练还原保护

  const TodoItem({
    required this.id,
    required this.source,
    this.projectId,
    this.date,
    required this.title,
    this.body,
    this.done = false,
    this.pinned = false,
    this.sortOrder = 0,
    this.completedAt,
    this.reminderTime,
    required this.createdAt,
    this.condensedFrom,
  });

  /// 判断 todo 是否属于指定日期。
  /// [date] 为 null 的 todo 仅归入今天。
  static bool belongsToDate(
    TodoItem t,
    String selectedDateKey,
    String todayKey,
  ) => t.date != null ? t.date == selectedDateKey : selectedDateKey == todayKey;

  /// copyWith 中用来表示“该字段未被传入”的哨兵，与显式传 null（清空字段）区分。
  /// 外部 mutation 方法（如 [updateTodo]）可用它来表达“不修改”。
  static const Object undefined = Symbol('TodoItem.undefined');

  TodoItem copyWith({
    String? title,
    Object? body = undefined,
    bool? done,
    bool? pinned,
    int? sortOrder,
    Object? completedAt = undefined,
    Object? reminderTime = undefined,
    Object? date = undefined,
    Object? projectId = undefined,
    Object? condensedFrom = undefined,
  }) {
    return TodoItem(
      id: id,
      source: source,
      projectId: projectId == undefined ? this.projectId : projectId as String?,
      date: date == undefined ? this.date : date as String?,
      title: title ?? this.title,
      body: body == undefined ? this.body : body as String?,
      done: done ?? this.done,
      pinned: pinned ?? this.pinned,
      sortOrder: sortOrder ?? this.sortOrder,
      completedAt: completedAt == undefined
          ? this.completedAt
          : completedAt as DateTime?,
      reminderTime: reminderTime == undefined
          ? this.reminderTime
          : reminderTime as String?,
      createdAt: createdAt,
      condensedFrom: condensedFrom == undefined
          ? this.condensedFrom
          : condensedFrom as String?,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'source': source.name,
    'projectId': projectId,
    'date': date,
    'title': title,
    'body': body,
    'done': done,
    'pinned': pinned,
    'sortOrder': sortOrder,
    'completedAt': completedAt?.toIso8601String(),
    'reminderTime': reminderTime,
    'createdAt': createdAt.toIso8601String(),
    if (condensedFrom != null) 'condensedFrom': condensedFrom,
  };

  factory TodoItem.fromJson(Map<String, Object?> json) {
    final sourceName = (json['source'] as String?) ?? 'user';
    return TodoItem(
      id: (json['id'] as String?) ?? '',
      source: TodoSource.values.firstWhere(
        (s) => s.name == sourceName,
        orElse: () => TodoSource.user,
      ),
      projectId: json['projectId'] as String?,
      date: json['date'] as String?,
      title: (json['title'] as String?) ?? '',
      body: json['body'] as String?,
      done: (json['done'] as bool?) ?? false,
      pinned: (json['pinned'] as bool?) ?? false,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.tryParse(json['completedAt'] as String),
      reminderTime: json['reminderTime'] as String?,
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      condensedFrom: json['condensedFrom'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// 07 轮新增：用户信号
// ---------------------------------------------------------------------------

class UserSignal {
  final int? id; // DB 自增主键
  final SignalType signal;
  final DateTime time;
  final String
  contextJson; // JSON 字符串：title, project, domain, plannedDate, completedOnTime, hourOfDay 等
  final String? projectId;
  final String? todoId;
  final String? domain;
  final DateTime createdAt;

  const UserSignal({
    this.id,
    required this.signal,
    required this.time,
    this.contextJson = '{}',
    this.projectId,
    this.todoId,
    this.domain,
    required this.createdAt,
  });

  /// 解析 contextJson 为 Map（供展示用）。
  Map<String, Object?> get context => _parseContext(contextJson);

  Map<String, Object?> _parseContext(String json) {
    try {
      final decoded = const JsonDecoder().convert(json);
      if (decoded is Map<String, Object?>) return decoded;
    } catch (_) {}
    return {};
  }

  Map<String, Object?> toJson() => {
    if (id != null) 'id': id,
    'signal': signal.name,
    'time': time.toIso8601String(),
    'contextJson': contextJson,
    'projectId': projectId,
    'todoId': todoId,
    'domain': domain,
    'createdAt': createdAt.toIso8601String(),
  };

  factory UserSignal.fromJson(Map<String, Object?> json) {
    final signalName = (json['signal'] as String?) ?? 'todoCreated';
    return UserSignal(
      id: json['id'] as int?,
      signal: SignalType.values.firstWhere(
        (s) => s.name == signalName,
        orElse: () => SignalType.todoCreated,
      ),
      time:
          DateTime.tryParse((json['time'] as String?) ?? '') ?? DateTime.now(),
      contextJson: (json['contextJson'] as String?) ?? '{}',
      projectId: json['projectId'] as String?,
      todoId: json['todoId'] as String?,
      domain: json['domain'] as String?,
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}
