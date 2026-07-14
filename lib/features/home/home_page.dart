import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../models/models.dart';
import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/utils.dart';
import '../calendar/date_strip.dart';
import '../calendar/month_view_sheet.dart';
import '../chat/chat_bubble.dart';
import '../chat/chat_input.dart';
import '../todos/todo_chip_carousel.dart';
import 'settings_panel.dart';
import 'side_drawer.dart';
import 'suggestion_strip.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  bool _drawerOpen = false;

  // 月视图动画
  late final AnimationController _monthController;
  static const _monthSpring = SpringDescription(
    mass: 1,
    stiffness: 250,
    damping: 22,
  );
  InputMode _inputMode = InputMode.todo;
  List<String> _suggestions = [];
  Timer? _suggestionTimer;
  bool _isGeneratingSuggestions = false;
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  int _lastMessageSentSignal = 0;

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
    _monthController = AnimationController(vsync: this);
    _monthController.addListener(() => setState(() {}));
    _refreshChatGreeting();
    _generateSuggestions();
    _startSuggestionPolling();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _suggestionTimer?.cancel();
    _scrollController.dispose();
    _monthController.dispose();
    super.dispose();
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

  void _startSuggestionPolling() {
    _suggestionTimer?.cancel();
    _suggestionTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      _generateSuggestions();
    });
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

  Future<void> _generateSuggestions() async {
    if (_isGeneratingSuggestions) return;
    _isGeneratingSuggestions = true;

    try {
      final store = SumiScope.read(context);
      final aiService = store.aiService;

      final todayTodos = store.todoItems
          .where((t) => t.date == null || t.date == dateKey(dateOnly(store.selectedDate)))
          .map((t) => t.title)
          .join('\n');

      if (aiService == null) {
        setState(() {
          _suggestions = [..._pinnedSuggestions, ..._defaultSuggestions];
        });
        return;
      }

      // 读取用户记忆，让 AI 建议更个性化
      final memory = await store.readMemory();

      final suggestions = await aiService.generateSuggestions(
        todayTodosText: todayTodos,
        memory: memory,
      );

      if (!mounted) return;
      setState(() {
        final aiSuggestions = suggestions.isNotEmpty ? suggestions : _defaultSuggestions;
        _suggestions = [..._pinnedSuggestions, ...aiSuggestions];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suggestions = [..._pinnedSuggestions, ..._defaultSuggestions];
      });
    } finally {
      _isGeneratingSuggestions = false;
    }
  }

  List<String> get _defaultSuggestions => [
        '我现在应该专注做什么',
        '帮我回顾一下最近学了什么',
      ];

  // 常驻固定建议（始终显示，不参与 AI 轮换）
  static const _pinnedSuggestions = [
    '建议以什么顺序开展我今天的待办',
    '帮我总结一下今天的进展',
  ];

  void _closeDrawer() {
    setState(() => _drawerOpen = false);
  }

  void _openSettings() {
    _closeDrawer();
    SettingsPanel.show(context);
  }

  void _handleSuggestionSelect(String suggestion) {
    final store = SumiScope.read(context);
    store.sendMessage(suggestion);
  }

  Future<void> _handleAddTodo(String title) async {
    final store = SumiScope.read(context);
    if (title.length > 16) {
      await store.splitAndAddTodo(title);
    } else {
      store.addUserTodo(title);
    }
  }

  // ---------------------------------------------------------------------------
  // 月视图手势 & 动画
  // ---------------------------------------------------------------------------

  void _onMonthDragUpdate(DragUpdateDetails d) {
    _dismissKeyboard();
    final h = MediaQuery.of(context).size.height;
    _monthController.value =
        (_monthController.value + d.delta.dy / h).clamp(0.0, 1.0);
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
    _monthController.animateWith(SpringSimulation(
      _monthSpring,
      _monthController.value,
      target,
      velocity / MediaQuery.of(context).size.height,
    ));
  }

  void _openMonthView() {
    _dismissKeyboard();
    _monthController.animateTo(1.0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic);
  }

  void _closeMonthView() {
    _monthController.animateTo(0.0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic);
  }

  bool get _monthViewExpanded => _monthController.value > 0;

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watch(context);
    final messages = store.currentMessages;
    final userName = store.appSettings.userName;

    // 检测消息发送信号 → 滚动用户消息到顶部
    if (store.messageSentSignal != _lastMessageSentSignal) {
      _lastMessageSentSignal = store.messageSentSignal;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollUserMessageToTop());
    }
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: paper,
      body: Stack(
        children: [
          // 主内容
          GestureDetector(
            onTap: _dismissKeyboard,
            behavior: HitTestBehavior.translucent,
            child: Column(
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
                    child: Builder(builder: (_) {
                      final sel = dateKey(dateOnly(store.selectedDate));
                      final todayKey = dateKey(dateOnly(DateTime.now()));
                      final hasDateTodos = store.todoItems
                          .any((t) => TodoItem.belongsToDate(t, sel, todayKey));
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasDateTodos) const SizedBox(height: s8),
                          TodoChipCarousel(),
                        ],
                      );
                    }),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        if (messages.isEmpty)
                          _buildEmptyState(store, userName)
                        else
                          _buildMessageList(messages, store),
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
                                  colors: [
                                    paper,
                                    paper.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SuggestionStrip(
                    suggestions: _suggestions,
                    onSelect: _handleSuggestionSelect,
                    enabled: !store.isStreaming,
                  ),
                  ChatInput(
                    mode: _inputMode,
                    onSend: (content) => store.sendMessage(content, currentGreeting: _chatGreeting),
                    onAddTodo: _handleAddTodo,
                    onModeChanged: _switchMode,
                    enabled: !store.isStreaming,
                    voiceService: store.voiceService,
                  ),
                ],
              ),
            ),
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
                          MediaQuery.of(context).size.height),
                  child: const MonthViewSheet(),
                ),
              ),
            ),
          // 抽屉已打开时的遮罩
          if (_drawerOpen)
            GestureDetector(
              onTap: _closeDrawer,
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity != null &&
                    details.primaryVelocity! > 0) {
                  _closeDrawer();
                }
              },
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
              ),
            ),
          SideDrawer(
            isOpen: _drawerOpen,
            onClose: _closeDrawer,
            onOpenSettings: _openSettings,
          ),
          // 左边缘手势区：仅覆盖内容区域，避开顶部 DateStrip 和底部输入栏
          _buildGestureArea(topPadding, bottomPadding),
          _buildScrollToBottomButton(bottomPadding),
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
    if (isFuture) {
      title = '前方的区域还没有开放\n过段时间再来探索吧';
    } else if (isPast) {
      title = '这一天没有对话';
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

  Widget _buildMessageList(List<ChatMessage> messages, SumiStore store) {
    final filtered = messages.where((m) => m.role != 'tool').toList();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: ListView.builder(
        key: ValueKey(store.currentConversationId),
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: s16),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final msg = filtered[index];
          final isLastAi = msg.role == 'assistant' &&
              index == filtered.length - 1;
          // 找到该消息在原始 messages 列表中的索引（用于删除）
          final origIndex = messages.indexOf(msg);

          return ChatBubble(
            content: msg.content,
            isUser: msg.role == 'user',
            isStreaming: isLastAi && store.isStreaming,
            timestamp: msg.role == 'user' ? msg.createdAt : null,
            reasoningContent: msg.reasoningContent,
            toolCallsJson: msg.toolCallsJson,
            onDelete: (msg.role == 'user' || msg.role == 'assistant')
                ? () => store.deleteMessagePair(origIndex)
                : null,
          );
        },
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
    // SuggestionStrip ≈ 40px, + 16px clearance
    final inputBottom = 16 + 60 + bottomSafe + 8; // ~84 + bottomSafe
    final suggestionHeight = 40.0;
    final clearance = 16.0;
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
