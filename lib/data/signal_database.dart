import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'local_database.dart';

/// 信号数据持久化 —— 管理 signals 表（07 轮新增）。
class SignalDatabase {
  final SumiLocalDatabase _store;
  bool _tableEnsured = false;

  SignalDatabase(this._store);

  Future<Database> get _db => _store.database;

  /// 确保 signals 表存在（自愈机制）。
  Future<void> _ensureTable() async {
    if (_tableEnsured) return;
    final db = await _db;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS signals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        signal TEXT NOT NULL,
        time TEXT NOT NULL,
        context_json TEXT NOT NULL DEFAULT '{}',
        project_id TEXT,
        todo_id TEXT,
        domain TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_signals_type ON signals(signal)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_signals_time ON signals(time)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_signals_project ON signals(project_id)',
    );
    _tableEnsured = true;
    debugPrint('[SignalDB] 自愈：已确保 signals 表存在');
  }

  /// 插入一条信号。
  Future<void> insert(UserSignal signal) async {
    await _ensureTable();
    final db = await _db;
    try {
      final rowId = await db.insert('signals', {
        'signal': signal.signal.name,
        'time': signal.time.toIso8601String(),
        'context_json': signal.contextJson,
        'project_id': signal.projectId,
        'todo_id': signal.todoId,
        'domain': signal.domain,
        'created_at': signal.createdAt.toIso8601String(),
      });
      debugPrint('[SignalDB] 写入成功 rowId=$rowId signal=${signal.signal.name}');
    } catch (e, stack) {
      debugPrint('[SignalDB] 写入失败: $e');
      debugPrint('[SignalDB] 堆栈: $stack');
    }
  }

  /// Keeps behavioural events while removing readable Todo content after the
  /// Todo has been deleted. This applies to the deletion event itself and to
  /// all earlier events for the same Todo.
  Future<void> redactDeletedTodoContent({String? todoId}) async {
    await _ensureTable();
    final db = await _db;
    final todoIds = todoId == null
        ? (await db.query(
            'signals',
            columns: const ['todo_id'],
            where: 'signal = ? AND todo_id IS NOT NULL',
            whereArgs: [SignalType.todoDeleted.name],
            distinct: true,
          )).map((row) => row['todo_id'] as String).toSet()
        : <String>{todoId};
    if (todoIds.isEmpty) return;

    for (final id in todoIds) {
      final rows = await db.query(
        'signals',
        columns: const ['id', 'context_json'],
        where: 'todo_id = ?',
        whereArgs: [id],
      );
      for (final row in rows) {
        final original = row['context_json'] as String? ?? '{}';
        Map<String, Object?> context;
        try {
          final decoded = jsonDecode(original);
          context = decoded is Map<String, Object?>
              ? Map<String, Object?>.of(decoded)
              : <String, Object?>{};
        } catch (_) {
          context = <String, Object?>{};
        }
        context.remove('title');
        context.remove('body');
        context.remove('oldTitle');
        context.remove('newTitle');
        context.remove('todoTitle');
        context.remove('condensedFrom');
        final redacted = jsonEncode(context);
        if (redacted == original) continue;
        await db.update(
          'signals',
          {'context_json': redacted},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }

  /// 查询信号。
  /// [type] 可指定类型筛选；[projectId] 按项目筛选；
  /// [range] "7d" / "30d" / "all"，默认 7d；
  /// [limit] 最多返回条数，默认 20。
  Future<List<UserSignal>> query({
    SignalType? type,
    String? projectId,
    String? range,
    int? limit,
  }) async {
    await _ensureTable();
    final db = await _db;
    final conditions = <String>[];
    final args = <Object?>[];

    if (type != null) {
      conditions.add('signal = ?');
      args.add(type.name);
    }
    if (projectId != null && projectId.isNotEmpty) {
      conditions.add('project_id = ?');
      args.add(projectId);
    }
    if (range != null && range != 'all') {
      final days = range == '30d' ? 30 : 7;
      final cutoff = DateTime.now().subtract(Duration(days: days));
      conditions.add('time >= ?');
      args.add(cutoff.toIso8601String());
    }

    final where = conditions.isNotEmpty ? conditions.join(' AND ') : null;
    final List<Map<String, Object?>> rows = await db.query(
      'signals',
      where: where,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'time DESC',
      limit: limit ?? 20,
    );

    return rows.map(_fromRow).toList();
  }

  /// 返回单个自然日的学习行为。使用半开区间，避免时区字符串比较的边界问题。
  Future<List<UserSignal>> queryDate(String date) async {
    await _ensureTable();
    final start = DateTime.parse(date);
    final end = start.add(const Duration(days: 1));
    final rows = await (await _db).query(
      'signals',
      where: 'time >= ? AND time < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'time ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<List<String>> pastSignalDates({
    required String beforeDate,
    int limit = 1000,
  }) async {
    await _ensureTable();
    final rows = await (await _db).rawQuery(
      '''SELECT DISTINCT substr(time, 1, 10) AS date_key
         FROM signals
         WHERE time < ?
         ORDER BY date_key ASC
         LIMIT ?''',
      ['${beforeDate}T00:00:00.000', limit],
    );
    return rows
        .map((row) => row['date_key'] as String?)
        .whereType<String>()
        .toList(growable: false);
  }

  /// 统计信号数量。
  Future<int> count({SignalType? type, String? range}) async {
    await _ensureTable();
    final db = await _db;
    final conditions = <String>[];
    final args = <Object?>[];

    if (type != null) {
      conditions.add('signal = ?');
      args.add(type.name);
    }
    if (range != null && range != 'all') {
      final days = range == '30d' ? 30 : 7;
      final cutoff = DateTime.now().subtract(Duration(days: days));
      conditions.add('time >= ?');
      args.add(cutoff.toIso8601String());
    }

    final where = conditions.isNotEmpty ? conditions.join(' AND ') : null;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM signals${where != null ? ' WHERE $where' : ''}',
      args.isNotEmpty ? args : null,
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// 清除全部信号。
  Future<void> clearAll() async {
    await _ensureTable();
    final db = await _db;
    await db.delete('signals');
  }

  /// 仅保留最近 [keepCount] 条信号，删除更早的记录。
  /// 在每日后台任务中调用，防止信号表无限增长。
  Future<void> pruneOldSignals({int keepCount = 200}) async {
    await _ensureTable();
    final db = await _db;
    final countResult =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM signals');
    final total = (countResult.first['cnt'] as int?) ?? 0;
    if (total <= keepCount) return;

    // 找到第 keepCount 条信号的时间戳，删除比它更早的记录
    final rows = await db.query(
      'signals',
      columns: ['time'],
      orderBy: 'time DESC',
      limit: 1,
      offset: keepCount - 1,
    );
    if (rows.isEmpty) return;
    final cutoff = rows.first['time'] as String;
    final deleted = await db.delete(
      'signals',
      where: 'time < ?',
      whereArgs: [cutoff],
    );
    debugPrint('[SignalDB] 清理了 $deleted 条旧信号（保留最近 $keepCount 条）');
  }

  /// 获取用户活跃天数（有信号的日期数）。
  Future<int> activeDays({int days = 7}) async {
    await _ensureTable();
    final db = await _db;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final result = await db.rawQuery(
      'SELECT COUNT(DISTINCT substr(time, 1, 10)) as cnt FROM signals WHERE time >= ?',
      [cutoff.toIso8601String()],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// 获取用户主要活跃时段（小时分布）。
  Future<List<Map<String, int>>> hourlyDistribution({int days = 30}) async {
    await _ensureTable();
    final db = await _db;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final List<Map<String, Object?>> rows = await db.rawQuery(
      "SELECT CAST(substr(time, 12, 2) AS INTEGER) as hour, COUNT(*) as cnt FROM signals WHERE time >= ? GROUP BY hour ORDER BY cnt DESC LIMIT 4",
      [cutoff.toIso8601String()],
    );
    return rows
        .map((r) => {'hour': r['hour'] as int, 'count': r['cnt'] as int})
        .toList();
  }

  UserSignal _fromRow(Map<String, Object?> row) {
    return UserSignal(
      id: row['id'] as int?,
      signal: SignalType.values.firstWhere(
        (s) => s.name == ((row['signal'] as String?) ?? ''),
        orElse: () => SignalType.todoCreated,
      ),
      time: DateTime.tryParse((row['time'] as String?) ?? '') ?? DateTime.now(),
      contextJson: (row['context_json'] as String?) ?? '{}',
      projectId: row['project_id'] as String?,
      todoId: row['todo_id'] as String?,
      domain: row['domain'] as String?,
      createdAt:
          DateTime.tryParse((row['created_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  /// Returns a defensive AI projection. The database migration removes content
  /// for every deleted Todo; this also protects a newly written deletion event
  /// before a cleanup task has finished.
  static Map<String, Object?> contextForAi(UserSignal signal) {
    final context = Map<String, Object?>.of(signal.context);
    if (signal.signal == SignalType.todoDeleted) {
      context.remove('title');
      context.remove('body');
      context.remove('oldTitle');
      context.remove('newTitle');
      context.remove('todoTitle');
      context.remove('condensedFrom');
    }
    return context;
  }

  /// 将信号列表格式化为 AI 可读文本。
  static String formatForPrompt(List<UserSignal> signals, {int maxItems = 50}) {
    if (signals.isEmpty) return '（暂无信号）';
    final buf = StringBuffer();
    final display = signals.length > maxItems
        ? signals.take(maxItems)
        : signals;
    for (final s in display) {
      final ctx = contextForAi(s);
      final time = s.time.toIso8601String().substring(0, 16);
      final title = ctx['title'] ?? '';
      final project = ctx['projectName'] ?? ctx['project'] ?? '';
      buf.write('- ${s.signal.name}');
      if (title is String && title.isNotEmpty) buf.write(' "$title"');
      if (project is String && project.isNotEmpty) buf.write(' [项目:$project]');
      buf.write(' ($time)');
      if (ctx['completedOnTime'] == true) buf.write(' ✓按时');
      if (ctx['changePercent'] != null) {
        buf.write(' 变化:${ctx['changePercent']}%');
      }
      buf.writeln();
    }
    if (signals.length > maxItems) {
      buf.writeln('... 还有 ${signals.length - maxItems} 条信号');
    }
    return buf.toString();
  }
}
