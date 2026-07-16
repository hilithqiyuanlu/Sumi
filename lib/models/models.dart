import 'dart:convert';

/// Sumi 数据模型 —— 所有模型集中在一个文件。

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum TodoSource { user, system }

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
  final bool thinkingEnabled;
  final bool showAllMonthCards; // 开发者开关：披露全部月卡
  final String userName; // 用户昵称
  final List<String> enabledTools;

  const AppSettings({
    this.deepseekApiKey = '',
    this.tavilyApiKey = '',
    this.thinkingEnabled = true,
    this.showAllMonthCards = false,
    this.userName = '',
    this.enabledTools = const [
      'search_web',
      'read_memory',
      'read_todos',
      'read_signals',
      'write_todo',
      'create_study_timer',
      'start_project_generation',
    ],
  });

  AppSettings copyWith({
    String? deepseekApiKey,
    String? tavilyApiKey,
    bool? thinkingEnabled,
    bool? showAllMonthCards,
    String? userName,
    List<String>? enabledTools,
  }) {
    return AppSettings(
      deepseekApiKey: deepseekApiKey ?? this.deepseekApiKey,
      tavilyApiKey: tavilyApiKey ?? this.tavilyApiKey,
      thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
      showAllMonthCards: showAllMonthCards ?? this.showAllMonthCards,
      userName: userName ?? this.userName,
      enabledTools: enabledTools ?? this.enabledTools,
    );
  }

  Map<String, Object?> toJson({bool includeSecrets = false}) => {
    'deepseekApiKey': includeSecrets ? deepseekApiKey : '',
    'tavilyApiKey': includeSecrets ? tavilyApiKey : '',
    'thinkingEnabled': thinkingEnabled,
    'showAllMonthCards': showAllMonthCards,
    'userName': userName,
    'enabledTools': enabledTools,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
    deepseekApiKey: (json['deepseekApiKey'] as String?) ?? '',
    tavilyApiKey: (json['tavilyApiKey'] as String?) ?? '',
    thinkingEnabled: (json['thinkingEnabled'] as bool?) ?? true,
    showAllMonthCards: (json['showAllMonthCards'] as bool?) ?? false,
    userName: (json['userName'] as String?) ?? '',
    enabledTools:
        (json['enabledTools'] as List<Object?>?)
            ?.whereType<String>()
            .toSet()
            .toList(growable: false) ??
        const [
          'search_web',
          'read_memory',
          'read_todos',
          'read_signals',
          'write_todo',
          'create_study_timer',
          'start_project_generation',
        ],
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

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    this.content = '',
    required this.createdAt,
    this.reasoningContent,
    this.toolCallsJson,
    this.toolCallId,
  });

  ChatMessage copyWith({
    String? content,
    String? reasoningContent,
    String? toolCallsJson,
    String? toolCallId,
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
