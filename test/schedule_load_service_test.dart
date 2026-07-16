import 'package:flutter_test/flutter_test.dart';
import 'package:sumi/models/models.dart';
import 'package:sumi/services/daily_planning_policy.dart';
import 'package:sumi/services/ai_service.dart';
import 'package:sumi/services/schedule_load_service.dart';

void main() {
  final today = DateTime(2026, 7, 13);
  final project = Project(
    id: 'project-1',
    name: '英语学习',
    color: ProjectColor.mint,
    goal: '完成英语阅读训练',
    timeConstraint: 6,
    createdAt: today,
  );

  TodoItem todo(
    String id,
    String title,
    String date, {
    bool pinned = false,
    String? reminderTime,
    bool done = false,
  }) => TodoItem(
    id: id,
    source: TodoSource.user,
    date: date,
    title: title,
    pinned: pinned,
    reminderTime: reminderTime,
    done: done,
    createdAt: today,
  );

  Map<String, double> pressureFor(DateTime start, int days, {double value = .2}) => {
    for (var index = 1; index <= days; index++)
      DateTime(start.year, start.month, start.day)
          .add(Duration(days: index))
          .toIso8601String()
          .substring(0, 10): value,
  };

  test('滚动窗口只返回缺失的未来七天日期', () {
    final missing = DailyPlanningPolicy.missingSystemDates(
      todos: [
        TodoItem(
          id: 'system-today',
          source: TodoSource.system,
          projectId: project.id,
          date: '2026-07-13',
          title: '已有系统事项',
          createdAt: today,
        ),
      ],
      projectId: project.id,
      today: today,
    );

    expect(missing, hasLength(6));
    expect(missing.first, '2026-07-14');
    expect(missing.last, '2026-07-19');
  });

  test('跨月日期会选用对应的月卡索引', () {
    expect(
      DailyPlanningPolicy.monthIndexForDate(
        projectStart: DateTime(2026, 7, 28),
        date: DateTime(2026, 8, 3),
      ),
      1,
    );
    expect(
      DailyPlanningPolicy.monthIndexForDate(
        projectStart: DateTime(2026, 7, 28),
        date: DateTime(2026, 7, 31),
      ),
      0,
    );
  });

  test('只有语义分析确认较满时才会产生排期预览', () {
    final assessor = ScheduleLoadAssessor();
    final todos = [
      todo('todo-1', '完成阅读报告', '2026-07-13'),
      todo('todo-2', '整理考试笔记', '2026-07-13'),
    ];
    final proposal = assessor.proposeForToday(
      analysis: TodayLoadAnalysis(
        risk: .82,
        reasons: ['两项深度产出任务集中在今天'],
        suggestion: '优先完成阅读报告，再安排笔记整理。',
        movableTodoIds: ['todo-2'],
        futureDayPressure: pressureFor(today, 14),
      ),
      todos: todos,
      today: today,
      fingerprint: 'today-heavy',
    );

    expect(proposal, isNotNull);
    expect(proposal!.moves, hasLength(1));
    expect(proposal.moves.single.todoId, 'todo-2');
    expect(proposal.moves.first.fromDate, '2026-07-13');
    expect(proposal.moves.first.toDate, isNot('2026-07-13'));
  });

  test('置顶、提醒、完成和过去事项绝不进入语义候选预览', () {
    final assessor = ScheduleLoadAssessor();
    final todos = [
      todo('pinned', '置顶事项', '2026-07-13', pinned: true),
      todo('reminder', '提醒事项', '2026-07-13', reminderTime: '09:00'),
      todo('done', '已完成事项', '2026-07-13', done: true),
      todo('past', '过去事项', '2026-07-12'),
      todo('movable', '可移动事项', '2026-07-13'),
    ];
    final proposal = assessor.proposeForToday(
      analysis: TodayLoadAnalysis(
        risk: .9,
        reasons: ['今天存在多个高专注任务'],
        suggestion: '将可延后事项放到后续较空的日期。',
        movableTodoIds: ['pinned', 'reminder', 'done', 'past', 'movable'],
        futureDayPressure: pressureFor(today, 14),
      ),
      todos: todos,
      today: today,
      fingerprint: 'exclude-locked',
    );
    final movedIds = proposal!.moves.map((move) => move.todoId).toSet();

    expect(movedIds, isNot(contains('pinned')));
    expect(movedIds, isNot(contains('reminder')));
    expect(movedIds, isNot(contains('done')));
    expect(movedIds, isNot(contains('past')));
    expect(movedIds, contains('movable'));
  });

  test('未来十四天无合适空档时保留事项，不强行延后', () {
    final assessor = ScheduleLoadAssessor();
    final todos = [
      todo('today', '可移动事项', '2026-07-13'),
      for (var day = 1; day <= 14; day++)
        for (var item = 0; item < 4; item++)
          todo(
            'future-$day-$item',
            '高负荷事项$item',
            DateTime(2026, 7, 13).add(Duration(days: day)).toIso8601String().substring(0, 10),
          ),
    ];
    final proposal = assessor.proposeForToday(
      analysis: TodayLoadAnalysis(
        risk: .8,
        reasons: ['今天任务需要调整'],
        suggestion: '尝试为可移动事项寻找空档。',
        movableTodoIds: ['today'],
        futureDayPressure: pressureFor(today, 14, value: .9),
      ),
      todos: todos,
      today: today,
      fingerprint: 'no-slot',
    );
    expect(proposal, isNotNull);
    expect(proposal!.moves, isEmpty);
    expect(proposal.unscheduledTodoIds, contains('today'));
  });

  test('目标日期按语义可承受度选择，不要求完全空白', () {
    final assessor = ScheduleLoadAssessor();
    final todos = [
      todo('today', '可移动事项', '2026-07-13'),
      todo('busy-but-ok', '已有轻任务', '2026-07-14'),
    ];
    final proposal = assessor.proposeForToday(
      analysis: TodayLoadAnalysis(
        risk: .8,
        reasons: const ['今天任务集中'],
        suggestion: '将可延后事项放入相对可承受的日期。',
        movableTodoIds: const ['today'],
        futureDayPressure: const {
          '2026-07-14': .3,
          '2026-07-15': .75,
        },
      ),
      todos: todos,
      today: today,
      fingerprint: 'semantic-target',
    );
    expect(proposal, isNotNull);
    expect(proposal!.moves.single.toDate, '2026-07-14');
  });
}
