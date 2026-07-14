import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'local_database.dart';

/// 对话数据持久化 —— 管理 conversations 和 messages 表。
class ChatDatabase {
  final SumiLocalDatabase _store;

  ChatDatabase(this._store);

  Future<Database> get _db => _store.database;

  // ---------------------------------------------------------------------------
  // Conversations
  // ---------------------------------------------------------------------------

  /// 加载全部会话（按更新时间降序）。
  Future<List<Conversation>> loadConversations() async {
    final db = await _db;
    final rows = await db.query(
      'conversations',
      orderBy: 'updated_at DESC',
    );
    return rows.map((r) => Conversation(
      id: r['id'] as String,
      title: (r['title'] as String?) ?? '',
      createdAt: DateTime.tryParse((r['created_at'] as String?) ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse((r['updated_at'] as String?) ?? '') ?? DateTime.now(),
    )).toList();
  }

  /// 创建新会话，返回创建的 Conversation。
  Future<Conversation> createConversation({String title = ''}) async {
    final db = await _db;
    final now = DateTime.now();
    final id = 'conv-${now.microsecondsSinceEpoch}';
    await db.insert('conversations', {
      'id': id,
      'title': title,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    return Conversation(
      id: id,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 更新会话标题。
  Future<void> updateConversationTitle(String id, String title) async {
    final db = await _db;
    await db.update(
      'conversations',
      {'title': title, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 刷新会话 updatedAt。
  Future<void> touchConversation(String id) async {
    final db = await _db;
    await db.update(
      'conversations',
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 删除会话（级联删除消息由 DB FOREIGN KEY 或手动处理）。
  Future<void> deleteConversation(String id) async {
    final db = await _db;
    // 先删消息（部分 SQLite 配置可能不启用外键级联）
    await db.delete('messages', where: 'conversation_id = ?', whereArgs: [id]);
    await db.delete('conversations', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  /// 加载指定会话的全部消息（按时间升序）。
  Future<List<ChatMessage>> loadMessages(String conversationId) async {
    final db = await _db;
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );
    return rows.map((r) => ChatMessage(
      id: r['id'] as String,
      conversationId: (r['conversation_id'] as String?) ?? '',
      role: (r['role'] as String?) ?? 'user',
      content: (r['content'] as String?) ?? '',
      createdAt: DateTime.tryParse((r['created_at'] as String?) ?? '') ?? DateTime.now(),
      reasoningContent: r['reasoning_content'] as String?,
      toolCallsJson: r['tool_calls_json'] as String?,
    )).toList();
  }

  /// 保存单条消息。
  Future<void> saveMessage(ChatMessage message) async {
    final db = await _db;
    await db.insert('messages', {
      'id': message.id,
      'conversation_id': message.conversationId,
      'role': message.role,
      'content': message.content,
      'created_at': message.createdAt.toIso8601String(),
      if (message.reasoningContent != null)
        'reasoning_content': message.reasoningContent,
      if (message.toolCallsJson != null)
        'tool_calls_json': message.toolCallsJson,
    });
  }

  /// 更新消息内容 + 可选 reasoning / tool_calls（用于流式输出完成后写入）。
  Future<void> updateMessageContent(String id, String content,
      {String? reasoningContent, String? toolCallsJson}) async {
    final db = await _db;
    final values = <String, Object?>{
      'content': content,
    };
    if (reasoningContent != null) {
      values['reasoning_content'] = reasoningContent;
    }
    if (toolCallsJson != null) {
      values['tool_calls_json'] = toolCallsJson;
    }
    await db.update(
      'messages',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 删除最后一条助手消息（用于重新生成）。
  Future<String?> popLastAssistantMessage(String conversationId) async {
    final db = await _db;
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ? AND role = ?',
      whereArgs: [conversationId, 'assistant'],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final lastId = rows.first['id'] as String;
    await db.delete('messages', where: 'id = ?', whereArgs: [lastId]);
    return lastId;
  }

  /// 删除全部对话和消息。
  Future<void> clearAll() async {
    final db = await _db;
    await db.delete('messages');
    await db.delete('conversations');
  }

  /// 获取会话消息数量。
  Future<int> messageCount(String conversationId) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM messages WHERE conversation_id = ?',
      [conversationId],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }
}
