import 'package:llamadart/llamadart.dart';

/// Owns the native GGUF session used by Sumi's local short-form tasks.
/// Conversation and tool-loop generation deliberately remain cloud-only.
class LocalTextGenerationRuntime {
  LlamaEngine? _engine;
  String? _modelVersion;
  String? _lastError;

  bool get isLoaded => _engine?.isReady ?? false;
  String? get modelVersion => _modelVersion;
  String? get lastError => _lastError;

  Future<void> load({
    required String modelPath,
    required String modelVersion,
  }) async {
    await unload();
    final engine = LlamaEngine(LlamaBackend());
    try {
      await engine.loadModel(
        modelPath,
        modelParams: const ModelParams(contextSize: 2048),
      );
      _engine = engine;
      _modelVersion = modelVersion;
      _lastError = null;
    } catch (error) {
      await engine.dispose();
      _lastError = error.toString();
      throw LocalTextGenerationException(_lastError!);
    }
  }

  Future<String> completeJson({
    required String system,
    required String user,
    required int maxTokens,
  }) async {
    final engine = _engine;
    if (engine == null || !engine.isReady) {
      throw const LocalTextGenerationException('本地文本模型尚未加载');
    }
    final result = StringBuffer();
    try {
      await for (final chunk in engine.create(
        [
          LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: user),
        ],
        enableThinking: false,
        responseFormat: const {'type': 'json_object'},
        params: GenerationParams(maxTokens: maxTokens, temp: 0.2),
      )) {
        result.write(chunk.choices.first.delta.content ?? '');
      }
      final output = result.toString().trim();
      if (output.isEmpty) {
        throw const LocalTextGenerationException('本地模型未返回内容');
      }
      _lastError = null;
      return output;
    } catch (error) {
      _lastError = error.toString();
      throw LocalTextGenerationException(_lastError!);
    }
  }

  Future<void> unload() async {
    final engine = _engine;
    _engine = null;
    _modelVersion = null;
    if (engine != null) await engine.dispose();
  }
}

class LocalTextGenerationException implements Exception {
  final String message;
  const LocalTextGenerationException(this.message);
  @override
  String toString() => message;
}
