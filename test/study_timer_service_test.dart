import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sumi/data/local_database.dart';
import 'package:sumi/data/study_timer_database.dart';
import 'package:sumi/models/models.dart';
import 'package:sumi/services/study_timer_service.dart';
import 'package:sumi/services/foreground_reminder_service.dart';
import 'package:sumi/services/system_reminder_service.dart';
import 'package:sumi/services/timer_controller.dart';

class _FakeReminderScheduler implements ReminderScheduler {
  final List<StudyTimer> scheduled = [];
  final List<String> cancelled = [];
  final List<StudyTimer> shown = [];

  @override
  Future<void> cancel(String timerId) async => cancelled.add(timerId);

  @override
  Future<void> cancelAll() async {}

  @override
  Future<ReminderScheduleQuality> schedule(StudyTimer timer) async {
    scheduled.add(timer);
    return ReminderScheduleQuality.exact;
  }

  @override
  Future<void> showNow(StudyTimer timer) async => shown.add(timer);
}

class _FakeForegroundReminder implements ForegroundReminder {
  final ValueNotifier<StudyTimer?> _activeReminder = ValueNotifier(null);
  final List<StudyTimer> started = [];
  var stopped = 0;

  @override
  ValueListenable<StudyTimer?> get activeReminder => _activeReminder;

  @override
  Future<void> start(StudyTimer timer) async {
    started.add(timer);
    _activeReminder.value = timer;
  }

  @override
  Future<void> stop() async {
    stopped++;
    _activeReminder.value = null;
  }

  @override
  Future<void> dispose() async => _activeReminder.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('计时器可开始、暂停并在重启后保留剩余时间', () async {
    var now = DateTime(2026, 7, 16, 9, 0);
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await _createStudyTimersTable(database);
    final store = SumiLocalDatabase(database: database);
    final controller = TimerController();
    final reminders = _FakeReminderScheduler();
    final service = StudyTimerService(
      database: StudyTimerDatabase(store),
      controller: controller,
      reminders: reminders,
      foregroundReminders: _FakeForegroundReminder(),
      now: () => now,
    );
    addTearDown(service.dispose);

    final created = await service.create(
      id: 'timer-1',
      toolCallId: 'call-1',
      conversationId: 'conv-1',
      title: '阅读英语',
      minutes: 30,
    );
    expect(created.status, StudyTimerStatus.ready);

    await service.start(created.id);
    expect(reminders.scheduled.single.id, created.id);
    now = now.add(const Duration(minutes: 8));
    await service.pause(created.id);
    expect(controller.byId(created.id)?.status, StudyTimerStatus.paused);
    expect(controller.byId(created.id)?.remainingSeconds, 22 * 60);

    final restored = TimerController();
    final afterRestart = StudyTimerService(
      database: StudyTimerDatabase(store),
      controller: restored,
      foregroundReminders: _FakeForegroundReminder(),
      now: () => now,
    );
    addTearDown(afterRestart.dispose);
    await afterRestart.restore();
    expect(restored.byToolCallId('call-1')?.remainingSeconds, 22 * 60);
  });

  test('前台恢复时已经到点的计时器会完成', () async {
    var now = DateTime(2026, 7, 16, 9, 0);
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await _createStudyTimersTable(database);
    final foregroundReminders = _FakeForegroundReminder();
    final service = StudyTimerService(
      database: StudyTimerDatabase(SumiLocalDatabase(database: database)),
      controller: TimerController(),
      reminders: _FakeReminderScheduler(),
      foregroundReminders: foregroundReminders,
      now: () => now,
    );
    addTearDown(service.dispose);
    final timer = await service.create(
      id: 'timer-2',
      toolCallId: 'call-2',
      conversationId: 'conv-1',
      title: '复习单词',
      minutes: 1,
    );
    await service.start(timer.id);
    await service.handleLifecycle(false);
    now = now.add(const Duration(minutes: 2));
    expect(foregroundReminders.started, isEmpty);
    await service.handleLifecycle(true);
    expect(
      service.controller.byId(timer.id)?.status,
      StudyTimerStatus.completed,
    );
    expect(foregroundReminders.started.single.id, timer.id);
    await service.finish(timer.id);
    expect(foregroundReminders.stopped, 1);
  });

  test('明确要求立即开始会直接启动并安排系统提醒', () async {
    var now = DateTime(2026, 7, 16, 9, 0);
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await _createStudyTimersTable(database);
    final reminders = _FakeReminderScheduler();
    final service = StudyTimerService(
      database: StudyTimerDatabase(SumiLocalDatabase(database: database)),
      controller: TimerController(),
      reminders: reminders,
      foregroundReminders: _FakeForegroundReminder(),
      now: () => now,
    );
    addTearDown(service.dispose);

    final timer = await service.create(
      id: 'timer-now',
      toolCallId: 'call-now',
      conversationId: 'conv-1',
      title: '阅读教材',
      minutes: 30,
      startImmediately: true,
    );

    expect(timer.status, StudyTimerStatus.running);
    expect(timer.triggerAt, now.add(const Duration(minutes: 30)));
    expect(reminders.scheduled.single.id, timer.id);
  });

  test('闹钟会在指定时间自动等待系统提醒', () async {
    final now = DateTime(2026, 7, 16, 9, 0);
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await _createStudyTimersTable(database);
    final reminders = _FakeReminderScheduler();
    final service = StudyTimerService(
      database: StudyTimerDatabase(SumiLocalDatabase(database: database)),
      controller: TimerController(),
      reminders: reminders,
      foregroundReminders: _FakeForegroundReminder(),
      now: () => now,
    );
    addTearDown(service.dispose);
    final alertAt = now.add(const Duration(hours: 2));

    final alarm = await service.create(
      id: 'alarm-1',
      toolCallId: 'call-alarm',
      conversationId: 'conv-1',
      title: '开始背单词',
      kind: StudyTimerKind.alarm,
      alertAt: alertAt,
    );

    expect(alarm.status, StudyTimerStatus.running);
    expect(alarm.triggerAt, alertAt);
    expect(reminders.scheduled.single.kind, StudyTimerKind.alarm);
    await service.cancel(alarm.id);
    expect(reminders.cancelled, contains(alarm.id));
  });

  test('删除计时器会停止提醒并移除本地记录', () async {
    var now = DateTime(2026, 7, 16, 9, 0);
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await _createStudyTimersTable(database);
    final foregroundReminders = _FakeForegroundReminder();
    final service = StudyTimerService(
      database: StudyTimerDatabase(SumiLocalDatabase(database: database)),
      controller: TimerController(),
      reminders: _FakeReminderScheduler(),
      foregroundReminders: foregroundReminders,
      now: () => now,
    );
    addTearDown(service.dispose);

    final timer = await service.create(
      id: 'timer-delete',
      toolCallId: 'call-delete',
      conversationId: 'conv-1',
      title: '整理笔记',
      minutes: 1,
      startImmediately: true,
    );
    now = now.add(const Duration(minutes: 2));
    await service.handleLifecycle(true);
    await service.delete(timer.id);

    expect(foregroundReminders.stopped, 1);
    expect(service.controller.byId(timer.id), isNull);
    expect(
      await StudyTimerDatabase(SumiLocalDatabase(database: database)).loadAll(),
      isEmpty,
    );
  });
}

Future<void> _createStudyTimersTable(Database db) => db.execute('''
  CREATE TABLE study_timers (
    id TEXT PRIMARY KEY, tool_call_id TEXT NOT NULL,
    conversation_id TEXT NOT NULL, title TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'timer',
    total_seconds INTEGER NOT NULL, remaining_seconds INTEGER NOT NULL,
    status TEXT NOT NULL, started_at TEXT,
    alert_at TEXT,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  )
''');
