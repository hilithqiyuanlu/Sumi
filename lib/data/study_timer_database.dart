import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'local_database.dart';

class StudyTimerDatabase {
  final SumiLocalDatabase _store;

  StudyTimerDatabase(this._store);

  Future<Database> get _db => _store.database;

  Future<void> upsert(StudyTimer timer) async {
    final db = await _db;
    await db.insert(
      'study_timers',
      _toRow(timer),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<StudyTimer>> loadAll() async {
    final db = await _db;
    final rows = await db.query('study_timers', orderBy: 'updated_at DESC');
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> clearAll() async {
    final db = await _db;
    await db.delete('study_timers');
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete('study_timers', where: 'id = ?', whereArgs: [id]);
  }

  Map<String, Object?> _toRow(StudyTimer timer) => {
    'id': timer.id,
    'tool_call_id': timer.toolCallId,
    'conversation_id': timer.conversationId,
    'title': timer.title,
    'kind': timer.kind.name,
    'total_seconds': timer.totalSeconds,
    'remaining_seconds': timer.remainingSeconds,
    'status': timer.status.name,
    'started_at': timer.startedAt?.toIso8601String(),
    'alert_at': timer.alertAt?.toIso8601String(),
    'created_at': timer.createdAt.toIso8601String(),
    'updated_at': timer.updatedAt.toIso8601String(),
  };

  StudyTimer _fromRow(Map<String, Object?> row) => StudyTimer(
    id: row['id'] as String,
    toolCallId: row['tool_call_id'] as String,
    conversationId: row['conversation_id'] as String,
    title: row['title'] as String,
    kind: StudyTimerKind.values.firstWhere(
      (value) => value.name == row['kind'],
      orElse: () => StudyTimerKind.timer,
    ),
    totalSeconds: (row['total_seconds'] as num).toInt(),
    remainingSeconds: (row['remaining_seconds'] as num).toInt(),
    status: StudyTimerStatus.values.firstWhere(
      (value) => value.name == row['status'],
      orElse: () => StudyTimerStatus.cancelled,
    ),
    startedAt: DateTime.tryParse(row['started_at'] as String? ?? ''),
    alertAt: DateTime.tryParse(row['alert_at'] as String? ?? ''),
    createdAt:
        DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(row['updated_at'] as String? ?? '') ?? DateTime.now(),
  );
}
