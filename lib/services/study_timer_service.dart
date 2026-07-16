import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/study_timer_database.dart';
import '../models/models.dart';
import 'foreground_reminder_service.dart';
import 'system_reminder_service.dart';
import 'timer_controller.dart';

class StudyTimerService {
  final StudyTimerDatabase database;
  final TimerController controller;
  final ReminderScheduler reminders;
  final ForegroundReminder foregroundReminders;
  final DateTime Function() _now;
  Timer? _ticker;
  bool _foreground = true;

  StudyTimerService({
    required this.database,
    required this.controller,
    ReminderScheduler? reminders,
    ForegroundReminder? foregroundReminders,
    DateTime Function()? now,
  }) : reminders = reminders ?? SystemReminderService(),
       foregroundReminders = foregroundReminders ?? ForegroundReminderService(),
       _now = now ?? DateTime.now;

  ValueListenable<StudyTimer?> get activeReminder =>
      foregroundReminders.activeReminder;

  Future<void> restore() async {
    final timers = await database.loadAll();
    controller.replaceAll(timers);
    await _reconcile();
    _ensureTicker();
  }

  Future<StudyTimer> create({
    required String id,
    required String toolCallId,
    required String conversationId,
    required String title,
    int? minutes,
    StudyTimerKind kind = StudyTimerKind.timer,
    DateTime? alertAt,
    bool startImmediately = false,
  }) async {
    final now = _now();
    final isAlarm = kind == StudyTimerKind.alarm;
    if (isAlarm && (alertAt == null || !alertAt.isAfter(now))) {
      throw ArgumentError('闹钟时间必须晚于当前时间');
    }
    if (!isAlarm && (minutes == null || minutes < 1 || minutes > 480)) {
      throw ArgumentError('计时时长必须为 1-480 分钟');
    }
    final seconds = isAlarm
        ? alertAt!.difference(now).inSeconds.clamp(1, 366 * 24 * 60 * 60)
        : minutes! * 60;
    final timer = StudyTimer(
      id: id,
      toolCallId: toolCallId,
      conversationId: conversationId,
      title: title,
      kind: kind,
      totalSeconds: seconds,
      remainingSeconds: seconds,
      status: isAlarm || startImmediately
          ? StudyTimerStatus.running
          : StudyTimerStatus.ready,
      startedAt: isAlarm || startImmediately ? now : null,
      alertAt: alertAt,
      createdAt: now,
      updatedAt: now,
    );
    await _save(timer);
    if (timer.status == StudyTimerStatus.running) {
      await _scheduleReminder(timer);
      _ensureTicker();
    }
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
    final started = timer.copyWith(
      status: StudyTimerStatus.running,
      startedAt: now,
      updatedAt: now,
    );
    await _save(started);
    await _scheduleReminder(started);
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
    await reminders.cancel(id);
    await _stopForegroundReminder(id);
    _ensureTicker();
  }

  Future<void> finish(String id) async {
    final timer = controller.byId(id);
    if (timer?.status == StudyTimerStatus.completed) {
      await _stopForegroundReminder(id);
      await reminders.cancel(id);
      return;
    }
    await _complete(id);
  }

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
    await reminders.cancel(id);
    await _stopForegroundReminder(id);
    _ensureTicker();
  }

  Future<void> delete(String id) async {
    final timer = controller.byId(id);
    if (timer == null) return;
    await reminders.cancel(id);
    await _stopForegroundReminder(id);
    await database.delete(id);
    controller.remove(id);
    _ensureTicker();
  }

  Future<void> handleLifecycle(bool foreground) async {
    _foreground = foreground;
    if (!foreground) {
      _ticker?.cancel();
      _ticker = null;
      final activeTimer = activeReminder.value;
      if (activeTimer != null) {
        await reminders.showNow(activeTimer);
        await foregroundReminders.stop();
      }
      return;
    }
    await _reconcile();
    _ensureTicker();
  }

  Future<void> _reconcile() async {
    final now = _now();
    for (final timer in controller.timers) {
      if (timer.status == StudyTimerStatus.running &&
          timer.remainingAt(now) == 0) {
        await _complete(timer.id);
      }
    }
  }

  Future<void> _complete(String id) async {
    final timer = controller.byId(id);
    if (timer == null) return;
    if (timer.status == StudyTimerStatus.completed) {
      if (_foreground) await foregroundReminders.start(timer);
      return;
    }
    final remainingAtCompletion = timer.remainingAt(_now());
    final completed = timer.copyWith(
      remainingSeconds: remainingAtCompletion,
      status: StudyTimerStatus.completed,
      clearStartedAt: true,
      updatedAt: _now(),
    );
    await _save(completed);
    await reminders.cancel(id);
    if (_foreground) await foregroundReminders.start(completed);
    _ensureTicker();
  }

  Future<void> _stopForegroundReminder(String id) async {
    if (activeReminder.value?.id == id) await foregroundReminders.stop();
  }

  Future<void> _save(StudyTimer timer) async {
    await database.upsert(timer);
    controller.put(timer);
  }

  Future<void> _scheduleReminder(StudyTimer timer) async {
    await reminders.schedule(timer);
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
      await _reconcile();
      controller.tick();
    });
  }

  Future<void> clearAll() async {
    _ticker?.cancel();
    _ticker = null;
    controller.clear();
    await foregroundReminders.stop();
    await reminders.cancelAll();
    await database.clearAll();
  }

  Future<void> dispose() async {
    _ticker?.cancel();
    await foregroundReminders.dispose();
  }
}
