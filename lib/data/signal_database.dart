import 'dart:convert';

import '../models/models.dart';
import 'local_database.dart';

/// 信号数据持久化 —— 管理 signals 表（07 轮新增）。
class SignalDatabase {
  final SumiLocalDatabase _store;

  SignalDatabase(this._store);

  Future<dynamic> get _db => _store.database;

  /// 插入一条信号。
  Future<void> insert(UserSignal signal) async {
    final db = await _db;
    await db.insert('signals', {
      'signal': signal.signal.name,
      'time': signal.time.toIso8601String(),
      'context_json': signal.contextJson,
      'project_id': signal.projectId,
      'todo_id': signal.todoId,
      'domain': signal.domain,
      'created_at': signal.createdAt.toIso8601String(),
    });
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
    final rows = await db.query(
      'signals',
      where: where,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'time DESC',
      limit: limit ?? 20,
    );

    return rows.map(_fromRow).toList();
  }

  /// 统计信号数量。
  Future<int> count({SignalType? type, String? range}) async {
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
    final db = await _db;
    await db.delete('signals');
  }

  /// 获取用户活跃天数（有信号的日期数）。
  Future<int> activeDays({int days = 7}) async {
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
    final db = await _db;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final rows = await db.rawQuery(
      "SELECT CAST(substr(time, 12, 2) AS INTEGER) as hour, COUNT(*) as cnt FROM signals WHERE time >= ? GROUP BY hour ORDER BY cnt DESC LIMIT 4",
      [cutoff.toIso8601String()],
    );
    return rows.map((r) => {'hour': r['hour'] as int, 'count': r['cnt'] as int}).toList();
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
      createdAt: DateTime.tryParse((row['created_at'] as String?) ?? '') ?? DateTime.now(),
    );
  }

  /// 将信号列表格式化为 AI 可读文本。
  static String formatForPrompt(List<UserSignal> signals, {int maxItems = 50}) {
    if (signals.isEmpty) return '（暂无信号）';
    final buf = StringBuffer();
    final display = signals.length > maxItems ? signals.take(maxItems) : signals;
    for (final s in display) {
      final ctx = s.context;
      final time = s.time.toIso8601String().substring(0, 16);
      final title = ctx['title'] ?? '';
      final project = ctx['project'] ?? '';
      buf.write('- ${s.signal.name}');
      if (title is String && title.isNotEmpty) buf.write(' "$title"');
      if (project is String && project.isNotEmpty) buf.write(' [项目:$project]');
      buf.write(' ($time)');
      if (ctx['completedOnTime'] == true) buf.write(' ✓按时');
      if (ctx['changePercent'] != null) buf.write(' 变化:${ctx['changePercent']}%');
      buf.writeln();
    }
    if (signals.length > maxItems) {
      buf.writeln('... 还有 ${signals.length - maxItems} 条信号');
    }
    return buf.toString();
  }
}
