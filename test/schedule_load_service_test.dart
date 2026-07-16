import 'package:flutter_test/flutter_test.dart';
import 'package:sumi/models/models.dart';
import 'package:sumi/services/daily_planning_policy.dart';
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

  test('多项目和普通事项激增会产生可确认的排期预览', () {
    final assessor = ScheduleLoadAssessor();
    final todos = [
      for (var i = 0; i < 12; i++) todo('todo-$i', '学习事项$i', '2026-07-13'),
    ];
    final assessment = assessor.assess(
      projects: [project],
      todos: todos,
      today: today,
    );
    final proposal = assessor.propose(
      assessment: assessment,
      todos: todos,
      today: today,
    );

    expect(assessment.overloaded, isTrue);
    expect(proposal, isNotNull);
    expect(proposal!.moves, isNotEmpty);
    expect(proposal.moves.first.fromDate, '2026-07-13');
    expect(proposal.moves.first.toDate, isNot('2026-07-13'));
  });

  test('置顶、提醒、完成和过去事项绝不进入可移动预览', () {
    final assessor = ScheduleLoadAssessor();
    final todos = [
      for (var i = 0; i < 10; i++) todo('normal-$i', '普通事项$i', '2026-07-13'),
      todo('pinned', '置顶事项', '2026-07-13', pinned: true),
      todo('reminder', '提醒事项', '2026-07-13', reminderTime: '09:00'),
      todo('done', '已完成事项', '2026-07-13', done: true),
      todo('past', '过去事项', '2026-07-12'),
    ];
    final assessment = assessor.assess(
      projects: [project],
      todos: todos,
      today: today,
    );
    final proposal = assessor.propose(
      assessment: assessment,
      todos: todos,
      today: today,
    );
    final movedIds = proposal!.moves.map((move) => move.todoId).toSet();

    expect(movedIds, isNot(contains('pinned')));
    expect(movedIds, isNot(contains('reminder')));
    expect(movedIds, isNot(contains('done')));
    expect(movedIds, isNot(contains('past')));
  });
}
