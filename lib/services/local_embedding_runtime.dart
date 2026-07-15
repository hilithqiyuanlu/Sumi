import 'dart:async';

import 'package:flutter/services.dart';

/// Native ONNX Runtime bridge. It never sends input text outside the device.
class LocalEmbeddingRuntime {
  static const dimensions = 512;
  static const _channel = MethodChannel('com.hellosumitech.sumi/embedding');

  bool _loaded = false;
  String? _lastError;

  bool get isLoaded => _loaded;
  String? get lastError => _lastError;

  Future<LocalEmbeddingDeviceStatus> checkDevice() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'checkDevice',
      );
      return LocalEmbeddingDeviceStatus.fromMap(raw ?? const {});
    } on PlatformException catch (error) {
      return LocalEmbeddingDeviceStatus.unavailable(
        error.message ?? '本地推理运行时不可用',
      );
    }
  }

  Future<void> loadModel({
    required String modelPath,
    required String tokenizerPath,
    required String outputName,
    required List<String> inputNames,
    required int maxLength,
  }) async {
    try {
      await _channel.invokeMethod<void>('loadModel', {
        'modelPath': modelPath,
        'tokenizerPath': tokenizerPath,
        'outputName': outputName,
        'inputNames': inputNames,
        'maxLength': maxLength,
      });
      _loaded = true;
      _lastError = null;
    } on PlatformException catch (error) {
      _loaded = false;
      _lastError = error.message ?? '本地模型加载失败';
      throw LocalEmbeddingException(_lastError!);
    }
  }

  Future<List<List<double>>> embed(List<String> texts) async {
    if (!_loaded) throw const LocalEmbeddingException('本地语义检索不可用');
    if (texts.isEmpty) return const [];
    try {
      final raw = await _channel.invokeListMethod<Object?>('embed', {
        'texts': texts,
      });
      final vectors =
          raw
              ?.map(
                (value) => (value as List<Object?>)
                    .map((entry) => (entry as num).toDouble())
                    .toList(),
              )
              .toList() ??
          const <List<double>>[];
      if (vectors.length != texts.length ||
          vectors.any((vector) => vector.length != dimensions)) {
        throw const LocalEmbeddingException('本地模型返回了无效向量');
      }
      return vectors;
    } on PlatformException catch (error) {
      _lastError = error.message ?? '本地向量化失败';
      throw LocalEmbeddingException(_lastError!);
    }
  }

  Future<void> unload() async {
    try {
      await _channel.invokeMethod<void>('unload');
    } finally {
      _loaded = false;
    }
  }
}

class LocalEmbeddingDeviceStatus {
  final bool isSupported;
  final int freeBytes;
  final String? reason;

  const LocalEmbeddingDeviceStatus({
    required this.isSupported,
    required this.freeBytes,
    this.reason,
  });

  factory LocalEmbeddingDeviceStatus.fromMap(Map<String, Object?> map) =>
      LocalEmbeddingDeviceStatus(
        isSupported: map['isSupported'] == true,
        freeBytes: (map['freeBytes'] as num?)?.toInt() ?? 0,
        reason: map['reason'] as String?,
      );

  const LocalEmbeddingDeviceStatus.unavailable(this.reason)
    : isSupported = false,
      freeBytes = 0;
}

class LocalEmbeddingException implements Exception {
  final String message;
  const LocalEmbeddingException(this.message);
  @override
  String toString() => message;
}
