import 'package:flutter/foundation.dart';

typedef SnapshotWriter = Future<void> Function(Map<String, Object?> snapshot);

/// 串行写入全量快照，并在繁忙时只保留最新待写状态。
class SnapshotWriteQueue {
  final SnapshotWriter _writer;
  Map<String, Object?>? _pending;
  Future<void>? _draining;
  Object? lastError;

  SnapshotWriteQueue(this._writer);

  void schedule(Map<String, Object?> snapshot) {
    _pending = Map<String, Object?>.of(snapshot);
    _draining ??= _drain();
  }

  Future<void> write(Map<String, Object?> snapshot) async {
    schedule(snapshot);
    await flush();
  }

  Future<void> flush() async {
    while (_draining != null || _pending != null) {
      _draining ??= _drain();
      await _draining;
    }
  }

  Future<void> _drain() async {
    try {
      while (_pending != null) {
        final snapshot = _pending!;
        _pending = null;
        try {
          await _writer(snapshot);
          lastError = null;
        } catch (e) {
          lastError = e;
          debugPrint('[SnapshotWriteQueue] 快照写入失败: $e');
        }
      }
    } finally {
      _draining = null;
      if (_pending != null) _draining = _drain();
    }
  }
}
