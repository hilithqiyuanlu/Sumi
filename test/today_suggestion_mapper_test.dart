import 'package:flutter_test/flutter_test.dart';
import 'package:sumi/services/ai_service.dart';
import 'package:sumi/services/memory_service.dart';
import 'package:sumi/services/today_suggestion_mapper.dart';

void main() {
  MemorySuggestion regular(int index) => MemorySuggestion(
    eventId: 'regular-$index',
    text: '常规建议$index',
    topic: 'regular-$index',
    source: 'default',
  );

  test('高风险且可移动事项生成调整与缩小范围两条今日建议', () {
    final suggestions = TodaySuggestionMapper.fromAnalysis(
      fingerprint: 'heavy',
      analysis: const TodayLoadAnalysis(
        risk: .8,
        reasons: ['两项深度任务集中在今天'],
        suggestion: 'unused',
        movableTodoIds: ['todo-1'],
      ),
    );

    expect(suggestions.map((item) => item.text), [
      '帮我调整今天较满的安排',
      '帮我缩小今天任务的范围',
    ]);
    expect(suggestions.every((item) => item.source == 'today_load'), isTrue);
  });

  test('任务切换风险映射为不同维度的今日建议', () {
    final suggestions = TodaySuggestionMapper.fromAnalysis(
      fingerprint: 'switching',
      analysis: const TodayLoadAnalysis(
        risk: .4,
        reasons: ['多个项目来回切换，注意力容易分散'],
        suggestion: 'unused',
        movableTodoIds: [],
      ),
    );

    expect(suggestions.map((item) => item.text), [
      '帮我减少今天的任务切换',
      '帮我确定今天最重要的一步',
    ]);
  });

  test('有今日分析时，五个槽位按常规和今日交替排列', () {
    final today = TodaySuggestionMapper.fromAnalysis(
      fingerprint: 'order',
      analysis: const TodayLoadAnalysis(
        risk: .2,
        reasons: ['今天任务节奏平稳'],
        suggestion: 'unused',
        movableTodoIds: [],
      ),
    );
    final composed = TodaySuggestionMapper.compose(
      regular: [regular(0), regular(1), regular(2)],
      today: today,
    );

    expect(composed.map((item) => item.source), [
      'default',
      'today_load',
      'default',
      'today_load',
      'default',
    ]);
  });

  test('没有今日分析时由五条常规建议填满', () {
    final composed = TodaySuggestionMapper.compose(
      regular: List.generate(5, regular),
      today: const [],
    );

    expect(composed, hasLength(5));
    expect(composed.every((item) => item.source == 'default'), isTrue);
  });

  test('系统兜底提供五条不同的常规建议', () {
    final fallback = TodaySuggestionMapper.fallbackRegular(count: 5);

    expect(fallback, hasLength(5));
    expect(fallback.map((item) => item.text).toSet(), hasLength(5));
  });
}
