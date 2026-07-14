import 'dart:async';

import '../models/models.dart';
import 'ai_service.dart';

/// 规划弹幕预设文本。
const _bubblePresets = <BubbleType, List<String>>{
  BubbleType.searching: [
    '让我搜索一下这个领域的学习路线…',
    '看看大家通常需要多长时间入门…',
    '找找有没有好的学习资源…',
    '搜索到不少信息，让我梳理一下…',
  ],
  BubbleType.thinking: [
    '根据你的情况，我来设计一个合适的节奏…',
    '第一个月先打好基础，把核心概念吃透…',
    '按照心流理论，难度要刚好在你能力之上一点点…',
    '第二个月可以开始接触更深入的内容了…',
    '让我算算时间够不够…',
    '最后一个月要做综合练习，检验学习成果…',
    '检查一下每个月之间的递进关系…',
    '让我想想这个安排是否合理…',
    '这个阶段需要多给一些练习时间…',
    '前期基础打牢，后面才能加速…',
  ],
  BubbleType.validating: [
    '让我验证一下整体计划的合理性…',
    '检查时间分配是否匹配…',
    '确认每个月的目标是否可达…',
    '最后再过一遍，确保没有遗漏…',
  ],
  BubbleType.info: [
    '计划已经生成好了！',
    '全部搞定，来看看你的学习路线吧！',
  ],
};

/// 规划编排器 —— 两阶段规划 + 弹幕回调。
class PlanGenerator {
  final AiService ai;

  PlanGenerator({required this.ai});

  /// 增强两阶段规划。
  /// [onBubble] 在关键节点被调用，用于 UI 弹幕展示。
  /// 返回 [PlanResult]，失败时返回 null。
  Future<PlanResult?> generate({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String startDate,
    required String assessmentReport,
    required String domainKnowledge,
    void Function(PlanningBubble bubble)? onBubble,
  }) async {
    void emit(BubbleType type, String text) {
      onBubble?.call(PlanningBubble(text: text, type: type));
    }

    Future<void> sleep(int ms) => Future.delayed(Duration(milliseconds: ms));

    // Phase 1: 置信度检查（放慢节奏）
    emit(BubbleType.searching, '让我梳理一下已有的信息…');
    await sleep(1200);

    if (domainKnowledge.contains('未能搜索到') ||
        domainKnowledge.length < 200) {
      emit(BubbleType.thinking,
          '关于这个方向的信息有点少，我先基于已知的来规划…');
      await sleep(900);
    } else {
      emit(BubbleType.searching, '找到不少参考信息，开始规划…');
      await sleep(900);
    }

    // Phase 2: 规划生成（弹幕在 AI 调用期间继续发射）
    emit(BubbleType.thinking, '根据你的水平，我来设计一个合适的学习节奏…');
    await sleep(400);

    // 异步发射弹幕，同时等待 AI 响应
    final bubbleFutures = <Future<void>>[];
    final presetThinking = List<String>.from(
        _bubblePresets[BubbleType.thinking]!)
      ..shuffle();
    for (final text in presetThinking.take(3)) {
      bubbleFutures.add(
        sleep(2000 + bubbleFutures.length * 100)
            .then((_) => emit(BubbleType.thinking, text)),
      );
    }

    // 发起 AI 规划
    PlanResult? plan;
    plan = await ai.generatePlanEnhanced(
      goal: goal,
      level: level,
      cycleMonths: cycleMonths,
      timeConstraint: timeConstraint,
      startDate: startDate,
      assessmentReport: assessmentReport,
      domainKnowledge: domainKnowledge,
    );

    // 等弹幕先发完
    await Future.wait(bubbleFutures);

    if (plan == null) {
      emit(BubbleType.info, '抱歉，规划生成失败，请检查网络后重试。');
      return null;
    }

    // Phase 3: 验证（放慢节奏）
    emit(BubbleType.validating, '让我验证一下整体计划的合理性…');
    await sleep(1500);

    if (plan.monthPlans.length < cycleMonths) {
      emit(BubbleType.thinking,
          '注意：生成的月计划数 (${plan.monthPlans.length}) 少于设定周期 ($cycleMonths)…');
      await sleep(900);
    }

    emit(BubbleType.validating, '确认每个月的递进关系…');
    await sleep(1200);

    // Phase 4: 完成
    emit(BubbleType.info, '计划已经生成好了！');
    await sleep(500);

    return plan;
  }
}
