import 'ai_service.dart';
import 'memory_service.dart';

/// Turns the semantic load analysis into concrete prompts a person can use.
/// These are transient UI prompts, not recommendation-history events.
class TodaySuggestionMapper {
  static const _fallbackRegular = [
    '帮我制定今天的学习计划',
    '建议我今天优先完成什么',
    '帮我回顾一下最近学了什么',
    '帮我分析一下学习进度',
    '推荐一个学习方法',
  ];

  static List<MemorySuggestion> fallbackRegular({required int count}) => [
    for (
      var index = 0;
      index < count && index < _fallbackRegular.length;
      index++
    )
      MemorySuggestion(
        eventId: 'fallback-regular-$index',
        text: _fallbackRegular[index],
        topic: 'fallback_regular_$index',
        source: 'default',
      ),
  ];

  static List<MemorySuggestion> fromAnalysis({
    required TodayLoadAnalysis analysis,
    required String fingerprint,
  }) {
    final reason = analysis.reasons.join(' ').toLowerCase();
    final hasSwitchingCost = _containsAny(reason, const [
      '切换',
      '多项目',
      '分散',
      '交替',
    ]);
    final hasDifficultWork = _containsAny(reason, const [
      '深度',
      '困难',
      '复杂',
      '高专注',
      '输出',
      '报告',
      '写作',
    ]);

    late final String primary;
    late final String secondary;
    if (analysis.needsRebalance && analysis.movableTodoIds.isNotEmpty) {
      primary = '帮我调整今天较满的安排';
      secondary = '帮我缩小今天任务的范围';
    } else if (hasSwitchingCost) {
      primary = '帮我减少今天的任务切换';
      secondary = '帮我确定今天最重要的一步';
    } else if (hasDifficultWork) {
      primary = '帮我把今天最难的任务拆小';
      secondary = '帮我排一下今天任务的先后顺序';
    } else {
      primary = '帮我确定今天最重要的一步';
      secondary = '帮我排一下今天任务的先后顺序';
    }

    return [
      _suggestion(fingerprint, 0, primary),
      _suggestion(fingerprint, 1, secondary),
    ];
  }

  static List<MemorySuggestion> fromScreening({
    required TodayLoadScreening screening,
    required String fingerprint,
  }) => fromAnalysis(
    fingerprint: fingerprint,
    analysis: TodayLoadAnalysis(
      risk: screening.risk,
      reasons: screening.reasons,
      suggestion: '',
      movableTodoIds: const [],
    ),
  );

  /// Keeps the strip stable: regular prompts own slots 1/3/5 and today's
  /// analysis owns slots 2/4. With no analysis, all five are regular prompts.
  static List<MemorySuggestion> compose({
    required List<MemorySuggestion> regular,
    required List<MemorySuggestion> today,
  }) {
    final result = <MemorySuggestion>[];
    final todayItems = today.take(2).toList(growable: false);
    final regularItems = regular
        .take(todayItems.isEmpty ? 5 : 3)
        .toList(growable: false);
    for (var index = 0; index < regularItems.length; index++) {
      result.add(regularItems[index]);
      if (index < todayItems.length) result.add(todayItems[index]);
    }
    if (regularItems.length < todayItems.length) {
      result.addAll(todayItems.skip(regularItems.length));
    }
    return result.take(5).toList(growable: false);
  }

  static MemorySuggestion _suggestion(
    String fingerprint,
    int slot,
    String text,
  ) => MemorySuggestion(
    eventId: 'today-guidance-$fingerprint-$slot',
    text: text,
    topic: 'today_guidance_$slot',
    source: 'today_load',
  );

  static bool _containsAny(String value, List<String> terms) =>
      terms.any(value.contains);
}
