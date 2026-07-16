import 'dart:convert';

import '../models/models.dart';
import 'ai_contracts.dart';
import 'ai_service.dart';
import 'local_text_generation_runtime.dart';
import 'model_router.dart';

/// Uses Qwen only for short, validated outputs. Complex planning remains cloud-only.
class LocalFirstStructuredGeneration implements StructuredGenerationCapability {
  final StructuredGenerationCapability cloud;
  final LocalTextGenerationRuntime local;
  LocalFirstStructuredGeneration({required this.cloud, required this.local});

  @override
  String? get lastError => local.lastError ?? cloud.lastError;

  @override
  Future<SplitResult?> splitTodo(String text) async {
    final value = await _json(
      '将用户输入拆为 1-10 个可执行事项。每项 2-16 个汉字。只输出 JSON：{"split":true,"items":["事项"]}。',
      text,
      300,
    );
    final checked = value == null ? null : AiContracts.split(value);
    return checked?.isValid == true
        ? SplitResult.fromJson(checked!.value!)
        : cloud.splitTodo(text);
  }

  @override
  Future<String?> polishTodo(String text) async {
    final value = await _json(
      '将输入凝练为 2-16 个汉字的 Todo 标题。只输出 JSON：{"title":"标题"}。',
      text,
      80,
    );
    final title = value?['title'] as String?;
    final checked = title == null ? null : AiContracts.polishedText(title);
    return checked?.isValid == true ? checked!.value : cloud.polishTodo(text);
  }

  @override
  Future<DailyTodoResult?> generateDailyTodos({
    required String monthPlanTitle,
    required String monthPlanSummary,
    required String date,
    required int timeConstraint,
    required int scheduledHours,
  }) async {
    final value = await _json(
      '根据月计划生成今天 0-3 项事项。每项 title 为 2-16 字，date 必须等于 $date。只输出 JSON：{"todos":[{"title":"事项","date":"$date"}]}。',
      '月计划：$monthPlanTitle\n$monthPlanSummary\n每周可投入：$timeConstraint\n本周已安排：$scheduledHours',
      360,
    );
    final checked = value == null
        ? null
        : AiContracts.dailyTodos(value, date: date);
    return checked?.isValid == true
        ? DailyTodoResult.fromJson(checked!.value!)
        : cloud.generateDailyTodos(
            monthPlanTitle: monthPlanTitle,
            monthPlanSummary: monthPlanSummary,
            date: date,
            timeConstraint: timeConstraint,
            scheduledHours: scheduledHours,
          );
  }

  @override
  Future<PlanResult?> generatePlan({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String startDate,
    required String assessmentReport,
    required String domainKnowledge,
    void Function(String chunk)? onProgress,
    void Function(AiStructuredStage stage)? onStage,
  }) => cloud.generatePlan(
    goal: goal,
    level: level,
    cycleMonths: cycleMonths,
    timeConstraint: timeConstraint,
    startDate: startDate,
    assessmentReport: assessmentReport,
    domainKnowledge: domainKnowledge,
    onProgress: onProgress,
    onStage: onStage,
  );

  @override
  Future<GoalAssessment?> assessGoal({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
    required String domainContext,
  }) => cloud.assessGoal(
    goal: goal,
    level: level,
    cycleMonths: cycleMonths,
    timeConstraint: timeConstraint,
    domainContext: domainContext,
  );

  Future<Map<String, Object?>?> _json(
    String system,
    String user,
    int maxTokens,
  ) async {
    if (!local.isLoaded) return null;
    try {
      final raw = await local.completeJson(
        system: system,
        user: user,
        maxTokens: maxTokens,
      );
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }
}
