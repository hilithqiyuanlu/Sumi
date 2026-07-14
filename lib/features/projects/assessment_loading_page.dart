import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/goal_assessor.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import 'assessment_result_page.dart';
import 'planning_loading_page.dart';

/// 评估 Loading 页 —— 展示评估进度，后台执行搜索 + AI 评估。
class AssessmentLoadingPage extends StatefulWidget {
  final String projectId;
  final String goal;
  final String level;
  final int cycleMonths;
  final int timeConstraint;

  const AssessmentLoadingPage({
    required this.projectId,
    required this.goal,
    required this.level,
    required this.cycleMonths,
    required this.timeConstraint,
    super.key,
  });

  @override
  State<AssessmentLoadingPage> createState() => _AssessmentLoadingPageState();
}

class _AssessmentLoadingPageState extends State<AssessmentLoadingPage> {
  int _currentStep = 0;
  bool _hasError = false;
  String _errorMessage = '';

  static const _steps = [
    '分析目标清晰度',
    '搜索领域标准学习路径',
    '校准能力-挑战匹配度',
    '估算时间投入合理性',
    '生成诊断报告',
  ];

  @override
  void initState() {
    super.initState();
    _runAssessment();
  }

  Future<void> _runAssessment() async {
    final store = SumiScope.read(context);
    final ai = store.aiService;
    if (ai == null) {
      setState(() {
        _hasError = true;
        _errorMessage = 'AI 服务未配置，请在设置中配置 API Key';
      });
      return;
    }

    final assessor = GoalAssessor(ai: ai);

    // 模拟步骤推进
    for (var i = 0; i < _steps.length; i++) {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      setState(() => _currentStep = i + 1);
    }

    // 执行评估
    GoalAssessment? assessment;
    try {
      assessment = await assessor.assess(
        goal: widget.goal,
        level: widget.level,
        cycleMonths: widget.cycleMonths,
        timeConstraint: widget.timeConstraint,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = '评估过程出错，请检查网络连接后重试';
      });
      return;
    }

    if (!mounted) return;

    if (assessment == null) {
      setState(() {
        _hasError = true;
        _errorMessage = '评估失败，请检查网络连接后重试';
      });
      return;
    }

    final result = assessment; // 类型收窄

    // 跳转到结果页
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AssessmentResultPage(
          projectId: widget.projectId,
          assessment: result,
          goal: widget.goal,
          level: widget.level,
          cycleMonths: widget.cycleMonths,
          timeConstraint: widget.timeConstraint,
        ),
      ),
    );
  }

  void _skipAssessment() {
    // 跳过评估 → 直接进入规划
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => _PlanningLoadingPlaceholder(
          projectId: widget.projectId,
          goal: widget.goal,
          level: widget.level,
          cycleMonths: widget.cycleMonths,
          timeConstraint: widget.timeConstraint,
          assessmentReport: '{}',
          domainKnowledge: '（跳过评估，无领域知识）',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const SizedBox.shrink()),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: s32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasError) ...[
                const Icon(Icons.error_outline, size: 48, color: textTertiary),
                const SizedBox(height: s16),
                Text(
                  _errorMessage,
                  style: const TextStyle(fontSize: 15, color: textTertiary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: s24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _hasError = false;
                          _currentStep = 0;
                        });
                        _runAssessment();
                      },
                      child: const Text('重试'),
                    ),
                    const SizedBox(width: s12),
                    TextButton(
                      onPressed: _skipAssessment,
                      child: const Text('跳过评估，直接规划'),
                    ),
                  ],
                ),
              ] else ...[
                const Icon(Icons.search, size: 48, color: mintDeep),
                const SizedBox(height: s16),
                const Text(
                  'Sumi 正在评估你的学习目标',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ink),
                ),
                const SizedBox(height: s32),
                Container(
                  padding: const EdgeInsets.all(s16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(radiusCard),
                    boxShadow: const [...shadow1],
                  ),
                  child: Column(
                    children: List.generate(_steps.length, (i) {
                      final done = i < _currentStep;
                      final active = i == _currentStep;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: s6),
                        child: Row(
                          children: [
                            Icon(
                              done
                                  ? Icons.check_circle
                                  : active
                                      ? Icons.circle
                                      : Icons.circle_outlined,
                              size: 16,
                              color: done
                                  ? success500
                                  : active
                                      ? mintDeep
                                      : textTertiary,
                            ),
                            const SizedBox(width: s10),
                            Text(
                              _steps[i],
                              style: TextStyle(
                                fontSize: 14,
                                color: active ? ink : textTertiary,
                                fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 跳过评估直接规划的占位页 —— 立即导航到 PlanningLoadingPage。
class _PlanningLoadingPlaceholder extends StatefulWidget {
  final String projectId;
  final String goal;
  final String level;
  final int cycleMonths;
  final int timeConstraint;
  final String assessmentReport;
  final String domainKnowledge;

  const _PlanningLoadingPlaceholder({
    required this.projectId,
    required this.goal,
    required this.level,
    required this.cycleMonths,
    required this.timeConstraint,
    required this.assessmentReport,
    required this.domainKnowledge,
  });

  @override
  State<_PlanningLoadingPlaceholder> createState() =>
      _PlanningLoadingPlaceholderState();
}

class _PlanningLoadingPlaceholderState
    extends State<_PlanningLoadingPlaceholder> {
  @override
  void initState() {
    super.initState();
    // 延迟一帧确保页面已挂载，然后导航到规划页
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PlanningLoadingPage(
            projectId: widget.projectId,
            goal: widget.goal,
            level: widget.level,
            cycleMonths: widget.cycleMonths,
            timeConstraint: widget.timeConstraint,
            assessmentReport: widget.assessmentReport,
            domainKnowledge: widget.domainKnowledge,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
