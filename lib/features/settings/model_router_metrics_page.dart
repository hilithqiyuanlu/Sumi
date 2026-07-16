import 'package:flutter/material.dart';

import '../../services/model_router.dart';
import '../../services/model_router_metrics.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';

class ModelRouterMetricsPage extends StatelessWidget {
  const ModelRouterMetricsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final metricStore = SumiScope.read(context).modelRouterMetrics;
    final metrics = metricStore.summaries();
    final speechEvents = metricStore.recentEvents(
      capability: ModelCapability.speechRecognition,
      providerPrefix: 'local-',
    );
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: paper,
        appBar: AppBar(
          title: const Text('模型路由诊断'),
          bottom: const TabBar(
            labelColor: primary500,
            unselectedLabelColor: textSecondary,
            tabs: [
              Tab(text: '云端'),
              Tab(text: '本地智能'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MetricsPanel(
              metrics: metrics
                  .where((metric) => !metric.provider.startsWith('local-'))
                  .toList(growable: false),
              emptyLabel: '近 7 天暂无云端调用记录',
            ),
            _MetricsPanel(
              metrics: metrics
                  .where((metric) => metric.provider.startsWith('local-'))
                  .toList(growable: false),
              emptyLabel: '近 7 天暂无本地智能调用记录',
              speechEvents: speechEvents,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricsPanel extends StatelessWidget {
  final List<ModelRouterMetricsSummary> metrics;
  final String emptyLabel;
  final List<ModelRouterMetricEvent> speechEvents;

  const _MetricsPanel({
    required this.metrics,
    required this.emptyLabel,
    this.speechEvents = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) {
      return Center(
        child: Text(emptyLabel, style: const TextStyle(color: textTertiary)),
      );
    }
    final total = metrics.fold<int>(0, (sum, item) => sum + item.total);
    final success = metrics.fold<int>(0, (sum, item) => sum + item.success);
    final degraded = metrics.fold<int>(0, (sum, item) => sum + item.degraded);
    final duration = metrics.fold<int>(
      0,
      (sum, item) => sum + item.totalDurationMs,
    );
    final average = total == 0 ? 0 : duration ~/ total;

    return ListView(
      padding: const EdgeInsets.fromLTRB(s16, s16, s16, s24),
      children: [
        _Summary(
          total: total,
          success: success,
          degraded: degraded,
          average: average,
        ),
        if (speechEvents.isNotEmpty) ...[
          const SizedBox(height: s20),
          const Text(
            '每次语音识别',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textTertiary,
            ),
          ),
          const SizedBox(height: s8),
          ...speechEvents.map(_SpeechRecognitionRow.new),
        ],
        const SizedBox(height: s20),
        const Text(
          '按天汇总',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textTertiary,
          ),
        ),
        const SizedBox(height: s8),
        ...metrics.map(_MetricRow.new),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  final int total;
  final int success;
  final int degraded;
  final int average;

  const _Summary({
    required this.total,
    required this.success,
    required this.degraded,
    required this.average,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(s16),
    decoration: BoxDecoration(
      color: surfaceAlt,
      borderRadius: BorderRadius.circular(radiusCard),
    ),
    child: Row(
      children: [
        _Stat(label: '调用', value: '$total'),
        _Stat(
          label: '成功',
          value: total == 0 ? '--' : '${(success * 100 ~/ total)}%',
        ),
        _Stat(label: '降级', value: '$degraded'),
        _Stat(label: '平均', value: '${average}ms'),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        const SizedBox(height: s2),
        Text(label, style: const TextStyle(fontSize: 11, color: textTertiary)),
      ],
    ),
  );
}

class _MetricRow extends StatelessWidget {
  final ModelRouterMetricsSummary metric;

  const _MetricRow(this.metric);

  @override
  Widget build(BuildContext context) {
    final date = '${metric.date.month}月${metric.date.day}日';
    final label = switch (metric.capability) {
      ModelCapability.chat => '聊天',
      ModelCapability.structured => '结构化生成',
      ModelCapability.suggestionQuestions => '建议提问',
      ModelCapability.dailyReflection => '每日回顾',
      ModelCapability.memoryExtraction => '记忆提取',
      ModelCapability.webSearch => '搜索',
      ModelCapability.embedding => '语义检索',
      ModelCapability.speechRecognition => '语音识别',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: s8),
      padding: const EdgeInsets.all(s14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: line.withValues(alpha: 0.15), width: 0.5),
        boxShadow: const [...shadow1],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$date · $label',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                const SizedBox(height: s2),
                Text(
                  metric.provider,
                  style: const TextStyle(fontSize: 12, color: textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '${metric.total} 次',
            style: const TextStyle(fontSize: 12, color: textSecondary),
          ),
          const SizedBox(width: s10),
          Text(
            '${(metric.successRate * 100).round()}%',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: primary500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeechRecognitionRow extends StatelessWidget {
  final ModelRouterMetricEvent event;

  const _SpeechRecognitionRow(this.event);

  @override
  Widget build(BuildContext context) {
    final time =
        '${event.occurredAt.month}月${event.occurredAt.day}日 '
        '${event.occurredAt.hour.toString().padLeft(2, '0')}:'
        '${event.occurredAt.minute.toString().padLeft(2, '0')}';
    final succeeded = event.outcome == ModelRouteOutcome.success;
    final outcome = succeeded ? '识别成功' : '识别失败';
    final color = succeeded ? primary500 : danger;
    return Container(
      margin: const EdgeInsets.only(bottom: s8),
      padding: const EdgeInsets.all(s14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: line.withValues(alpha: 0.15), width: 0.5),
        boxShadow: const [...shadow1],
      ),
      child: Row(
        children: [
          const Icon(Icons.graphic_eq_rounded, color: primary500, size: 20),
          const SizedBox(width: s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                const SizedBox(height: s2),
                Text(
                  '${event.provider} · ${event.durationMs}ms',
                  style: const TextStyle(fontSize: 12, color: textSecondary),
                ),
              ],
            ),
          ),
          Text(
            outcome,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
