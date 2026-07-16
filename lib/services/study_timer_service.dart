import 'dart:async';

import '../data/study_timer_database.dart';
import '../models/models.dart';
import 'timer_controller.dart';
import '../utils/haptics.dart';

class StudyTimerService {
  final StudyTimerDatabase database;
  final TimerController controller;
  final DateTime Function() _now;
  Timer? _ticker;
  bool _foreground = true;

  StudyTimerService({
    required this.database,
    required this.controller,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  Future<void> restore() async {
    final timers = await database.loadAll();
    controller.replaceAll(timers);
    await _reconcile(playHaptic: false);
    _ensureTicker();
  }

  Future<StudyTimer> create({
    required String id,
    required String toolCallId,
    required String conversationId,
    required String title,
    required int minutes,
  }) async {
    final now = _now();
    final timer = StudyTimer(
      id: id,
      toolCallId: toolCallId,
      conversationId: conversationId,
      title: title,
      totalSeconds: minutes * 60,
      remainingSeconds: minutes * 60,
      status: StudyTimerStatus.ready,
      createdAt: now,
      updatedAt: now,
    );
    await _save(timer);
    return timer;
  }

  Future<void> start(String id) async {
    final timer = controller.byId(id);
    if (timer == null ||
        (timer.status != StudyTimerStatus.ready &&
            timer.status != StudyTimerStatus.paused)) {
      return;
    }
    final now = _now();
    await _save(
      timer.copyWith(
        status: StudyTimerStatus.running,
        startedAt: now,
        updatedAt: now,
      ),
    );
    _ensureTicker();
  }

  Future<void> pause(String id) async {
    final timer = controller.byId(id);
    if (timer == null || timer.status != StudyTimerStatus.running) return;
    final now = _now();
    await _save(
      timer.copyWith(
        remainingSeconds: timer.remainingAt(now),
        status: StudyTimerStatus.paused,
        clearStartedAt: true,
        updatedAt: now,
      ),
    );
    _ensureTicker();
  }

  Future<void> finish(String id) => _complete(id, playHaptic: false);

  Future<void> cancel(String id) async {
    final timer = controller.byId(id);
    if (timer == null ||
        timer.status == StudyTimerStatus.completed ||
        timer.status == StudyTimerStatus.cancelled) {
      return;
    }
    await _save(
      timer.copyWith(
        remainingSeconds: timer.remainingAt(_now()),
        status: StudyTimerStatus.cancelled,
        clearStartedAt: true,
        updatedAt: _now(),
      ),
    );
    _ensureTicker();
  }

  Future<void> handleLifecycle(bool foreground) async {
    _foreground = foreground;
    if (!foreground) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    await _reconcile(playHaptic: true);
    _ensureTicker();
  }

  Future<void> _reconcile({required bool playHaptic}) async {
    final now = _now();
    for (final timer in controller.timers) {
      if (timer.status == StudyTimerStatus.running &&
          timer.remainingAt(now) == 0) {
        await _complete(timer.id, playHaptic: playHaptic);
      }
    }
  }

  Future<void> _complete(String id, {required bool playHaptic}) async {
    final timer = controller.byId(id);
    if (timer == null || timer.status == StudyTimerStatus.completed) return;
    await _save(
      timer.copyWith(
        remainingSeconds: 0,
        status: StudyTimerStatus.completed,
        clearStartedAt: true,
        updatedAt: _now(),
      ),
    );
    if (playHaptic && _foreground) H.timerFinished();
    _ensureTicker();
  }

  Future<void> _save(StudyTimer timer) async {
    await database.upsert(timer);
    controller.put(timer);
  }

  void _ensureTicker() {
    final hasRunning = controller.timers.any(
      (timer) => timer.status == StudyTimerStatus.running,
    );
    if (!_foreground || !hasRunning) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) async {
      await _reconcile(playHaptic: true);
      controller.tick();
    });
  }

  Future<void> clearAll() async {
    _ticker?.cancel();
    _ticker = null;
    controller.clear();
    await database.clearAll();
  }

  void dispose() => _ticker?.cancel();
}
