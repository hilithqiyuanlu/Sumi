import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../models/models.dart';
import '../../services/schedule_load_service.dart';

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
import '../todos/todo_edit_sheet.dart';
import '../todos/split_confirm_sheet.dart';
import 'settings_panel.dart';
import '../memory/memory_center_page.dart';
import '../projects/project_generation_page.dart';
import '../tools/tools_page.dart';
import 'side_drawer.dart';
import 'suggestion_strip.dart';
import 'daily_reflection_card.dart';

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
  List<SuggestionQuestion> _suggestions = const [];
  SuggestionQuestion? _draftedSuggestion;
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  DateTime? _lastSelectedDate;
  int _lastDataVersion = 0;
  bool _lastSuggestionsDirty = true;
  late final SumiStore _store;
  late ChatViewState _lastChatView;
  String? _inputDraft;
  int _inputDraftRevision = 0;
  final Map<String, String> _draftsByDate = {};
  String? _handledFutureTodoRequestId;

  // 对话轻提示
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

  // 未来日期问候语（随机轮播）
  static const _futureGreetings = [
    '这一天还没到，可以先安排事项',
    '前方的区域还没有开放，过段时间再来探索吧',
    '先写一下待办，让我看看这 O 不 OK',
    '你说，我记 (´・ω・`)',
    '提前写下 Todo，就等这天到了',
    '需要 Sumi 帮你记点啥，随便讲',
    '预言一波，你记不过我你信吗 (っ●ω●)っ',
    '₍^. .^₎⟆ ₍^. .^₎⟆ ₍^. .^₎⟆',
    '404 not found，过段时间再来探索吧',
    '快点 do something 啊 (╯°□°)╯︵ ┻━┻',
  ];
  String _futureGreeting = _futureGreetings[0];
  Timer? _futureGreetingTimer;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _monthController = AnimationController(vsync: this);
    _monthController.addListener(() => setState(() {}));
    _refreshChatGreeting();
    _pickRandomFutureGreeting();
    _store = SumiScope.read(context);
    _lastSelectedDate = _store.selectedDate;
    _lastSuggestionsDirty = _store.suggestionsDirty;
    _lastChatView = _store.chatView.value;
    _store.chatView.addListener(_onChatViewChanged);
    _store.projectGenerationController.addListener(_onProjectGenerationChanged);
    _store.dailyReflectionController.addListener(_onDailyReflectionChanged);
    _store.futureTodoController.state.addListener(_onFutureTodoChanged);
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
    _store.dailyReflectionController.removeListener(_onDailyReflectionChanged);
    _store.futureTodoController.state.removeListener(_onFutureTodoChanged);
    _scrollController.dispose();
    _monthController.dispose();
    _futureGreetingTimer?.cancel();
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

  void _onDailyReflectionChanged() {
    if (mounted) setState(() {});
  }

  void _onFutureTodoChanged() {
    if (!mounted) return;
    final state = _store.futureTodoController.state.value;
    if (state.stage == FutureTodoComposeStage.cancelled &&
        state.targetDate != null) {
      _draftsByDate[state.targetDate!] = state.originalInput;
      if (state.targetDate == dateKey(_store.selectedDate)) {
        _inputDraft = state.originalInput;
        _inputDraftRevision++;
      }
    }
    setState(() {});
    if (state.stage == FutureTodoComposeStage.awaitingConfirmation &&
        state.requestId != null &&
        state.requestId != _handledFutureTodoRequestId) {
      _handledFutureTodoRequestId = state.requestId;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final selected = await showSplitConfirmSheet(context, state.candidates);
        if (!mounted) return;
        if (selected == null) {
          _store.cancelFutureTodoCreation();
        } else {
          await _store.confirmFutureTodoCreation(
            state.requestId!,
            selected,
            targetDate: state.targetDate!,
          );
        }
      });
    }
  }

  // 07 轮：App 生命周期监听
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_generateSuggestions());
    }
  }

  void _refreshChatGreeting() {
    _chatGreeting =
        _chatGreetings[DateTime.now().millisecond % _chatGreetings.length];
  }

  void _pickRandomFutureGreeting() {
    _futureGreeting = _futureGreetings[_random.nextInt(_futureGreetings.length)];
  }

  void _startFutureGreetingTimer() {
    _futureGreetingTimer?.cancel();
    _futureGreetingTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        if (!mounted) return;
        setState(() => _pickRandomFutureGreeting());
      },
    );
  }

  void _stopFutureGreetingTimer() {
    _futureGreetingTimer?.cancel();
    _futureGreetingTimer = null;
  }

  Future<void> _generateSuggestions() async {
    if (!mounted) return;
    final store = _store;
    if (calendarDayMode(store.selectedDate, store.currentTime) !=
        CalendarDayMode.today) {
      return;
    }
    if (!store.appSettings.suggestionQuestionsEnabled) {
      if (mounted) setState(() => _suggestions = const []);
      return;
    }

    // Keep the last complete result visible while a new day or changed data is
    // being refreshed. Repeated refresh triggers must never blank the strip.
    final cached = store.cachedSuggestionQuestions;
    if (cached.isNotEmpty && mounted) {
      setState(() => _suggestions = cached);
    }
    if (!store.suggestionsDirty && store.hasUsableSuggestionQuestionCache) {
      return;
    }
    List<SuggestionQuestion>? generated;
    try {
      generated = await store.refreshSuggestionQuestions();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final next = generated ?? store.cachedSuggestionQuestions;
    if (next.isNotEmpty) {
      setState(() => _suggestions = next);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final offset = _scrollController.offset;
    final shouldShow = maxScroll > 0 && offset < maxScroll - 100;
    if (shouldShow != _showScrollToBottom) {
      setState(() => _showScrollToBottom = shouldShow);
    }
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

  void _handleSuggestionSelect(SuggestionQuestion suggestion) {
    if (_isInputBusy) return;
    setState(() {
      _inputDraft = suggestion.text;
      _inputDraftRevision++;
      _draftedSuggestion = suggestion;
    });
  }

  void _consumeInputDraft(int revision) {
    if (!mounted || revision != _inputDraftRevision) return;
    setState(() => _inputDraft = null);
  }

  Future<void> _handleSuggestionFeedback(
    SuggestionQuestion suggestion,
    bool disableTopic,
  ) async {
    final store = SumiScope.read(context);
    final generated = await store.rejectSuggestionQuestion(
      suggestion,
      disableIntent: disableTopic,
    );
    if (!mounted) return;
    final next = generated ?? store.cachedSuggestionQuestions;
    if (next.isNotEmpty) {
      setState(() => _suggestions = next);
    }
  }

  ChatSendResult _handleChatSend(String content) {
    final store = SumiScope.read(context);
    final result = store.sendUnifiedMessage(
      content,
      currentGreeting: _chatGreeting,
    );
    if (result == ChatSendResult.accepted && _draftedSuggestion != null) {
      store.recordSuggestionQuestionSent(_draftedSuggestion!);
      _draftedSuggestion = null;
    }
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

  ChatSendResult _handleFutureTodoSend(String content) {
    final result = _store.startFutureTodoCreation(content);
    return switch (result) {
      TodoComposeResult.accepted => ChatSendResult.accepted,
      TodoComposeResult.empty => ChatSendResult.empty,
      TodoComposeResult.busy => ChatSendResult.busy,
    };
  }

  void _rememberDraft(String value) {
    final key = dateKey(_store.selectedDate);
    if (value.isEmpty) {
      _draftsByDate.remove(key);
    } else {
      _draftsByDate[key] = value;
    }
  }

  bool get _isInputBusy =>
      _store.chatView.value.isStreaming ||
      _store.futureTodoController.state.value.isBusy;

  void _stopInputGeneration() {
    if (_store.futureTodoController.state.value.isBusy) {
      _store.cancelFutureTodoCreation();
    } else {
      _store.stopGenerating();
    }
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
    SumiScope.watchDailyReflections(context);
    final userName = store.appSettings.userName;
    final selectedDate = store.selectedDate;
    final dayMode = calendarDayMode(selectedDate, store.currentTime);
    final isPast = dayMode == CalendarDayMode.past;
    final isFuture = dayMode == CalendarDayMode.future;

    // 检测日期切换 → 重载建议
    if (_lastSelectedDate != null &&
        !isSameDate(selectedDate, _lastSelectedDate!)) {
      final lastMode = calendarDayMode(_lastSelectedDate!, store.currentTime);
      final wasFuture = lastMode == CalendarDayMode.future;
      _lastSelectedDate = selectedDate;
      _showScrollToBottom = false; // 日期切换时重置悬浮按钮状态
      final savedDraft = _draftsByDate[dateKey(selectedDate)] ?? '';
      _inputDraft = savedDraft;
      _inputDraftRevision++;
      if (dayMode == CalendarDayMode.today) {
        _stopFutureGreetingTimer();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _generateSuggestions();
        });
      } else if (dayMode == CalendarDayMode.future) {
        // 从未来的某天切到未来的某天，不立即刷新问候语
        if (!wasFuture) {
          _pickRandomFutureGreeting();
        }
        _startFutureGreetingTimer();
      } else {
        _stopFutureGreetingTimer();
      }
    }
    _lastSelectedDate ??= selectedDate;

    // 确保 Timer 状态与当前 dayMode 一致（处理首次构建等边界情况）
    if (dayMode == CalendarDayMode.future && _futureGreetingTimer == null) {
      _startFutureGreetingTimer();
    } else if (dayMode != CalendarDayMode.future &&
        _futureGreetingTimer != null) {
      _stopFutureGreetingTimer();
    }

    // 检测数据变更 → 刷新建议
    if (store.dataVersion != _lastDataVersion) {
      _lastDataVersion = store.dataVersion;
      if (dayMode == CalendarDayMode.today) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _generateSuggestions();
        });
      }
    }
    if (store.suggestionsDirty != _lastSuggestionsDirty) {
      _lastSuggestionsDirty = store.suggestionsDirty;
      if (dayMode == CalendarDayMode.today) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _generateSuggestions();
        });
      }
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
                    final todayKey = dateKey(dateOnly(store.currentTime));
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
                      final today = dateOnly(store.currentTime);
                      if (!isSameDate(store.selectedDate, today)) {
                        store.selectDate(today);
                      }
                    },
                    child: Stack(
                      children: [
                        // 日程卡有独立的显示锚点，删除消息后可能仍在缓存中却
                        // 不会被渲染。空状态只能依据真正可见的聊天消息判断。
                        if (chat.messages
                                .where((message) => message.role != 'tool')
                                .isEmpty &&
                            chat.pendingUserMessage == null)
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
              if (isPast)
                DailyReflectionSlot(
                  key: ValueKey('past-reflection-${dateKey(selectedDate)}'),
                  store: store,
                  date: selectedDate,
                  revision: store.dailyReflectionController.revision,
                )
              else
                ValueListenableBuilder<ChatViewState>(
                  valueListenable: store.chatView,
                  builder: (context, chat, _) {
                    final futureState = store.futureTodoController.state.value;
                    final busy = isFuture
                        ? futureState.isBusy
                        : chat.isStreaming;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRect(
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            heightFactor: isFuture ? 0 : 1,
                            alignment: Alignment.bottomCenter,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              opacity: isFuture ? 0 : 1,
                              child: SuggestionStrip(
                                suggestions: _suggestions,
                                onSelect: _handleSuggestionSelect,
                                onFeedback: _handleSuggestionFeedback,
                                enabled: !busy,
                              ),
                            ),
                          ),
                        ),
                        ChatInput(
                          onSend: isFuture
                              ? _handleFutureTodoSend
                              : _handleChatSend,
                          mode: isFuture
                              ? ChatInputMode.todo
                              : ChatInputMode.chat,
                          enabled: !busy,
                          isStreaming: busy,
                          onStopGenerating: _stopInputGeneration,
                          voiceService: store.voiceService,
                          draftText: _inputDraft,
                          draftRevision: _inputDraftRevision,
                          onDraftApplied: _consumeInputDraft,
                          onTextChanged: _rememberDraft,
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
          // 滚动到底部按钮（位于月视图遮罩之下）
          _buildScrollToBottomButton(bottomPadding, store.chatView.value),
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
    final mode = calendarDayMode(selected, store.currentTime);
    final isFuture = mode == CalendarDayMode.future;
    final isPast = mode == CalendarDayMode.past;

    final String title;
    if (isPast) {
      title = '这一天没有对话';
    } else if (isFuture) {
      title = _futureGreeting;
    } else {
      title = '嗨 $userName，今天要和 Sumi 一起做点什么？';
    }

    return Align(
      alignment: const Alignment(0, -0.35),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w300,
              color: ink,
              height: 1.4,
            ),
          ),
          if (isPast || isFuture) ...[
            const SizedBox(height: s8),
            const Text(
              '（双击回到今天）',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w300,
                color: textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageList(ChatViewState chat, SumiStore store) {
    final canMutateConversation =
        calendarDayMode(store.selectedDate, store.currentTime) ==
        CalendarDayMode.today;
    final messages = chat.messages;
    final filtered = messages
        .where((message) => message.role != 'tool')
        .toList(growable: false);
    final streamingAssistantId = store.streamingAssistantMessageId;
    final milestoneSourceIds = chat.milestoneSourceMessageIds;
    final memorySourceIds = chat.memorySourceMessageIds;

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
          todoResultJson: message.todoResultJson,
          showMilestoneSaved: milestoneSourceIds.contains(message.id),
          showMemorySaved: memorySourceIds.contains(message.id),
          onOpenTodo: !canMutateConversation || message.todoResultJson == null
              ? null
              : () {
                  try {
                    final data = jsonDecode(
                      message.todoResultJson!,
                    ) as Map<String, Object?>;
                    final id = data['todoId'] as String?;
                    TodoItem? todo;
                    if (id != null) {
                      for (final item in store.todoItems) {
                        if (item.id == id) {
                          todo = item;
                          break;
                        }
                      }
                    }
                    if (todo != null) showTodoEditSheet(context, store, todo);
                  } catch (_) {}
                },
          timerController: store.timerController,
          onStartTimer: store.startStudyTimer,
          onPauseTimer: store.pauseStudyTimer,
          onFinishTimer: store.finishStudyTimer,
          projectGenerationController: store.projectGenerationController,
          onDelete: canMutateConversation && message.role == 'user'
              ? () => store.deleteMessagePair(originalIndex)
              : null,
          onEdit:
              canMutateConversation &&
                  message.role == 'user' &&
                  message.id == latestUserMessageId
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
    final pendingUserMessage = chat.pendingUserMessage;
    if (pendingUserMessage != null) {
      listItems.add(
        ChatBubble(
          content: pendingUserMessage.content,
          isUser: true,
          timestamp: pendingUserMessage.createdAt,
          timerController: store.timerController,
          onStartTimer: store.startStudyTimer,
          onPauseTimer: store.pauseStudyTimer,
          onFinishTimer: store.finishStudyTimer,
          projectGenerationController: store.projectGenerationController,
        ),
      );
    }
    if (chat.failure != null) {
      listItems.add(_buildChatFailure(chat.failure!, store));
    }
    // 日程建议会在异步评估完成后插入列表；不要让整个聊天列表跟着淡入，
    // 否则卡片首次显示时会闪烁。
    return ListView(
      key: ValueKey(chat.conversationId),
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: s16),
      children: listItems,
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

  Widget _buildScrollToBottomButton(double bottomSafe, ChatViewState chat) {
    final store = SumiScope.read(context);
    final isToday =
        calendarDayMode(store.selectedDate, store.currentTime) ==
        CalendarDayMode.today;
    final hasMessages = chat.messages.any((message) => message.role != 'tool');
    if (!_showScrollToBottom || !isToday || !hasMessages) {
      return const SizedBox.shrink();
    }

    // ChatInput ≈ s16(top) + 60(container) + bottomSafe + s8(const)
    // SuggestionStrip ≈ 40px, + 32px clearance
    final inputBottom = 16 + 60 + bottomSafe + 8; // ~84 + bottomSafe
    final suggestionHeight = 40.0;
    final clearance = 32.0;
    final btnBottom = inputBottom + suggestionHeight + clearance;

    return Positioned(
      bottom: btnBottom,
      right: s24,
      child: GestureDetector(
        onTap: _scrollToBottom,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: paper,
            shape: BoxShape.circle,
            boxShadow: const [...shadow2],
          ),
          child: const Icon(
            Icons.keyboard_arrow_down,
            size: 24,
            color: primary500,
          ),
        ),
      ),
    );
  }
}
