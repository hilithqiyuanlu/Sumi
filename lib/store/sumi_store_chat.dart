part of 'sumi_store.dart';

// ---------------------------------------------------------------------------
// Chat Mutations mixin
// ---------------------------------------------------------------------------

mixin SumiStoreChat on ChangeNotifier {
  ChatDatabase? get chatDatabase;
  AiService? get aiService;
  ToolExecutor? get toolExecutor;
  bool get thinkingEnabled;
  void afterMutation();

  // --- 状态 ---
  List<Conversation> _conversations = [];
  String? _currentConversationId;
  List<ChatMessage> _currentMessages = [];
  bool _isStreaming = false;

  /// Agent 状态
  bool _isThinking = false;
  String? _currentToolCallLabel;

  List<Conversation> get conversations => List.unmodifiable(_conversations);
  String? get currentConversationId => _currentConversationId;
  List<ChatMessage> get currentMessages => List.unmodifiable(_currentMessages);
  bool get isStreaming => _isStreaming;
  bool get isThinking => _isThinking;
  String? get currentToolCallLabel => _currentToolCallLabel;

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

  /// 创建新会话并设为当前（仅在列表界面点击"新建"时调用）。
  Future<void> createConversation() async {
    final db = chatDatabase;
    if (db == null) return;
    // 先清理当前空对话
    await cleanupEmptyConversation();
    final conv = await db.createConversation();
    _conversations.insert(0, conv);
    _currentConversationId = conv.id;
    _currentMessages = [];
    notifyListeners();
  }

  /// 确保有活跃对话：优先加载最近对话，无对话时创建新的。
  Future<void> ensureLastConversation() async {
    final db = chatDatabase;
    if (db == null) return;
    if (_conversations.isNotEmpty) {
      await switchConversation(_conversations.first.id);
    } else {
      await createConversation();
    }
  }

  /// 清理空对话：当前对话无任何用户消息时删除。
  Future<void> cleanupEmptyConversation() async {
    final db = chatDatabase;
    if (db == null) return;
    if (_currentConversationId == null) return;
    final hasUserMsg = _currentMessages.any((m) => m.role == 'user');
    if (!hasUserMsg) {
      final convId = _currentConversationId!;
      // 从 DB 和内存中移除
      await db.deleteConversation(convId);
      _conversations.removeWhere((c) => c.id == convId);
      _currentConversationId = null;
      _currentMessages = [];
      notifyListeners();
    }
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
      if (_currentConversationId != null) {
        _currentMessages = await db.loadMessages(_currentConversationId!);
      }
    }
    notifyListeners();
  }

  /// 清除全部对话数据。
  Future<void> clearChatData() async {
    final db = chatDatabase;
    if (db != null) {
      await db.clearAll();
    }
    _conversations.clear();
    _currentConversationId = null;
    _currentMessages.clear();
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
  // 消息发送（05 轮重写：Agent Loop）
  // ---------------------------------------------------------------------------

  /// 发送用户消息并进入 Agent Loop。
  Future<void> sendMessage(String content) async {
    final db = chatDatabase;
    final svc = aiService;
    final exec = toolExecutor;
    if (db == null || svc == null) return;
    if (content.trim().isEmpty) return;

    // 确保有当前会话
    if (_currentConversationId == null) {
      await createConversation();
    }
    final convId = _currentConversationId!;
    if (convId.isEmpty) return;

    // 自动设置会话标题
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

    // 构建 API 消息上下文
    final messages = _buildMessagesContextForAgent();

    // 创建 AI 消息占位
    final assistantMsgId = 'msg-${DateTime.now().microsecondsSinceEpoch}';
    final assistantMsg = ChatMessage(
      id: assistantMsgId,
      conversationId: convId,
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
    );
    _currentMessages = [..._currentMessages, assistantMsg];
    _isStreaming = true;
    notifyListeners();

    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
    final toolCallsList = <Map<String, Object?>>[];
    String? lastToolName;

    try {
      await for (final event in svc.sendAgentLoop(
        messages: messages,
        thinkingEnabled: thinkingEnabled,
        executeTool: (call) async {
          lastToolName = call.name;
          _currentToolCallLabel = _toolLabel(call.name);
          _isThinking = false;
          notifyListeners();
          final result = await exec!.execute(call);
          // 保存 tool call 信息
          toolCallsList.add({
            'id': call.id,
            'type': 'function',
            'function': {
              'name': call.name,
              'arguments': jsonEncode(call.arguments),
            },
          });
          _currentToolCallLabel = null;
          notifyListeners();
          return result;
        },
      )) {
        switch (event) {
          case ContentDelta(text: final t):
            contentBuf.write(t);
            final lastIdx = _currentMessages.length - 1;
            if (lastIdx >= 0) {
              _currentMessages[lastIdx] =
                  _currentMessages[lastIdx].copyWith(content: contentBuf.toString());
            }
            _isThinking = false;
            notifyListeners();
          case ReasoningDelta(text: final t):
            reasoningBuf.write(t);
            _isThinking = true;
            notifyListeners();
          case ToolCallsComplete():
            // tool calls 由 executeTool 回调处理
            break;
          case StreamDone():
            break;
        }
      }
    } catch (e) {
      // 异常 → 保留已收到内容，并提示用户
      debugPrint('Sumi 对话错误: $e');
      if (contentBuf.isEmpty) {
        contentBuf.write('抱歉，请求遇到错误，请稍后重试。');
      }
    }

    _isStreaming = false;
    _isThinking = false;
    _currentToolCallLabel = null;

    // 持久化 AI 回复
    final finalContent = contentBuf.toString();
    if (finalContent.isNotEmpty) {
      final finalReasoning = reasoningBuf.isNotEmpty ? reasoningBuf.toString() : null;
      final finalToolCallsJson = toolCallsList.isNotEmpty
          ? jsonEncode(toolCallsList)
          : null;

      // 更新内存中的消息
      final lastIdx = _currentMessages.length - 1;
      if (lastIdx >= 0) {
        _currentMessages[lastIdx] = _currentMessages[lastIdx].copyWith(
          content: finalContent,
          reasoningContent: finalReasoning,
          toolCallsJson: finalToolCallsJson,
        );
      }

      // 持久化到 DB
      await db.saveMessage(ChatMessage(
        id: assistantMsgId,
        conversationId: convId,
        role: 'assistant',
        content: finalContent,
        createdAt: DateTime.now(),
        reasoningContent: finalReasoning,
        toolCallsJson: finalToolCallsJson,
      ));
    } else {
      // 空回复 → 移除占位
      _currentMessages.removeLast();
    }

    // 持久化 tool 结果消息（agent loop 中新增的 role=tool 消息）
    for (final m in messages) {
      if (m['role'] == 'tool') {
        final toolMsg = ChatMessage(
          id: 'msg-${DateTime.now().microsecondsSinceEpoch}-tool',
          conversationId: convId,
          role: 'tool',
          content: (m['content'] as String?) ?? '',
          createdAt: DateTime.now(),
          toolCallId: (m['tool_call_id'] as String?) ?? '',
        );
        await db.saveMessage(toolMsg);
        _currentMessages = [..._currentMessages, toolMsg];
      }
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
    final exec = toolExecutor;
    if (db == null || svc == null) return;
    final convId = _currentConversationId;
    if (convId == null) return;

    // 找到并移除最后一条 AI 消息及关联的 tool 消息
    final lastAiIdx = _currentMessages.lastIndexWhere((m) => m.role == 'assistant');
    String? lastUserContent;
    if (lastAiIdx >= 0) {
      for (var i = lastAiIdx - 1; i >= 0; i--) {
        if (_currentMessages[i].role == 'user') {
          lastUserContent = _currentMessages[i].content;
          break;
        }
      }
      // 移除 assistant 及其后的 tool 消息
      _currentMessages.removeWhere((m) {
        final idx = _currentMessages.indexOf(m);
        return idx >= lastAiIdx && (m.role == 'assistant' || m.role == 'tool');
      });
      await db.popLastAssistantMessage(convId);
      // 也清除 DB 中残留的 tool 消息
      await db.popToolMessages(convId);
      notifyListeners();
    }

    if (lastUserContent == null) return;

    // 构建上下文
    final messages = _buildMessagesContextForAgent();

    final assistantMsgId = 'msg-${DateTime.now().microsecondsSinceEpoch}';
    final assistantMsg = ChatMessage(
      id: assistantMsgId,
      conversationId: convId,
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
    );
    _currentMessages = [..._currentMessages, assistantMsg];
    _isStreaming = true;
    notifyListeners();

    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
    final toolCallsList = <Map<String, Object?>>[];

    try {
      await for (final event in svc.sendAgentLoop(
        messages: messages,
        thinkingEnabled: thinkingEnabled,
        executeTool: (call) async {
          _currentToolCallLabel = _toolLabel(call.name);
          _isThinking = false;
          notifyListeners();
          final result = await exec!.execute(call);
          toolCallsList.add({
            'id': call.id,
            'type': 'function',
            'function': {
              'name': call.name,
              'arguments': jsonEncode(call.arguments),
            },
          });
          _currentToolCallLabel = null;
          notifyListeners();
          return result;
        },
      )) {
        switch (event) {
          case ContentDelta(text: final t):
            contentBuf.write(t);
            final lastIdx = _currentMessages.length - 1;
            if (lastIdx >= 0) {
              _currentMessages[lastIdx] =
                  _currentMessages[lastIdx].copyWith(content: contentBuf.toString());
            }
            _isThinking = false;
            notifyListeners();
          case ReasoningDelta(text: final t):
            reasoningBuf.write(t);
            _isThinking = true;
            notifyListeners();
          case ToolCallsComplete():
            break;
          case StreamDone():
            break;
        }
      }
    } catch (e) {
      debugPrint('Sumi 重新生成错误: $e');
      if (contentBuf.isEmpty) {
        contentBuf.write('抱歉，请求遇到错误，请稍后重试。');
      }
    }

    _isStreaming = false;
    _isThinking = false;
    _currentToolCallLabel = null;

    // 持久化 AI 回复（重新生成）
    final finalContent = contentBuf.toString();
    if (finalContent.isNotEmpty) {
      final finalReasoning = reasoningBuf.isNotEmpty ? reasoningBuf.toString() : null;
      final finalToolCallsJson = toolCallsList.isNotEmpty
          ? jsonEncode(toolCallsList)
          : null;

      final lastIdx = _currentMessages.length - 1;
      if (lastIdx >= 0) {
        _currentMessages[lastIdx] = _currentMessages[lastIdx].copyWith(
          content: finalContent,
          reasoningContent: finalReasoning,
          toolCallsJson: finalToolCallsJson,
        );
      }

      await db.saveMessage(ChatMessage(
        id: assistantMsgId,
        conversationId: convId,
        role: 'assistant',
        content: finalContent,
        createdAt: DateTime.now(),
        reasoningContent: finalReasoning,
        toolCallsJson: finalToolCallsJson,
      ));
    } else {
      _currentMessages.removeLast();
    }

    // 持久化 tool 结果消息（agent loop 中新增的 role=tool 消息）
    for (final m in messages) {
      if (m['role'] == 'tool') {
        final toolMsg = ChatMessage(
          id: 'msg-${DateTime.now().microsecondsSinceEpoch}-tool',
          conversationId: convId,
          role: 'tool',
          content: (m['content'] as String?) ?? '',
          createdAt: DateTime.now(),
          toolCallId: (m['tool_call_id'] as String?) ?? '',
        );
        await db.saveMessage(toolMsg);
        _currentMessages = [..._currentMessages, toolMsg];
      }
    }

    await db.touchConversation(convId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 内部：消息构建
  // ---------------------------------------------------------------------------

  static const _chatSystemPrompt =
      '你是 Sumi，一个能干的个人学习助手。你有工具可以帮助用户。\n'
      '\n'
      '## 风格\n'
      '- 简洁直接，像朋友聊天，不要机器人套话\n'
      '- 用户没要求时，默认 ≤ 100 字\n'
      '- 不要用"当然可以！""希望对你有帮助！"这类 AI 废话\n'
      '- 用工具来做对的事，而不是反复问用户\n'
      '\n'
      '## 工具\n'
      '你可以搜索网络、读写记忆、管理待办事项。需要时直接用工具。\n'
      '\n'
      '## 记忆\n'
      '使用 read_memory / write_memory 记录用户的重要信息、偏好和学习进度。';

  /// 构建 agent loop 用的消息上下文（含 system + 历史 + reasoning_content 传回）。
  List<Map<String, Object?>> _buildMessagesContextForAgent() {
    final messages = <Map<String, Object?>>[
      {'role': 'system', 'content': _chatSystemPrompt},
    ];

    // 最近消息（约 10 轮对话，考虑到 tool 消息占用更多空间）
    final recentMessages = _currentMessages;
    final contextMessages = recentMessages.length > 40
        ? recentMessages.sublist(recentMessages.length - 40)
        : recentMessages;

    for (final msg in contextMessages) {
      final map = <String, Object?>{
        'role': msg.role,
        'content': msg.content,
      };

      // tool 消息需要传回 tool_call_id
      if (msg.role == 'tool' && msg.toolCallId != null) {
        map['tool_call_id'] = msg.toolCallId;
      }

      // 传回 reasoning_content（如果有）
      if (msg.reasoningContent != null &&
          msg.reasoningContent!.isNotEmpty) {
        map['reasoning_content'] = msg.reasoningContent;
      }

      // 传回 tool_calls（如果有，仅 assistant 消息）
      if (msg.toolCallsJson != null && msg.toolCallsJson!.isNotEmpty) {
        try {
          final tcList =
              jsonDecode(msg.toolCallsJson!) as List<Object?>;
          map['tool_calls'] = tcList;
        } catch (_) {}
      }

      messages.add(map);
    }

    return messages;
  }

  /// 工具名称 → 中文标签。
  String _toolLabel(String name) => switch (name) {
    'search_web' => '搜索网络',
    'read_memory' => '读取记忆',
    'write_memory' => '写入记忆',
    'read_todos' => '查看事项',
    'write_todo' => '创建事项',
    _ => name,
  };
}
