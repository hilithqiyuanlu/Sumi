import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../models/models.dart';
import '../../services/ai_service.dart';
import '../../services/memory_service.dart';
import '../../services/schedule_load_service.dart';
import '../../services/today_suggestion_mapper.dart';

import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';
import '../../utils/utils.dart';
import '../calendar/date_strip.dart';
import '../calendar/month_view_sheet.dart';
import '../chat/chat_bubble.dart';
import '../chat/chat_input.dart';
import '../todos/todo_chip_carousel.dart';
import '../todos/split_confirm_sheet.dart';
import 'settings_panel.dart';
import '../memory/memory_center_page.dart';
import '../projects/project_generation_page.dart';
import '../tools/tools_page.dart';
import 'side_drawer.dart';
import 'suggestion_strip.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _ScheduleRebalanceCard extends StatelessWidget {
  final ScheduleRebalanceProposal proposal;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDismiss;
  final Future<void> Function() onRequestAdvice;

  const _ScheduleRebalanceCard({
    required this.proposal,
    required this.onAccept,
    required this.onDismiss,
    required this.onRequestAdvice,
  });

  @override
  Widget build(BuildContext context) {
    final reason = proposal.reasons.isEmpty
        ? '今天的任务安排可能影响完成质量'
        : proposal.reasons.first;
    final moveCount = proposal.moves.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(s16, s12, s16, s4),
      child: Container(
        padding: const EdgeInsets.all(s14),
        decoration: BoxDecoration(
          color: primary50,
          borderRadius: BorderRadius.circular(radius8),
          border: Border.all(color: primary100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.calendar_month_outlined, color: primary500),
                SizedBox(width: s8),
                Text(
                  '安排较满',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: s8),
            Text(reason, style: const TextStyle(fontSize: 13, color: ink)),
            const SizedBox(height: s4),
            if (proposal.stage == ScheduleProposalStage.attention)
              const Text(
                '要我为你看看怎么调整吗？',
                style: TextStyle(fontSize: 13, color: textTertiary),
              )
            else if (proposal.stage == ScheduleProposalStage.completed)
              Text(
                '已调整 ${proposal.completedMoveCount ?? 0} 项事项。',
                style: const TextStyle(fontSize: 13, color: textTertiary),
              )
            else
              Text(
                moveCount > 0
                    ? '已准备将 $moveCount 项未完成事项移到后续较合适的日期。'
                    : '后续暂时没有相对可承受的日期，先保留原日期。',
                style: const TextStyle(fontSize: 13, color: textTertiary),
              ),
            if (proposal.stage == ScheduleProposalStage.preview &&
                moveCount > 0) ...[
              const SizedBox(height: s10),
              Text(
                proposal.moves
                    .take(3)
                    .map((move) => '${move.title} -> ${move.toDate}')
                    .join('\n'),
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: textTertiary,
                ),
              ),
            ],
            const SizedBox(height: s10),
            Row(
              children: [
                if (proposal.stage == ScheduleProposalStage.attention)
                  FilledButton(
                    onPressed: onRequestAdvice,
                    child: const Text('获取建议'),
                  ),
                if (proposal.stage == ScheduleProposalStage.preview &&
                    moveCount > 0)
                  FilledButton(onPressed: onAccept, child: const Text('确认调整')),
                if (proposal.stage != ScheduleProposalStage.completed)
                  const SizedBox(width: s8),
                if (proposal.stage != ScheduleProposalStage.completed)
                  TextButton(onPressed: onDismiss, child: const Text('忽略本次')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _drawerOpen = false;

  // 月视图动画
  late final AnimationController _monthController;
  static const _monthSpring = SpringDescription(
    mass: 1,
    stiffness: 250,
    damping: 22,
  );
  InputMode _inputMode = InputMode.todo;
  List<MemorySuggestion> _suggestions = [];
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  DateTime? _lastSelectedDate;
  int _lastDataVersion = 0;
  late final SumiStore _store;
  late ChatViewState _lastChatView;
  bool _isTodoGenerating = false;
  int _todoGenerationId = 0;
  String? _inputDraft;
  int _inputDraftRevision = 0;

  // 对话模式轻提示
  static const _chatGreetings = [
    '最近在忙什么有趣的事？',
    '有什么好奇想问的吗？',
    '今天学了什么新东西？',
    '最近有什么想聊的话题？',
    '今天过得怎么样？',
    '有什么我可以帮你的吗？',
    '最近在读什么书或者看什么课？',
    '有什么想尝试但还没开始的事吗？',
  ];
  String _chatGreeting = _chatGreetings[0];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _monthController = AnimationController(vsync: this);
    _monthController.addListener(() => setState(() {}));
    _refreshChatGreeting();
    _store = SumiScope.read(context);
    _lastSelectedDate = _store.selectedDate;
    _lastChatView = _store.chatView.value;
    _store.chatView.addListener(_onChatViewChanged);
    _store.projectGenerationController.addListener(_onProjectGenerationChanged);
    _generateSuggestions();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.chatView.removeListener(_onChatViewChanged);
    _store.projectGenerationController.removeListener(
      _onProjectGenerationChanged,
    );
    _scrollController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  void _onChatViewChanged() {
    final next = _store.chatView.value;
    if (next.messageSentSequence != _lastChatView.messageSentSequence) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollUserMessageToTop(),
      );
    }
    if (_lastChatView.isStreaming && !next.isStreaming) H.medium();
    _lastChatView = next;
  }

  void _onProjectGenerationChanged() {
    final session = _store.projectGenerationController.takePendingNavigation();
    if (session == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProjectGenerationPage(session: session),
        ),
      );
    });
  }

  // 07 轮：App 生命周期监听
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _generateSuggestions();
  }

  void _refreshChatGreeting() {
    _chatGreeting =
        _chatGreetings[DateTime.now().millisecond % _chatGreetings.length];
  }

  void _switchMode(InputMode mode) {
    if (mode == InputMode.chat && _inputMode != InputMode.chat) {
      _refreshChatGreeting();
    }
    setState(() => _inputMode = mode);
  }

  /// 常规建议慢刷新；当天建议复用负荷分析并随它实时变化。
  Future<void> _generateSuggestions() async {
    final store = SumiScope.read(context);

    final cached = store.cachedSuggestions;
    if (!store.suggestionsDirty && cached.isNotEmpty) {
      if (mounted) {
        setState(
          () => _suggestions = TodaySuggestionMapper.compose(
            regular: cached,
            today: store.todayLoadSuggestions,
          ),
        );
      }
      return;
    }
    try {
      final memory = store.memoryService;
      final stats = await store.legacyRealtimeStats();
      final regularCount = store.todayLoadSuggestions.isEmpty ? 5 : 3;
      final generated = memory == null
          ? TodaySuggestionMapper.fallbackRegular(count: regularCount)
          : await memory.createSuggestions(
              realtimeStats: stats,
              limit: regularCount,
            );
      final combined = TodaySuggestionMapper.compose(
        regular: generated,
        today: store.todayLoadSuggestions,
      );
      if (combined.isNotEmpty && mounted) {
        // Cache only the slow-changing half. Today's two prompts are always
        // recomposed from the newest semantic assessment.
        store.cachedSuggestions = generated;
        store.lastSuggestionTime = DateTime.now();
        store.setSuggestionsDirty(false);
        setState(() => _suggestions = combined);
      } else if (mounted) {
        store.cachedSuggestions = const [];
        store.setSuggestionsDirty(false);
        setState(() => _suggestions = const []);
      }
    } catch (_) {
      if (mounted && cached.isNotEmpty) setState(() => _suggestions = cached);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final offset = _scrollController.offset;
    setState(() {
      _showScrollToBottom = maxScroll > 0 && offset < maxScroll - 100;
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  /// 发送消息后，将用户消息滚动到视口顶部附近。
  void _scrollUserMessageToTop() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final viewport = _scrollController.position.viewportDimension;
    if (maxScroll <= 0) return;
    // 让最后一条用户消息出现在视口上方约 120px 处
    final target = (maxScroll - viewport + 120).clamp(0.0, maxScroll);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _closeDrawer() {
    setState(() => _drawerOpen = false);
  }

  void _openSettings() {
    SettingsPanel.show(context);
  }

  void _openMemory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MemoryCenterPage()),
    );
  }

  void _openTools() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ToolsPage()),
    );
  }

  Future<void> _openSearchResult(ChatSearchResult result) =>
      SumiScope.read(context).selectDate(result.date);

  void _handleSuggestionSelect(MemorySuggestion suggestion) {
    if (_isInputBusy) return;
    setState(() {
      _inputMode = InputMode.chat;
      _inputDraft = suggestion.text;
      _inputDraftRevision++;
    });
    if (suggestion.source != 'today_load') {
      final store = SumiScope.read(context);
      store.memoryService
          ?.recordSelected(suggestion)
          .then((_) => store.scheduleLocalIndex());
    }
  }

  Future<void> _handleSuggestionFeedback(
    MemorySuggestion suggestion,
    bool disableTopic,
  ) async {
    final store = SumiScope.read(context);
    if (suggestion.source != 'today_load') {
      await store.memoryService?.recordFeedback(
        suggestion,
        disableTopic: disableTopic,
      );
    }
    store.scheduleLocalIndex();
    if (!mounted) return;
    setState(
      () => _suggestions.removeWhere(
        (item) => item.eventId == suggestion.eventId,
      ),
    );
    store.setSuggestionsDirty(true);
    _generateSuggestions();
  }

  ChatSendResult _handleChatSend(String content) {
    final store = SumiScope.read(context);
    final result = store.sendMessage(content, currentGreeting: _chatGreeting);
    if (result == ChatSendResult.missingApiKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先设置 DeepSeek API Key'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '去设置',
            onPressed: () => SettingsPanel.show(context),
          ),
        ),
      );
    }
    return result;
  }

  bool get _isInputBusy =>
      _isTodoGenerating || _store.chatView.value.isStreaming;

  bool _isTodoGenerationActive(int id) =>
      mounted && _isTodoGenerating && _todoGenerationId == id;

  void _stopInputGeneration() {
    if (_isTodoGenerating) {
      _todoGenerationId++;
      setState(() => _isTodoGenerating = false);
      return;
    }
    _store.stopGenerating();
  }

  Future<void> _handleAddTodo(String title) async {
    final store = SumiScope.read(context);
    if (title.length <= SumiStore.todoTitleMaxLength) {
      final todo = await store.addUserTodo(title);
      if (todo == null || !mounted) return;
      return;
    }

    if (_isTodoGenerating) return;
    final operationId = ++_todoGenerationId;
    setState(() => _isTodoGenerating = true);
    SplitResult? result;
    try {
      result = await store.splitAndAddTodo(
        title,
        isCancelled: () => !_isTodoGenerationActive(operationId),
      );
    } finally {
      if (mounted && _todoGenerationId == operationId) {
        setState(() => _isTodoGenerating = false);
      }
    }
    final completed = _todoGenerationId == operationId;
    if (!mounted || !completed || result == null || !result.split) return;
    await showSplitConfirmSheet(context, store, result.items);
  }

  // ---------------------------------------------------------------------------
  // 月视图手势 & 动画
  // ---------------------------------------------------------------------------

  void _onMonthDragUpdate(DragUpdateDetails d) {
    _dismissKeyboard();
    final h = MediaQuery.of(context).size.height;
    _monthController.value = (_monthController.value + d.delta.dy / h).clamp(
      0.0,
      1.0,
    );
  }

  void _onMonthDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    // 有速度时按方向决定；慢拖时以 0.35 为界：展开易关，收起易开
    final bool shouldOpen;
    if (velocity.abs() > 250) {
      shouldOpen = velocity > 0;
    } else {
      shouldOpen = _monthController.value > 0.35;
    }
    final target = shouldOpen ? 1.0 : 0.0;
    _monthController.animateWith(
      SpringSimulation(
        _monthSpring,
        _monthController.value,
        target,
        velocity / MediaQuery.of(context).size.height,
      ),
    );
  }

  void _openMonthView() {
    _dismissKeyboard();
    _monthController.animateTo(
      1.0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watchTodos(context);
    SumiScope.watchProjects(context);
    SumiScope.watchSettings(context);
    SumiScope.watchSelection(context);
    final userName = store.appSettings.userName;
    final selectedDate = store.selectedDate;
    final isPast = dateOnly(selectedDate).isBefore(dateOnly(DateTime.now()));
    final isFuture = dateOnly(selectedDate).isAfter(dateOnly(DateTime.now()));

    // 检测日期切换 → 重载建议
    if (_lastSelectedDate != null &&
        !isSameDate(selectedDate, _lastSelectedDate!)) {
      _lastSelectedDate = selectedDate;
      _showScrollToBottom = false; // 日期切换时重置悬浮按钮状态
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _generateSuggestions();
      });
    }
    _lastSelectedDate ??= selectedDate;

    // 检测数据变更 → 刷新建议
    if (store.dataVersion != _lastDataVersion) {
      _lastDataVersion = store.dataVersion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _generateSuggestions();
      });
    }
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: paper,
      body: Stack(
        children: [
          // 主内容
          Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: _onMonthDragUpdate,
                onVerticalDragEnd: _onMonthDragEnd,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: s16,
                    right: s16,
                    top: topPadding + s16,
                    bottom: s8,
                  ),
                  child: DateStrip(onExpandMonth: _openMonthView),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Builder(
                  builder: (_) {
                    final sel = dateKey(dateOnly(store.selectedDate));
                    final todayKey = dateKey(dateOnly(DateTime.now()));
                    final hasDateTodos = store.todoItems.any(
                      (t) => TodoItem.belongsToDate(t, sel, todayKey),
                    );
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasDateTodos) const SizedBox(height: s8),
                        TodoChipCarousel(),
                      ],
                    );
                  },
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<ChatViewState>(
                  valueListenable: store.chatView,
                  builder: (context, chat, _) => GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: () {
                      final store = SumiScope.read(context);
                      final today = dateOnly(DateTime.now());
                      if (!isSameDate(store.selectedDate, today)) {
                        store.selectDate(today);
                      }
                    },
                    child: Stack(
                      children: [
                        if (chat.messages.isEmpty &&
                            !store.scheduleCards.any(
                              (card) =>
                                  card.conversationId == chat.conversationId,
                            ))
                          _buildEmptyState(store, userName)
                        else
                          _buildMessageList(chat, store),
                        // 顶部渐变遮罩 —— 衔接日历导航栏
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 24,
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [paper, paper.withValues(alpha: 0.0)],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: isPast ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 320),
                curve: isPast ? Curves.easeIn : Curves.easeOut,
                child: ClipRect(
                  child: AnimatedAlign(
                    alignment: Alignment.topCenter,
                    heightFactor: isPast ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    child: ValueListenableBuilder<ChatViewState>(
                      valueListenable: store.chatView,
                      builder: (context, chat, _) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SuggestionStrip(
                            suggestions: _suggestions,
                            onSelect: _handleSuggestionSelect,
                            onFeedback: _handleSuggestionFeedback,
                            enabled: !_isTodoGenerating && !chat.isStreaming,
                          ),
                          ChatInput(
                            mode: _inputMode,
                            isFutureDate: isFuture,
                            onSend: _handleChatSend,
                            onAddTodo: _handleAddTodo,
                            onModeChanged: _switchMode,
                            enabled: !_isTodoGenerating && !chat.isStreaming,
                            isStreaming: _isTodoGenerating || chat.isStreaming,
                            onStopGenerating: _stopInputGeneration,
                            voiceService: store.voiceService,
                            draftText: _inputDraft,
                            draftRevision: _inputDraftRevision,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // 滚动到底部按钮（位于月视图遮罩之下）
          _buildScrollToBottomButton(bottomPadding),
          // 月视图覆盖层 —— 跟手拖拽 + 弹簧吸附
          if (_monthController.value > 0.0)
            IgnorePointer(
              ignoring: _monthController.value < 0.01,
              child: GestureDetector(
                onVerticalDragUpdate: _onMonthDragUpdate,
                onVerticalDragEnd: _onMonthDragEnd,
                child: Transform.translate(
                  offset: Offset(
                    0,
                    (_monthController.value - 1) *
                        MediaQuery.of(context).size.height,
                  ),
                  child: const MonthViewSheet(),
                ),
              ),
            ),
          // 抽屉遮罩淡入，避免左边缘打开时出现整块黑屏。
          IgnorePointer(
            ignoring: !_drawerOpen,
            child: AnimatedOpacity(
              opacity: _drawerOpen ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: GestureDetector(
                onTap: _closeDrawer,
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity != null &&
                      details.primaryVelocity! > 0) {
                    _closeDrawer();
                  }
                },
                child: Container(color: Colors.black.withValues(alpha: 0.3)),
              ),
            ),
          ),
          SideDrawer(
            isOpen: _drawerOpen,
            onClose: _closeDrawer,
            onOpenSettings: _openSettings,
            onOpenMemory: _openMemory,
            onOpenTools: _openTools,
            onOpenSearchResult: _openSearchResult,
          ),
          // 左边缘手势区仅在抽屉关闭时存在，避免覆盖打开中的抽屉。
          if (!_drawerOpen) _buildGestureArea(topPadding, bottomPadding),
        ],
      ),
    );
  }

  Widget _buildEmptyState(SumiStore store, String userName) {
    final selected = dateOnly(store.selectedDate);
    final today = dateOnly(DateTime.now());
    final isFuture = selected.isAfter(today);
    final isPast = selected.isBefore(today);

    final String title;
    if (isPast) {
      title = '这一天没有对话';
    } else if (isFuture) {
      title = '前方的区域还没有开放，过段时间再来探索吧';
    } else if (_inputMode == InputMode.todo) {
      title = userName.isEmpty
          ? '嗨，今天要和 Sumi 一起做点什么？'
          : '嗨 $userName，今天要和 Sumi 一起做点什么？';
    } else {
      title = _chatGreeting;
    }

    return Align(
      alignment: const Alignment(0, -0.35),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: Text(
          title,
          key: ValueKey(title),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w300,
            color: ink,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList(ChatViewState chat, SumiStore store) {
    final messages = chat.messages;
    final filtered = messages
        .where((message) => message.role != 'tool')
        .toList(growable: false);
    String? streamingAssistantId;
    if (chat.isStreaming) {
      for (final message in chat.messages.reversed) {
        if (message.role == 'assistant') {
          streamingAssistantId = message.id;
          break;
        }
      }
    }

    String? latestUserMessageId;
    if (!chat.isStreaming) {
      for (final message in chat.messages.reversed) {
        if (message.role == 'user') {
          latestUserMessageId = message.id;
          break;
        }
      }
    }

    final cards = store.scheduleCards
        .where(
          (card) =>
              card.conversationId == chat.conversationId &&
              card.displayAnchorMessageId != streamingAssistantId,
        )
        .toList(growable: false);
    final placedCardIds = <String>{};
    final listItems = <Widget>[];
    void addCard(ScheduleRebalanceProposal card) {
      if (!placedCardIds.add(card.id)) return;
      listItems.add(
        _ScheduleRebalanceCard(
          proposal: card,
          onAccept: store.acceptScheduleProposal,
          onDismiss: store.dismissScheduleProposal,
          onRequestAdvice: store.requestScheduleAdvice,
        ),
      );
    }

    for (final message in filtered) {
      for (final card in cards) {
        if (card.displayAnchorMessageId == null &&
            !card.updatedAt.isAfter(message.createdAt)) {
          addCard(card);
        }
      }
      final originalIndex = messages.indexOf(message);
      listItems.add(
        ChatBubble(
          content: message.content,
          isUser: message.role == 'user',
          isStreaming: message.id == streamingAssistantId,
          timestamp: message.role == 'user' ? message.createdAt : null,
          activityLabel: message.id == streamingAssistantId
              ? chat.activityLabel
              : null,
          toolCallsJson: message.toolCallsJson,
          timerController: store.timerController,
          onStartTimer: store.startStudyTimer,
          onPauseTimer: store.pauseStudyTimer,
          onFinishTimer: store.finishStudyTimer,
          onCancelTimer: store.cancelStudyTimer,
          projectGenerationController: store.projectGenerationController,
          onDelete: message.role == 'user'
              ? () => store.deleteMessagePair(originalIndex)
              : null,
          onEdit: message.role == 'user' && message.id == latestUserMessageId
              ? (content) => store.editAndResendMessage(
                  originalIndex,
                  content,
                  currentGreeting: _chatGreeting,
                )
              : null,
        ),
      );
      for (final card in cards) {
        if (card.displayAnchorMessageId == message.id) addCard(card);
      }
    }
    for (final card in cards) {
      addCard(card);
    }
    if (chat.failure != null) {
      listItems.add(_buildChatFailure(chat.failure!, store));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: ListView(
        key: ValueKey(chat.conversationId),
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: s16),
        children: listItems,
      ),
    );
  }

  Widget _buildChatFailure(ChatFailure failure, SumiStore store) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(s16, s4, s16, s8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.fromLTRB(s12, s10, s8, s10),
          decoration: BoxDecoration(
            color: danger.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(radiusCard),
            border: Border.all(color: danger.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 18, color: danger),
              const SizedBox(width: s8),
              Flexible(
                child: Text(
                  failure.message,
                  style: const TextStyle(fontSize: 13, color: ink),
                ),
              ),
              if (failure.retryable) ...[
                const SizedBox(width: s4),
                TextButton(
                  onPressed: store.retryLastFailedMessage,
                  child: const Text('重试'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGestureArea(double topSafe, double bottomSafe) {
    // 仅覆盖内容区域，避开顶部的 DateStrip（~144px）和底部的输入栏（~90px），
    // 避免 HorizontalDragGestureRecognizer 与子控件的 tap / vertical drag 竞争。
    final inputArea = bottomSafe + 90;
    final dateStripArea = topSafe + 144;
    return Positioned(
      left: 0,
      top: dateStripArea,
      bottom: inputArea,
      width: 60,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) {
          if (details.delta.dx > 6 && !_drawerOpen) {
            H.light();
            _dismissKeyboard();
            setState(() => _drawerOpen = true);
          } else if (details.delta.dx < -6 && _drawerOpen) {
            setState(() => _drawerOpen = false);
          }
        },
        child: Container(color: Colors.transparent),
      ),
    );
  }

  Widget _buildScrollToBottomButton(double bottomSafe) {
    if (!_showScrollToBottom) return const SizedBox.shrink();

    // ChatInput ≈ s16(top) + 60(container) + bottomSafe + s8(const)
    // SuggestionStrip ≈ 40px, + 32px clearance
    final inputBottom = 16 + 60 + bottomSafe + 8; // ~84 + bottomSafe
    final suggestionHeight = 40.0;
    final clearance = 32.0;
    final btnBottom = inputBottom + suggestionHeight + clearance;

    return Positioned(
      bottom: btnBottom,
      right: s16,
      child: GestureDetector(
        onTap: _scrollToBottom,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: paper,
            shape: BoxShape.circle,
            boxShadow: const [...shadow2],
          ),
          child: const Icon(
            Icons.keyboard_arrow_down,
            size: 22,
            color: primary500,
          ),
        ),
      ),
    );
  }
}
