part of 'sumi_store.dart';

enum ChatSendResult { accepted, empty, busy, missingApiKey }

// ---------------------------------------------------------------------------
// Chat Mutations mixin
// ---------------------------------------------------------------------------

mixin SumiStoreChat {
  ChatDatabase? get chatDatabase;
  ChatCapability? get chatAgent;
  ToolExecutor? get toolExecutor;
  bool get thinkingEnabled;
  DateTime get selectedDate;
  set selectedDate(DateTime d);
  void triggerNavigateToToday();
  MemoryService? get memoryService;
  MemoryExtractionService? get memoryExtractionService;
  AppSettings get appSettings;
  List<Project> get projectList;
  ChatController get chatController;
  LocalRetrievalService get localRetrieval;
  void scheduleLocalIndex();

  // --- 状态 ---
  String? _currentConversationId;
  String? _currentDateKey;
  List<ChatMessage> _currentMessages = [];
  bool _isStreaming = false;
  bool _isLoadingConversation = false;
  bool _isTemporaryConversation = false;

  String? _currentToolCallLabel;
  ChatFailure? _chatFailure;
  String? _chatFailureConversationId;
  int _messageSentSequence = 0;
  Timer? _chatPublishTimer;

  // 流式请求必须绑定到创建它的会话和占位消息，不能依赖当前列表的位置。
  String? _streamConversationId;
  String? _streamAssistantMessageId;

  /// 用户发起对话时的首页问候语（仅首条消息注入一次上下文）
  String? _activeGreeting;

  String? get currentConversationId => _currentConversationId;
  List<ChatMessage> get currentMessages => List.unmodifiable(_currentMessages);
  bool get isStreaming => _isStreaming;
  bool get isLoadingConversation => _isLoadingConversation;
  String? get currentToolCallLabel => _currentToolCallLabel;
  bool get isTemporaryConversation => _isTemporaryConversation;
  ValueListenable<ChatViewState> get chatView => chatController.view;

  void _publishChatState({bool throttled = false}) {
    if (throttled) {
      if (_chatPublishTimer?.isActive ?? false) return;
      _chatPublishTimer = Timer(
        const Duration(milliseconds: 50),
        _emitChatViewState,
      );
      return;
    }
    _chatPublishTimer?.cancel();
    _chatPublishTimer = null;
    _emitChatViewState();
  }

  void _emitChatViewState() {
    _chatPublishTimer = null;
    final isShowingStream =
        _isStreaming && _streamConversationId == _currentConversationId;
    chatController.view.value = ChatViewState(
      conversationId: _currentConversationId,
      messages: List.unmodifiable(_currentMessages),
      isStreaming: isShowingStream,
      isLoadingConversation: _isLoadingConversation,
      isTemporaryConversation: _isTemporaryConversation,
      activityLabel: isShowingStream ? _currentToolCallLabel : null,
      messageSentSequence: _messageSentSequence,
      failure: _chatFailureConversationId == _currentConversationId
          ? _chatFailure
          : null,
    );
  }

  bool _isCurrentConversation(String conversationId) =>
      _currentConversationId == conversationId;

  void _startStreaming(String conversationId, String assistantMessageId) {
    _isStreaming = true;
    _streamConversationId = conversationId;
    _streamAssistantMessageId = assistantMessageId;
  }

  void _finishStreaming(String assistantMessageId) {
    if (_streamAssistantMessageId != assistantMessageId) return;
    _isStreaming = false;
    _streamConversationId = null;
    _streamAssistantMessageId = null;
    _currentToolCallLabel = null;
  }

  void _updateCurrentAssistantMessage({
    required String conversationId,
    required String assistantMessageId,
    required String content,
    String? toolCallsJson,
    bool insertIfMissing = false,
  }) {
    if (!_isCurrentConversation(conversationId)) return;
    final index = _currentMessages.indexWhere(
      (message) =>
          message.id == assistantMessageId &&
          message.conversationId == conversationId &&
          message.role == 'assistant',
    );
    if (index >= 0) {
      _currentMessages[index] = _currentMessages[index].copyWith(
        content: content,
        toolCallsJson: toolCallsJson,
      );
    } else if (insertIfMissing) {
      _currentMessages = [
        ..._currentMessages,
        ChatMessage(
          id: assistantMessageId,
          conversationId: conversationId,
          role: 'assistant',
          content: content,
          createdAt: DateTime.now(),
          toolCallsJson: toolCallsJson,
        ),
      ];
    }
  }

  void _removeCurrentMessage(String conversationId, String messageId) {
    if (!_isCurrentConversation(conversationId)) return;
    _currentMessages.removeWhere(
      (message) =>
          message.id == messageId && message.conversationId == conversationId,
    );
  }

  void _setChatFailure(String conversationId, ChatFailure failure) {
    _chatFailureConversationId = conversationId;
    _chatFailure = failure;
  }

  void disposeChatView() {
    _chatPublishTimer?.cancel();
  }

  /// 判断 dateKey 是否为未来日期（相对于今天）。
  static bool _isFutureDate(String dateKeyStr) {
    final today = dateKey(DateTime.now());
    return dateKeyStr.compareTo(today) > 0;
  }

  // ---------------------------------------------------------------------------
  // 日期驱动会话
  // ---------------------------------------------------------------------------

  /// 获取或创建指定日期的会话，加载其消息。
  /// 未来日期走临时会话（内存中，不持久化）。
  Future<void> _getOrCreateConversationForDate(String dateKey) async {
    final db = chatDatabase;
    if (_currentDateKey == dateKey && _currentConversationId != null) return;

    _isLoadingConversation = true;
    _publishChatState();

    final isFuture = _isFutureDate(dateKey);

    if (isFuture) {
      _currentConversationId = 'temp-$dateKey';
      _currentDateKey = dateKey;
      _currentMessages = [];
      _isTemporaryConversation = true;
    } else {
      if (db == null) {
        _isLoadingConversation = false;
        _publishChatState();
        return;
      }
      Conversation? conv = await db.findConversationByDate(dateKey);
      conv ??= await db.createConversationForDate(dateKey);

      _currentConversationId = conv.id;
      _currentDateKey = dateKey;
      _currentMessages = await db.loadMessages(conv.id);
      _isTemporaryConversation = false;
    }

    _isLoadingConversation = false;
    _publishChatState();
  }

  /// 删除一个消息对：从指定 user 消息开始，直到下一个 user 消息（或末尾）。
  Future<void> deleteMessagePair(int userMsgIndex) async {
    final db = chatDatabase;
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

    // 从 DB 和内存中删除（临时会话仅内存）
    if (!_isTemporaryConversation && db != null) {
      await db.deleteMessagesByIds(idsToDelete);
    }
    _currentMessages.removeRange(userMsgIndex, endIndex + 1);
    scheduleLocalIndex();
    _publishChatState();
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
    scheduleLocalIndex();
    _chatFailure = null;
    _chatFailureConversationId = null;
    _publishChatState();
  }

  // ---------------------------------------------------------------------------
  // 消息发送（05 轮重写：Agent Loop）
  // ---------------------------------------------------------------------------

  /// 接受消息后异步进入 Agent Loop，让输入框能立即决定是否清空。
  ChatSendResult sendMessage(String content, {String? currentGreeting}) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return ChatSendResult.empty;
    if (_isStreaming) return ChatSendResult.busy;

    final db = chatDatabase;
    final svc = chatAgent;
    final exec = toolExecutor;
    if (svc == null || exec == null) {
      debugPrint('[sendMessage] chatAgent 或 toolExecutor 为 null，无法发送');
      return ChatSendResult.missingApiKey;
    }

    _isStreaming = true;
    _streamConversationId = _currentConversationId;
    _streamAssistantMessageId = null;
    _chatFailure = null;
    _chatFailureConversationId = null;
    _currentToolCallLabel = '正在生成回复';
    _publishChatState();
    unawaited(
      _sendAcceptedMessage(
        trimmed,
        currentGreeting: currentGreeting,
        db: db,
        svc: svc,
        exec: exec,
      ),
    );
    return ChatSendResult.accepted;
  }

  Future<void> _sendAcceptedMessage(
    String content, {
    required String? currentGreeting,
    required ChatDatabase? db,
    required ChatCapability svc,
    required ToolExecutor exec,
  }) async {
    // 记录问候语上下文（仅用于新会话首条消息）
    _activeGreeting = currentGreeting;

    final today = dateKey(DateTime.now());
    final selectedKey = dateKey(selectedDate);
    final isFuture = _isFutureDate(selectedKey);

    String? userMessageId;
    String? assistantMessageId;
    String? conversationId;
    try {
      if (isFuture) {
        // 未来日期：留在当前日期，使用临时会话
        await _getOrCreateConversationForDate(selectedKey);
      } else {
        // 非未来日期：强制切回今天的会话
        await _getOrCreateConversationForDate(today);
        if (selectedKey != today) {
          selectedDate = dateOnly(DateTime.now());
          triggerNavigateToToday();
        }
      }
      final convId = _currentConversationId!;
      conversationId = convId;
      if (convId.isEmpty) return;
      final isTemporary = _isTemporaryConversation;

      // 保存用户消息（临时会话仅内存，不写DB）
      userMessageId = 'msg-${DateTime.now().microsecondsSinceEpoch}';
      final userMsg = ChatMessage(
        id: userMessageId,
        conversationId: convId,
        role: 'user',
        content: content.trim(),
        createdAt: DateTime.now(),
      );
      if (!isTemporary && db != null) {
        await db.saveMessage(userMsg);
        await db.touchConversation(convId);
      }
      _currentMessages = [..._currentMessages, userMsg];
      if (!isTemporary) scheduleLocalIndex();
      if (!isTemporary) {
        final extractor = memoryExtractionService;
        if (extractor != null) {
          unawaited(
            extractor.process(
              messageId: userMessageId,
              message: userMsg.content,
            ),
          );
        }
      }
      _messageSentSequence++;
      _publishChatState();

      // 先创建可见占位，再构建可选上下文；上下文失败也不会静默消失。
      assistantMessageId = 'msg-${DateTime.now().microsecondsSinceEpoch}';
      _currentMessages = [
        ..._currentMessages,
        ChatMessage(
          id: assistantMessageId,
          conversationId: convId,
          role: 'assistant',
          content: '',
          createdAt: DateTime.now(),
        ),
      ];
      _startStreaming(convId, assistantMessageId);
      _publishChatState();

      final messages = await _buildMessagesContextForAgent(
        excludeMessageId: assistantMessageId,
      );
      final msgCountBefore = messages.length;

      await _streamAndPersistReply(
        messages: messages,
        msgCountBefore: msgCountBefore,
        assistantMsgId: assistantMessageId,
        userMessageId: userMessageId,
        convId: convId,
        db: db,
        svc: svc,
        exec: exec,
        isTemporary: isTemporary,
      );

      if (!isTemporary && db != null) {
        await db.touchConversation(convId);
      }
    } catch (e) {
      debugPrint('[sendMessage] 异常: $e');
      if (assistantMessageId != null) {
        _finishStreaming(assistantMessageId);
        if (conversationId != null) {
          _removeCurrentMessage(conversationId, assistantMessageId);
        }
      }
      if (userMessageId != null) {
        final failureConversationId = conversationId ?? _currentConversationId;
        if (failureConversationId != null) {
          _setChatFailure(
            failureConversationId,
            ChatFailure(
              userMessageId: userMessageId,
              message: '准备回复时遇到错误，请重试。',
              retryable: true,
            ),
          );
        }
      }
      _isStreaming = false;
      _currentToolCallLabel = null;
      _publishChatState();
    }
    _publishChatState();
  }

  Future<void> retryLastFailedMessage() async {
    final failure = _chatFailure;
    final svc = chatAgent;
    final exec = toolExecutor;
    final convId = _currentConversationId;
    if (failure == null || !failure.retryable || _isStreaming) return;
    if (svc == null || exec == null || convId == null) return;
    final userExists = _currentMessages.any(
      (message) =>
          message.id == failure.userMessageId && message.role == 'user',
    );
    if (!userExists) return;

    _chatFailure = null;
    _chatFailureConversationId = null;
    _isStreaming = true;
    _currentToolCallLabel = '正在准备回复';
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
    _startStreaming(convId, assistantMsgId);
    _publishChatState();

    try {
      final messages = await _buildMessagesContextForAgent(
        excludeMessageId: assistantMsgId,
      );
      await _streamAndPersistReply(
        messages: messages,
        msgCountBefore: messages.length,
        assistantMsgId: assistantMsgId,
        userMessageId: failure.userMessageId,
        convId: convId,
        db: chatDatabase,
        svc: svc,
        exec: exec,
        isTemporary: _isTemporaryConversation,
      );
    } catch (e) {
      debugPrint('[retryLastFailedMessage] 异常: $e');
      _removeCurrentMessage(convId, assistantMsgId);
      _finishStreaming(assistantMsgId);
      _setChatFailure(
        convId,
        ChatFailure(
          userMessageId: failure.userMessageId,
          message: '准备回复时遇到错误，请重试。',
          retryable: true,
        ),
      );
      _publishChatState();
    }
  }

  /// 重新生成最后一条 AI 回复。
  Future<void> regenerateLast() async {
    final db = chatDatabase;
    final svc = chatAgent;
    final exec = toolExecutor;
    if (svc == null || exec == null) return;
    final convId = _currentConversationId;
    if (convId == null) return;
    final isTemporary = _isTemporaryConversation;

    // 找到并移除最后一条 AI 消息及该消息之后（同一轮）的 tool 消息，
    // 保留更早轮次的 assistant/tool 结果，避免上下文非法。
    final lastAiMsg = _currentMessages.cast<ChatMessage?>().lastWhere(
      (m) => m?.role == 'assistant',
      orElse: () => null,
    );
    String? lastUserContent;
    String? lastUserId;
    if (lastAiMsg != null) {
      final lastAiIdx = _currentMessages.indexOf(lastAiMsg);
      for (var i = lastAiIdx - 1; i >= 0; i--) {
        if (_currentMessages[i].role == 'user') {
          lastUserContent = _currentMessages[i].content;
          lastUserId = _currentMessages[i].id;
          break;
        }
      }
      final lastAiCreatedAt = lastAiMsg.createdAt;
      _currentMessages.removeWhere(
        (m) =>
            (m.role == 'assistant' || m.role == 'tool') &&
            !m.createdAt.isBefore(lastAiCreatedAt),
      );
      if (!isTemporary && db != null) {
        await db.popToolMessagesAfter(convId, lastAiMsg.id);
        await db.popLastAssistantMessage(convId);
      }
      _publishChatState();
    }

    if (lastUserContent == null || lastUserId == null) return;

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
    _startStreaming(convId, assistantMsgId);
    _publishChatState();

    await _streamAndPersistReply(
      messages: messages,
      msgCountBefore: msgCountBefore,
      assistantMsgId: assistantMsgId,
      userMessageId: lastUserId,
      convId: convId,
      db: db,
      svc: svc,
      exec: exec,
      isTemporary: isTemporary,
    );

    if (!isTemporary && db != null) {
      await db.touchConversation(convId);
    }
    _publishChatState();
  }

  // ---------------------------------------------------------------------------
  // 内部：Agent Loop 流式执行 + 持久化
  // ---------------------------------------------------------------------------

  /// 执行一次 Agent Loop 流式调用，处理所有事件并持久化结果。
  /// [messages] 会就地修改（追加 assistant + tool 消息）。
  /// [msgCountBefore] sendAgentLoop 调用前 messages 的长度，用于只持久化新增的 tool 消息。
  /// [isTemporary] 临时会话不写 DB，仅更新内存。
  Future<void> _streamAndPersistReply({
    required List<Map<String, Object?>> messages,
    required int msgCountBefore,
    required String assistantMsgId,
    required String userMessageId,
    required String convId,
    required ChatDatabase? db,
    required ChatCapability svc,
    required ToolExecutor exec,
    bool isTemporary = false,
  }) async {
    final contentBuf = StringBuffer();
    final toolCallsList = <Map<String, Object?>>[];
    String? agentError;

    try {
      await for (final event in svc.sendAgentLoop(
        messages: messages,
        thinkingEnabled: thinkingEnabled,
        validProjectIds: projectList.map((project) => project.id).toSet(),
        onToolCall: (call) {
          toolCallsList.add({
            'id': call.id,
            'type': 'function',
            'function': {
              'name': call.name,
              'arguments': jsonEncode(call.arguments),
            },
          });
        },
        executeTool: (call) async {
          final result = await exec.execute(call);
          return result;
        },
      )) {
        switch (event) {
          case ContentDelta(text: final t):
            contentBuf.write(t);
            _updateCurrentAssistantMessage(
              conversationId: convId,
              assistantMessageId: assistantMsgId,
              content: contentBuf.toString(),
            );
            _currentToolCallLabel = null;
            _publishChatState(throttled: true);
          case ReasoningDelta():
            break;
          case ToolCallsComplete():
            break;
          case AgentActivityEvent(label: final label):
            _currentToolCallLabel = label;
            _publishChatState();
          case AgentErrorEvent(message: final message):
            agentError = message;
          case StreamDone():
            break;
        }
      }
    } catch (e) {
      debugPrint('Sumi Agent Loop 错误: $e');
      agentError = '请求失败，请检查网络后重试。';
    }

    if (agentError != null) {
      _removeCurrentMessage(convId, assistantMsgId);
      _finishStreaming(assistantMsgId);
      _setChatFailure(
        convId,
        ChatFailure(
          userMessageId: userMessageId,
          message: agentError,
          retryable: toolCallsList.isEmpty,
        ),
      );
      _publishChatState();
      return;
    }

    // 持久化 AI 回复（临时会话仅内存）
    final finalContent = contentBuf.toString();
    if (finalContent.isNotEmpty) {
      final finalToolCallsJson = toolCallsList.isNotEmpty
          ? jsonEncode(toolCallsList)
          : null;

      _updateCurrentAssistantMessage(
        conversationId: convId,
        assistantMessageId: assistantMsgId,
        content: finalContent,
        toolCallsJson: finalToolCallsJson,
        insertIfMissing: true,
      );

      if (!isTemporary && db != null) {
        await db.saveMessage(
          ChatMessage(
            id: assistantMsgId,
            conversationId: convId,
            role: 'assistant',
            content: finalContent,
            createdAt: DateTime.now(),
            toolCallsJson: finalToolCallsJson,
          ),
        );
        scheduleLocalIndex();
      }
    } else {
      _removeCurrentMessage(convId, assistantMsgId);
    }

    // 持久化本轮新增的 tool 结果消息（临时会话仅内存）
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
        if (!isTemporary && db != null) {
          await db.saveMessage(toolMsg);
        }
        if (_isCurrentConversation(convId)) {
          _currentMessages = [..._currentMessages, toolMsg];
        }
      }
    }
    _finishStreaming(assistantMsgId);
    _publishChatState();
  }

  // ---------------------------------------------------------------------------
  // 内部：消息构建
  // ---------------------------------------------------------------------------

  Future<String> _buildSystemPrompt({String? greeting}) async {
    var hotPrompt = '';
    final query =
        _currentMessages
            .where((message) => message.role == 'user')
            .cast<ChatMessage?>()
            .lastWhere((message) => message != null, orElse: () => null)
            ?.content ??
        '';
    if (memoryService != null && query.isNotEmpty) {
      try {
        final memories = await memoryService!.hotForAgent(query);
        hotPrompt = memories.map((item) => '- ${item.content}').join('\n');
      } catch (e) {
        debugPrint('[chatContext] 记忆不可用，已跳过: $e');
      }
    }

    return ChatPromptBuilder.build(
      hotMemory: hotPrompt,
      projects: projectList
          .map(
            (project) => {
              'id': project.id,
              'name': project.name,
              'goal': project.goal,
              'currentMonthIndex': project.currentMonthIndex,
            },
          )
          .toList(),
      greeting: greeting,
    );
  }

  /// 构建 agent loop 用的消息上下文（07 轮：动态 system prompt + HOT/WARM 注入）。
  Future<List<Map<String, Object?>>> _buildMessagesContextForAgent({
    String? excludeMessageId,
  }) async {
    String? greeting;
    if (_activeGreeting != null && _currentMessages.length <= 1) {
      greeting = _activeGreeting;
      _activeGreeting = null;
    }
    final systemPrompt = await _buildSystemPrompt(greeting: greeting);

    final messages = <Map<String, Object?>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    final userQuery = _currentMessages
        .where((message) => message.role == 'user')
        .cast<ChatMessage?>()
        .lastWhere((message) => message != null, orElse: () => null)
        ?.content;
    if (userQuery != null && localRetrieval.shouldRetrieve(userQuery)) {
      try {
        _currentToolCallLabel = '正在查找你的学习记录';
        _publishChatState();
        final retrieved = await localRetrieval.retrieve(userQuery);
        if (retrieved.isNotEmpty) {
          messages.add({
            'role': 'system',
            'content': PromptContext.dataBlock(
              kind: 'local_retrieval',
              source: 'on_device_embedding',
              data: LocalRetrievalService.promptData(retrieved),
            ),
          });
        }
      } catch (error) {
        debugPrint('[localRetrieval] 已跳过: $error');
      } finally {
        _currentToolCallLabel = '正在生成回复';
        _publishChatState();
      }
    }

    final contextMessages = _selectCompleteTurns(
      excludeMessageId == null
          ? _currentMessages
          : _currentMessages
                .where((message) => message.id != excludeMessageId)
                .toList(),
    );

    for (final msg in contextMessages) {
      final map = <String, Object?>{'role': msg.role, 'content': msg.content};

      // tool 消息需要传回 tool_call_id
      if (msg.role == 'tool' && msg.toolCallId != null) {
        map['tool_call_id'] = msg.toolCallId;
      }

      // 传回 tool_calls（如果有，仅 assistant 消息）
      if (msg.toolCallsJson != null && msg.toolCallsJson!.isNotEmpty) {
        try {
          final tcList = jsonDecode(msg.toolCallsJson!) as List<Object?>;
          map['tool_calls'] = tcList;
        } catch (_) {}
      }

      messages.add(map);
    }

    return messages;
  }

  /// 从最新一轮向前选取完整轮次，避免从孤立 tool 消息开始。
  static List<ChatMessage> _selectCompleteTurns(
    List<ChatMessage> source, {
    int maxChars = 24000,
  }) {
    final userStarts = <int>[];
    for (var i = 0; i < source.length; i++) {
      if (source[i].role == 'user') userStarts.add(i);
    }
    if (userStarts.isEmpty) return const [];

    var start = userStarts.last;
    var total = 0;
    for (var turn = userStarts.length - 1; turn >= 0; turn--) {
      final turnStart = userStarts[turn];
      final turnEnd = turn + 1 < userStarts.length
          ? userStarts[turn + 1]
          : source.length;
      final turnChars = source
          .sublist(turnStart, turnEnd)
          .fold<int>(0, (sum, message) => sum + _messageContextLength(message));
      if (total > 0 && total + turnChars > maxChars) break;
      start = turnStart;
      total += turnChars;
    }
    final selected = source.sublist(start);
    final selectedChars = selected.fold<int>(
      0,
      (sum, message) => sum + message.content.length,
    );
    if (selectedChars <= maxChars) return selected;

    // 单个最新轮次也可能超限。保留完整消息序列，只压缩文本内容，
    // 这样 assistant/tool 的配对关系不会被截断破坏。
    var remaining = maxChars;
    final trimmed = List<ChatMessage>.of(selected);
    for (var i = trimmed.length - 1; i >= 0; i--) {
      final message = trimmed[i];
      if (message.content.length <= remaining) {
        remaining -= message.content.length;
        continue;
      }
      final content = remaining == 0
          ? ''
          : message.role == 'user'
          ? message.content.substring(0, remaining)
          : message.content.substring(message.content.length - remaining);
      trimmed[i] = message.copyWith(content: content);
      remaining = 0;
    }
    return trimmed;
  }

  static int _messageContextLength(ChatMessage message) {
    return message.content.length;
  }
}
