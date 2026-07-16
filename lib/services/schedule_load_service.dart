import 'dart:convert';

import '../models/models.dart';
import '../utils/utils.dart';

enum ScheduleProposalStatus { pending, accepted, dismissed }

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
  final String fingerprint;
  final double overloadScore;
  final List<String> reasons;
  final List<ScheduleMove> moves;
  final List<String> unscheduledTodoIds;
  final ScheduleProposalStatus status;
  final bool notificationSent;

  const ScheduleRebalanceProposal({
    required this.id,
    required this.createdAt,
    required this.fingerprint,
    required this.overloadScore,
    required this.reasons,
    required this.moves,
    required this.unscheduledTodoIds,
    this.status = ScheduleProposalStatus.pending,
    this.notificationSent = false,
  });

  ScheduleRebalanceProposal copyWith({
    ScheduleProposalStatus? status,
    bool? notificationSent,
  }) =>
      ScheduleRebalanceProposal(
        id: id,
        createdAt: createdAt,
        fingerprint: fingerprint,
        overloadScore: overloadScore,
        reasons: reasons,
        moves: moves,
        unscheduledTodoIds: unscheduledTodoIds,
        status: status ?? this.status,
        notificationSent: notificationSent ?? this.notificationSent,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'fingerprint': fingerprint,
    'overloadScore': overloadScore,
    'reasons': reasons,
    'moves': moves.map((move) => move.toJson()).toList(),
    'unscheduledTodoIds': unscheduledTodoIds,
    'status': status.name,
    'notificationSent': notificationSent,
  };

  factory ScheduleRebalanceProposal.fromJson(Map<String, Object?> json) =>
      ScheduleRebalanceProposal(
        id: (json['id'] as String?) ?? '',
        createdAt:
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
        notificationSent: json['notificationSent'] == true,
      );
}

class ScheduleLoadAssessment {
  final double score;
  final String fingerprint;
  final List<String> reasons;
  final Map<String, double> dayLoads;
  final double dailyCapacity;

  const ScheduleLoadAssessment({
    required this.score,
    required this.fingerprint,
    required this.reasons,
    required this.dayLoads,
    required this.dailyCapacity,
  });

  bool get overloaded => score > 0;
}

/// Evaluates and rebalances only future, movable work. It never mutates Todos.
class ScheduleLoadAssessor {
  static const _windowDays = 7;
  static const _searchDays = 21;

  ScheduleLoadAssessment assess({
    required List<Project> projects,
    required List<TodoItem> todos,
    required DateTime today,
  }) {
    final days = _days(today, _windowDays);
    final loads = {for (final day in days) dateKey(day): 0.0};
    for (final todo in todos) {
      if (todo.done || todo.date == null || !loads.containsKey(todo.date)) {
        continue;
      }
      loads[todo.date!] = loads[todo.date!]! + _weight(todo);
    }
    final weeklyHours = projects.fold<int>(
      0,
      (sum, project) =>
          sum + (project.timeConstraint > 0 ? project.timeConstraint : 7),
    );
    final weeklyCapacity = (weeklyHours / 2).clamp(2, 70).toDouble();
    final dailyCapacity = (weeklyCapacity / _windowDays).clamp(1.5, 10.0);
    final total = loads.values.fold<double>(0, (sum, value) => sum + value);
    final reasons = <String>[];
    var score = 0.0;
    if (total > weeklyCapacity * 1.2) {
      score += total - weeklyCapacity * 1.2;
      reasons.add('未来 7 天事项较多，超过当前项目投入可承受范围');
    }
    final highDays = loads.entries
        .where((entry) => entry.value > dailyCapacity * 1.5)
        .toList();
    if (highDays.isNotEmpty) {
      score += highDays.fold<double>(
        0,
        (sum, entry) => sum + entry.value - dailyCapacity * 1.5,
      );
      reasons.add('${highDays.length} 天任务集中，可能影响完成质量');
    }
    for (var index = 0; index < days.length - 1; index++) {
      final first = loads[dateKey(days[index])]!;
      final second = loads[dateKey(days[index + 1])]!;
      if (first > dailyCapacity * 1.25 && second > dailyCapacity * 1.25) {
        score += .5;
        if (!reasons.contains('连续高负荷日较多，恢复空间不足')) {
          reasons.add('连续高负荷日较多，恢复空间不足');
        }
      }
    }
    final fingerprint = jsonEncode({
      'start': dateKey(today),
      'loads': loads.map(
        (key, value) => MapEntry(key, value.toStringAsFixed(1)),
      ),
      'projects': projects
          .map((project) => '${project.id}:${project.timeConstraint}')
          .toList(),
    });
    return ScheduleLoadAssessment(
      score: score,
      fingerprint: fingerprint,
      reasons: reasons,
      dayLoads: loads,
      dailyCapacity: dailyCapacity,
    );
  }

  ScheduleRebalanceProposal? propose({
    required ScheduleLoadAssessment assessment,
    required List<TodoItem> todos,
    required DateTime today,
  }) {
    if (!assessment.overloaded) return null;
    final loads = Map<String, double>.of(assessment.dayLoads);
    final days = _days(today, _searchDays);
    for (final day in days.skip(_windowDays)) {
      loads.putIfAbsent(dateKey(day), () => _loadForDate(todos, day));
    }
    final candidates =
        todos
            .where(
              (todo) =>
                  !todo.done &&
                  !todo.pinned &&
                  todo.reminderTime == null &&
                  todo.date != null &&
                  !DateTime.parse(todo.date!).isBefore(dateOnly(today)),
            )
            .toList(growable: false)
          ..sort((a, b) => b.sortOrder.compareTo(a.sortOrder));
    final moves = <ScheduleMove>[];
    final unscheduled = <String>[];
    for (final todo in candidates) {
      final from = todo.date!;
      final fromLoad = loads[from] ?? 0;
      if (fromLoad <= assessment.dailyCapacity * 1.15) continue;
      final target = days
          .skipWhile((day) => dateKey(day).compareTo(from) <= 0)
          .where((day) => (loads[dateKey(day)] ?? 0) < assessment.dailyCapacity)
          .cast<DateTime?>()
          .firstWhere((day) => day != null, orElse: () => null);
      if (target == null) {
        unscheduled.add(todo.id);
        continue;
      }
      final targetKey = dateKey(target);
      final weight = _weight(todo);
      loads[from] = fromLoad - weight;
      loads[targetKey] = (loads[targetKey] ?? 0) + weight;
      moves.add(
        ScheduleMove(
          todoId: todo.id,
          fromDate: from,
          toDate: targetKey,
          title: todo.title,
        ),
      );
    }
    if (moves.isEmpty && unscheduled.isEmpty) return null;
    return ScheduleRebalanceProposal(
      id: newSumiId('rebalance'),
      createdAt: DateTime.now(),
      fingerprint: assessment.fingerprint,
      overloadScore: assessment.score,
      reasons: assessment.reasons,
      moves: moves,
      unscheduledTodoIds: unscheduled,
    );
  }

  static List<DateTime> _days(DateTime start, int count) => [
    for (var index = 0; index < count; index++)
      dateOnly(start.add(Duration(days: index))),
  ];

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
