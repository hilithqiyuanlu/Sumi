import 'package:flutter/material.dart';

import '../../services/model_router.dart';
import '../../services/model_router_metrics.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';

class ModelRouterMetricsPage extends StatelessWidget {
  const ModelRouterMetricsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final metrics = SumiScope.read(context).modelRouterMetrics.summaries();
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

  const _MetricsPanel({required this.metrics, required this.emptyLabel});

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) {
      return Center(
        child: Text(emptyLabel, style: const TextStyle(color: textSecondary)),
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
        const SizedBox(height: s20),
        const Text(
          '按天汇总',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textSecondary,
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
      color: primary50,
      borderRadius: BorderRadius.circular(radius8),
      border: Border.all(color: primary100),
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
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: s2),
        Text(label, style: const TextStyle(fontSize: 11, color: textSecondary)),
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
    };
    return Container(
      margin: const EdgeInsets.only(bottom: s8),
      padding: const EdgeInsets.all(s14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius8),
        border: Border.all(color: surfaceChip),
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
