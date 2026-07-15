import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sumi/models/models.dart';
import 'package:sumi/services/ai_runtime.dart';
import 'package:sumi/services/project_generation.dart';

http.Response _assessmentResponse() => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {
              'content': jsonEncode({
                'clarity': 0.8,
                'feasibility': 0.8,
                'challengeFit': 0.7,
                'decomposability': 0.8,
                'timeRealism': 0.7,
                'motivationPotential': 0.7,
                'resourceAccess': 0.9,
                'measurability': 0.8,
                'verdict': 'a',
                'concerns': <String>[],
                'suggestions': <String>[],
                'goalSummary': '学习测试',
                'domainSummary': '测试领域资料',
              }),
            },
          },
        ],
      }),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

String _planJson() {
  final now = DateTime.now();
  final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  return jsonEncode({
    'monthPlans': [
      {
        'monthIndex': 0,
        'title': '基础阶段',
        'summary': '先建立清晰的基础知识结构，再通过连续练习理解核心概念并完成阶段检验。',
      },
    ],
    'todayTodos': [
      {'title': '阅读入门资料', 'date': date},
    ],
  });
}

http.Response _sse(String content) => http.Response(
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': content},
          },
        ],
      })}\n\ndata: [DONE]\n\n',
      200,
      headers: const {'content-type': 'text/event-stream; charset=utf-8'},
    );

ProjectGenerationRequest _request() => const ProjectGenerationRequest(
      projectId: 'project-new',
      goal: '学习测试技术',
      level: '零基础',
      cycleMonths: 1,
      timeConstraint: 6,
      color: ProjectColor.mint,
    );

void main() {
  test('统一流程按真实阶段评估、确认、生成、校验和提交', () async {
    var calls = 0;
    var commits = 0;
    final runtime = AiRuntime(
      apiKey: 'key',
      httpClient: MockClient((_) async {
        calls++;
        return calls == 1 ? _assessmentResponse() : _sse(_planJson());
      }),
    );
    final coordinator = ProjectGenerationCoordinator(
      request: _request(),
      runtime: runtime,
      commit: (_, assessment, plan) async {
        commits++;
        expect(assessment?.goalSummary, '学习测试');
        expect(plan.monthPlans, hasLength(1));
      },
    );
    addTearDown(coordinator.dispose);
    final stages = <ProjectGenerationStage>[];
    coordinator.state.addListener(() => stages.add(coordinator.state.value.stage));

    await coordinator.start();
    expect(coordinator.state.value.stage, ProjectGenerationStage.awaitingConfirmation);
    expect(coordinator.state.value.searchSkipped, isTrue);

    await coordinator.continueWithPlan();

    expect(coordinator.state.value.stage, ProjectGenerationStage.completed);
    expect(stages, contains(ProjectGenerationStage.assessing));
    expect(stages, contains(ProjectGenerationStage.planning));
    expect(stages, contains(ProjectGenerationStage.validating));
    expect(stages, contains(ProjectGenerationStage.saving));
    expect(commits, 1);
    expect(calls, 2);
  });

  test('规划格式错误只修复一次并展示真实修复阶段', () async {
    var calls = 0;
    final runtime = AiRuntime(
      apiKey: 'key',
      httpClient: MockClient((_) async {
        calls++;
        if (calls == 1) return _assessmentResponse();
        if (calls == 2) return _sse('不是 JSON');
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': _planJson()},
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final coordinator = ProjectGenerationCoordinator(
      request: _request(),
      runtime: runtime,
      commit: (_, _, _) async {},
    );
    addTearDown(coordinator.dispose);
    final stages = <ProjectGenerationStage>[];
    coordinator.state.addListener(() => stages.add(coordinator.state.value.stage));

    await coordinator.start();
    await coordinator.continueWithPlan();

    expect(coordinator.state.value.stage, ProjectGenerationStage.completed);
    expect(stages, contains(ProjectGenerationStage.validating));
    expect(calls, 3);
  });

  test('取消后忽略迟到评估结果且不提交', () async {
    final response = Completer<http.Response>();
    var commits = 0;
    final runtime = AiRuntime(
      apiKey: 'key',
      httpClient: MockClient((_) => response.future),
    );
    final coordinator = ProjectGenerationCoordinator(
      request: _request(),
      runtime: runtime,
      commit: (_, _, _) async => commits++,
    );
    addTearDown(coordinator.dispose);

    final running = coordinator.start();
    coordinator.cancel();
    response.complete(_assessmentResponse());
    await running;

    expect(coordinator.state.value.stage, ProjectGenerationStage.cancelled);
    expect(commits, 0);
  });

  test('评估鉴权失败显示真实原因而不是网络错误', () async {
    final runtime = AiRuntime(
      apiKey: 'bad-key',
      httpClient: MockClient((_) async => http.Response('unauthorized', 401)),
    );
    final coordinator = ProjectGenerationCoordinator(
      request: _request(),
      runtime: runtime,
      commit: (_, _, _) async {},
    );
    addTearDown(coordinator.dispose);

    await coordinator.start();

    expect(coordinator.state.value.stage, ProjectGenerationStage.failed);
    expect(coordinator.state.value.error, contains('API Key'));
    expect(coordinator.state.value.error, isNot(contains('网络')));
  });
}
