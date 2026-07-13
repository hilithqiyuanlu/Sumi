import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'snapshot_store_base.dart';

/// SQLite 实现 —— 单表单行存全量 JSON 快照。
class SumiLocalDatabase implements SumiSnapshotStore {
  static const _dbName = 'sumi_v1.db';
  static const _rowId = 'main';

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbName);
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE app_snapshot (
            id TEXT PRIMARY KEY,
            body TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  @override
  Future<Map<String, Object?>?> readSnapshot() async {
    final db = await _database;
    final rows = await db.query(
      'app_snapshot',
      where: 'id = ?',
      whereArgs: [_rowId],
    );
    if (rows.isEmpty) return null;
    final body = rows.first['body'] as String;
    return jsonDecode(body) as Map<String, Object?>;
  }

  @override
  Future<void> writeSnapshot(Map<String, Object?> snapshot) async {
    final db = await _database;
    final body = jsonEncode(snapshot);
    await db.insert(
      'app_snapshot',
      {
        'id': _rowId,
        'body': body,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<String> exportSnapshotText() async {
    final snapshot = await readSnapshot();
    if (snapshot == null) return '{}';
    return jsonEncode(snapshot);
  }

  @override
  Future<void> importSnapshotText(String text) async {
    final snapshot = jsonDecode(text) as Map<String, Object?>;
    await writeSnapshot(snapshot);
  }
}

/// 工厂 —— 后续可做 web/io 条件导出。
SumiSnapshotStore createSnapshotStore() => SumiLocalDatabase();
