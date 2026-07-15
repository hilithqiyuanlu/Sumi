import '../models/models.dart';
import 'ai_service.dart';

/// 目标评估编排器 —— 搜索 + AI 评估。
class GoalAssessor {
  final AiService ai;

  GoalAssessor({required this.ai});

  /// 完整评估流程：并行搜索 → 汇总 → AI 多维度评估。
  /// 返回 [GoalAssessment] 或 null（API 全部失败时）。
  Future<GoalAssessment?> assess({
    required String goal,
    required String level,
    required int cycleMonths,
    required int timeConstraint,
  }) async {
    // 1. 并行搜索领域信息
    final queries = _buildSearchQueries(goal);
    final searchResults = await Future.wait(
      queries.map((q) => ai.searchWeb(q)),
    );

    // 2. 汇总搜索结果为文本
    final domainContext = _buildDomainContext(searchResults, queries);

    // 3. 调用 AI 评估
    final assessment = await ai.assessGoal(
      goal: goal,
      level: level,
      cycleMonths: cycleMonths,
      timeConstraint: timeConstraint,
      domainContext: domainContext,
    );

    // 4. 附加搜索来源到评估结果
    if (assessment != null) {
      final sources = _extractSources(searchResults);
      return GoalAssessment(
        clarity: assessment.clarity,
        feasibility: assessment.feasibility,
        challengeFit: assessment.challengeFit,
        decomposability: assessment.decomposability,
        timeRealism: assessment.timeRealism,
        motivationPotential: assessment.motivationPotential,
        resourceAccess: assessment.resourceAccess,
        measurability: assessment.measurability,
        verdict: assessment.verdict,
        concerns: assessment.concerns,
        suggestions: assessment.suggestions,
        estimatedHours: assessment.estimatedHours,
        domainSummary: assessment.domainSummary,
        sources: sources,
        goalSummary: assessment.goalSummary,
      );
    }

    return null;
  }

  /// 构建搜索 query 列表。
  List<String> _buildSearchQueries(String goal) {
    return [
      '$goal 学习路线 从零开始',
      'how long to learn $goal hours beginner',
      '$goal 入门 前置知识 prerequisites',
    ];
  }

  /// 汇总多条搜索结果为一段文本。
  String _buildDomainContext(
    List<List<Map<String, String>>> results,
    List<String> queries,
  ) {
    final buf = StringBuffer();

    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      if (r.isEmpty) continue;

      // 跳过错误/空结果
      final first = r.first;
      if (first.containsKey('error') || first.containsKey('info')) continue;

      buf.writeln('## 搜索：${queries[i]}');
      for (var j = 0; j < r.length; j++) {
        final item = r[j];
        final title = item['title'] ?? '';
        final content = item['content'] ?? '';
        final url = item['url'] ?? '';
        if (title.isNotEmpty || content.isNotEmpty) {
          buf.writeln('${j + 1}. $title');
          if (content.isNotEmpty) buf.writeln('   $content');
          if (url.isNotEmpty) buf.writeln('   来源：$url');
        }
      }
      buf.writeln();
    }

    if (buf.isEmpty) {
      return '（未能搜索到相关领域信息，请基于常识评估）';
    }
    // 截断保护（评估 prompt + domainContext 不宜过长）
    final text = buf.toString();
    if (text.length > 4000) {
      return '${text.substring(0, 4000)}\n\n（搜索结果较长，已截断）';
    }
    return text;
  }

  /// 从搜索结果中提取来源列表。
  List<SearchSnippet> _extractSources(
    List<List<Map<String, String>>> results,
  ) {
    final sources = <SearchSnippet>[];
    for (final r in results) {
      for (final item in r) {
        final title = item['title'];
        final url = item['url'];
        final content = item['content'];
        if (title != null && title.isNotEmpty) {
          sources.add(SearchSnippet(
            title: title,
            url: url ?? '',
            content: content ?? '',
          ));
        }
      }
    }
    return sources.take(10).toList();
  }
}
