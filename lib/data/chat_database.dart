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

  /// 按日期查找会话，不存在则返回 null。
  Future<Conversation?> findConversationByDate(String dateKey) async {
    final db = await _db;
    final rows = await db.query(
      'conversations',
      where: 'date_key = ?',
      whereArgs: [dateKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return Conversation(
      id: r['id'] as String,
      dateKey: (r['date_key'] as String?) ?? '',
      title: (r['title'] as String?) ?? '',
      pinned: (r['pinned'] as int?) == 1,
      createdAt: DateTime.tryParse((r['created_at'] as String?) ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse((r['updated_at'] as String?) ?? '') ?? DateTime.now(),
    );
  }

  /// 为指定日期创建新会话。
  Future<Conversation> createConversationForDate(String dateKey) async {
    final db = await _db;
    final now = DateTime.now();
    final id = 'conv-${now.microsecondsSinceEpoch}';
    await db.insert('conversations', {
      'id': id,
      'date_key': dateKey,
      'title': '',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'pinned': 0,
    });
    return Conversation(
      id: id,
      dateKey: dateKey,
      createdAt: now,
      updatedAt: now,
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
      toolCallId: r['tool_call_id'] as String?,
    )).toList();
  }

  /// Loads persisted messages for rebuilding the local semantic index.
  Future<List<ChatMessage>> loadAllMessages() async {
    final db = await _db;
    final rows = await db.query('messages', orderBy: 'created_at ASC');
    return rows.map((row) => ChatMessage(
      id: row['id'] as String,
      conversationId: (row['conversation_id'] as String?) ?? '',
      role: (row['role'] as String?) ?? 'user',
      content: (row['content'] as String?) ?? '',
      createdAt: DateTime.tryParse((row['created_at'] as String?) ?? '') ?? DateTime.now(),
      reasoningContent: row['reasoning_content'] as String?,
      toolCallsJson: row['tool_calls_json'] as String?,
      toolCallId: row['tool_call_id'] as String?,
    )).toList(growable: false);
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
      if (message.toolCallId != null)
        'tool_call_id': message.toolCallId,
    });
  }

  /// 批量删除消息。
  Future<void> deleteMessagesByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _db;
    final placeholders = ids.map((_) => '?').join(',');
    await db.delete(
      'messages',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
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

  /// 删除指定会话中，在指定 assistant 消息之后（含同时）产生的 tool 消息。
  /// 用于重新生成时只清理最后一轮 tool 结果，保留历史 tool 结果。
  Future<void> popToolMessagesAfter(
    String conversationId,
    String assistantMessageId,
  ) async {
    final db = await _db;
    final assistantRows = await db.query(
      'messages',
      columns: ['created_at'],
      where: 'id = ? AND role = ?',
      whereArgs: [assistantMessageId, 'assistant'],
    );
    if (assistantRows.isEmpty) return;
    final createdAt = assistantRows.first['created_at'] as String;
    await db.delete(
      'messages',
      where:
          'conversation_id = ? AND role = ? AND created_at >= ?',
      whereArgs: [conversationId, 'tool', createdAt],
    );
  }

  /// 删除全部对话和消息。
  Future<void> clearAll() async {
    final db = await _db;
    await db.delete('messages');
    await db.delete('conversations');
  }

}
