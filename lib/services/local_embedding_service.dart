import 'dart:typed_data';

import 'local_embedding_runtime.dart';

abstract interface class EmbeddingCapability {
  bool get isAvailable;
  String? get unavailableReason;
  String? get embeddingVersion;
  Future<List<Float32List>> embed(List<String> texts);
}

/// Local-only embedding capability. There is deliberately no cloud fallback.
class LocalEmbeddingService implements EmbeddingCapability {
  final LocalEmbeddingRuntime _runtime;
  final void Function({
    required bool succeeded,
    required Duration elapsed,
    required Object? error,
  })?
  onMetric;
  String? _unavailableReason;

  LocalEmbeddingService(this._runtime, {this.onMetric});

  @override
  bool get isAvailable => _runtime.isLoaded;

  @override
  String? get unavailableReason => _unavailableReason ?? _runtime.lastError;

  String? _embeddingVersion;
  @override
  String? get embeddingVersion => _embeddingVersion;

  Future<void> load({
    required String modelPath,
    required String vocabPath,
    required String embeddingVersion,
    required String outputName,
    required List<String> inputNames,
    required int maxLength,
  }) async {
    try {
      await _runtime.loadModel(
        modelPath: modelPath,
        tokenizerPath: vocabPath,
        outputName: outputName,
        inputNames: inputNames,
        maxLength: maxLength,
      );
      _unavailableReason = null;
      _embeddingVersion = embeddingVersion;
    } on LocalEmbeddingException catch (error) {
      _unavailableReason = error.message;
      rethrow;
    }
  }

  @override
  Future<List<Float32List>> embed(List<String> texts) async {
    final watch = Stopwatch()..start();
    if (!isAvailable) {
      final error = LocalEmbeddingException(unavailableReason ?? '本地语义检索不可用');
      _recordFailure(error, watch.elapsed);
      throw error;
    }
    try {
      final values = await _runtime.embed(texts);
      onMetric?.call(succeeded: true, elapsed: watch.elapsed, error: null);
      return values.map(Float32List.fromList).toList(growable: false);
    } catch (error) {
      _recordFailure(error, watch.elapsed);
      rethrow;
    } finally {
      watch.stop();
    }
  }

  void _recordFailure(Object error, Duration elapsed) {
    onMetric?.call(succeeded: false, elapsed: elapsed, error: error);
  }

  Future<void> unload() async {
    await _runtime.unload();
    _embeddingVersion = null;
  }
}
