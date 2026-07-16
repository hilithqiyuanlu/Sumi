import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/models.dart';
import '../utils/haptics.dart';

abstract interface class ForegroundReminder {
  ValueListenable<StudyTimer?> get activeReminder;
  Future<void> start(StudyTimer timer);
  Future<void> stop();
  Future<void> dispose();
}

/// 在应用可见时循环播放提醒音，并持续提供强触觉反馈。
class ForegroundReminderService implements ForegroundReminder {
  AudioPlayer? _player;
  final ValueNotifier<StudyTimer?> _activeReminder = ValueNotifier(null);
  Timer? _hapticTimer;
  bool _prepared = false;

  ForegroundReminderService();

  AudioPlayer get _audioPlayer => _player ??= AudioPlayer();

  @override
  ValueListenable<StudyTimer?> get activeReminder => _activeReminder;

  @override
  Future<void> start(StudyTimer timer) async {
    if (_activeReminder.value?.id == timer.id) return;
    await stop();
    _activeReminder.value = timer;
    H.heavy();
    _hapticTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      H.heavy();
    });
    try {
      final player = _audioPlayer;
      if (!_prepared) {
        await player.setAsset('assets/audio/sumi_alarm.wav');
        await player.setLoopMode(LoopMode.one);
        _prepared = true;
      }
      await player.seek(Duration.zero);
      await player.play();
    } catch (_) {
      // 音频不可用时仍显示全屏提醒并保留触觉反馈。
    }
  }

  @override
  Future<void> stop() async {
    _hapticTimer?.cancel();
    _hapticTimer = null;
    _activeReminder.value = null;
    final player = _player;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {
      // 播放器已释放或平台音频会话不可用时无需阻断停止流程。
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _player?.dispose();
    _player = null;
    _activeReminder.dispose();
  }
}
