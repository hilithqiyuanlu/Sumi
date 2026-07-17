part of 'sumi_store.dart';

enum ChatSendResult { accepted, empty, busy, missingApiKey }

// ---------------------------------------------------------------------------
// Chat Mutations mixin
// ---------------------------------------------------------------------------

mixin SumiStoreChat {
  ChatDatabase? get chatDatabase;
  ChatCapability? get chatAgent;
  ToolExecutor? get toolExecutor;
  DateTime get selectedDate;
  DateTime get currentTime;
  set selectedDate(DateTime d);
  void triggerNavigateToToday();
  MemoryService? get memoryService;
  MemoryExtractionService? get memoryExtractionService;
  AppSettings get appSettings;
  List<Project> get projectList;
  ChatController get chatController;
  LocalRetrievalService get localRetrieval;
  String? get currentProjectId;
  void scheduleLocalIndex();
  Future<void> refreshScheduleCardsForConversation(String? conversationId);
  Future<void> releaseScheduleCardsAfterStream(
    String conversationId,
    String assistantMessageId,
  );
  Future<void> processMilestoneMessage({
    required String messageId,
    required String message,
  });
  Future<void> removeSourcesForMessages(Iterable<String> messageIds);
  Future<void> deleteStudyTimersForMessages(Iterable<ChatMessage> messages);
  MilestoneService get milestones;
  StructuredGenerationCapability? get structuredAi;
  Future<TodoItem?> addUserTodo(
    String title, {
    String? condensedFrom,
    String? date,
    String? body,
    String? reminderTime,
  });

  // --- 状态 ---
  String? _currentConversationId;
  String? _currentDateKey;
  int _conversationLoadRequest = 0;
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
  StreamIterator<StreamEvent>? _activeAgentIterator;
  Future<void>? _activeSendTask;
  final Set<Future<void>> _postStreamTasks = <Future<void>>{};
  bool _stopRequested = false;

  /// 用户发起对话时的首页问候语（仅首条消息注入一次上下文）
  String? _activeGreeting;
  String? _activeToolDefaultDate;
  String? _todoDraft;
  Set<String> _milestoneSourceMessageIds = <String>{};
  Set<String> _memorySourceMessageIds = <String>{};
  ChatMessage? _pendingUserMessage;

  String? get currentConversationId => _currentConversationId;
  String? get streamingAssistantMessageId =>
      _isStreaming && _streamConversationId == _currentConversationId
      ? _streamAssistantMessageId
      : null;
  List<ChatMessage> get currentMessages => List.unmodifiable(_currentMessages);
  bool get isStreaming => _isStreaming;
  bool get isLoadingConversation => _isLoadingConversation;
  String? get currentToolCallLabel => _currentToolCallLabel;
  bool get isTemporaryConversation => _isTemporaryConversation;
  String? get activeToolDefaultDate => _activeToolDefaultDate;
  ValueListenable<ChatViewState> get chatView => chatController.view;

  void recordMilestoneSource(String messageId) {
    if (!_milestoneSourceMessageIds.add(messageId)) return;
    _publishChatState();
  }

  void removeMilestoneSources(Iterable<String> messageIds) {
    final before = _milestoneSourceMessageIds.length;
    _milestoneSourceMessageIds.removeAll(messageIds);
    if (_milestoneSourceMessageIds.length == before) return;
    _publishChatState();
  }

  void recordMemorySource(String messageId) {
    if (!_memorySourceMessageIds.add(messageId)) return;
    _publishChatState();
  }

  void removeMemorySources(Iterable<String> messageIds) {
    final before = _memorySourceMessageIds.length;
    _memorySourceMessageIds.removeAll(messageIds);
    if (_memorySourceMessageIds.length == before) return;
    _publishChatState();
  }

  void _processPersistedUserMessage(
    ChatMessage message, {
    required String source,
  }) {
    unawaited(
      processMilestoneMessage(messageId: message.id, message: message.content),
    );
    final extractor = memoryExtractionService;
    if (extractor != null) {
      unawaited(
        extractor.process(
          messageId: message.id,
          message: message.content,
          source: source,
        ),
      );
    }
  }

  ChatSendResult sendUnifiedMessage(String content, {String? currentGreeting}) {
    final text = content.trim();
    if (text.isEmpty) return ChatSendResult.empty;
    if (calendarDayMode(selectedDate, currentTime) != CalendarDayMode.today) {
      return ChatSendResult.empty;
    }
    if (_isStreaming) return ChatSendResult.busy;
    final defaultDate = dateKey(selectedDate);
    _pendingUserMessage = ChatMessage(
      id: newSumiId('pending'),
      conversationId: _currentConversationId ?? '',
      role: 'user',
      content: text,
      createdAt: DateTime.now(),
    );
    _isStreaming = true;
    _streamConversationId = _currentConversationId;
    _streamAssistantMessageId = null;
    _currentToolCallLabel = '正在理解输入';
    _publishChatState();
    unawaited(
      _routeUnifiedInput(
        text,
        defaultDate: defaultDate,
        currentGreeting: currentGreeting,
      ),
    );
    return ChatSendResult.accepted;
  }

  Future<void> _routeUnifiedInput(
    String text, {
    required String defaultDate,
    String? currentGreeting,
  }) async {
    if (_shouldRouteToAgentTool(text)) {
      _todoDraft = null;
      _isStreaming = false;
      _currentToolCallLabel = null;
      _publishChatState();
      final result = sendMessage(text, currentGreeting: currentGreeting);
      if (result != ChatSendResult.accepted) {
        _pendingUserMessage = null;
        _publishChatState();
      }
      return;
    }

    InputClassification? decision;
    try {
      decision = await structuredAi?.classifyInput(text, draft: _todoDraft);
    } catch (_) {
      // 高确定性的创建命令仍可由本地规则兜底；其他输入按聊天处理。
    }

    final explicitTitle = _explicitTodoTitle(text);
    final classifiedTitle = decision?.title?.trim() ?? '';
    final missingOnlyDate =
        decision?.intent == InputIntent.clarifyTodo &&
        classifiedTitle.isNotEmpty &&
        decision!.missingFields.isNotEmpty &&
        decision.missingFields.every((field) => field == 'date');
    final modelWantsTodo =
        decision?.intent == InputIntent.createTodo || missingOnlyDate;
    final confidence = decision?.confidence ?? 0;
    final canDefaultMissingDate =
        modelWantsTodo &&
        classifiedTitle.isNotEmpty &&
        (decision?.date?.isEmpty ?? true) &&
        confidence >= 0.65;
    final canTrustModel =
        modelWantsTodo &&
        classifiedTitle.isNotEmpty &&
        (confidence >= 0.72 || canDefaultMissingDate || explicitTitle != null);
    var title = canTrustModel ? classifiedTitle : explicitTitle;

    if (title != null && title.isNotEmpty) {
      if (title.length > AppStore.todoTitleMaxLength) {
        title = (await structuredAi?.polishTodo(title))?.trim() ?? title;
      }
      await _recordTodoCreation(
        text,
        InputClassification(
          intent: InputIntent.createTodo,
          confidence: decision?.confidence ?? 1,
          title: title,
          date: (decision?.date?.isNotEmpty ?? false)
              ? decision!.date
              : defaultDate,
          reminderTime: decision?.reminderTime,
        ),
      );
      _todoDraft = null;
      return;
    }

    try {
      final lacksTodoFields =
          decision != null && (decision.title?.trim().isEmpty ?? true);
      final shouldClarify =
          decision != null &&
          (decision.intent == InputIntent.clarifyTodo ||
              (decision.intent == InputIntent.createTodo &&
                  (lacksTodoFields || decision.confidence >= 0.65)));
      if (shouldClarify) {
        _todoDraft = _todoDraft == null ? text : '$_todoDraft\n$text';
        final question =
            decision.clarification ??
            ((decision.title?.trim().isEmpty ?? true)
                ? '要记下什么事项？'
                : '你要我把它记成待办吗？');
        await _recordClarification(text, question);
        return;
      }
    } catch (_) {
      // 分类不可用时按普通聊天处理，绝不创建事项。
    }
    _todoDraft = null;
    _isStreaming = false;
    _currentToolCallLabel = null;
    _publishChatState();
    final result = sendMessage(text, currentGreeting: currentGreeting);
    if (result != ChatSendResult.accepted) {
      _pendingUserMessage = null;
      _publishChatState();
    }
  }

  String? _explicitTodoTitle(String text) {
    final value = text.trim();
    final patterns = <RegExp>[
      RegExp(
        r'^(?:请|麻烦)?(?:你)?(?:帮我)?(?:创建|新建|添加|加上|加)(?:一下)?(?:一个|个|一条)?(?:待办事项|待办|事项|任务)',
      ),
      RegExp(
        r'^(?:请|麻烦)?(?:你)?(?:帮我)?(?:记下|记录)(?:一下)?(?:一个|个|一条)?(?:待办事项|待办|事项|任务)?',
      ),
      RegExp(r'^(?:请|麻烦)?(?:你)?提醒我'),
      RegExp(r'^(?:请|麻烦)?(?:你)?帮我记(?:一下|下来)?'),
    ];
    for (final pattern in patterns) {
      if (!pattern.hasMatch(value)) continue;
      final title = value
          .replaceFirst(pattern, '')
          .replaceFirst(RegExp(r'^[\s，,。：:]+'), '')
          .trim();
      return title.length >= 2 ? title : null;
    }
    return null;
  }

  bool _shouldRouteToAgentTool(String text) {
    final value = text.trim();
    final explicitlyTodo = RegExp(r'待办事项|待办|事项|任务').hasMatch(value);
    if (explicitlyTodo) return false;

    // 项目、学习计划、课程规划等应交给 Agent 工具处理，不要创建为待办。
    if (RegExp(
      r'(?:创建|新建|规划|制定).{0,8}(?:项目|计划|学习|课程|路径|方案)',
    ).hasMatch(value)) {
      return true;
    }

    if (RegExp(r'计时器|倒计时|闹钟').hasMatch(value)) return true;
    return RegExp(
      r'(?:提醒我.{0,12}(?:\d+|[一二两三四五六七八九十半]+)(?:秒|分钟|小时)后|(?:\d+|[一二两三四五六七八九十半]+)(?:秒|分钟|小时)后.{0,12}提醒我)',
    ).hasMatch(value);
  }

  Future<void> _recordClarification(String userText, String question) async {
    await _ensureInputConversation();
    final convId = _currentConversationId!;
    final messages = [
      ChatMessage(
        id: newSumiId('msg'),
        conversationId: convId,
        role: 'user',
        content: userText,
        createdAt: DateTime.now(),
      ),
      ChatMessage(
        id: newSumiId('msg'),
        conversationId: convId,
        role: 'assistant',
        content: question,
        createdAt: DateTime.now(),
      ),
    ];
    await _appendDirectMessages(messages);
  }

  Future<void> _recordTodoCreation(
    String userText,
    InputClassification decision,
  ) async {
    final todo = await addUserTodo(
      decision.title!.trim(),
      date: decision.date,
      reminderTime: decision.reminderTime,
    );
    if (todo == null) return;
    await _ensureInputConversation();
    final convId = _currentConversationId!;
    final messages = [
      ChatMessage(
        id: newSumiId('msg'),
        conversationId: convId,
        role: 'user',
        content: userText,
        createdAt: DateTime.now(),
      ),
      ChatMessage(
        id: newSumiId('msg'),
        conversationId: convId,
        role: 'assistant',
        content: '已创建事项',
        createdAt: DateTime.now(),
        todoResultJson: jsonEncode({
          'todoId': todo.id,
          'title': todo.title,
          'date': todo.date,
          'reminderTime': todo.reminderTime,
        }),
      ),
    ];
    await _appendDirectMessages(messages);
  }

  Future<void> _ensureInputConversation() async {
    final today = dateKey(currentTime);
    await _getOrCreateConversationForDate(today);
  }

  Future<void> _appendDirectMessages(List<ChatMessage> messages) async {
    final db = chatDatabase;
    final temporary = _isTemporaryConversation;
    if (!temporary && db != null) {
      for (final message in messages) {
        await db.saveMessage(message);
      }
      await db.touchConversation(_currentConversationId!);
    }
    _currentMessages = [..._currentMessages, ...messages];
    _pendingUserMessage = null;
    for (final message in messages) {
      if (message.role == 'user' && !temporary) {
        _processPersistedUserMessage(message, source: 'unified_input');
      }
    }
    _messageSentSequence++;
    _isStreaming = false;
    _currentToolCallLabel = null;
    if (!temporary) scheduleLocalIndex();
    _publishChatState();
  }

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
        _isStreaming &&
        (_streamConversationId == null ||
            _streamConversationId == _currentConversationId);
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
      milestoneSourceMessageIds: Set.unmodifiable(_milestoneSourceMessageIds),
      memorySourceMessageIds: Set.unmodifiable(_memorySourceMessageIds),
      pendingUserMessage: _pendingUserMessage,
    );
  }

  bool _isCurrentConversation(String conversationId) =>
      _currentConversationId == conversationId;

  void _startStreaming(String conversationId, String assistantMessageId) {
    if (_stopRequested) return;
    _isStreaming = true;
    _streamConversationId = conversationId;
    _streamAssistantMessageId = assistantMessageId;
    _activeToolDefaultDate = dateKey(selectedDate);
  }

  void _finishStreaming(String assistantMessageId) {
    if (_streamAssistantMessageId != assistantMessageId) return;
    final conversationId = _streamConversationId;
    _isStreaming = false;
    _streamConversationId = null;
    _streamAssistantMessageId = null;
    _currentToolCallLabel = null;
    _activeToolDefaultDate = null;
    if (conversationId != null) {
      final task = releaseScheduleCardsAfterStream(
        conversationId,
        assistantMessageId,
      );
      _postStreamTasks.add(task);
      unawaited(
        task.whenComplete(() {
          _postStreamTasks.remove(task);
        }),
      );
    }
  }

  /// Stops the active response while preserving content received so far.
  void stopGenerating() {
    final iterator = _activeAgentIterator;
    if (!_isStreaming) return;
    _stopRequested = true;
    if (iterator != null) unawaited(iterator.cancel());
    final assistantMessageId = _streamAssistantMessageId;
    if (assistantMessageId != null) {
      _finishStreaming(assistantMessageId);
    } else {
      _isStreaming = false;
      _streamConversationId = null;
      _currentToolCallLabel = null;
      _activeToolDefaultDate = null;
    }
    _pendingUserMessage = null;
    _publishChatState();
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

  Future<void> disposeChatView() async {
    _chatPublishTimer?.cancel();
    _stopRequested = true;
    await _activeAgentIterator?.cancel();
    final sendTask = _activeSendTask;
    if (sendTask != null) {
      try {
        await sendTask;
      } catch (_) {
        // 发送错误已由聊天状态处理，关闭流程只需等待它结束。
      }
    }
    if (_postStreamTasks.isNotEmpty) {
      await Future.wait(_postStreamTasks.toList(growable: false));
    }
  }

  // ---------------------------------------------------------------------------
  // 日期驱动会话
  // ---------------------------------------------------------------------------

  /// 今天可创建会话；过去只读取已有会话；未来没有会话。
  Future<void> _getOrCreateConversationForDate(String targetDateKey) async {
    final db = chatDatabase;
    final parsedDate = DateTime.tryParse(targetDateKey) ?? currentTime;
    final mode = calendarDayMode(parsedDate, currentTime);
    if (_currentDateKey == targetDateKey && _isLoadingConversation) return;
    if (_currentDateKey == targetDateKey &&
        (mode != CalendarDayMode.today || _currentConversationId != null)) {
      return;
    }

    final request = ++_conversationLoadRequest;
    _isLoadingConversation = true;
    _currentDateKey = targetDateKey;
    // 立即移除上一天的数据。否则异步读取期间会把旧会话误显示在新日期下。
    _currentConversationId = null;
    _currentMessages = [];
    _milestoneSourceMessageIds = <String>{};
    _memorySourceMessageIds = <String>{};
    _isTemporaryConversation = false;
    unawaited(refreshScheduleCardsForConversation(null));
    _publishChatState();

    bool isCurrentRequest() =>
        request == _conversationLoadRequest && _currentDateKey == targetDateKey;

    if (mode == CalendarDayMode.future) {
      if (!isCurrentRequest()) return;
    } else {
      if (db == null) {
        if (!isCurrentRequest()) return;
        _isLoadingConversation = false;
        _publishChatState();
        return;
      }
      Conversation? conv = await db.findConversationByDate(targetDateKey);
      if (conv == null && mode == CalendarDayMode.today) {
        conv = await db.createConversationForDate(targetDateKey);
      }
      if (!isCurrentRequest()) return;

      if (conv != null) {
        final messages = await db.loadMessages(conv.id);
        final milestoneSourceIds = await milestones.sourceMessageIdsFor(
          messages.map((message) => message.id),
        );
        final memorySourceIds =
            await memoryService?.sourceMessageIdsFor(
              messages.map((message) => message.id),
            ) ??
            <String>{};
        if (!isCurrentRequest()) return;
        _currentConversationId = conv.id;
        _currentMessages = messages;
        _milestoneSourceMessageIds = milestoneSourceIds;
        _memorySourceMessageIds = memorySourceIds;
      }
    }

    if (!isCurrentRequest()) return;
    _isLoadingConversation = false;
    await refreshScheduleCardsForConversation(_currentConversationId);
    if (!isCurrentRequest()) return;
    _publishChatState();
  }

  /// 删除一个消息对：从指定 user 消息开始，直到下一个 user 消息（或末尾）。
  Future<void> deleteMessagePair(int userMsgIndex) async {
    if (calendarDayMode(selectedDate, currentTime) != CalendarDayMode.today) {
      return;
    }
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

    final messagesToDelete = _currentMessages.sublist(
      userMsgIndex,
      endIndex + 1,
    );
    await deleteStudyTimersForMessages(messagesToDelete);

    // 从 DB 和内存中删除（临时会话仅内存）
    if (!_isTemporaryConversation && db != null) {
      await db.deleteMessagesByIds(idsToDelete);
      await removeSourcesForMessages(idsToDelete);
    }
    _currentMessages.removeRange(userMsgIndex, endIndex + 1);
    scheduleLocalIndex();
    _publishChatState();
  }

  /// 编辑最新一条用户消息时，从该消息起清除后续对话后重新发送。
  ///
  /// 更早的用户消息不允许编辑，避免历史回答与其依赖的上下文脱节。
  Future<ChatSendResult> editAndResendMessage(
    int userMsgIndex,
    String content, {
    String? currentGreeting,
  }) async {
    final trimmed = content.trim();
    if (calendarDayMode(selectedDate, currentTime) != CalendarDayMode.today) {
      return ChatSendResult.empty;
    }
    if (trimmed.isEmpty) return ChatSendResult.empty;
    if (_isStreaming) return ChatSendResult.busy;
    if (userMsgIndex < 0 || userMsgIndex >= _currentMessages.length) {
      return ChatSendResult.empty;
    }
    if (_currentMessages[userMsgIndex].role != 'user' ||
        _currentMessages
            .skip(userMsgIndex + 1)
            .any((message) => message.role == 'user')) {
      return ChatSendResult.empty;
    }
    if (chatAgent == null || toolExecutor == null) {
      return ChatSendResult.missingApiKey;
    }

    final messagesToRemove = _currentMessages.sublist(userMsgIndex);
    await deleteStudyTimersForMessages(messagesToRemove);
    if (!_isTemporaryConversation && chatDatabase != null) {
      await chatDatabase!.deleteMessagesByIds(
        messagesToRemove.map((message) => message.id).toList(),
      );
      await removeSourcesForMessages(
        messagesToRemove.map((message) => message.id),
      );
    }
    _currentMessages.removeRange(userMsgIndex, _currentMessages.length);
    _chatFailure = null;
    _chatFailureConversationId = null;
    scheduleLocalIndex();
    _publishChatState();

    return sendMessage(trimmed, currentGreeting: currentGreeting);
  }

  /// 清除全部对话数据。
  Future<void> clearChatData() async {
    final db = chatDatabase;
    if (db != null) {
      final messages = await db.loadAllMessages();
      await deleteStudyTimersForMessages(messages);
      await removeSourcesForMessages(messages.map((message) => message.id));
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
    if (calendarDayMode(selectedDate, currentTime) != CalendarDayMode.today) {
      return ChatSendResult.empty;
    }
    if (_isStreaming) return ChatSendResult.busy;

    final db = chatDatabase;
    final svc = chatAgent;
    final exec = toolExecutor;
    if (svc == null || exec == null) {
      debugPrint('[sendMessage] chatAgent 或 toolExecutor 为 null，无法发送');
      return ChatSendResult.missingApiKey;
    }

    _isStreaming = true;
    _stopRequested = false;
    _streamConversationId = _currentConversationId;
    _streamAssistantMessageId = null;
    _chatFailure = null;
    _chatFailureConversationId = null;
    _currentToolCallLabel = '正在生成回复';
    _publishChatState();
    final task = _sendAcceptedMessage(
      trimmed,
      currentGreeting: currentGreeting,
      db: db,
      svc: svc,
      exec: exec,
    );
    _activeSendTask = task;
    unawaited(
      task.whenComplete(() {
        if (identical(_activeSendTask, task)) _activeSendTask = null;
      }),
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

    final today = dateKey(currentTime);

    String? userMessageId;
    String? assistantMessageId;
    String? conversationId;
    try {
      await _getOrCreateConversationForDate(today);
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
      _pendingUserMessage = null;
      if (!isTemporary) scheduleLocalIndex();
      if (!isTemporary) {
        _processPersistedUserMessage(userMsg, source: 'chat');
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
    if (calendarDayMode(selectedDate, currentTime) != CalendarDayMode.today) {
      return;
    }
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
    _stopRequested = false;
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

    final iterator = StreamIterator(
      svc.sendAgentLoop(
        messages: messages,
        validProjectIds: projectList.map((project) => project.id).toSet(),
        enabledTools: appSettings.enabledTools.toSet(),
        onToolCall: (call) {
          if (_stopRequested) return;
          toolCallsList.add({
            'id': call.id,
            'type': 'function',
            'function': {
              'name': call.name,
              'arguments': jsonEncode(call.arguments),
            },
          });
          _updateCurrentAssistantMessage(
            conversationId: convId,
            assistantMessageId: assistantMsgId,
            content: contentBuf.toString(),
            toolCallsJson: jsonEncode(toolCallsList),
            insertIfMissing: true,
          );
          _publishChatState();
        },
        executeTool: (call) async {
          if (_stopRequested) return '用户已停止生成。';
          final result = await exec.execute(call);
          return result;
        },
      ),
    );
    _activeAgentIterator = iterator;
    try {
      while (!_stopRequested && await iterator.moveNext()) {
        if (_stopRequested) break;
        final event = iterator.current;
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
      if (!_stopRequested) {
        debugPrint('Sumi Agent Loop 错误: $e');
        agentError = '请求失败，请检查网络后重试。';
      }
    } finally {
      if (identical(_activeAgentIterator, iterator)) {
        _activeAgentIterator = null;
      }
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

  Future<String> _buildSystemPrompt({
    String? greeting,
    required String query,
    Map<String, double> memorySemanticScores = const {},
    required DateTime localNow,
    required DateTime conversationDate,
  }) async {
    var hotPrompt = '';
    if (memoryService != null && query.isNotEmpty) {
      try {
        final memories = await memoryService!.hotForAgent(
          query,
          semanticScores: memorySemanticScores,
        );
        hotPrompt = memories
            .map(
              (item) =>
                  '- [${item.type.name}/${item.category}] ${item.content}',
            )
            .join('\n');
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
      localNow: localNow,
      selectedDate: conversationDate,
      enabledTools: appSettings.enabledTools,
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
    final userQuery = _currentMessages
        .where((message) => message.role == 'user')
        .cast<ChatMessage?>()
        .lastWhere((message) => message != null, orElse: () => null)
        ?.content;
    var retrieved = const <HybridRetrievalResult>[];
    if (userQuery != null && localRetrieval.shouldRetrieve(userQuery)) {
      try {
        _currentToolCallLabel = '正在查找你的学习记录';
        _publishChatState();
        retrieved = await localRetrieval.retrieve(userQuery, limit: 10);
      } catch (error) {
        debugPrint('[localRetrieval] 已跳过: $error');
      } finally {
        _currentToolCallLabel = '正在生成回复';
        _publishChatState();
      }
    }

    final memorySemanticScores = <String, double>{
      for (final result in retrieved)
        if (result.document.source == EmbeddingDocumentSource.userMemory)
          result.document.sourceId: result.semanticScore,
    };
    final localNow = DateTime.now();
    final conversationDate = selectedDate;
    final systemPrompt = await _buildSystemPrompt(
      greeting: greeting,
      query: userQuery ?? '',
      memorySemanticScores: memorySemanticScores,
      localNow: localNow,
      conversationDate: conversationDate,
    );
    final messages = <Map<String, Object?>>[
      {'role': 'system', 'content': systemPrompt},
    ];
    final nonMemoryResults = retrieved
        .where(
          (result) =>
              result.document.source != EmbeddingDocumentSource.userMemory,
        )
        .take(6)
        .toList(growable: false);
    if (nonMemoryResults.isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': PromptContext.dataBlock(
          kind: 'local_retrieval',
          source: 'on_device_embedding',
          data: LocalRetrievalService.promptData(nonMemoryResults),
        ),
      });
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
