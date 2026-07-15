import 'ai_service.dart';
import 'model_router.dart';

enum PlanGenerationProgress { receiving, validating, repairing }

/// 规划编排器。只转发真实的网络与校验阶段，不制造定时进度。
class PlanGenerator {
  final StructuredGenerationCapability ai;

  PlanGenerator({required this.ai});

  Future<PlanResult?> generate({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String startDate,
    required String assessmentReport,
    required String domainKnowledge,
    void Function(PlanGenerationProgress progress)? onProgress,
  }) {
    var receivedFirstChunk = false;
    return ai.generatePlan(
      goal: goal,
      level: level,
      cycleMonths: cycleMonths,
      timeConstraint: timeConstraint,
      startDate: startDate,
      assessmentReport: assessmentReport,
      domainKnowledge: domainKnowledge,
      onProgress: (_) {
        if (receivedFirstChunk) return;
        receivedFirstChunk = true;
        onProgress?.call(PlanGenerationProgress.receiving);
      },
      onStage: (stage) {
        switch (stage) {
          case AiStructuredStage.validating:
            onProgress?.call(PlanGenerationProgress.validating);
          case AiStructuredStage.repairing:
            onProgress?.call(PlanGenerationProgress.repairing);
        }
      },
    );
  }
}
