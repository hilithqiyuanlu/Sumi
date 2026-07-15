import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../services/project_generation.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/score_bar.dart';
import '../../widgets/verdict_badge.dart';

class ProjectGenerationPage extends StatefulWidget {
  final ProjectGenerationRequest request;

  const ProjectGenerationPage({required this.request, super.key});

  @override
  State<ProjectGenerationPage> createState() => _ProjectGenerationPageState();
}

class _ProjectGenerationPageState extends State<ProjectGenerationPage> {
  late final ProjectGenerationCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    final store = SumiScope.read(context);
    _coordinator = ProjectGenerationCoordinator(
      request: widget.request,
      router: store.modelRouter!,
      commit: store.commitProjectPlan,
    );
    _coordinator.start();
  }

  @override
  void dispose() {
    _coordinator.dispose();
    super.dispose();
  }

  bool _isRunning(ProjectGenerationStage stage) => switch (stage) {
        ProjectGenerationStage.searching ||
        ProjectGenerationStage.assessing ||
        ProjectGenerationStage.planning ||
        ProjectGenerationStage.validating ||
        ProjectGenerationStage.saving => true,
        _ => false,
      };

  Future<void> _handleBack() async {
    final state = _coordinator.state.value;
    if (_isRunning(state.stage)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('取消生成？'),
          content: const Text('本次结果不会保存，返回后可以重新生成。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续等待'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('取消生成'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    _coordinator.cancel();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: ValueListenableBuilder<ProjectGenerationState>(
        valueListenable: _coordinator.state,
        builder: (context, state, _) {
          final isCompleted = state.stage == ProjectGenerationStage.completed;
          return Scaffold(
            backgroundColor: paper,
            appBar: isCompleted
                ? null
                : AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    systemOverlayStyle: const SystemUiOverlayStyle(
                      statusBarColor: Colors.transparent,
                      statusBarIconBrightness: Brightness.dark,
                      statusBarBrightness: Brightness.light,
                    ),
                    leading: IconButton(
                      onPressed: _handleBack,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: '返回',
                    ),
                  ),
            body: SafeArea(
              top: false,
              child: Builder(builder: (_) {
                if (state.stage == ProjectGenerationStage.awaitingConfirmation &&
                    state.assessment != null) {
                  return _buildAssessment(state.assessment!, state);
                }
                if (state.stage == ProjectGenerationStage.completed) {
                  return _buildCompleted(state);
                }
                return _buildProgress(state);
              }),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProgress(ProjectGenerationState state) {
    final waitingLong = state.elapsed >= const Duration(seconds: 15) &&
        _isRunning(state.stage);
    return Padding(
      padding: const EdgeInsets.fromLTRB(s24, s24, s24, s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.auto_awesome, size: 40, color: mintDeep),
          const SizedBox(height: s16),
          Text(
            state.status,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
          const SizedBox(height: s6),
          Text(
            '已用时 ${state.elapsed.inSeconds} 秒',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: textTertiary),
          ),
          if (waitingLong) ...[
            const SizedBox(height: s8),
            const Text(
              '服务仍在处理，可以继续等待或取消。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: textTertiary),
            ),
          ],
          const SizedBox(height: s32),
          _StageTimeline(state: state),
          const Spacer(),
          if (state.stage == ProjectGenerationStage.failed) ...[
            FilledButton.icon(
              onPressed: state.canRetry ? _coordinator.retry : null,
              icon: const Icon(Icons.refresh),
              label: const Text('重试当前阶段'),
            ),
            if (!_coordinator.failedDuringPlanning) ...[
              const SizedBox(height: s8),
              TextButton(
                onPressed: _coordinator.skipAssessmentAndPlan,
                child: const Text('跳过评估，直接生成计划'),
              ),
            ],
          ] else if (_isRunning(state.stage))
            OutlinedButton.icon(
              onPressed: _handleBack,
              icon: const Icon(Icons.close),
              label: const Text('取消生成'),
            ),
        ],
      ),
    );
  }

  Widget _buildAssessment(
    GoalAssessment assessment,
    ProjectGenerationState state,
  ) {
    final canProceed = assessment.verdict != AssessmentVerdict.d;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(s20, s12, s20, s24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VerdictBadge(verdict: assessment.verdict),
                const SizedBox(height: s20),
                if (state.searchSkipped)
                  const _InfoLine(text: '未配置搜索服务，本次评估未使用外部资料。')
                else
                  _InfoLine(text: '已参考 ${assessment.sources.length} 条资料来源。'),
                const SizedBox(height: s16),
                ScoreBar(label: '清晰度', score: assessment.clarity),
                ScoreBar(label: '可行性', score: assessment.feasibility),
                ScoreBar(label: '挑战匹配', score: assessment.challengeFit),
                ScoreBar(label: '可分解性', score: assessment.decomposability),
                ScoreBar(label: '时间合理', score: assessment.timeRealism),
                ScoreBar(label: '动机潜力', score: assessment.motivationPotential),
                ScoreBar(label: '资源可达', score: assessment.resourceAccess),
                ScoreBar(label: '可衡量性', score: assessment.measurability),
                if (assessment.concerns.isNotEmpty) ...[
                  const SizedBox(height: s20),
                  const Text('需要注意', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: s8),
                  ...assessment.concerns.map((item) => _InfoLine(text: item)),
                ],
                if (assessment.suggestions.isNotEmpty) ...[
                  const SizedBox(height: s20),
                  const Text('调整建议', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: s8),
                  ...assessment.suggestions.map((item) => _InfoLine(text: item)),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(s20, s8, s20, s16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _handleBack,
                  child: const Text('返回修改'),
                ),
              ),
              if (canProceed) ...[
                const SizedBox(width: s12),
                Expanded(
                  child: FilledButton(
                    onPressed: _coordinator.continueWithPlan,
                    child: const Text('确认并生成'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompleted(ProjectGenerationState state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 52, color: primary500),
            const SizedBox(height: s16),
            const Text('计划已生成', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: s6),
            Text('总用时 ${state.elapsed.inSeconds} 秒', style: const TextStyle(color: textTertiary)),
            const SizedBox(height: s24),
            FilledButton(
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('查看项目'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageTimeline extends StatelessWidget {
  final ProjectGenerationState state;

  const _StageTimeline({required this.state});

  @override
  Widget build(BuildContext context) {
    const stages = [
      (ProjectGenerationStage.searching, '检索参考资料'),
      (ProjectGenerationStage.assessing, '评估目标'),
      (ProjectGenerationStage.planning, '生成月度计划'),
      (ProjectGenerationStage.validating, '校验计划结构'),
      (ProjectGenerationStage.saving, '保存项目'),
    ];
    final current = switch (state.stage) {
      ProjectGenerationStage.awaitingConfirmation => 1,
      ProjectGenerationStage.completed => stages.length,
      ProjectGenerationStage.failed => -1,
      _ => stages.indexWhere((item) => item.$1 == state.stage),
    };
    return Column(
      children: List.generate(stages.length, (index) {
        final done = current >= 0 && index < current;
        final active = index == current ||
            (state.stage == ProjectGenerationStage.failed &&
                index == stages.indexWhere((item) => item.$1 ==
                    (state.assessment == null
                        ? ProjectGenerationStage.assessing
                        : ProjectGenerationStage.planning)));
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: s6),
          child: Row(
            children: [
              Icon(
                done ? Icons.check_circle : active ? Icons.radio_button_checked : Icons.circle_outlined,
                size: 18,
                color: done ? primary500 : active ? mintDeep : textTertiary,
              ),
              const SizedBox(width: s10),
              Text(
                stages[index].$2,
                style: TextStyle(
                  fontSize: 14,
                  color: active ? ink : textTertiary,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String text;

  const _InfoLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: s6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, size: 5, color: textTertiary),
          ),
          const SizedBox(width: s8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.45, color: textSecondary))),
        ],
      ),
    );
  }
}
