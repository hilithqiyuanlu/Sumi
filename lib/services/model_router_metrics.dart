import 'model_router.dart';

/// Local, content-free aggregates for the developer diagnostics screen.
class ModelRouterMetricsStore implements ModelRouterMetricsSink {
  static const retentionDays = 7;
  final DateTime Function() _now;
  final void Function()? onChanged;
  final Map<String, _MetricBucket> _buckets = {};
  final List<ModelRouterMetricEvent> _events = [];

  ModelRouterMetricsStore({DateTime Function()? now, this.onChanged})
    : _now = now ?? DateTime.now;

  @override
  void record(ModelRouterMetric metric) {
    _removeExpired(reference: metric.occurredAt);
    if (metric.capability == ModelCapability.speechRecognition) {
      _events.add(ModelRouterMetricEvent.fromMetric(metric));
    }
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
    final values = _buckets.values.map((bucket) => bucket.toSummary()).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(values);
  }

  List<ModelRouterMetricEvent> recentEvents({
    ModelCapability? capability,
    String? providerPrefix,
    DateTime? now,
  }) {
    _removeExpired(reference: now ?? _now());
    final values = _events.where((event) {
      if (capability != null && event.capability != capability) return false;
      if (providerPrefix != null &&
          !event.provider.startsWith(providerPrefix)) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return List.unmodifiable(values);
  }

  Map<String, Object?> toJson() {
    _removeExpired(reference: _now());
    return {
      'buckets': _buckets.values.map((bucket) => bucket.toJson()).toList(),
      'events': _events.map((event) => event.toJson()).toList(),
    };
  }

  void restore(Map<String, Object?>? json) {
    _buckets.clear();
    _events.clear();
    final raw = json?['buckets'];
    if (raw is! List<Object?>) return;
    for (final item in raw) {
      if (item is! Map<String, Object?>) continue;
      final bucket = _MetricBucket.fromJson(item);
      if (bucket != null) _buckets[_keyFromBucket(bucket)] = bucket;
    }
    final events = json?['events'];
    if (events is List<Object?>) {
      for (final item in events) {
        if (item is! Map<String, Object?>) continue;
        final event = ModelRouterMetricEvent.fromJson(item);
        if (event != null) _events.add(event);
      }
    }
    _removeExpired(reference: _now());
  }

  void clear() {
    if (_buckets.isEmpty && _events.isEmpty) return;
    _buckets.clear();
    _events.clear();
    onChanged?.call();
  }

  void _removeExpired({required DateTime reference}) {
    final cutoff = DateTime(
      reference.year,
      reference.month,
      reference.day,
    ).subtract(const Duration(days: retentionDays - 1));
    _buckets.removeWhere((_, bucket) => bucket.date.isBefore(cutoff));
    _events.removeWhere((event) => event.occurredAt.isBefore(cutoff));
  }

  static DateTime _date(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _key(
    DateTime date,
    ModelCapability capability,
    String provider,
  ) => '${_date(date).toIso8601String()}|${capability.name}|$provider';

  static String _keyFromBucket(_MetricBucket bucket) =>
      _key(bucket.date, bucket.capability, bucket.provider);
}

/// 单次、无内容的调用记录，仅用于本地诊断界面。
class ModelRouterMetricEvent {
  final DateTime occurredAt;
  final ModelCapability capability;
  final String provider;
  final ModelRouteOutcome outcome;
  final int durationMs;
  final ModelRouterErrorCategory errorCategory;

  const ModelRouterMetricEvent({
    required this.occurredAt,
    required this.capability,
    required this.provider,
    required this.outcome,
    required this.durationMs,
    required this.errorCategory,
  });

  factory ModelRouterMetricEvent.fromMetric(ModelRouterMetric metric) =>
      ModelRouterMetricEvent(
        occurredAt: metric.occurredAt,
        capability: metric.capability,
        provider: metric.provider,
        outcome: metric.outcome,
        durationMs: metric.elapsed.inMilliseconds,
        errorCategory: metric.errorCategory,
      );

  Map<String, Object?> toJson() => {
    'occurredAt': occurredAt.toIso8601String(),
    'capability': capability.name,
    'provider': provider,
    'outcome': outcome.name,
    'durationMs': durationMs,
    'errorCategory': errorCategory.name,
  };

  static ModelRouterMetricEvent? fromJson(Map<String, Object?> json) {
    final occurredAt = DateTime.tryParse(json['occurredAt'] as String? ?? '');
    final capability = _enumValue(ModelCapability.values, json['capability']);
    final outcome = _enumValue(ModelRouteOutcome.values, json['outcome']);
    final errorCategory = _enumValue(
      ModelRouterErrorCategory.values,
      json['errorCategory'],
    );
    final provider = json['provider'] as String?;
    if (occurredAt == null ||
        capability == null ||
        outcome == null ||
        errorCategory == null ||
        provider == null ||
        provider.isEmpty) {
      return null;
    }
    return ModelRouterMetricEvent(
      occurredAt: occurredAt,
      capability: capability,
      provider: provider,
      outcome: outcome,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      errorCategory: errorCategory,
    );
  }

  static T? _enumValue<T extends Enum>(List<T> values, Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
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
    if (date == null ||
        capability.isEmpty ||
        provider == null ||
        provider.isEmpty) {
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
