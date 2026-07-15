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
  String? _unavailableReason;

  LocalEmbeddingService(this._runtime);

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
    if (!isAvailable) {
      throw LocalEmbeddingException(unavailableReason ?? '本地语义检索不可用');
    }
    final values = await _runtime.embed(texts);
    return values.map(Float32List.fromList).toList(growable: false);
  }

  Future<void> unload() async {
    await _runtime.unload();
    _embeddingVersion = null;
  }
}
