import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sumi/data/local_database.dart';
import 'package:sumi/data/study_timer_database.dart';
import 'package:sumi/models/models.dart';
import 'package:sumi/services/study_timer_service.dart';
import 'package:sumi/services/timer_controller.dart';

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
    final service = StudyTimerService(
      database: StudyTimerDatabase(store),
      controller: controller,
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
    now = now.add(const Duration(minutes: 8));
    await service.pause(created.id);
    expect(controller.byId(created.id)?.status, StudyTimerStatus.paused);
    expect(controller.byId(created.id)?.remainingSeconds, 22 * 60);

    final restored = TimerController();
    final afterRestart = StudyTimerService(
      database: StudyTimerDatabase(store),
      controller: restored,
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
    final service = StudyTimerService(
      database: StudyTimerDatabase(SumiLocalDatabase(database: database)),
      controller: TimerController(),
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
    await service.handleLifecycle(true);
    expect(
      service.controller.byId(timer.id)?.status,
      StudyTimerStatus.completed,
    );
  });
}

Future<void> _createStudyTimersTable(Database db) => db.execute('''
  CREATE TABLE study_timers (
    id TEXT PRIMARY KEY, tool_call_id TEXT NOT NULL,
    conversation_id TEXT NOT NULL, title TEXT NOT NULL,
    total_seconds INTEGER NOT NULL, remaining_seconds INTEGER NOT NULL,
    status TEXT NOT NULL, started_at TEXT,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  )
''');
