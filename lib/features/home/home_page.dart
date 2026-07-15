import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../models/models.dart';

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
import 'settings_panel.dart';
import 'side_drawer.dart';
import 'suggestion_strip.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
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
  List<String> _suggestions = [];
  bool _isGeneratingSuggestions = false;
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  DateTime? _lastSelectedDate;
  int _lastDataVersion = 0;
  late final SumiStore _store;
  late ChatViewState _lastChatView;

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
    _generateSuggestions();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.chatView.removeListener(_onChatViewChanged);
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

  // 07 轮：App 生命周期监听
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final store = SumiScope.read(context);
      final now = DateTime.now();

      // 节流：2 分钟内不重复
      if (store.lastSuggestionTime != null &&
          now.difference(store.lastSuggestionTime!).inMinutes < 2) {
        return;
      }
      // 强制刷新：后台 > 30 分钟
      if (store.lastForegroundTime != null &&
          now.difference(store.lastForegroundTime!).inMinutes > 30) {
        store.setSuggestionsDirty(true);
      }
      store.lastForegroundTime = now;

      // 检查周度反思
      store.checkAndRunWeeklyReflection();

      _generateSuggestions();
    }
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

  /// 07 轮：缓存策略。UI 立即展示缓存/规则预设，后台异步 AI 替换。
  Future<void> _generateSuggestions() async {
    final store = SumiScope.read(context);

    // 规则预设：立即展示
    final presets = _rulePresetSuggestions(store);
    // 优先使用缓存
    final cached = store.cachedSuggestions;
    if (!mounted) return;
    setState(() {
      _suggestions = cached.isNotEmpty ? cached : presets;
    });

    // 后台 AI 生成（如果缓存脏或首次）
    if (!store.suggestionsDirty && cached.isNotEmpty) return;
    if (_isGeneratingSuggestions) return;

    final ai = store.structuredAi;
    if (ai == null) return;

    _isGeneratingSuggestions = true;

    try {
      final ums = store.userModelService;
      if (ums == null) return;
      final model = await ums.readUserModel();
      final stats = await ums.computeRealtimeStats();
      final modelWithStats = ums.injectRealtimeStats(model, stats);
      final coreMemory = ums.buildHotPrompt(modelWithStats);

      final aiSuggestions = await ai.generateOpeningSuggestions(
        realtimeStats: stats.entries
            .map((e) => '${e.key}: ${e.value}')
            .join('\n'),
        coreMemory: coreMemory,
      );

      if (aiSuggestions.isNotEmpty && mounted) {
        store.cachedSuggestions = aiSuggestions;
        store.lastSuggestionTime = DateTime.now();
        store.setSuggestionsDirty(false);
        // 去重合并：AI 结果优先，与当前显示的预设做去重
        setState(() {
          if (_suggestions == presets || _suggestions == cached) {
            _suggestions = _mergeAndDedup(aiSuggestions, _suggestions);
          }
        });
      }
    } catch (_) {
      // 失败保持当前展示
    } finally {
      _isGeneratingSuggestions = false;
    }
  }

  /// 规则预设建议：随机池不放回抽取 3-4 条，作为 AI 结果回来前的瞬时展示。
  List<String> _rulePresetSuggestions(SumiStore store) {
    final pool = List<String>.from(_suggestionPool)..shuffle();
    return pool.take(4).toList();
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

  static const _suggestionPool = [
    // 规划向
    '帮我制定今天的学习计划',
    '建议我今天优先完成什么',
    // 总结向
    '帮我回顾一下最近学了什么',
    '帮我分析一下学习进度',
    '帮我总结一下最近的学习进展',
    // 探索向
    '最近有什么值得学的',
    '推荐一个学习方法',
    '推荐相关学习资源',
    // 调整向
    '帮我调整今天的学习计划',
    '帮我看看还有什么没完成的',
    // 效率向
    '如何提高学习效率',
    '给我一些学习建议',
    // 灵感向
    '最近有什么值得关注的学习趋势',
    '有没有适合我的学习技巧',
  ];

  /// 合并 AI 建议与现有建议，去重，AI 结果优先，最多 4 条。
  List<String> _mergeAndDedup(List<String> ai, List<String> existing) {
    final result = <String>[];
    final seen = <String>{};
    for (final s in [...ai, ...existing]) {
      if (result.length >= 4) break;
      // 精确去重
      if (seen.contains(s)) continue;
      // 近似去重：任一已有条目是当前条目的子串（≥4 字），或反之
      final isSimilar = result.any((r) {
        final shorter = r.length < s.length ? r : s;
        final longer = r.length < s.length ? s : r;
        return shorter.length >= 4 && longer.contains(shorter);
      });
      if (isSimilar) continue;
      result.add(s);
      seen.add(s);
    }
    return result;
  }

  void _closeDrawer() {
    setState(() => _drawerOpen = false);
  }

  void _openSettings() {
    _closeDrawer();
    SettingsPanel.show(context);
  }

  void _handleSuggestionSelect(String suggestion) {
    _handleChatSend(suggestion);
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

  Future<void> _handleAddTodo(String title) async {
    final store = SumiScope.read(context);
    if (title.length > SumiStore.todoTitleMaxLength) {
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
                          if (chat.messages.isEmpty)
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
                              enabled: !chat.isStreaming,
                            ),
                            ChatInput(
                              mode: _inputMode,
                              isFutureDate: isFuture,
                              onSend: _handleChatSend,
                              onAddTodo: _handleAddTodo,
                              onModeChanged: _switchMode,
                              enabled: !chat.isStreaming,
                              voiceService: store.voiceService,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
              child: Container(color: Colors.black.withValues(alpha: 0.3)),
            ),
          SideDrawer(
            isOpen: _drawerOpen,
            onClose: _closeDrawer,
            onOpenSettings: _openSettings,
          ),
          // 左边缘手势区：仅覆盖内容区域，避开顶部 DateStrip 和底部输入栏
          _buildGestureArea(topPadding, bottomPadding),
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
    final filtered = messages.where((m) => m.role != 'tool').toList();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: ListView.builder(
        key: ValueKey(chat.conversationId),
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: s16),
        itemCount: filtered.length + (chat.failure == null ? 0 : 1),
        itemBuilder: (context, index) {
          if (index == filtered.length) {
            final failure = chat.failure!;
            return _buildChatFailure(failure, store);
          }
          final msg = filtered[index];
          final isLastAi =
              msg.role == 'assistant' && index == filtered.length - 1;
          // 找到该消息在原始 messages 列表中的索引（用于删除）
          final origIndex = messages.indexOf(msg);

          return ChatBubble(
            content: msg.content,
            isUser: msg.role == 'user',
            isStreaming: isLastAi && chat.isStreaming,
            timestamp: msg.role == 'user' ? msg.createdAt : null,
            activityLabel: isLastAi && chat.isStreaming
                ? chat.activityLabel
                : null,
            toolCallsJson: msg.toolCallsJson,
            onDelete: msg.role == 'user'
                ? () => store.deleteMessagePair(origIndex)
                : null,
          );
        },
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
