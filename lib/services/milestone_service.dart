import 'package:sqflite/sqflite.dart';

import '../data/local_database.dart';
import '../models/models.dart';
import '../utils/utils.dart';

class PendingMilestoneStatement {
  final String messageId;
  final String todoId;
  final String quote;
  final DateTime occurredAt;

  const PendingMilestoneStatement({
    required this.messageId,
    required this.todoId,
    required this.quote,
    required this.occurredAt,
  });
}

/// Single writer for milestone evidence and the matching queue.
class MilestoneService {
  final SumiLocalDatabase _store;
  final DateTime Function() _now;

  MilestoneService(this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  Future<Database> get _db => _store.database;

  Future<void> ensureTables() async {
    final db = await _db;
    await db.execute('''CREATE TABLE IF NOT EXISTS milestones (
      id TEXT PRIMARY KEY, project_id TEXT NOT NULL, todo_id TEXT NOT NULL,
      source_message_id TEXT NOT NULL, quote TEXT NOT NULL, todo_title TEXT NOT NULL,
      month_index INTEGER NOT NULL, occurred_at TEXT NOT NULL, memory_id TEXT,
      created_at TEXT NOT NULL,
      UNIQUE(source_message_id, todo_id))''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS pending_milestone_statements (
      message_id TEXT NOT NULL, todo_id TEXT NOT NULL, quote TEXT NOT NULL, occurred_at TEXT NOT NULL,
      created_at TEXT NOT NULL, UNIQUE(message_id, todo_id))''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_milestones_project_month ON milestones(project_id, month_index, occurred_at)',
    );
  }

  Future<List<Milestone>> forProjectMonth(
    String projectId,
    int monthIndex,
  ) async {
    await ensureTables();
    final rows = await (await _db).query(
      'milestones',
      where: 'project_id = ? AND month_index = ?',
      whereArgs: [projectId, monthIndex],
      orderBy: 'occurred_at DESC',
    );
    return rows.map(_milestone).toList(growable: false);
  }

  Future<List<Milestone>> forSourceMessage(String messageId) async {
    await ensureTables();
    final rows = await (await _db).query(
      'milestones',
      where: 'source_message_id = ?',
      whereArgs: [messageId],
    );
    return rows.map(_milestone).toList(growable: false);
  }

  Future<Set<String>> sourceMessageIdsFor(Iterable<String> messageIds) async {
    final ids = messageIds.toSet().toList(growable: false);
    if (ids.isEmpty) return <String>{};
    await ensureTables();
    final placeholders = List<String>.filled(ids.length, '?').join(', ');
    final rows = await (await _db).query(
      'milestones',
      columns: const ['source_message_id'],
      where: 'source_message_id IN ($placeholders)',
      whereArgs: ids,
    );
    return rows.map((row) => row['source_message_id'] as String).toSet();
  }

  Future<void> savePending({
    required String messageId,
    required String todoId,
    required String quote,
    required DateTime occurredAt,
  }) async {
    await ensureTables();
    await (await _db).insert('pending_milestone_statements', {
      'message_id': messageId,
      'todo_id': todoId,
      'quote': quote,
      'occurred_at': occurredAt.toIso8601String(),
      'created_at': _now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<PendingMilestoneStatement>> pendingStatements() async {
    await ensureTables();
    final rows = await (await _db).query(
      'pending_milestone_statements',
      orderBy: 'occurred_at ASC',
    );
    return rows
        .map(
          (row) => PendingMilestoneStatement(
            messageId: row['message_id'] as String,
            todoId: row['todo_id'] as String,
            quote: row['quote'] as String,
            occurredAt:
                DateTime.tryParse(row['occurred_at'] as String? ?? '') ??
                _now(),
          ),
        )
        .toList(growable: false);
  }

  Future<Milestone?> create({
    required TodoItem todo,
    required String sourceMessageId,
    required String quote,
    required DateTime occurredAt,
    required int monthIndex,
  }) async {
    if (!todo.done || todo.projectId == null || quote.trim().isEmpty) {
      return null;
    }
    await ensureTables();
    final id = newSumiId('milestone');
    try {
      await (await _db).insert('milestones', {
        'id': id,
        'project_id': todo.projectId,
        'todo_id': todo.id,
        'source_message_id': sourceMessageId,
        'quote': quote.trim(),
        'todo_title': todo.title,
        'month_index': monthIndex,
        'occurred_at': occurredAt.toIso8601String(),
        'created_at': _now().toIso8601String(),
      });
      await (await _db).delete(
        'pending_milestone_statements',
        where: 'message_id = ? AND todo_id = ?',
        whereArgs: [sourceMessageId, todo.id],
      );
      return Milestone(
        id: id,
        projectId: todo.projectId!,
        todoId: todo.id,
        sourceMessageId: sourceMessageId,
        quote: quote.trim(),
        todoTitle: todo.title,
        monthIndex: monthIndex,
        occurredAt: occurredAt,
      );
    } on DatabaseException {
      return null;
    }
  }

  Future<void> attachMemory(String milestoneId, String memoryId) async {
    await ensureTables();
    await (await _db).update(
      'milestones',
      {'memory_id': memoryId},
      where: 'id = ?',
      whereArgs: [milestoneId],
    );
  }

  Future<List<Milestone>> deleteByMemoryId(String memoryId) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query(
      'milestones',
      where: 'memory_id = ?',
      whereArgs: [memoryId],
    );
    await db.delete(
      'milestones',
      where: 'memory_id = ?',
      whereArgs: [memoryId],
    );
    return rows.map(_milestone).toList(growable: false);
  }

  Future<List<Milestone>> deleteForTodo(String todoId) async {
    await ensureTables();
    await (await _db).delete(
      'pending_milestone_statements',
      where: 'todo_id = ?',
      whereArgs: [todoId],
    );
    return _deleteWhere('todo_id = ?', [todoId]);
  }

  Future<List<Milestone>> deleteForProject(String projectId) =>
      _deleteWhere('project_id = ?', [projectId]);

  Future<List<Milestone>> _deleteWhere(
    String where,
    List<Object?> whereArgs,
  ) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query(
      'milestones',
      where: where,
      whereArgs: whereArgs,
    );
    final items = rows.map(_milestone).toList(growable: false);
    await db.delete('milestones', where: where, whereArgs: whereArgs);
    return items;
  }

  Future<void> clearAll() async {
    await ensureTables();
    final db = await _db;
    await db.delete('milestones');
    await db.delete('pending_milestone_statements');
  }

  Milestone _milestone(Map<String, Object?> row) => Milestone(
    id: row['id'] as String,
    projectId: row['project_id'] as String,
    todoId: row['todo_id'] as String,
    sourceMessageId: row['source_message_id'] as String,
    quote: row['quote'] as String,
    todoTitle: row['todo_title'] as String,
    monthIndex: (row['month_index'] as num).toInt(),
    occurredAt:
        DateTime.tryParse(row['occurred_at'] as String? ?? '') ?? _now(),
    memoryId: row['memory_id'] as String?,
  );
}
