import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/score_bar.dart';
import '../../widgets/verdict_badge.dart';
import 'planning_loading_page.dart';

/// 评估诊断结果页 —— 展示多维度评分 + 建议，用户可选择重新编辑或继续规划。
class AssessmentResultPage extends StatelessWidget {
  final String projectId;
  final GoalAssessment assessment;
  final String goal;
  final String level;
  final int cycleMonths;
  final int timeConstraint;

  const AssessmentResultPage({
    required this.projectId,
    required this.assessment,
    required this.goal,
    required this.level,
    required this.cycleMonths,
    required this.timeConstraint,
    super.key,
  });

  bool get _canProceed => assessment.verdict != AssessmentVerdict.d;

  @override
  Widget build(BuildContext context) {
    final isD = assessment.verdict == AssessmentVerdict.d;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('诊断报告'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(s20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 综合评定徽章
                  VerdictBadge(verdict: assessment.verdict),
                  const SizedBox(height: s20),

                  // 维度评分
                  const Text(
                    '维度评分',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
                  ),
                  const SizedBox(height: s8),
                  Container(
                    padding: const EdgeInsets.all(s16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(radiusCard),
                      boxShadow: const [...shadow1],
                    ),
                    child: Column(
                      children: [
                        ScoreBar(label: '清晰度', score: assessment.clarity),
                        ScoreBar(label: '可行性', score: assessment.feasibility),
                        ScoreBar(label: '匹配度', score: assessment.challengeFit),
                        ScoreBar(label: '可分解性', score: assessment.decomposability),
                        ScoreBar(label: '时间合理性', score: assessment.timeRealism),
                        ScoreBar(label: '动机可持续', score: assessment.motivationPotential),
                        ScoreBar(label: '资源可达', score: assessment.resourceAccess),
                        ScoreBar(label: '进展可测', score: assessment.measurability),
                      ],
                    ),
                  ),

                  // 关注区域
                  if (assessment.concerns.isNotEmpty) ...[
                    const SizedBox(height: s16),
                    const Text(
                      '⚠️ 关注',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
                    ),
                    const SizedBox(height: s8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(s16),
                      decoration: BoxDecoration(
                        color: warning500.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(radiusCard),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...assessment.concerns.map((c) => Padding(
                                padding: const EdgeInsets.only(bottom: s6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('· ', style: TextStyle(color: warning600)),
                                    Expanded(
                                      child: Text(c,
                                          style: const TextStyle(fontSize: 14, color: ink)),
                                    ),
                                  ],
                                ),
                              )),
                          if (assessment.suggestions.isNotEmpty) ...[
                            const SizedBox(height: s8),
                            const Text('建议：',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textTertiary)),
                            ...assessment.suggestions.map((s) => Padding(
                                  padding: const EdgeInsets.only(top: s4),
                                  child: Text('→ $s',
                                      style: const TextStyle(fontSize: 14, color: ink)),
                                )),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // 领域参考
                  if (assessment.domainSummary != null ||
                      assessment.estimatedHours != null) ...[
                    const SizedBox(height: s16),
                    const Text(
                      '📊 领域参考',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
                    ),
                    const SizedBox(height: s8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(s16),
                      decoration: BoxDecoration(
                        color: surfaceAlt,
                        borderRadius: BorderRadius.circular(radiusCard),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (assessment.estimatedHours != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: s6),
                              child: Text('预计总时间：${assessment.estimatedHours}',
                                  style: const TextStyle(fontSize: 14, color: ink)),
                            ),
                          if (assessment.domainSummary != null)
                            Text(assessment.domainSummary!,
                                style: const TextStyle(fontSize: 14, color: textTertiary)),
                        ],
                      ),
                    ),
                  ],

                  // 来源
                  if (assessment.sources.isNotEmpty) ...[
                    const SizedBox(height: s16),
                    const Text(
                      '参考来源',
                      style: TextStyle(fontSize: 13, color: textTertiary),
                    ),
                    const SizedBox(height: s4),
                    ...assessment.sources.take(5).map((src) => Padding(
                          padding: const EdgeInsets.only(bottom: s4),
                          child: Text(
                            '· ${src.title}',
                            style: const TextStyle(fontSize: 12, color: textTertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],

                  const SizedBox(height: s48),
                ],
              ),
            ),
          ),

          // 底部按钮
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(s20, s8, s20, s16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('重新编辑'),
                    ),
                  ),
                  const SizedBox(width: s12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _canProceed
                          ? () => _proceedToPlanning(context)
                          : null,
                      style: isD
                          ? FilledButton.styleFrom(backgroundColor: neutral300)
                          : null,
                      child: Text(isD ? '目标需要调整后再规划' : '确认并开始规划'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _proceedToPlanning(BuildContext context) {
    // 将评估结果序列化为 JSON
    final assessmentJson = jsonEncode(assessment.toJson());
    final domainKnowledge = assessment.domainSummary ?? '';

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PlanningLoadingPage(
          projectId: projectId,
          goal: goal,
          level: level,
          cycleMonths: cycleMonths,
          timeConstraint: timeConstraint,
          assessmentReport: assessmentJson,
          domainKnowledge: domainKnowledge,
        ),
      ),
    );
  }
}
