part of 'sumi_store.dart';

// ---------------------------------------------------------------------------
// Chat Mutations mixin
// ---------------------------------------------------------------------------

mixin SumiStoreChat on ChangeNotifier {
  ChatDatabase? get chatDatabase;
  AiService? get aiService;
  ToolExecutor? get toolExecutor;
  bool get thinkingEnabled;
  DateTime get selectedDate;
  set selectedDate(DateTime d);
  Future<String> readMemory();
  void afterMutation();
  void notifyMessageSent();
  void triggerNavigateToToday();

  // --- 状态 ---
  String? _currentConversationId;
  String? _currentDateKey;
  List<ChatMessage> _currentMessages = [];
  bool _isStreaming = false;
  bool _isLoadingConversation = false;

  /// Agent 状态
  bool _isThinking = false;
  String? _currentToolCallLabel;

  /// 用户发起对话时的首页问候语（仅首条消息注入一次上下文）
  String? _activeGreeting;

  String? get currentConversationId => _currentConversationId;
  List<ChatMessage> get currentMessages => List.unmodifiable(_currentMessages);
  bool get isStreaming => _isStreaming;
  bool get isThinking => _isThinking;
  bool get isLoadingConversation => _isLoadingConversation;
  String? get currentToolCallLabel => _currentToolCallLabel;

  // ---------------------------------------------------------------------------
  // 日期驱动会话
  // ---------------------------------------------------------------------------

  /// 获取或创建指定日期的会话，加载其消息。
  Future<void> _getOrCreateConversationForDate(String dateKey) async {
    final db = chatDatabase;
    if (db == null) return;
    if (_currentDateKey == dateKey && _currentConversationId != null) return;

    _isLoadingConversation = true;
    notifyListeners();

    // 查找或创建
    Conversation? conv = await db.findConversationByDate(dateKey);
    conv ??= await db.createConversationForDate(dateKey);

    _currentConversationId = conv.id;
    _currentDateKey = dateKey;
    _currentMessages = await db.loadMessages(conv.id);
    _isLoadingConversation = false;
    notifyListeners();
  }

  /// 删除一个消息对：从指定 user 消息开始，直到下一个 user 消息（或末尾）。
  Future<void> deleteMessagePair(int userMsgIndex) async {
    final db = chatDatabase;
    if (db == null) return;
    if (userMsgIndex < 0 || userMsgIndex >= _currentMessages.length) return;
    if (_currentMessages[userMsgIndex].role != 'user') return;

    // 找到删除范围：从 userMsgIndex 到下一个 user 消息之前
    int endIndex = _currentMessages.length - 1;
    for (var i = userMsgIndex + 1; i < _currentMessages.length; i++) {
      if (_currentMessages[i].role == 'user') {
        endIndex = i - 1;
        break;
      }
    }

    // 收集要删除的消息 ID
    final idsToDelete = <String>[];
    for (var i = userMsgIndex; i <= endIndex; i++) {
      idsToDelete.add(_currentMessages[i].id);
    }

    // 从 DB 和内存中删除
    await db.deleteMessagesByIds(idsToDelete);
    _currentMessages.removeRange(userMsgIndex, endIndex + 1);
    notifyListeners();
  }

  /// 清除全部对话数据。
  Future<void> clearChatData() async {
    final db = chatDatabase;
    if (db != null) {
      await db.clearAll();
    }
    _currentConversationId = null;
    _currentDateKey = null;
    _currentMessages.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 消息发送（05 轮重写：Agent Loop）
  // ---------------------------------------------------------------------------

  /// 发送用户消息并进入 Agent Loop。
  /// [currentGreeting] 首页问候语，仅在首条消息时作为上下文注入一次。
  Future<void> sendMessage(String content, {String? currentGreeting}) async {
    final db = chatDatabase;
    final svc = aiService;
    final exec = toolExecutor;
    if (db == null || svc == null || exec == null) return;
    if (content.trim().isEmpty) return;

    // 记录问候语上下文（仅用于新会话首条消息）
    _activeGreeting = currentGreeting;

    // 对话模式始终使用今天的会话，发送后回到今天
    final today = dateKey(DateTime.now());
    await _getOrCreateConversationForDate(today);
    final convId = _currentConversationId!;

    // 如果当前不在今天，切回今天
    if (dateKey(selectedDate) != today) {
      selectedDate = dateOnly(DateTime.now());
      triggerNavigateToToday();
    }
    if (convId.isEmpty) return;

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
    notifyMessageSent(); // 通知 UI 滚动到用户消息

    // 构建 API 消息上下文
    final messages = await _buildMessagesContextForAgent();
    final msgCountBefore = messages.length;

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
      msgCountBefore: msgCountBefore,
      assistantMsgId: assistantMsgId,
      convId: convId,
      db: db,
      svc: svc,
      exec: exec,
    );

    await db.touchConversation(convId);
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
    final msgCountBefore = messages.length;

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
      msgCountBefore: msgCountBefore,
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
  /// [messages] 会就地修改（追加 assistant + tool 消息）。
  /// [msgCountBefore] sendAgentLoop 调用前 messages 的长度，用于只持久化新增的 tool 消息。
  Future<void> _streamAndPersistReply({
    required List<Map<String, Object?>> messages,
    required int msgCountBefore,
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

    // 持久化本轮新增的 tool 结果消息（历史 tool 已在之前轮次保存过）
    for (var i = msgCountBefore; i < messages.length; i++) {
      final m = messages[i];
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
      '你是 Sumi，一个个人学习助手。风格：简洁直接，≤100 字，不用"当然可以""希望对你有帮助"这类 AI 废话。\n'
      '\n'
      '## 工具\n'
      '你有搜索网络、读写记忆、管理待办的工具，需要时直接使用。\n'
      '\n'
      '## 记忆（MEMORY.md）\n'
      '已加载到上下文中，不需要重复读取。记录关于用户的信息时加「用户：」前缀。\n'
      '遇到长期偏好、工作反馈、里程碑、长期目标时主动写入，不要每句话都记。\n'
      '每条记忆简洁独立，写提炼后的事实而非流水账。\n'
      '\n'
      '--- MEMORY.md ---\n'
      '{memory}\n'
      '--- END MEMORY.md ---';

  /// 构建 agent loop 用的消息上下文（含 system + memory + 历史 +
  /// reasoning_content 传回）。
  Future<List<Map<String, Object?>>> _buildMessagesContextForAgent() async {
    // 读取 Sumi 自身记忆
    final memoryContent = await readMemory();
    var systemPrompt = _chatSystemPrompt.replaceAll(
      '{memory}',
      memoryContent.trim().isEmpty ? '（暂无记忆）' : memoryContent,
    );

    // 新会话首条消息：注入问候语上下文，帮助 AI 判断用户是否在回应问候语
    if (_activeGreeting != null && _currentMessages.length <= 1) {
      systemPrompt += '\n\n[上下文] 首页问候语："${_activeGreeting}"。请自行判断用户是否在回应它。';
      _activeGreeting = null; // 仅用一次
    }

    final messages = <Map<String, Object?>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    // 最近 N 条消息（tool 消息会成倍消耗配额，40 条 ≈ 4-5 轮 agent loop）
    final recentMessages = _currentMessages;
    int startIndex = 0;
    if (recentMessages.length > 60) {
      startIndex = recentMessages.length - 60;
    }
    // 确保不以孤立的 tool 消息开头 —— 否则 API 因消息序列非法而拒绝请求
    while (startIndex > 0 && recentMessages[startIndex].role == 'tool') {
      startIndex--;
    }
    final contextMessages = recentMessages.sublist(startIndex);

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
