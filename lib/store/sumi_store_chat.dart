part of 'sumi_store.dart';

// ---------------------------------------------------------------------------
// Chat Mutations mixin
// ---------------------------------------------------------------------------

mixin SumiStoreChat on ChangeNotifier {
  ChatDatabase? get chatDatabase;
  AiService? get aiService;
  ToolExecutor? get toolExecutor;
  bool get thinkingEnabled;
  Future<String> readMemory();
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
    if (db == null || svc == null || exec == null) return;
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
    final messages = await _buildMessagesContextForAgent();

    // 创建 AI 消息占位
    final assistantMsgId = 'msg-${DateTime.now().microsecondsSinceEpoch}';
    _currentMessages = [
      ..._currentMessages,
      ChatMessage(
        id: assistantMsgId,
        conversationId: convId,
        role: 'assistant',
        content: '',
        createdAt: DateTime.now(),
      ),
    ];
    _isStreaming = true;
    notifyListeners();

    await _streamAndPersistReply(
      messages: messages,
      assistantMsgId: assistantMsgId,
      convId: convId,
      db: db,
      svc: svc,
      exec: exec,
    );

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
    if (db == null || svc == null || exec == null) return;
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
    final messages = await _buildMessagesContextForAgent();

    final assistantMsgId = 'msg-${DateTime.now().microsecondsSinceEpoch}';
    _currentMessages = [
      ..._currentMessages,
      ChatMessage(
        id: assistantMsgId,
        conversationId: convId,
        role: 'assistant',
        content: '',
        createdAt: DateTime.now(),
      ),
    ];
    _isStreaming = true;
    notifyListeners();

    await _streamAndPersistReply(
      messages: messages,
      assistantMsgId: assistantMsgId,
      convId: convId,
      db: db,
      svc: svc,
      exec: exec,
    );

    await db.touchConversation(convId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 内部：Agent Loop 流式执行 + 持久化
  // ---------------------------------------------------------------------------

  /// 执行一次 Agent Loop 流式调用，处理所有事件并持久化结果。
  /// [messages] 会就地修改（追加 tool 消息）。
  Future<void> _streamAndPersistReply({
    required List<Map<String, Object?>> messages,
    required String assistantMsgId,
    required String convId,
    required ChatDatabase db,
    required AiService svc,
    required ToolExecutor exec,
  }) async {
    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
    final toolCallsList = <Map<String, Object?>>[];

    try {
      await for (final event in svc.sendAgentLoop(
        messages: messages,
        thinkingEnabled: thinkingEnabled,
        executeTool: (call) async {
          _currentToolCallLabel = toolDisplayName(call.name);
          _isThinking = false;
          notifyListeners();
          final result = await exec.execute(call);
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
      debugPrint('Sumi Agent Loop 错误: $e');
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
      final finalReasoning =
          reasoningBuf.isNotEmpty ? reasoningBuf.toString() : null;
      final finalToolCallsJson =
          toolCallsList.isNotEmpty ? jsonEncode(toolCallsList) : null;

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

    // 持久化 tool 结果消息
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
      '## 你的记忆（MEMORY.md）\n'
      'MEMORY.md 是你的持久记忆文件，记录你从对话中学到的一切。\n'
      '对话开始时它已加载到你的上下文中，你不需要重复调用 read_memory。\n'
      '\n'
      '### 核心规则：归属\n'
      'MEMORY.md 中的每一条内容，默认描述的是**你（Sumi）自己**。\n'
      '如果要记录关于用户的信息，必须在内容开头加 `用户：` 前缀。\n'
      '对比：\n'
      '  ❌ `喜欢简洁回复` → 被理解为 Sumi 自己喜欢简洁回复\n'
      '  ✅ `用户：喜欢简洁回复` → 明确是用户的偏好\n'
      '  ❌ `正在学微积分` → 谁在学？\n'
      '  ✅ `用户：正在学微积分，已完成导数章节` → 明确归属+具体进度\n'
      '\n'
      '### 何时写入记忆\n'
      '遇到以下情况，主动调用 write_memory：\n'
      '1. 用户明确表达了长期偏好或习惯（不是一次性请求）\n'
      '2. 用户给了关于你工作方式的反馈（"以后都这样"、"别再说XX"）\n'
      '3. 你帮用户完成了一个里程碑式的任务\n'
      '4. 对话中出现了用户长期关注的主题或目标\n'
      '5. 你发现记忆中有过时或矛盾的内容，需要更新\n'
      '不要每句话都记。只记那些"如果下次对话不知道这个，会让我显得不够了解用户"的事。\n'
      '\n'
      '### 怎么写\n'
      '- 每条记忆要**简洁、独立、可检索**——即使只看这一条也能理解\n'
      '- 写**提炼后的事实**，不要写"某天用户说了XX"这种流水账\n'
      '- 相关的事实合并成一条，不要分散成碎片\n'
      '- 如果信息有时效性，注明时间范围（"目前"、"今年"、"截至7月"）\n'
      '- 好的记忆：`用户：偏好 Rust，有 3 年后端经验，最近在学嵌入式开发`\n'
      '- 差的记忆：`2026-07-14 用户说他想学 Rust 因为他觉得很有意思`\n'
      '\n'
      '--- MEMORY.md ---\n'
      '{memory}\n'
      '--- END MEMORY.md ---';

  /// 构建 agent loop 用的消息上下文（含 system + memory + 历史 +
  /// reasoning_content 传回）。
  Future<List<Map<String, Object?>>> _buildMessagesContextForAgent() async {
    // 读取 Sumi 自身记忆
    final memoryContent = await readMemory();
    final systemPrompt = _chatSystemPrompt.replaceAll(
      '{memory}',
      memoryContent.trim().isEmpty ? '（暂无记忆）' : memoryContent,
    );

    final messages = <Map<String, Object?>>[
      {'role': 'system', 'content': systemPrompt},
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

}
