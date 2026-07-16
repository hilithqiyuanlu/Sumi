import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'local_speech_recognition_runtime.dart';
import 'model_router.dart';

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

/// 语音输入服务。未下载模型时继续使用系统实时识别；下载 SenseVoice 后
/// 改为本地录音和松开后的最终识别，避免两套录音器同时抢占麦克风。
class VoiceInputService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final LocalSpeechRecognitionRuntime? localRuntime;
  final bool Function() _localSpeechEnabled;
  final ModelRouterMetricsSink? _metrics;
  final DateTime Function() _now;
  AudioRecorder? _recorder;

  bool _recording = false;
  DateTime? _startTime;
  String _latestText = '';
  String? _recordingPath;
  bool _recordingLocally = false;

  /// 实时部分识别结果回调。
  void Function(String text)? onPartialResult;

  /// 音量回调（0.0 ~ 1.0）。
  void Function(double level)? onSoundLevel;

  /// 状态变更回调。
  void Function(VoiceState state)? onStateChanged;

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;

  bool get isRecording => _recording;
  bool get usingLocalModel =>
      _localSpeechEnabled() && (localRuntime?.isLoaded ?? false);
  AudioRecorder get _audioRecorder => _recorder ??= AudioRecorder();

  VoiceInputService({
    this.localRuntime,
    bool Function()? localSpeechEnabled,
    this._metrics,
    DateTime Function()? now,
  }) : _localSpeechEnabled = localSpeechEnabled ?? _alwaysEnabled,
       _now = now ?? DateTime.now;

  static bool _alwaysEnabled() => true;

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
      return usingLocalModel
          ? await _audioRecorder.hasPermission()
          : await _speech.hasPermission;
    } catch (_) {
      return false;
    }
  }

  /// 开始录音识别。
  Future<void> start() async {
    if (_recording) return;

    _latestText = '';
    _startTime = DateTime.now();

    final localAvailable =
        usingLocalModel && await _audioRecorder.hasPermission();
    var available = false;
    if (!localAvailable) {
      available = await _speech.initialize(onError: (_) {}, onStatus: (_) {});
    }
    if (!available && !localAvailable) {
      _setState(VoiceState.error);
      throw const VoiceInputException('无法使用语音识别，请检查麦克风和语音识别权限。');
    }

    try {
      if (localAvailable) {
        final directory = await getTemporaryDirectory();
        _recordingPath = p.join(
          directory.path,
          'sumi-voice-${DateTime.now().microsecondsSinceEpoch}.wav',
        );
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
            autoGain: true,
            echoCancel: true,
            noiseSuppress: true,
          ),
          path: _recordingPath!,
        );
      } else {
        await _speech.listen(
          listenOptions: stt.SpeechListenOptions(
            localeId: 'zh_CN',
            listenMode: stt.ListenMode.deviceDefault,
          ),
          onResult: (result) {
            _latestText = result.recognizedWords.trim();
            onPartialResult?.call(_latestText);
          },
          onSoundLevelChange: (level) {
            onSoundLevel?.call(level);
          },
        );
      }
      _recordingLocally = localAvailable;
      _recording = true;
      _setState(VoiceState.recording);
    } catch (error) {
      _recordingPath = null;
      _recordingLocally = false;
      _setState(VoiceState.error);
      throw VoiceInputException('无法开始录音：$error');
    }
  }

  /// 停止录音，返回最终识别结果。
  Future<VoiceResult?> stop() async {
    if (!_recording) return null;

    _recording = false;
    final duration = recordingDuration;
    _startTime = null;
    _setState(VoiceState.idle);

    final usedLocalModel = _recordingLocally;
    _recordingLocally = false;
    if (!usedLocalModel) await _speech.stop();
    String text = _latestText.trim();
    final path = usedLocalModel ? await _audioRecorder.stop() : null;
    final localPath = path ?? _recordingPath;
    _recordingPath = null;
    if (usedLocalModel && localPath == null) {
      _recordLocalRecognition(
        succeeded: false,
        elapsed: Duration.zero,
        error: const VoiceInputException('本地录音文件不可用'),
      );
      throw const VoiceInputException('本地录音文件不可用，请重新录音。');
    }
    if (localPath != null && usedLocalModel) {
      final recognitionStartedAt = _now();
      try {
        if (!usingLocalModel) {
          throw const VoiceInputException('本地语音模型已被移除，请重新录音。');
        }
        final localText = await localRuntime!.transcribeWav(localPath);
        if (localText.isEmpty) {
          throw const VoiceInputException('没有识别到语音，请重试。');
        }
        text = localText;
        onPartialResult?.call(text);
        _recordLocalRecognition(
          succeeded: true,
          elapsed: _now().difference(recognitionStartedAt),
          error: null,
        );
      } on VoiceInputException catch (error) {
        _recordLocalRecognition(
          succeeded: false,
          elapsed: _now().difference(recognitionStartedAt),
          error: error,
        );
        rethrow;
      } catch (error) {
        _recordLocalRecognition(
          succeeded: false,
          elapsed: _now().difference(recognitionStartedAt),
          error: error,
        );
        throw VoiceInputException('本地语音识别失败：$error');
      } finally {
        final file = File(localPath);
        if (await file.exists()) await file.delete();
      }
    }

    if (text.isEmpty) {
      throw const VoiceInputException('没有识别到语音，请重试。');
    }

    return VoiceResult(text: text, duration: duration);
  }

  void _recordLocalRecognition({
    required bool succeeded,
    required Duration elapsed,
    required Object? error,
  }) {
    final version = localRuntime?.version;
    _metrics?.record(
      ModelRouterMetric(
        occurredAt: _now(),
        capability: ModelCapability.speechRecognition,
        provider: 'local-sensevoice${version == null ? '' : '-$version'}',
        outcome: succeeded
            ? ModelRouteOutcome.success
            : ModelRouteOutcome.failure,
        elapsed: elapsed,
        errorCategory: error == null
            ? ModelRouterErrorCategory.none
            : ModelRouterErrorClassifier.fromException(error),
      ),
    );
  }

  /// 取消录音（不发送）。
  Future<void> cancel() async {
    if (!_recording) return;

    _recording = false;
    _startTime = null;
    _latestText = '';
    _setState(VoiceState.idle);

    final usedLocalModel = _recordingLocally;
    _recordingLocally = false;
    if (usedLocalModel) {
      await _audioRecorder.cancel();
    } else {
      await _speech.stop();
    }
    _recordingPath = null;
  }

  void _setState(VoiceState s) {
    _state = s;
    onStateChanged?.call(s);
  }

  void dispose() {
    if (_recording) {
      _speech.stop();
      _recorder?.cancel();
    }
    _recorder?.dispose();
    _recording = false;
    _recordingLocally = false;
    _startTime = null;
  }
}

/// 语音输入状态。
enum VoiceState { idle, recording, error }
