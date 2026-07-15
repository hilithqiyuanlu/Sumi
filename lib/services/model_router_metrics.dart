import 'model_router.dart';

/// Local, content-free aggregates for the developer diagnostics screen.
class ModelRouterMetricsStore implements ModelRouterMetricsSink {
  static const retentionDays = 7;
  final DateTime Function() _now;
  final void Function()? onChanged;
  final Map<String, _MetricBucket> _buckets = {};

  ModelRouterMetricsStore({
    DateTime Function()? now,
    this.onChanged,
  })
      : _now = now ?? DateTime.now;

  @override
  void record(ModelRouterMetric metric) {
    _removeExpired(reference: metric.occurredAt);
    final key = _key(metric.occurredAt, metric.capability, metric.provider);
    (_buckets[key] ??= _MetricBucket(
      date: _date(metric.occurredAt),
      capability: metric.capability,
      provider: metric.provider,
    )).record(metric);
    onChanged?.call();
  }

  List<ModelRouterMetricsSummary> summaries({DateTime? now}) {
    _removeExpired(reference: now ?? _now());
    final values = _buckets.values
        .map((bucket) => bucket.toSummary())
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(values);
  }

  Map<String, Object?> toJson() {
    _removeExpired(reference: _now());
    return {
      'buckets': _buckets.values.map((bucket) => bucket.toJson()).toList(),
    };
  }

  void restore(Map<String, Object?>? json) {
    _buckets.clear();
    final raw = json?['buckets'];
    if (raw is! List<Object?>) return;
    for (final item in raw) {
      if (item is! Map<String, Object?>) continue;
      final bucket = _MetricBucket.fromJson(item);
      if (bucket != null) _buckets[_keyFromBucket(bucket)] = bucket;
    }
    _removeExpired(reference: _now());
  }

  void clear() {
    if (_buckets.isEmpty) return;
    _buckets.clear();
    onChanged?.call();
  }

  void _removeExpired({required DateTime reference}) {
    final cutoff = DateTime(reference.year, reference.month, reference.day)
        .subtract(const Duration(days: retentionDays - 1));
    _buckets.removeWhere((_, bucket) => bucket.date.isBefore(cutoff));
  }

  static DateTime _date(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _key(DateTime date, ModelCapability capability, String provider) =>
      '${_date(date).toIso8601String()}|${capability.name}|$provider';

  static String _keyFromBucket(_MetricBucket bucket) =>
      _key(bucket.date, bucket.capability, bucket.provider);
}

class ModelRouterMetricsSummary {
  final DateTime date;
  final ModelCapability capability;
  final String provider;
  final int total;
  final int success;
  final int failed;
  final int degraded;
  final int totalDurationMs;

  const ModelRouterMetricsSummary({
    required this.date,
    required this.capability,
    required this.provider,
    required this.total,
    required this.success,
    required this.failed,
    required this.degraded,
    required this.totalDurationMs,
  });

  double get successRate => total == 0 ? 0 : success / total;
  int get averageDurationMs => total == 0 ? 0 : totalDurationMs ~/ total;
}

class _MetricBucket {
  final DateTime date;
  final ModelCapability capability;
  final String provider;
  int total;
  int success;
  int failed;
  int degraded;
  int totalDurationMs;

  _MetricBucket({
    required this.date,
    required this.capability,
    required this.provider,
    this.total = 0,
    this.success = 0,
    this.failed = 0,
    this.degraded = 0,
    this.totalDurationMs = 0,
  });

  void record(ModelRouterMetric metric) {
    total++;
    totalDurationMs += metric.elapsed.inMilliseconds;
    switch (metric.outcome) {
      case ModelRouteOutcome.success:
        success++;
      case ModelRouteOutcome.failure:
        failed++;
      case ModelRouteOutcome.degraded:
        degraded++;
    }
  }

  ModelRouterMetricsSummary toSummary() => ModelRouterMetricsSummary(
    date: date,
    capability: capability,
    provider: provider,
    total: total,
    success: success,
    failed: failed,
    degraded: degraded,
    totalDurationMs: totalDurationMs,
  );

  Map<String, Object?> toJson() => {
    'date': date.toIso8601String(),
    'capability': capability.name,
    'provider': provider,
    'total': total,
    'success': success,
    'failed': failed,
    'degraded': degraded,
    'totalDurationMs': totalDurationMs,
  };

  static _MetricBucket? fromJson(Map<String, Object?> json) {
    final date = DateTime.tryParse(json['date'] as String? ?? '');
    final capability = ModelCapability.values.where(
      (value) => value.name == json['capability'],
    );
    final provider = json['provider'] as String?;
    if (date == null || capability.isEmpty || provider == null || provider.isEmpty) {
      return null;
    }
    int integer(String key) => (json[key] as num?)?.toInt() ?? 0;
    return _MetricBucket(
      date: DateTime(date.year, date.month, date.day),
      capability: capability.first,
      provider: provider,
      total: integer('total'),
      success: integer('success'),
      failed: integer('failed'),
      degraded: integer('degraded'),
      totalDurationMs: integer('totalDurationMs'),
    );
  }
}
