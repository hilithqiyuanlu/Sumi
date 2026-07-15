import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite 实现 —— 单表单行存全量 JSON 快照 + 对话表。
class SumiLocalDatabase {
  static const _dbName = 'sumi_v1.db';
  static const _rowId = 'main';

  Database? _db;

  SumiLocalDatabase({Database? database}) : _db = database;

  /// 暴露 Database 实例供 ChatDatabase 等复用。
  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbName);
    _db = await openDatabase(
      dbPath,
      version: 14,
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
        await _createEmbeddingDocumentsTable(db);
        await _createMemoryTables(db);
        await _createMemoryExtractionTables(db);
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
        if (oldVersion < 5) {
          await _migrateV4toV5(db);
        }
        if (oldVersion < 6) {
          await _migrateV5toV6(db);
        }
        if (oldVersion < 7) {
          await _migrateV6toV7(db);
        }
        if (oldVersion < 8) {
          await _migrateV7toV8(db);
        }
        if (oldVersion < 9) {
          await _migrateV8toV9(db);
        }
        if (oldVersion < 10) {
          await _migrateV9toV10(db);
        }
        if (oldVersion < 11) {
          await _migrateV10toV11(db);
        }
        if (oldVersion < 13) {
          await _migrateV12toV13(db);
        }
        if (oldVersion < 14) {
          await _migrateV13toV14(db);
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
        date_key TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        pinned INTEGER NOT NULL DEFAULT 0
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
    // 07 轮：信号表
    await _createSignalsTable(db);
  }

  /// 创建 signals 表（07 轮新增）。
  Future<void> _createSignalsTable(Database db) async {
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
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_signals_type ON signals(signal)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_signals_time ON signals(time)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_signals_project ON signals(project_id)
    ''');
  }

  /// v2→v3: messages 表新增 reasoning_content 和 tool_calls_json 列。
  Future<void> _migrateV2toV3(Database db) async {
    await db.execute("ALTER TABLE messages ADD COLUMN reasoning_content TEXT");
    await db.execute("ALTER TABLE messages ADD COLUMN tool_calls_json TEXT");
  }

  /// v3→v4: messages 表新增 tool_call_id 列（tool role 消息用）。
  Future<void> _migrateV3toV4(Database db) async {
    await db.execute("ALTER TABLE messages ADD COLUMN tool_call_id TEXT");
  }

  /// v4→v5: conversations 表新增 pinned 列。
  Future<void> _migrateV4toV5(Database db) async {
    await db.execute(
      "ALTER TABLE conversations ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0",
    );
  }

  /// v6→v7: 新增 signals 表（07 轮）。
  Future<void> _migrateV6toV7(Database db) async {
    await _createSignalsTable(db);
  }

  /// v7→v8: 保留为空，历史版本的迁移位置已被本地检索占用。
  Future<void> _migrateV7toV8(Database db) async {}

  Future<void> _createUserUnderstandingTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_hypotheses (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        scope TEXT NOT NULL DEFAULT 'global',
        claim_json TEXT NOT NULL,
        confidence REAL NOT NULL,
        support_count INTEGER NOT NULL DEFAULT 0,
        contradict_count INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        source TEXT NOT NULL,
        last_verified_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recommendation_events (
        id TEXT PRIMARY KEY,
        text TEXT NOT NULL,
        topic TEXT NOT NULL,
        hypothesis_id TEXT,
        shown_at TEXT NOT NULL,
        selected_at TEXT,
        feedback_at TEXT,
        feedback_type TEXT,
        context_json TEXT NOT NULL DEFAULT '{}'
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_hypotheses_status ON user_hypotheses(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_hypotheses_kind ON user_hypotheses(kind)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_recommendations_shown ON recommendation_events(shown_at)',
    );
  }

  /// v8→v9: 本地语义检索向量文档。
  Future<void> _migrateV8toV9(Database db) async {
    await _createEmbeddingDocumentsTable(db);
  }

  /// v9→v10: 可校正用户理解的假设与建议事件。
  Future<void> _migrateV9toV10(Database db) async {
    await _createUserUnderstandingTables(db);
  }

  /// v10→v11: vectors produced by different embedding models cannot mix.
  Future<void> _migrateV10toV11(Database db) async {
    await db.execute(
      "ALTER TABLE embedding_documents ADD COLUMN embedding_version TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_embedding_documents_version ON embedding_documents(embedding_version)',
    );
  }

  Future<void> _migrateV12toV13(Database db) async {
    await _createMemoryTables(db);
    final columns = await db.rawQuery(
      'PRAGMA table_info(recommendation_events)',
    );
    if (columns.isNotEmpty &&
        !columns.any((row) => row['name'] == 'memory_id')) {
      await db.execute(
        'ALTER TABLE recommendation_events ADD COLUMN memory_id TEXT',
      );
    }
    await db.execute('DROP TABLE IF EXISTS schedule_recommendation_events');
  }

  Future<void> _migrateV13toV14(Database db) =>
      _createMemoryExtractionTables(db);

  Future<void> _createMemoryTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS memory_items (
      id TEXT PRIMARY KEY, type TEXT NOT NULL, category TEXT NOT NULL,
      content TEXT NOT NULL, project_id TEXT, status TEXT NOT NULL,
      confidence REAL NOT NULL, source TEXT NOT NULL, replaces_id TEXT,
      created_at TEXT NOT NULL, last_confirmed_at TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS memory_evidence (
      id TEXT PRIMARY KEY, memory_id TEXT NOT NULL, kind TEXT NOT NULL,
      reference_id TEXT, summary TEXT NOT NULL, occurred_at TEXT NOT NULL,
      created_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS memory_migration_state (
      key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_items_status ON memory_items(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_items_type ON memory_items(type)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_items_project ON memory_items(project_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_evidence_memory ON memory_evidence(memory_id)',
    );
  }

  Future<void> _createMemoryExtractionTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS memory_extraction_runs (
      message_id TEXT PRIMARY KEY, status TEXT NOT NULL,
      decision_json TEXT, processed_at TEXT NOT NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_extraction_runs_processed ON memory_extraction_runs(processed_at)',
    );
  }

  Future<void> _createEmbeddingDocumentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS embedding_documents (
        source_type TEXT NOT NULL,
        source_id TEXT NOT NULL,
        project_id TEXT,
        updated_at TEXT NOT NULL,
        confidence REAL NOT NULL,
        text_summary TEXT NOT NULL,
        embedding BLOB NOT NULL,
        embedding_version TEXT NOT NULL,
        PRIMARY KEY (source_type, source_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_embedding_documents_project
      ON embedding_documents(project_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_embedding_documents_updated
      ON embedding_documents(updated_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_embedding_documents_version
      ON embedding_documents(embedding_version)
    ''');
  }

  /// v5→v6: conversations 表新增 date_key 列，并回填已有数据。
  Future<void> _migrateV5toV6(Database db) async {
    await db.execute("ALTER TABLE conversations ADD COLUMN date_key TEXT");
    // 回填已有会话的 date_key 为 created_at 的日期部分
    await db.rawUpdate(
      "UPDATE conversations SET date_key = substr(created_at, 1, 10) WHERE date_key IS NULL",
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
    await db.insert('app_snapshot', {
      'id': _rowId,
      'body': body,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }
}

/// 工厂 —— 后续可做 web/io 条件导出。
SumiLocalDatabase createSnapshotStore() => SumiLocalDatabase();
