import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/ai_service.dart';
import '../../services/plan_generator.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/bubble_barrage.dart';

/// 规划 Loading 页 —— 弹幕气泡 + 后台规划生成。
class PlanningLoadingPage extends StatefulWidget {
  final String projectId;
  final String goal;
  final String level;
  final int cycleMonths;
  final int timeConstraint;
  final String assessmentReport;
  final String domainKnowledge;

  const PlanningLoadingPage({
    required this.projectId,
    required this.goal,
    required this.level,
    required this.cycleMonths,
    required this.timeConstraint,
    required this.assessmentReport,
    required this.domainKnowledge,
    super.key,
  });

  @override
  State<PlanningLoadingPage> createState() => _PlanningLoadingPageState();
}

class _PlanningLoadingPageState extends State<PlanningLoadingPage> {
  final _bubbleController = StreamController<PlanningBubble>.broadcast();
  bool _isGenerating = true;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _runPlanning();
  }

  @override
  void dispose() {
    _bubbleController.close();
    super.dispose();
  }

  Future<void> _runPlanning() async {
    final store = SumiScope.read(context);
    final ai = store.aiService;
    if (ai == null) {
      setState(() {
        _hasError = true;
        _errorMessage = 'AI 服务未配置';
        _isGenerating = false;
      });
      return;
    }

    final generator = PlanGenerator(ai: ai);
    final startDate =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';

    PlanResult? plan;
    try {
      plan = await generator.generate(
        goal: widget.goal,
        level: widget.level,
        cycleMonths: widget.cycleMonths,
        timeConstraint: widget.timeConstraint,
        startDate: startDate,
        assessmentReport: widget.assessmentReport,
        domainKnowledge: widget.domainKnowledge,
        onBubble: (bubble) {
          if (!_bubbleController.isClosed) {
            _bubbleController.add(bubble);
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = '规划生成失败：${e.toString()}';
        _isGenerating = false;
      });
      return;
    }

    if (!mounted) return;

    if (plan == null) {
      setState(() {
        _hasError = true;
        _errorMessage = '规划生成失败：AI 返回空结果';
        _isGenerating = false;
      });
      return;
    }

    // 一次性提交规划结果
    store.commitPlan(widget.projectId, plan);

    // 返回到项目视图（pop 整个栈）
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _stopAndGoBack() {
    _bubbleController.close();
    // 清理草稿项目
    final store = SumiScope.read(context);
    store.deleteProject(widget.projectId);
    // pop 回编辑页
    Navigator.of(context).pop();
  }

  /// 返回编辑并清理草稿。
  void _goBackAndCleanup() {
    _bubbleController.close();
    final store = SumiScope.read(context);
    store.deleteProject(widget.projectId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          // 弹幕层
          if (_isGenerating && !_hasError)
            Positioned.fill(
              child: BubbleBarrage(
                bubbles: _bubbleController.stream,
              ),
            ),

          // 中央状态
          Center(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  s32, topPadding + 56 + s16, s32, s16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_hasError) ...[
                    const Icon(Icons.error_outline,
                        size: 48, color: textTertiary),
                    const SizedBox(height: s16),
                    Text(
                      _errorMessage,
                      style: const TextStyle(
                          fontSize: 15, color: textTertiary),
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
                              _isGenerating = true;
                            });
                            _runPlanning();
                          },
                          child: const Text('重试'),
                        ),
                        const SizedBox(width: s12),
                        TextButton(
                          onPressed: _goBackAndCleanup,
                          child: const Text('返回编辑'),
                        ),
                      ],
                    ),
                  ] else ...[
                    const Icon(Icons.auto_awesome,
                        size: 48, color: mintDeep),
                    const SizedBox(height: s16),
                    const Text(
                      'Sumi 正在定制学习计划',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: ink),
                    ),
                    const SizedBox(height: s8),
                    const Text(
                      '正在分析评估报告并结合领域知识…',
                      style:
                          TextStyle(fontSize: 13, color: textTertiary),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 底部停止按钮
          if (_isGenerating && !_hasError)
            Positioned(
              bottom: s32,
              left: 0,
              right: 0,
              child: Center(
                child: TextButton.icon(
                  onPressed: _stopAndGoBack,
                  icon: const Icon(Icons.stop, size: iconSmall),
                  label: const Text('停止生成，返回编辑'),
                ),
              ),
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
          // 返回按钮
          Positioned(
            top: topPadding,
            left: 4,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _stopAndGoBack,
            ),
          ),
        ],
      ),
    );
  }
}
