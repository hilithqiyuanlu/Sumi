import 'package:speech_to_text/speech_to_text.dart' as stt;

/// 语音录音结果。
class VoiceResult {
  final String text;
  final Duration duration;

  const VoiceResult({required this.text, required this.duration});
}

/// 语音输入异常。
class VoiceInputException implements Exception {
  final String message;
  const VoiceInputException(this.message);

  @override
  String toString() => message;
}

/// 语音输入服务 —— 封装系统语音识别（iOS SFSpeech / Android SpeechRecognizer）。
class VoiceInputService {
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _recording = false;
  DateTime? _startTime;
  String _latestText = '';

  /// 实时部分识别结果回调。
  void Function(String text)? onPartialResult;

  /// 音量回调（0.0 ~ 1.0）。
  void Function(double level)? onSoundLevel;

  /// 状态变更回调。
  void Function(VoiceState state)? onStateChanged;

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;

  bool get isRecording => _recording;

  Duration get recordingDuration {
    if (_startTime == null) return Duration.zero;
    return DateTime.now().difference(_startTime!);
  }

  /// 初始化语音识别（检查权限）。
  Future<bool> initialize() async {
    try {
      final available = await _speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
      return available;
    } catch (_) {
      return false;
    }
  }

  /// 检查麦克风权限是否已授权。
  Future<bool> get hasPermission async {
    try {
      return await _speech.hasPermission ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 开始录音识别。
  Future<void> start() async {
    if (_recording) return;

    _latestText = '';
    _startTime = DateTime.now();

    final available = await _speech.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
    if (!available) {
      _setState(VoiceState.error);
      throw const VoiceInputException(
        '无法使用语音识别，请检查麦克风和语音识别权限。',
      );
    }

    _recording = true;
    _setState(VoiceState.recording);

    await _speech.listen(
      localeId: 'zh_CN',
      onResult: (result) {
        _latestText = result.recognizedWords.trim();
        onPartialResult?.call(_latestText);
      },
      listenMode: stt.ListenMode.deviceDefault,
      onSoundLevelChange: (level) {
        onSoundLevel?.call(level);
      },
    );
  }

  /// 停止录音，返回最终识别结果。
  Future<VoiceResult?> stop() async {
    if (!_recording) return null;

    _recording = false;
    final duration = recordingDuration;
    _startTime = null;
    _setState(VoiceState.idle);

    await _speech.stop();
    final text = _latestText.trim();

    if (text.isEmpty) {
      throw const VoiceInputException('没有识别到语音，请重试。');
    }

    return VoiceResult(text: text, duration: duration);
  }

  /// 取消录音（不发送）。
  Future<void> cancel() async {
    if (!_recording) return;

    _recording = false;
    _startTime = null;
    _latestText = '';
    _setState(VoiceState.idle);

    await _speech.stop();
  }

  void _setState(VoiceState s) {
    _state = s;
    onStateChanged?.call(s);
  }

  void dispose() {
    if (_recording) {
      _speech.stop();
    }
    _recording = false;
    _startTime = null;
  }
}

/// 语音输入状态。
enum VoiceState { idle, recording, error }
