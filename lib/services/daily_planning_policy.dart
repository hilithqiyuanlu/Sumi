import '../models/models.dart';
import '../utils/utils.dart';

class DailyPlanningPolicy {
  const DailyPlanningPolicy._();

  static int scheduledCountForWeek({
    required List<TodoItem> todos,
    required String projectId,
    required DateTime today,
  }) {
    final weekStart = dateKey(
      today.subtract(Duration(days: today.weekday - 1)),
    );
    final nextWeekStart = dateKey(
      today.add(Duration(days: 8 - today.weekday)),
    );
    return todos
        .where(
          (todo) =>
              todo.source == TodoSource.system &&
              todo.projectId == projectId &&
              todo.date != null &&
              todo.date!.compareTo(weekStart) >= 0 &&
              todo.date!.compareTo(nextWeekStart) < 0,
        )
        .length;
  }

  static MonthCard? cardForMonth({
    required List<MonthCard> cards,
    required String projectId,
    required int monthIndex,
  }) {
    return cards.cast<MonthCard?>().firstWhere(
      (card) =>
          card?.projectId == projectId && card?.monthIndex == monthIndex,
      orElse: () => null,
    );
  }
}
