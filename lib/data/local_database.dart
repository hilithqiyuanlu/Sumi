import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite 实现 —— 单表单行存全量 JSON 快照 + 对话表。
class SumiLocalDatabase {
  static const _dbName = 'sumi_v1.db';
  static const _rowId = 'main';

  Database? _db;

  /// 暴露 Database 实例供 ChatDatabase 等复用。
  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbName);
    _db = await openDatabase(
      dbPath,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE app_snapshot (
            id TEXT PRIMARY KEY,
            body TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        // version 2 新表一并创建
        await _createChatTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createChatTables(db);
        }
        if (oldVersion < 3) {
          await _migrateV2toV3(db);
        }
        if (oldVersion < 4) {
          await _migrateV3toV4(db);
        }
      },
    );
    return _db!;
  }

  Future<void> _createChatTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        reasoning_content TEXT,
        tool_calls_json TEXT,
        tool_call_id TEXT,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_conv
      ON messages(conversation_id, created_at)
    ''');
  }

  /// v2→v3: messages 表新增 reasoning_content 和 tool_calls_json 列。
  Future<void> _migrateV2toV3(Database db) async {
    await db.execute(
      "ALTER TABLE messages ADD COLUMN reasoning_content TEXT",
    );
    await db.execute(
      "ALTER TABLE messages ADD COLUMN tool_calls_json TEXT",
    );
  }

  /// v3→v4: messages 表新增 tool_call_id 列（tool role 消息用）。
  Future<void> _migrateV3toV4(Database db) async {
    await db.execute(
      "ALTER TABLE messages ADD COLUMN tool_call_id TEXT",
    );
  }

  Future<Map<String, Object?>?> readSnapshot() async {
    final db = await database;
    final rows = await db.query(
      'app_snapshot',
      where: 'id = ?',
      whereArgs: [_rowId],
    );
    if (rows.isEmpty) return null;
    final body = rows.first['body'] as String;
    return jsonDecode(body) as Map<String, Object?>;
  }

  Future<void> writeSnapshot(Map<String, Object?> snapshot) async {
    final db = await database;
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

  Future<String> exportSnapshotText() async {
    final snapshot = await readSnapshot();
    if (snapshot == null) return '{}';
    return jsonEncode(snapshot);
  }

  Future<void> importSnapshotText(String text) async {
    final snapshot = jsonDecode(text) as Map<String, Object?>;
    await writeSnapshot(snapshot);
  }
}

/// 工厂 —— 后续可做 web/io 条件导出。
SumiLocalDatabase createSnapshotStore() => SumiLocalDatabase();
