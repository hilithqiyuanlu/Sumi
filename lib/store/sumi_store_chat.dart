part of 'sumi_store.dart';

// ---------------------------------------------------------------------------
// Chat Mutations mixin
// ---------------------------------------------------------------------------

mixin SumiStoreChat on ChangeNotifier {
  ChatDatabase? get chatDatabase;
  AiService? get aiService;
  void afterMutation();

  // --- 状态 ---
  List<Conversation> _conversations = [];
  String? _currentConversationId;
  List<ChatMessage> _currentMessages = [];
  bool _isStreaming = false;

  List<Conversation> get conversations => List.unmodifiable(_conversations);
  String? get currentConversationId => _currentConversationId;
  List<ChatMessage> get currentMessages => List.unmodifiable(_currentMessages);
  bool get isStreaming => _isStreaming;

  /// 当前会话标题。
  String get currentConversationTitle {
    final conv = _conversations.cast<Conversation?>().firstWhere(
      (c) => c?.id == _currentConversationId,
      orElse: () => null,
    );
    return conv?.title ?? '';
  }

  // ---------------------------------------------------------------------------
  // 会话 CRUD
  // ---------------------------------------------------------------------------

  /// 从 DB 加载会话列表。
  Future<void> loadConversations() async {
    final db = chatDatabase;
    if (db == null) return;
    _conversations = await db.loadConversations();
    notifyListeners();
  }

  /// 创建新会话并设为当前。
  Future<void> createConversation() async {
    final db = chatDatabase;
    if (db == null) return;
    final conv = await db.createConversation();
    _conversations.insert(0, conv);
    _currentConversationId = conv.id;
    _currentMessages = [];
    notifyListeners();
  }

  /// 删除会话。
  Future<void> deleteConversation(String id) async {
    final db = chatDatabase;
    if (db == null) return;
    await db.deleteConversation(id);
    _conversations.removeWhere((c) => c.id == id);
    if (_currentConversationId == id) {
      _currentConversationId = _conversations.isNotEmpty ? _conversations.first.id : null;
      _currentMessages = [];
      // 切换到另一个会话或加载空
      if (_currentConversationId != null) {
        _currentMessages = await db.loadMessages(_currentConversationId!);
      }
    }
    notifyListeners();
  }

  /// 切换会话。
  Future<void> switchConversation(String id) async {
    final db = chatDatabase;
    if (db == null) return;
    _currentConversationId = id;
    _currentMessages = await db.loadMessages(id);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 消息
  // ---------------------------------------------------------------------------

  /// 发送用户消息并获取 AI 流式回复。
  Future<void> sendMessage(String content) async {
    final db = chatDatabase;
    final svc = aiService;
    if (db == null || svc == null) return;
    if (content.trim().isEmpty) return;

    // 确保有当前会话
    if (_currentConversationId == null) {
      await createConversation();
    }
    final convId = _currentConversationId!;
    if (convId.isEmpty) return;

    // 自动设置会话标题（取首条用户消息前 20 字）
    final conv = _conversations.cast<Conversation?>().firstWhere(
      (c) => c?.id == convId,
      orElse: () => null,
    );
    if (conv != null && conv.title.isEmpty) {
      final title = content.length > 20
          ? '${content.substring(0, 20)}…'
          : content;
      await db.updateConversationTitle(convId, title);
      final ci = _conversations.indexWhere((c) => c.id == convId);
      if (ci != -1) {
        _conversations[ci] = _conversations[ci].copyWith(title: title);
      }
    }

    // 保存用户消息
    final userMsg = ChatMessage(
      id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: convId,
      role: 'user',
      content: content.trim(),
      createdAt: DateTime.now(),
    );
    await db.saveMessage(userMsg);
    await db.touchConversation(convId);
    _currentMessages = [..._currentMessages, userMsg];
    notifyListeners();

    // 构建消息上下文
    final messages = _buildMessagesContext(content.trim());

    // 流式获取 AI 回复
    _isStreaming = true;
    notifyListeners();

    final assistantMsgId = 'msg-${DateTime.now().microsecondsSinceEpoch}';
    final assistantMsg = ChatMessage(
      id: assistantMsgId,
      conversationId: convId,
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
    );
    _currentMessages = [..._currentMessages, assistantMsg];
    notifyListeners();

    final buffer = StringBuffer();
    try {
      await for (final chunk in svc.streamChatMessages(messages)) {
        buffer.write(chunk);
        // 更新最后一条消息
        final lastIdx = _currentMessages.length - 1;
        if (lastIdx >= 0) {
          _currentMessages[lastIdx] =
              _currentMessages[lastIdx].copyWith(content: buffer.toString());
        }
        notifyListeners();
      }
    } catch (_) {
      // 流异常 → 保留已收到的内容
    }

    _isStreaming = false;

    // 持久化 AI 回复
    if (buffer.isNotEmpty) {
      await db.saveMessage(ChatMessage(
        id: assistantMsgId,
        conversationId: convId,
        role: 'assistant',
        content: buffer.toString(),
        createdAt: DateTime.now(),
      ));
    } else {
      // 空回复 → 移除占位消息
      _currentMessages.removeLast();
    }

    await db.touchConversation(convId);

    // 更新会话列表排序
    final ci = _conversations.indexWhere((c) => c.id == convId);
    if (ci > 0) {
      final c = _conversations.removeAt(ci);
      _conversations.insert(0, c);
    }

    notifyListeners();
  }

  /// 重新生成最后一条 AI 回复。
  Future<void> regenerateLast() async {
    final db = chatDatabase;
    final svc = aiService;
    if (db == null || svc == null) return;
    final convId = _currentConversationId;
    if (convId == null) return;

    // 找到并移除最后一条 AI 消息
    final lastAiIdx = _currentMessages.lastIndexWhere((m) => m.role == 'assistant');
    String? lastUserContent;
    if (lastAiIdx >= 0) {
      // 找 AI 消息前最近的一条用户消息
      for (var i = lastAiIdx - 1; i >= 0; i--) {
        if (_currentMessages[i].role == 'user') {
          lastUserContent = _currentMessages[i].content;
          break;
        }
      }
      _currentMessages.removeAt(lastAiIdx);
      await db.popLastAssistantMessage(convId);
      notifyListeners();
    }

    if (lastUserContent == null) return;

    // 重新发送
    _isStreaming = true;
    notifyListeners();

    final messages = _buildMessagesContext(lastUserContent);

    final assistantMsgId = 'msg-${DateTime.now().microsecondsSinceEpoch}';
    final assistantMsg = ChatMessage(
      id: assistantMsgId,
      conversationId: convId,
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
    );
    _currentMessages = [..._currentMessages, assistantMsg];
    notifyListeners();

    final buffer = StringBuffer();
    try {
      await for (final chunk in svc.streamChatMessages(messages)) {
        buffer.write(chunk);
        final lastIdx = _currentMessages.length - 1;
        if (lastIdx >= 0) {
          _currentMessages[lastIdx] =
              _currentMessages[lastIdx].copyWith(content: buffer.toString());
        }
        notifyListeners();
      }
    } catch (_) {}

    _isStreaming = false;

    if (buffer.isNotEmpty) {
      await db.saveMessage(ChatMessage(
        id: assistantMsgId,
        conversationId: convId,
        role: 'assistant',
        content: buffer.toString(),
        createdAt: DateTime.now(),
      ));
    } else {
      _currentMessages.removeLast();
    }

    await db.touchConversation(convId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 内部
  // ---------------------------------------------------------------------------

  static const _chatSystemPrompt =
      '你是 Sumi，一个温暖的个人学习助手。\n'
      '你的风格：鼓励、简洁、有同理心。像朋友一样聊天，不要像机器人。\n'
      '\n'
      '你可以帮用户：\n'
      '- 制定和调整学习计划\n'
      '- 解答学习中的疑问\n'
      '- 管理待办事项\n'
      '- 提供学习建议和鼓励\n'
      '\n'
      '回答控制在 200 字以内，除非用户明确需要详细解释。';

  /// 构建消息上下文（system prompt + 最近 10 轮 + 当前用户消息）。
  List<Map<String, String>> _buildMessagesContext(String currentUserMessage) {
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _chatSystemPrompt},
    ];

    // 最近 10 轮对话 = 最近 20 条消息（不包含当前正在发送的用户消息）
    final recentMessages = _currentMessages;
    final contextMessages = recentMessages.length > 20
        ? recentMessages.sublist(recentMessages.length - 20)
        : recentMessages;

    for (final msg in contextMessages) {
      messages.add({
        'role': msg.role,
        'content': msg.content,
      });
    }

    // 当前用户消息已通过 saveMessage 保存到 _currentMessages
    // 所以它已经在 recentMessages 里面了（如果 <= 20 条）

    return messages;
  }
}
