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
      createdAt:
          DateTime.tryParse((r['created_at'] as String?) ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((r['updated_at'] as String?) ?? '') ??
          DateTime.now(),
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
    return rows
        .map(
          (r) => ChatMessage(
            id: r['id'] as String,
            conversationId: (r['conversation_id'] as String?) ?? '',
            role: (r['role'] as String?) ?? 'user',
            content: (r['content'] as String?) ?? '',
            createdAt:
                DateTime.tryParse((r['created_at'] as String?) ?? '') ??
                DateTime.now(),
            reasoningContent: r['reasoning_content'] as String?,
            toolCallsJson: r['tool_calls_json'] as String?,
            toolCallId: r['tool_call_id'] as String?,
          ),
        )
        .toList();
  }

  /// Loads persisted messages for rebuilding the local semantic index.
  Future<List<ChatMessage>> loadAllMessages() async {
    final db = await _db;
    final rows = await db.query('messages', orderBy: 'created_at ASC');
    return rows
        .map(
          (row) => ChatMessage(
            id: row['id'] as String,
            conversationId: (row['conversation_id'] as String?) ?? '',
            role: (row['role'] as String?) ?? 'user',
            content: (row['content'] as String?) ?? '',
            createdAt:
                DateTime.tryParse((row['created_at'] as String?) ?? '') ??
                DateTime.now(),
            reasoningContent: row['reasoning_content'] as String?,
            toolCallsJson: row['tool_calls_json'] as String?,
            toolCallId: row['tool_call_id'] as String?,
          ),
        )
        .toList(growable: false);
  }

  /// Loads every persisted message in one calendar month, grouped by the
  /// conversation's date at the caller level.
  Future<List<MonthChatMessage>> loadMessagesForMonth(DateTime month) async {
    final startOfMonth = DateTime(month.year, month.month);
    final startOfNextMonth = DateTime(month.year, month.month + 1);
    final db = await _db;
    final rows = await db.rawQuery(
      '''
        SELECT
          messages.id,
          messages.conversation_id,
          messages.role,
          messages.content,
          messages.created_at,
          messages.reasoning_content,
          messages.tool_calls_json,
          messages.tool_call_id,
          conversations.date_key
        FROM messages
        INNER JOIN conversations
          ON conversations.id = messages.conversation_id
        WHERE conversations.date_key >= ?
          AND conversations.date_key < ?
        ORDER BY conversations.date_key ASC, messages.created_at ASC
      ''',
      [_dateKey(startOfMonth), _dateKey(startOfNextMonth)],
    );
    return rows
        .map(
          (row) => MonthChatMessage(
            date:
                DateTime.tryParse(row['date_key'] as String? ?? '') ??
                startOfMonth,
            message: ChatMessage(
              id: row['id'] as String,
              conversationId: (row['conversation_id'] as String?) ?? '',
              role: (row['role'] as String?) ?? 'user',
              content: (row['content'] as String?) ?? '',
              createdAt:
                  DateTime.tryParse(row['created_at'] as String? ?? '') ??
                  DateTime.now(),
              reasoningContent: row['reasoning_content'] as String?,
              toolCallsJson: row['tool_calls_json'] as String?,
              toolCallId: row['tool_call_id'] as String?,
            ),
          ),
        )
        .toList(growable: false);
  }

  /// Searches persisted messages within one explicit calendar month.
  Future<List<ChatSearchResult>> searchMessages({
    required DateTime month,
    required String query,
    String role = 'user',
    int limit = 50,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return const [];

    final startOfMonth = DateTime(month.year, month.month);
    final startOfNextMonth = DateTime(month.year, month.month + 1);
    final db = await _db;
    final rows = await db.rawQuery(
      '''
        SELECT
          messages.id AS message_id,
          messages.conversation_id,
          messages.role,
          messages.content,
          messages.created_at,
          conversations.date_key
        FROM messages
        INNER JOIN conversations
          ON conversations.id = messages.conversation_id
        WHERE messages.role = ?
          AND conversations.date_key >= ?
          AND conversations.date_key < ?
          AND LOWER(messages.content) LIKE LOWER(?) ESCAPE '\\'
        ORDER BY conversations.date_key DESC, messages.created_at DESC
        LIMIT ?
      ''',
      [
        role,
        _dateKey(startOfMonth),
        _dateKey(startOfNextMonth),
        '%${_escapeLike(normalizedQuery)}%',
        limit,
      ],
    );
    return rows
        .map(
          (row) => ChatSearchResult(
            messageId: row['message_id'] as String,
            conversationId: row['conversation_id'] as String,
            date:
                DateTime.tryParse(row['date_key'] as String? ?? '') ??
                startOfMonth,
            content: (row['content'] as String?) ?? '',
            createdAt:
                DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now(),
            role: (row['role'] as String?) ?? role,
          ),
        )
        .toList(growable: false);
  }

  /// Searches all persisted user messages across every calendar month.
  /// Tool calls and assistant responses are excluded by the role filter.
  Future<List<ChatSearchResult>> searchUserMessages({
    required String query,
    int limit = 50,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return const [];

    final db = await _db;
    final rows = await db.rawQuery(
      '''
        SELECT
          messages.id AS message_id,
          messages.conversation_id,
          messages.role,
          messages.content,
          messages.created_at,
          conversations.date_key
        FROM messages
        INNER JOIN conversations
          ON conversations.id = messages.conversation_id
        WHERE messages.role = 'user'
          AND LOWER(messages.content) LIKE LOWER(?) ESCAPE '\\'
        ORDER BY conversations.date_key DESC, messages.created_at DESC
        LIMIT ?
      ''',
      ['%${_escapeLike(normalizedQuery)}%', limit],
    );
    return rows
        .map(
          (row) => ChatSearchResult(
            messageId: row['message_id'] as String,
            conversationId: row['conversation_id'] as String,
            date: DateTime.tryParse(row['date_key'] as String? ?? '') ??
                DateTime.now(),
            content: (row['content'] as String?) ?? '',
            createdAt:
                DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now(),
            role: 'user',
          ),
        )
        .toList(growable: false);
  }

  static String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

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
      if (message.toolCallId != null) 'tool_call_id': message.toolCallId,
    });
  }

  /// 批量删除消息。
  Future<void> deleteMessagesByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _db;
    final placeholders = ids.map((_) => '?').join(',');
    await db.delete('messages', where: 'id IN ($placeholders)', whereArgs: ids);
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
      where: 'conversation_id = ? AND role = ? AND created_at >= ?',
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
