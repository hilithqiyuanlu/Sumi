import 'package:flutter_test/flutter_test.dart';
import 'package:sumi/services/ai_contracts.dart';

void main() {
  group('结构化输出契约', () {
    test('拆分限制数量、标题和 split=false 语义', () {
      expect(
        AiContracts.split({
          'split': false,
          'items': ['阅读文档'],
        }).isValid,
        isTrue,
      );
      expect(
        AiContracts.split({
          'split': false,
          'items': ['阅读文档', '整理笔记'],
        }).isValid,
        isFalse,
      );
    });

    test('规划必须完整覆盖月份且首日日期一致', () {
      final valid = AiContracts.plan(
        {
          'monthPlans': [
            {
              'monthIndex': 0,
              'title': '基础训练',
              'summary': '完成基础概念梳理并通过持续练习建立稳定理解，同时用小型成果检查掌握情况。',
            },
            {
              'monthIndex': 1,
              'title': '综合应用',
              'summary': '结合真实问题开展综合练习，补齐薄弱环节并完成一个可验证的阶段成果。',
            },
          ],
          'todayTodos': [
            {'title': '阅读基础章节', 'date': '2026-07-15'},
          ],
        },
        cycleMonths: 2,
        startDate: '2026-07-15',
      );
      expect(valid.isValid, isTrue, reason: valid.errors.join('；'));

      final invalid = AiContracts.plan(
        {
          'monthPlans': [
            {
              'monthIndex': 0,
              'title': '基础训练',
              'summary': '完成基础概念梳理并通过持续练习建立稳定理解，同时用小型成果检查掌握情况。',
            },
          ],
          'todayTodos': [
            {'title': '阅读基础章节', 'date': '2026-07-16'},
          ],
        },
        cycleMonths: 2,
        startDate: '2026-07-15',
      );
      expect(invalid.isValid, isFalse);
    });

    test('评估分数和评级会严格校验', () {
      final result = AiContracts.assessment({
        'clarity': 1.1,
        'feasibility': 0.8,
        'challengeFit': 0.7,
        'decomposability': 0.7,
        'timeRealism': 0.6,
        'motivationPotential': 0.5,
        'resourceAccess': 0.9,
        'measurability': 0.8,
        'verdict': 'E',
        'concerns': <String>[],
        'suggestions': <String>[],
        'goalSummary': '学习目标',
      });

      expect(result.isValid, isFalse);
      expect(result.errors.join(), contains('clarity'));
      expect(result.errors.join(), contains('verdict'));
    });

    test('项目凝练标题允许 2-16 字并拒绝更长标题', () {
      Map<String, Object?> assessment(String title) => {
        'clarity': 0.8,
        'feasibility': 0.8,
        'challengeFit': 0.7,
        'decomposability': 0.7,
        'timeRealism': 0.6,
        'motivationPotential': 0.5,
        'resourceAccess': 0.9,
        'measurability': 0.8,
        'verdict': 'a',
        'concerns': <String>[],
        'suggestions': <String>[],
        'goalSummary': title,
      };

      expect(
        AiContracts.assessment(assessment('一二三四五六七八九十一二三四五六')).isValid,
        isTrue,
      );
      expect(
        AiContracts.assessment(assessment('一二三四五六七八九十一二三四五六七')).isValid,
        isFalse,
      );
    });

    test('建议需要 3-4 条、去重且长度合格', () {
      final result = AiContracts.suggestions({
        'suggestions': ['先完成今日重点任务', '先完成今日重点任务', '复盘最近学习进度'],
      });
      expect(result.isValid, isFalse);
      expect(result.errors, contains('建议不能重复'));
    });
  });

  group('记忆提取契约', () {
    test('只允许 ignore、save 和 replace 的严格结构', () {
      expect(
        AiContracts.memoryExtraction({'action': 'ignore'}).isValid,
        isTrue,
      );
      expect(
        AiContracts.memoryExtraction({
          'action': 'save',
          'category': 'preference',
          'content': '偏好短时练习',
          'quotedText': '我长期偏好短时练习',
        }).isValid,
        isTrue,
      );
      expect(
        AiContracts.memoryExtraction({
          'action': 'replace',
          'category': 'constraint',
          'content': '晚上不安排任务',
          'quotedText': '以后晚上不要安排任务',
        }).isValid,
        isFalse,
      );
      expect(
        AiContracts.memoryExtraction({
          'action': 'save',
          'category': 'current',
          'content': '本周要考试',
          'quotedText': '本周要考试',
        }).isValid,
        isFalse,
      );
    });
  });

  group('工具参数契约', () {
    test('项目 ID、日期、标题和 limit 会校验', () {
      final invalidTodo = ToolCallValidator.validate(
        'call-1',
        'write_todo',
        {'title': '写', 'date': '2026-02-30', 'projectId': 'missing'},
        validProjectIds: {'project-1'},
      );
      expect(invalidTodo.isValid, isFalse);

      final invalidSignals = ToolCallValidator.validate(
        'call-2',
        'read_signals',
        {'limit': 101, 'projectId': 'missing'},
        validProjectIds: {'project-1'},
      );
      expect(invalidSignals.isValid, isFalse);
    });

    test('合法项目参数会被保留', () {
      final result = ToolCallValidator.validate(
        'call-3',
        'write_todo',
        {'title': '整理学习笔记', 'date': '2026-07-15', 'projectId': 'project-1'},
        validProjectIds: {'project-1'},
      );
      expect(result.isValid, isTrue, reason: result.errors.join('；'));
      expect(result.value?['projectId'], 'project-1');
    });

    test('关闭工具和非法计时、项目参数会被拒绝', () {
      final disabled = ToolCallValidator.validate(
        'call-4',
        'create_study_timer',
        {'title': '阅读英语', 'minutes': 30},
        validProjectIds: const {},
        enabledTools: const {'read_todos'},
      );
      expect(disabled.isValid, isFalse);

      final invalidTimer = ToolCallValidator.validate(
        'call-5',
        'create_study_timer',
        {'title': '读', 'minutes': 481},
        validProjectIds: const {},
      );
      expect(invalidTimer.isValid, isFalse);

      final project = ToolCallValidator.validate(
        'call-6',
        'start_project_generation',
        {
          'goal': '完成日语入门学习',
          'level': '零基础',
          'cycleMonths': 3,
          'timeConstraint': 10,
        },
        validProjectIds: const {},
      );
      expect(project.isValid, isTrue, reason: project.errors.join('；'));
    });

    test('立即计时和未来闹钟会保留正确参数', () {
      final immediateTimer = ToolCallValidator.validate(
        'call-7',
        'create_study_timer',
        {
          'title': '阅读教材',
          'kind': 'timer',
          'minutes': 30,
          'startImmediately': true,
        },
        validProjectIds: const {},
      );
      expect(
        immediateTimer.isValid,
        isTrue,
        reason: immediateTimer.errors.join('；'),
      );
      expect(immediateTimer.value?['startImmediately'], isTrue);

      final alarmAt = DateTime.now().add(const Duration(minutes: 30));
      final alarm = ToolCallValidator.validate('call-8', 'create_study_timer', {
        'title': '开始背单词',
        'kind': 'alarm',
        'alertAt': alarmAt.toIso8601String(),
      }, validProjectIds: const {});
      expect(alarm.isValid, isTrue, reason: alarm.errors.join('；'));
      expect(alarm.value?['kind'], 'alarm');
    });
  });
}
