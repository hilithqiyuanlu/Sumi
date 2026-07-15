import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'ai_service.dart';
import 'ai_runtime.dart';
import 'goal_assessor.dart';
import 'plan_generator.dart';

enum ProjectGenerationStage {
  searching,
  assessing,
  awaitingConfirmation,
  planning,
  validating,
  saving,
  completed,
  failed,
  cancelled,
}

class ProjectGenerationRequest {
  final String projectId;
  final String? existingProjectId;
  final String goal;
  final String level;
  final int cycleMonths;
  final int timeConstraint;
  final ProjectColor color;

  const ProjectGenerationRequest({
    required this.projectId,
    this.existingProjectId,
    required this.goal,
    required this.level,
    required this.cycleMonths,
    required this.timeConstraint,
    required this.color,
  });

  bool get isEditing => existingProjectId != null;
}

class ProjectGenerationState {
  final ProjectGenerationStage stage;
  final String status;
  final Duration elapsed;
  final int searchCompleted;
  final int searchTotal;
  final bool searchSkipped;
  final GoalAssessment? assessment;
  final String? error;
  final bool canRetry;

  const ProjectGenerationState({
    required this.stage,
    required this.status,
    this.elapsed = Duration.zero,
    this.searchCompleted = 0,
    this.searchTotal = 3,
    this.searchSkipped = false,
    this.assessment,
    this.error,
    this.canRetry = false,
  });

  ProjectGenerationState copyWith({
    ProjectGenerationStage? stage,
    String? status,
    Duration? elapsed,
    int? searchCompleted,
    int? searchTotal,
    bool? searchSkipped,
    GoalAssessment? assessment,
    String? error,
    bool clearError = false,
    bool? canRetry,
  }) {
    return ProjectGenerationState(
      stage: stage ?? this.stage,
      status: status ?? this.status,
      elapsed: elapsed ?? this.elapsed,
      searchCompleted: searchCompleted ?? this.searchCompleted,
      searchTotal: searchTotal ?? this.searchTotal,
      searchSkipped: searchSkipped ?? this.searchSkipped,
      assessment: assessment ?? this.assessment,
      error: clearError ? null : error ?? this.error,
      canRetry: canRetry ?? this.canRetry,
    );
  }
}

class GenerationCancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

typedef ProjectPlanCommit = Future<void> Function(
  ProjectGenerationRequest request,
  GoalAssessment? assessment,
  PlanResult plan,
);

class ProjectGenerationCoordinator {
  final ProjectGenerationRequest request;
  final AiRuntime runtime;
  final ProjectPlanCommit commit;
  final GenerationCancellationToken cancellation;
  final ValueNotifier<ProjectGenerationState> state;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _elapsedTimer;
  GoalAssessment? _assessment;
  bool _lastFailureWasPlanning = false;
  bool _disposed = false;

  ProjectGenerationCoordinator({
    required this.request,
    required this.runtime,
    required this.commit,
    GenerationCancellationToken? cancellation,
  })  : cancellation = cancellation ?? GenerationCancellationToken(),
        state = ValueNotifier(const ProjectGenerationState(
          stage: ProjectGenerationStage.searching,
          status: '正在准备资料检索',
        ));

  bool get failedDuringPlanning => _lastFailureWasPlanning;

  Future<void> start() => runAssessment();

  Future<void> runAssessment() async {
    if (cancellation.isCancelled) return;
    _lastFailureWasPlanning = false;
    _assessment = null;
    _startClock();
    _emit(ProjectGenerationState(
      stage: ProjectGenerationStage.searching,
      status: runtime.search.isConfigured ? '正在检索参考资料' : '未配置搜索服务，已跳过外部资料',
      elapsed: _stopwatch.elapsed,
      searchTotal: runtime.search.isConfigured ? 3 : 0,
      searchSkipped: !runtime.search.isConfigured,
    ));

    try {
      final assessor = GoalAssessor(ai: runtime.structured, search: runtime.search);
      final result = await assessor.assess(
        goal: request.goal,
        level: request.level,
        cycleMonths: request.cycleMonths,
        timeConstraint: request.timeConstraint,
        onSearchProgress: (completed, total) {
          if (cancellation.isCancelled) return;
          _emit(state.value.copyWith(
            stage: ProjectGenerationStage.searching,
            status: '已完成 $completed/$total 项资料检索',
            searchCompleted: completed,
            searchTotal: total,
          ));
        },
        onAssessing: () {
          if (cancellation.isCancelled) return;
          _emit(state.value.copyWith(
            stage: ProjectGenerationStage.assessing,
            status: '正在评估目标可行性',
          ));
        },
      );
      if (cancellation.isCancelled) return;
      if (result == null) throw StateError('评估服务没有返回有效结果');
      _assessment = result;
      _emit(state.value.copyWith(
        stage: ProjectGenerationStage.awaitingConfirmation,
        status: '评估完成，请确认后继续',
        assessment: result,
        clearError: true,
        canRetry: false,
      ));
    } catch (e) {
      if (cancellation.isCancelled) return;
      _fail(_aiFailureMessage('目标评估'));
    }
  }

  Future<void> continueWithPlan() => _runPlanning(_assessment);

  Future<void> skipAssessmentAndPlan() => _runPlanning(null);

  Future<void> retry() {
    return _lastFailureWasPlanning ? _runPlanning(_assessment) : runAssessment();
  }

  Future<void> _runPlanning(GoalAssessment? assessment) async {
    if (cancellation.isCancelled) return;
    _lastFailureWasPlanning = true;
    _emit(state.value.copyWith(
      stage: ProjectGenerationStage.planning,
      status: '正在请求生成月度计划',
      assessment: assessment,
      clearError: true,
      canRetry: false,
    ));

    try {
      final generator = PlanGenerator(ai: runtime.structured);
      final now = DateTime.now();
      final startDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final plan = await generator.generate(
        goal: request.goal,
        level: request.level,
        cycleMonths: request.cycleMonths,
        timeConstraint: request.timeConstraint,
        startDate: startDate,
        assessmentReport: jsonEncode(assessment?.toJson() ?? const <String, Object?>{}),
        domainKnowledge: assessment?.domainSummary ?? '（未提供外部领域资料）',
        onProgress: (progress) {
          if (cancellation.isCancelled) return;
          final validating = progress == PlanGenerationProgress.validating ||
              progress == PlanGenerationProgress.repairing;
          _emit(state.value.copyWith(
            stage: validating
                ? ProjectGenerationStage.validating
                : ProjectGenerationStage.planning,
            status: switch (progress) {
              PlanGenerationProgress.receiving => '正在接收计划内容',
              PlanGenerationProgress.validating => '正在校验计划结构',
              PlanGenerationProgress.repairing => '返回格式需要修复，正在重试一次',
            },
          ));
        },
      );
      if (cancellation.isCancelled) return;
      if (plan == null) throw StateError('规划服务没有返回有效结果');

      _emit(state.value.copyWith(
        stage: ProjectGenerationStage.saving,
        status: '正在保存项目计划',
      ));
      await commit(request, assessment, plan);
      if (cancellation.isCancelled) return;
      _emit(state.value.copyWith(
        stage: ProjectGenerationStage.completed,
        status: '计划已生成',
        clearError: true,
      ));
      _stopClock();
    } catch (e) {
      if (cancellation.isCancelled) return;
      _fail(_aiFailureMessage('计划生成'));
    }
  }

  void cancel() {
    cancellation.cancel();
    _stopClock();
    _emit(state.value.copyWith(
      stage: ProjectGenerationStage.cancelled,
      status: '已取消生成',
      clearError: true,
      canRetry: false,
    ));
  }

  void _fail(String message) {
    _emit(state.value.copyWith(
      stage: ProjectGenerationStage.failed,
      status: message,
      error: message,
      canRetry: true,
    ));
  }

  String _aiFailureMessage(String operation) {
    final error = runtime.structured.lastError ?? '';
    if (error.startsWith('HTTP 401') || error.startsWith('HTTP 403')) {
      return 'API Key 无效或没有访问权限，请到设置中检查。';
    }
    if (error.startsWith('HTTP 429')) {
      return 'AI 请求过于频繁，请稍后再试。';
    }
    if (error.startsWith('HTTP 400')) {
      return 'AI 服务拒绝了$operation请求，请检查模型或接口配置。';
    }
    if (error.contains('结构校验失败') || error.contains('JSON')) {
      return 'AI 返回的$operation内容不完整，自动修复后仍未通过。';
    }
    if (error.contains('超时')) {
      return '$operation服务响应超时，请稍后重试。';
    }
    if (error.startsWith('HTTP 5')) {
      return 'AI 服务暂时不可用，请稍后重试。';
    }
    return '$operation暂时无法完成，请重试。';
  }

  void _startClock() {
    if (!_stopwatch.isRunning) _stopwatch.start();
    _elapsedTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      _emit(state.value.copyWith(elapsed: _stopwatch.elapsed));
    });
  }

  void _stopClock() {
    _stopwatch.stop();
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  void _emit(ProjectGenerationState value) {
    if (!_disposed) state.value = value.copyWith(elapsed: _stopwatch.elapsed);
  }

  void dispose() {
    _disposed = true;
    _stopClock();
    state.dispose();
  }
}
