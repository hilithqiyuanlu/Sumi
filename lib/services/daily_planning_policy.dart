import '../models/models.dart';
import '../utils/utils.dart';

class DailyPlanningPolicy {
  const DailyPlanningPolicy._();

  static List<String> rollingWindow(DateTime today, {int days = 7}) => [
    for (var index = 0; index < days; index++)
      dateKey(dateOnly(today.add(Duration(days: index)))),
  ];

  static List<String> missingSystemDates({
    required List<TodoItem> todos,
    required String projectId,
    required DateTime today,
  }) {
    final existing = todos
        .where(
          (todo) =>
              todo.source == TodoSource.system &&
              todo.projectId == projectId &&
              todo.date != null,
        )
        .map((todo) => todo.date!)
        .toSet();
    return rollingWindow(
      today,
    ).where((date) => !existing.contains(date)).toList(growable: false);
  }

  static int scheduledCountForWeek({
    required List<TodoItem> todos,
    required String projectId,
    required DateTime today,
  }) {
    final weekStart = dateKey(
      today.subtract(Duration(days: today.weekday - 1)),
    );
    final nextWeekStart = dateKey(today.add(Duration(days: 8 - today.weekday)));
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
      (card) => card?.projectId == projectId && card?.monthIndex == monthIndex,
      orElse: () => null,
    );
  }

  /// 月卡按自然月推进；例如 7 月创建的项目在 8 月使用第 2 张月卡。
  static int monthIndexForDate({
    required DateTime projectStart,
    required DateTime date,
  }) =>
      (date.year - projectStart.year) * 12 + date.month - projectStart.month;
}
