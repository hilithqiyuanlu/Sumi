import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/score_bar.dart';
import '../../widgets/verdict_badge.dart';
import 'planning_loading_page.dart';

/// 评估诊断结果页 —— 展示多维度评分 + 建议，用户可选择重新编辑或继续规划。
class AssessmentResultPage extends StatefulWidget {
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

  @override
  State<AssessmentResultPage> createState() => _AssessmentResultPageState();
}

class _AssessmentResultPageState extends State<AssessmentResultPage> {
  bool _isNavigating = false;

  bool get _canProceed => widget.assessment.verdict != AssessmentVerdict.d;

  void _proceedToPlanning() {
    if (_isNavigating) return;
    _isNavigating = true;

    // 将评估结果序列化为 JSON
    final assessmentJson = jsonEncode(widget.assessment.toJson());
    final domainKnowledge = widget.assessment.domainSummary ?? '';

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PlanningLoadingPage(
          projectId: widget.projectId,
          goal: widget.goal,
          level: widget.level,
          cycleMonths: widget.cycleMonths,
          timeConstraint: widget.timeConstraint,
          assessmentReport: assessmentJson,
          domainKnowledge: domainKnowledge,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isD = widget.assessment.verdict == AssessmentVerdict.d;

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                      s20, topPadding + 56 + s8, s20, s48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 综合评定徽章
                      VerdictBadge(verdict: widget.assessment.verdict),
                      const SizedBox(height: s20),

                      // 维度评分
                      const Text(
                        '维度评分',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ink),
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
                            ScoreBar(
                                label: '清晰度',
                                score: widget.assessment.clarity),
                            ScoreBar(
                                label: '可行性',
                                score: widget.assessment.feasibility),
                            ScoreBar(
                                label: '匹配度',
                                score: widget.assessment.challengeFit),
                            ScoreBar(
                                label: '可分解性',
                                score: widget.assessment.decomposability),
                            ScoreBar(
                                label: '时间合理性',
                                score: widget.assessment.timeRealism),
                            ScoreBar(
                                label: '动机可持续',
                                score:
                                    widget.assessment.motivationPotential),
                            ScoreBar(
                                label: '资源可达',
                                score: widget.assessment.resourceAccess),
                            ScoreBar(
                                label: '进展可测',
                                score: widget.assessment.measurability),
                          ],
                        ),
                      ),

                      // 关注区域
                      if (widget.assessment.concerns.isNotEmpty) ...[
                        const SizedBox(height: s16),
                        const Text(
                          '⚠️ 关注',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: ink),
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
                              ...widget.assessment.concerns.map((c) =>
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: s6),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('· ',
                                            style: TextStyle(
                                                color: warning600)),
                                        Expanded(
                                          child: Text(c,
                                              style: const TextStyle(
                                                  fontSize: 14,
                                                  color: ink)),
                                        ),
                                      ],
                                    ),
                                  )),
                              if (widget.assessment.suggestions
                                  .isNotEmpty) ...[
                                const SizedBox(height: s8),
                                const Text('建议：',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: textTertiary)),
                                ...widget.assessment.suggestions.map((s) =>
                                    Padding(
                                      padding: const EdgeInsets.only(top: s4),
                                      child: Text('→ $s',
                                          style: const TextStyle(
                                              fontSize: 14, color: ink)),
                                    )),
                              ],
                            ],
                          ),
                        ),
                      ],

                      // 领域参考
                      if (widget.assessment.domainSummary != null ||
                          widget.assessment.estimatedHours != null) ...[
                        const SizedBox(height: s16),
                        const Text(
                          '📊 领域参考',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: ink),
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
                              if (widget.assessment.estimatedHours != null)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: s6),
                                  child: Text(
                                      '预计总时间：${widget.assessment.estimatedHours}',
                                      style: const TextStyle(
                                          fontSize: 14, color: ink)),
                                ),
                              if (widget.assessment.domainSummary != null)
                                Text(widget.assessment.domainSummary!,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: textTertiary)),
                            ],
                          ),
                        ),
                      ],

                      // 来源
                      if (widget.assessment.sources.isNotEmpty) ...[
                        const SizedBox(height: s16),
                        const Text(
                          '参考来源',
                          style:
                              TextStyle(fontSize: 13, color: textTertiary),
                        ),
                        const SizedBox(height: s4),
                        ...widget.assessment.sources.take(5).map((src) =>
                            Padding(
                              padding: const EdgeInsets.only(bottom: s4),
                              child: Text(
                                '· ${src.title}',
                                style: const TextStyle(
                                    fontSize: 12, color: textTertiary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                      ],
                    ],
                  ),
                ),
              ),

              // 底部按钮
              SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(s20, s8, s20, s16),
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
                              ? _proceedToPlanning
                              : null,
                          style: isD
                              ? FilledButton.styleFrom(
                                  backgroundColor: neutral300)
                              : null,
                          child: Text(isD
                              ? '目标需要调整后再规划'
                              : '确认并开始规划'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // 顶部渐变遮罩
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topPadding + 56,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white,
                      Colors.white.withValues(alpha: 0.92),
                      Colors.white.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // 返回按钮 + 标题
          Positioned(
            top: topPadding,
            left: 4,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                const Text(
                  '诊断报告',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
