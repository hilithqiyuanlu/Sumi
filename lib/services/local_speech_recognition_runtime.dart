import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class LocalSpeechRecognitionException implements Exception {
  const LocalSpeechRecognitionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Keeps the recognizer warm after the package is verified. Decoding happens
/// after the user releases the input, never while the press gesture is pending.
class LocalSpeechRecognitionRuntime {
  sherpa.OfflineRecognizer? _recognizer;
  String? _version;

  bool get isLoaded => _recognizer != null;
  String? get version => _version;

  Future<void> load({
    required String modelPath,
    required String tokensPath,
    required String version,
  }) async {
    if (!await File(modelPath).exists() || !await File(tokensPath).exists()) {
      throw const LocalSpeechRecognitionException('语音模型文件不完整');
    }
    try {
      sherpa.initBindings();
      final nextRecognizer = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            senseVoice: sherpa.OfflineSenseVoiceModelConfig(
              model: modelPath,
              language: 'auto',
              useInverseTextNormalization: true,
            ),
            tokens: tokensPath,
            numThreads: 2,
            debug: false,
          ),
        ),
      );
      final previous = _recognizer;
      _recognizer = nextRecognizer;
      _version = version;
      previous?.free();
    } catch (error) {
      throw LocalSpeechRecognitionException('无法加载本地语音模型：$error');
    }
  }

  Future<String> transcribeWav(String path) async {
    final recognizer = _recognizer;
    if (recognizer == null) {
      throw const LocalSpeechRecognitionException('本地语音模型尚未加载');
    }
    try {
      final wave = sherpa.readWave(path);
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(
          samples: wave.samples,
          sampleRate: wave.sampleRate,
        );
        recognizer.decode(stream);
        return recognizer.getResult(stream).text.trim();
      } finally {
        stream.free();
      }
    } catch (error) {
      if (error is LocalSpeechRecognitionException) rethrow;
      throw LocalSpeechRecognitionException('本地语音识别失败：$error');
    }
  }

  Future<void> unload() async {
    _recognizer?.free();
    _recognizer = null;
    _version = null;
  }
}
