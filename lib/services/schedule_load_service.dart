import '../models/models.dart';
import 'ai_service.dart';
import '../utils/utils.dart';

enum ScheduleProposalStatus { pending, accepted, dismissed }

/// The system card first asks whether the user wants help, then shows a
/// preview, and finally remains as a non-actionable completion record.
enum ScheduleProposalStage { attention, preview, completed }

const _scheduleProposalUnset = Object();

class ScheduleMove {
  final String todoId;
  final String fromDate;
  final String toDate;
  final String title;

  const ScheduleMove({
    required this.todoId,
    required this.fromDate,
    required this.toDate,
    required this.title,
  });

  Map<String, Object?> toJson() => {
    'todoId': todoId,
    'fromDate': fromDate,
    'toDate': toDate,
    'title': title,
  };

  factory ScheduleMove.fromJson(Map<String, Object?> json) => ScheduleMove(
    todoId: (json['todoId'] as String?) ?? '',
    fromDate: (json['fromDate'] as String?) ?? '',
    toDate: (json['toDate'] as String?) ?? '',
    title: (json['title'] as String?) ?? '',
  );
}

class ScheduleRebalanceProposal {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String fingerprint;
  final double overloadScore;
  final List<String> reasons;
  final List<ScheduleMove> moves;
  final List<String> unscheduledTodoIds;
  final ScheduleProposalStatus status;
  final ScheduleProposalStage stage;
  final String? displayAnchorMessageId;
  final DateTime? completedAt;
  final int? completedMoveCount;
  final bool notificationSent;
  final String? conversationId;
  final String? lastNotificationDate;
  final double? lastNotificationRisk;
  final int notificationsOnLastDate;

  const ScheduleRebalanceProposal({
    required this.id,
    required this.createdAt,
    DateTime? updatedAt,
    required this.fingerprint,
    required this.overloadScore,
    required this.reasons,
    required this.moves,
    required this.unscheduledTodoIds,
    this.status = ScheduleProposalStatus.pending,
    this.stage = ScheduleProposalStage.preview,
    this.displayAnchorMessageId,
    this.completedAt,
    this.completedMoveCount,
    this.notificationSent = false,
    this.conversationId,
    this.lastNotificationDate,
    this.lastNotificationRisk,
    this.notificationsOnLastDate = 0,
  }) : updatedAt = updatedAt ?? createdAt;

  ScheduleRebalanceProposal copyWith({
    ScheduleProposalStatus? status,
    ScheduleProposalStage? stage,
    DateTime? updatedAt,
    Object? displayAnchorMessageId = _scheduleProposalUnset,
    Object? completedAt = _scheduleProposalUnset,
    int? completedMoveCount,
    bool? notificationSent,
    String? conversationId,
    String? lastNotificationDate,
    double? lastNotificationRisk,
    int? notificationsOnLastDate,
  }) => ScheduleRebalanceProposal(
    id: id,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    fingerprint: fingerprint,
    overloadScore: overloadScore,
    reasons: reasons,
    moves: moves,
    unscheduledTodoIds: unscheduledTodoIds,
    status: status ?? this.status,
    stage: stage ?? this.stage,
    displayAnchorMessageId:
        identical(displayAnchorMessageId, _scheduleProposalUnset)
        ? this.displayAnchorMessageId
        : displayAnchorMessageId as String?,
    completedAt: identical(completedAt, _scheduleProposalUnset)
        ? this.completedAt
        : completedAt as DateTime?,
    completedMoveCount: completedMoveCount ?? this.completedMoveCount,
    notificationSent: notificationSent ?? this.notificationSent,
    conversationId: conversationId ?? this.conversationId,
    lastNotificationDate: lastNotificationDate ?? this.lastNotificationDate,
    lastNotificationRisk: lastNotificationRisk ?? this.lastNotificationRisk,
    notificationsOnLastDate:
        notificationsOnLastDate ?? this.notificationsOnLastDate,
  );

  /// Converts an accepted preview into a durable, non-actionable chat record.
  ScheduleRebalanceProposal complete({
    required int movedCount,
    DateTime? completedAt,
    Object? displayAnchorMessageId = _scheduleProposalUnset,
  }) => copyWith(
    status: ScheduleProposalStatus.accepted,
    stage: ScheduleProposalStage.completed,
    completedAt: completedAt ?? DateTime.now(),
    completedMoveCount: movedCount,
    displayAnchorMessageId: displayAnchorMessageId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'fingerprint': fingerprint,
    'overloadScore': overloadScore,
    'reasons': reasons,
    'moves': moves.map((move) => move.toJson()).toList(),
    'unscheduledTodoIds': unscheduledTodoIds,
    'status': status.name,
    'stage': stage.name,
    if (displayAnchorMessageId != null)
      'displayAnchorMessageId': displayAnchorMessageId,
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (completedMoveCount != null) 'completedMoveCount': completedMoveCount,
    'notificationSent': notificationSent,
    if (conversationId != null) 'conversationId': conversationId,
    if (lastNotificationDate != null)
      'lastNotificationDate': lastNotificationDate,
    if (lastNotificationRisk != null)
      'lastNotificationRisk': lastNotificationRisk,
    'notificationsOnLastDate': notificationsOnLastDate,
  };

  factory ScheduleRebalanceProposal.fromJson(
    Map<String, Object?> json,
  ) => ScheduleRebalanceProposal(
    id: (json['id'] as String?) ?? '',
    createdAt:
        DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
        DateTime.now(),
    updatedAt:
        DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
        DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
        DateTime.now(),
    fingerprint: (json['fingerprint'] as String?) ?? '',
    overloadScore: (json['overloadScore'] as num?)?.toDouble() ?? 0,
    reasons:
        (json['reasons'] as List<Object?>?)?.whereType<String>().toList(
          growable: false,
        ) ??
        const [],
    moves:
        (json['moves'] as List<Object?>?)
            ?.whereType<Map>()
            .map((item) => ScheduleMove.fromJson(item.cast<String, Object?>()))
            .toList(growable: false) ??
        const [],
    unscheduledTodoIds:
        (json['unscheduledTodoIds'] as List<Object?>?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const [],
    status: ScheduleProposalStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => ScheduleProposalStatus.dismissed,
    ),
    // Proposals saved before stages existed already contain a full move
    // list, so preserve their former preview presentation.
    stage: ScheduleProposalStage.values.firstWhere(
      (value) => value.name == json['stage'],
      orElse: () => ScheduleProposalStage.preview,
    ),
    displayAnchorMessageId: json['displayAnchorMessageId'] as String?,
    completedAt: DateTime.tryParse((json['completedAt'] as String?) ?? ''),
    completedMoveCount: (json['completedMoveCount'] as num?)?.toInt(),
    notificationSent: json['notificationSent'] == true,
    conversationId: json['conversationId'] as String?,
    lastNotificationDate: json['lastNotificationDate'] as String?,
    lastNotificationRisk: (json['lastNotificationRisk'] as num?)?.toDouble(),
    notificationsOnLastDate: (json['notificationsOnLastDate'] as int?) ?? 0,
  );
}

/// Produces a local preview after AI has judged today's task semantics.
class ScheduleLoadAssessor {
  /// 触发条件来自 AI 对“今天事项语义”的判断；本地只负责预览移动目标。
  ScheduleRebalanceProposal? proposeForToday({
    required TodayLoadAnalysis analysis,
    required List<TodoItem> todos,
    required DateTime today,
    required String fingerprint,
    String? conversationId,
  }) {
    if (!analysis.needsRebalance) return null;
    final todayKey = dateKey(today);
    final movableIds = analysis.movableTodoIds.toSet();
    final candidates = todos
        .where(
          (todo) =>
              movableIds.contains(todo.id) &&
              todo.date == todayKey &&
              !todo.done &&
              !todo.pinned &&
              todo.reminderTime == null,
        )
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    final days = analysis.futureDayPressure.keys.map(DateTime.parse).toList()
      ..sort();
    if (days.isEmpty) return null;
    final loads = {
      for (final day in days) dateKey(day): _loadForDate(todos, day),
    };
    final moves = <ScheduleMove>[];
    final unscheduled = <String>[];
    for (final todo in candidates) {
      final target = _findBestFutureDate(
        days,
        loads,
        todo,
        todos,
        analysis.futureDayPressure,
      );
      if (target == null) {
        unscheduled.add(todo.id);
        continue;
      }
      final targetKey = dateKey(target);
      loads[todayKey] = (loads[todayKey] ?? 0) - _weight(todo);
      loads[targetKey] = (loads[targetKey] ?? 0) + _weight(todo);
      moves.add(
        ScheduleMove(
          todoId: todo.id,
          fromDate: todayKey,
          toDate: targetKey,
          title: todo.title,
        ),
      );
    }
    if (moves.isEmpty && unscheduled.isEmpty) return null;
    return ScheduleRebalanceProposal(
      id: newSumiId('rebalance'),
      createdAt: DateTime.now(),
      fingerprint: fingerprint,
      overloadScore: analysis.risk,
      reasons: analysis.reasons,
      moves: moves,
      unscheduledTodoIds: unscheduled,
      conversationId: conversationId,
    );
  }

  /// Prefer the nearest low-pressure day. Project continuity breaks ties.
  static DateTime? _findBestFutureDate(
    List<DateTime> days,
    Map<String, double> loads,
    TodoItem todo,
    List<TodoItem> todos,
    Map<String, double> semanticPressure,
  ) {
    final candidates = List<DateTime>.of(days)
      ..sort((a, b) {
        final aKey = dateKey(a);
        final bKey = dateKey(b);
        final aLoad = loads[aKey] ?? 0;
        final bLoad = loads[bKey] ?? 0;
        final aProject = _projectSwitchCost(aKey, todo.projectId, todos);
        final bProject = _projectSwitchCost(bKey, todo.projectId, todos);
        final aPressure = semanticPressure[aKey] ?? 1;
        final bPressure = semanticPressure[bKey] ?? 1;
        final aScore =
            aPressure * 3 +
            aLoad * .15 +
            aProject * .35 +
            a.difference(days.first).inDays * .04;
        final bScore =
            bPressure * 3 +
            bLoad * .15 +
            bProject * .35 +
            b.difference(days.first).inDays * .04;
        return aScore.compareTo(bScore);
      });
    for (final candidate in candidates) {
      if ((semanticPressure[dateKey(candidate)] ?? 1) <= .58) return candidate;
    }
    return null;
  }

  static double _projectSwitchCost(
    String date,
    String? projectId,
    List<TodoItem> todos,
  ) {
    final dayTodos = todos.where((todo) => !todo.done && todo.date == date);
    final hasSameProject =
        projectId != null &&
        dayTodos.any((todo) => todo.projectId == projectId);
    final projectCount = dayTodos
        .map((todo) => todo.projectId ?? 'user')
        .toSet()
        .length;
    return (hasSameProject ? -.5 : .25) + projectCount * .15;
  }

  static double _weight(TodoItem todo) {
    var value = todo.source == TodoSource.system ? 1.0 : 1.1;
    if (todo.pinned) value += .6;
    if (todo.reminderTime != null) value += .4;
    return value;
  }

  static double _loadForDate(List<TodoItem> todos, DateTime day) {
    final key = dateKey(day);
    return todos
        .where((todo) => !todo.done && todo.date == key)
        .fold<double>(0, (sum, todo) => sum + _weight(todo));
  }
}
