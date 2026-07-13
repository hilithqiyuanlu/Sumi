/// Sumi 数据模型 —— 所有模型集中在一个文件。

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum TodoSource { user, system }

enum ProjectColor {
  lemon,
  mint,
  lilac,
  cherry,
  sky,
  peach,
  sage,
  lavender,
  warmGray,
  coolGray,
}

// ---------------------------------------------------------------------------
// AppSettings
// ---------------------------------------------------------------------------

class AppSettings {
  final String deepseekApiKey;
  final String tavilyApiKey;
  final String plannerModel; // 预留：deepseek-v4-pro
  final String defaultModel; // 预留：deepseek-v4-flash

  const AppSettings({
    this.deepseekApiKey = '',
    this.tavilyApiKey = '',
    this.plannerModel = 'deepseek-v4-pro',
    this.defaultModel = 'deepseek-v4-flash',
  });

  AppSettings copyWith({
    String? deepseekApiKey,
    String? tavilyApiKey,
    String? plannerModel,
    String? defaultModel,
  }) {
    return AppSettings(
      deepseekApiKey: deepseekApiKey ?? this.deepseekApiKey,
      tavilyApiKey: tavilyApiKey ?? this.tavilyApiKey,
      plannerModel: plannerModel ?? this.plannerModel,
      defaultModel: defaultModel ?? this.defaultModel,
    );
  }

  Map<String, Object?> toJson({bool includeSecrets = false}) => {
        'deepseekApiKey': includeSecrets ? deepseekApiKey : '',
        'tavilyApiKey': includeSecrets ? tavilyApiKey : '',
        'plannerModel': plannerModel,
        'defaultModel': defaultModel,
      };

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
        deepseekApiKey: (json['deepseekApiKey'] as String?) ?? '',
        tavilyApiKey: (json['tavilyApiKey'] as String?) ?? '',
        plannerModel:
            (json['plannerModel'] as String?) ?? 'deepseek-v4-pro',
        defaultModel:
            (json['defaultModel'] as String?) ?? 'deepseek-v4-flash',
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
  });

  Project copyWith({
    String? name,
    ProjectColor? color,
    String? goal,
    String? level,
    int? cycleMonths,
    int? timeConstraint,
    int? currentMonthIndex,
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
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
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

  const MonthCard({
    required this.id,
    required this.projectId,
    required this.monthIndex,
    required this.title,
    this.summary,
  });

  MonthCard copyWith({
    String? title,
    String? summary,
  }) {
    return MonthCard(
      id: id,
      projectId: projectId,
      monthIndex: monthIndex,
      title: title ?? this.title,
      summary: summary ?? this.summary,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'projectId': projectId,
        'monthIndex': monthIndex,
        'title': title,
        'summary': summary,
      };

  factory MonthCard.fromJson(Map<String, Object?> json) => MonthCard(
        id: (json['id'] as String?) ?? '',
        projectId: (json['projectId'] as String?) ?? '',
        monthIndex: (json['monthIndex'] as num?)?.toInt() ?? 0,
        title: (json['title'] as String?) ?? '',
        summary: json['summary'] as String?,
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
  });

  TodoItem copyWith({
    String? title,
    String? body,
    bool? done,
    bool? pinned,
    int? sortOrder,
    String? reminderTime,
    String? date,
    String? projectId,
  }) {
    return TodoItem(
      id: id,
      source: source,
      projectId: projectId ?? this.projectId,
      date: date ?? this.date,
      title: title ?? this.title,
      body: body ?? this.body,
      done: done ?? this.done,
      pinned: pinned ?? this.pinned,
      sortOrder: sortOrder ?? this.sortOrder,
      reminderTime: reminderTime ?? this.reminderTime,
      createdAt: createdAt,
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
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}
