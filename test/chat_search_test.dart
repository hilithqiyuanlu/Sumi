import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sumi/data/chat_database.dart';
import 'package:sumi/data/local_database.dart';
import 'package:sumi/models/models.dart';

Future<Database> _openDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE conversations (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL DEFAULT '',
      date_key TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      pinned INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE messages (
      id TEXT PRIMARY KEY,
      conversation_id TEXT NOT NULL,
      role TEXT NOT NULL,
      content TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      reasoning_content TEXT,
      tool_calls_json TEXT,
      tool_call_id TEXT
    )
  ''');
  return db;
}

Future<void> _createConversation(
  Database db, {
  required String id,
  required String dateKey,
}) => db.insert('conversations', {
  'id': id,
  'title': '',
  'date_key': dateKey,
  'created_at': '${dateKey}T00:00:00.000',
  'updated_at': '${dateKey}T00:00:00.000',
  'pinned': 0,
});

ChatMessage _message({
  required String id,
  required String conversationId,
  required String role,
  required String content,
  required DateTime createdAt,
}) => ChatMessage(
  id: id,
  conversationId: conversationId,
  role: role,
  content: content,
  createdAt: createdAt,
);

void main() {
  setUpAll(sqfliteFfiInit);

  test('按月份搜索时只返回用户消息，并按日期倒序排列', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final chat = ChatDatabase(SumiLocalDatabase(database: db));
    await _createConversation(db, id: 'july-early', dateKey: '2026-07-04');
    await _createConversation(db, id: 'july-late', dateKey: '2026-07-17');
    await _createConversation(db, id: 'july-ai', dateKey: '2026-07-22');
    await _createConversation(db, id: 'june', dateKey: '2026-06-30');
    await chat.saveMessage(
      _message(
        id: 'early-user',
        conversationId: 'july-early',
        role: 'user',
        content: 'needle earlier',
        createdAt: DateTime(2026, 7, 4, 9),
      ),
    );
    await chat.saveMessage(
      _message(
        id: 'late-user',
        conversationId: 'july-late',
        role: 'user',
        content: 'Needle latest',
        createdAt: DateTime(2026, 7, 17, 10),
      ),
    );
    await chat.saveMessage(
      _message(
        id: 'ai-message',
        conversationId: 'july-ai',
        role: 'assistant',
        content: 'needle from AI',
        createdAt: DateTime(2026, 7, 22, 11),
      ),
    );
    await chat.saveMessage(
      _message(
        id: 'june-user',
        conversationId: 'june',
        role: 'user',
        content: 'needle from June',
        createdAt: DateTime(2026, 6, 30, 12),
      ),
    );

    final results = await chat.searchMessages(
      month: DateTime(2026, 7),
      query: 'needle',
    );

    expect(results.map((result) => result.messageId), [
      'late-user',
      'early-user',
    ]);
    expect(results.every((result) => result.role == 'user'), isTrue);
  });

  test('搜索关键词将 SQL 通配符按字面含义匹配', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final chat = ChatDatabase(SumiLocalDatabase(database: db));
    await _createConversation(db, id: 'july', dateKey: '2026-07-12');
    await chat.saveMessage(
      _message(
        id: 'literal',
        conversationId: 'july',
        role: 'user',
        content: r'预算 100%_ready\path',
        createdAt: DateTime(2026, 7, 12, 9),
      ),
    );
    await chat.saveMessage(
      _message(
        id: 'wildcard-only',
        conversationId: 'july',
        role: 'user',
        content: '预算 100AAreadypath',
        createdAt: DateTime(2026, 7, 12, 10),
      ),
    );

    final results = await chat.searchMessages(
      month: DateTime(2026, 7),
      query: r'100%_ready\path',
    );

    expect(results.map((result) => result.messageId), ['literal']);
  });

  test('全历史搜索跨月返回用户消息，排除 AI 和工具消息', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final chat = ChatDatabase(SumiLocalDatabase(database: db));
    await _createConversation(db, id: 'july', dateKey: '2026-07-12');
    await _createConversation(db, id: 'june', dateKey: '2026-06-30');
    await chat.saveMessage(
      _message(
        id: 'july-user',
        conversationId: 'july',
        role: 'user',
        content: '复习线性代数',
        createdAt: DateTime(2026, 7, 12, 9),
      ),
    );
    await chat.saveMessage(
      _message(
        id: 'july-ai',
        conversationId: 'july',
        role: 'assistant',
        content: '复习线性代数的建议',
        createdAt: DateTime(2026, 7, 12, 9, 1),
      ),
    );
    await chat.saveMessage(
      _message(
        id: 'june-user',
        conversationId: 'june',
        role: 'user',
        content: '复习微积分',
        createdAt: DateTime(2026, 6, 30, 12),
      ),
    );

    final results = await chat.searchUserMessages(query: '复习');

    expect(results.map((result) => result.messageId), [
      'july-user',
      'june-user',
    ]);
    expect(results.every((result) => result.role == 'user'), isTrue);
  });

  test('按月加载包含用户、AI 和工具消息，且不混入相邻月份', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    final chat = ChatDatabase(SumiLocalDatabase(database: db));
    await _createConversation(db, id: 'july', dateKey: '2026-07-12');
    await _createConversation(db, id: 'june', dateKey: '2026-06-30');
    await chat.saveMessage(
      _message(
        id: 'user',
        conversationId: 'july',
        role: 'user',
        content: '用户问题',
        createdAt: DateTime(2026, 7, 12, 9),
      ),
    );
    await chat.saveMessage(
      _message(
        id: 'assistant',
        conversationId: 'july',
        role: 'assistant',
        content: 'AI 回复',
        createdAt: DateTime(2026, 7, 12, 9, 1),
      ),
    );
    await chat.saveMessage(
      _message(
        id: 'tool',
        conversationId: 'july',
        role: 'tool',
        content: '工具结果',
        createdAt: DateTime(2026, 7, 12, 9, 2),
      ),
    );
    await chat.saveMessage(
      _message(
        id: 'june-user',
        conversationId: 'june',
        role: 'user',
        content: '六月消息',
        createdAt: DateTime(2026, 6, 30, 12),
      ),
    );

    final messages = await chat.loadMessagesForMonth(DateTime(2026, 7));

    expect(messages.map((entry) => entry.message.id), [
      'user',
      'assistant',
      'tool',
    ]);
    expect(
      messages.every((entry) => entry.date == DateTime(2026, 7, 12)),
      isTrue,
    );
  });
}
