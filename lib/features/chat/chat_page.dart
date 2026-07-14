import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import 'chat_bubble.dart';
import 'chat_input.dart';
import 'conversation_list.dart';
import 'wrench_panel.dart';

/// Sumi Tab —— AI 对话助手。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    // 确保有活跃对话（优先加载最近对话）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SumiScope.read(context).ensureLastConversation();
    });
  }

  @override
  void dispose() {
    // 离开时清理空对话
    final store = SumiScope.read(context);
    store.cleanupEmptyConversation();
    _scrollController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watch(context);
    final messages = store.currentMessages;
    final isStreaming = store.isStreaming;

    // 流式输出时自动滚到底部
    if (isStreaming) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToBottom());
    }

    // 构建 AppBar 副标题
    String? appBarSubtitle;
    if (store.isThinking) {
      appBarSubtitle = '思考中...';
    } else if (store.currentToolCallLabel != null) {
      appBarSubtitle = '🔧 ${store.currentToolCallLabel}...';
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              store.currentConversationTitle.isNotEmpty
                  ? store.currentConversationTitle
                  : 'Sumi',
              style: const TextStyle(fontSize: 17),
            ),
            if (appBarSubtitle != null)
              Text(
                appBarSubtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: textTertiary,
                ),
              ),
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => ConversationList.show(context, store),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.build_rounded, size: 22),
            tooltip: 'Sumi 工具',
            onPressed: () => SumiToolsSheet.show(context, store),
          ),
        ],
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(
            child: messages.isEmpty
                ? _EmptyState()
                : NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollEndNotification) {
                        setState(() {
                          _showScrollToBottom =
                              _scrollController.hasClients &&
                                  _scrollController.offset <
                                      _scrollController
                                              .position
                                              .maxScrollExtent -
                                          100;
                        });
                      }
                      return false;
                    },
                    child: Stack(
                      children: [
                        ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(
                            top: s16,
                            bottom: s16,
                          ),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index];
                            final isLastAi = msg.role == 'assistant' &&
                                index == messages.length - 1;

                            // tool 消息：折叠展示
                            if (msg.role == 'tool') {
                              return _CondensedToolResult(
                                content: msg.content,
                                toolCallId: msg.toolCallId,
                              );
                            }

                            return ChatBubble(
                              content: msg.content,
                              isUser: msg.role == 'user',
                              isStreaming: isLastAi && isStreaming,
                              reasoningContent:
                                  msg.reasoningContent,
                              toolCallsJson: msg.toolCallsJson,
                            );
                          },
                        ),
                        // 滚到底部按钮
                        if (_showScrollToBottom)
                          Positioned(
                            bottom: s8,
                            right: s16,
                            child: GestureDetector(
                              onTap: _scrollToBottom,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.1),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 22,
                                  color: mintDeep,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          // 输入栏
          ChatInput(
            onSend: (text) {
              HapticFeedback.lightImpact();
              store.sendMessage(text);
            },
            enabled: !isStreaming,
            voiceService: store.voiceService,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.psychology_rounded,
            size: 64,
            color: mintDeep.withValues(alpha: 0.4),
          ),
          const SizedBox(height: s16),
          Text(
            '和 Sumi 聊聊学习计划吧',
            style: TextStyle(
              fontSize: 16,
              color: textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: s8),
          Text(
            '我可以帮你制定计划、解答疑问',
            style: TextStyle(
              fontSize: 14,
              color: textTertiary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 工具执行结果（折叠展示）
// ---------------------------------------------------------------------------

class _CondensedToolResult extends StatefulWidget {
  final String content;
  final String? toolCallId;
  const _CondensedToolResult({
    required this.content,
    this.toolCallId,
  });

  @override
  State<_CondensedToolResult> createState() =>
      _CondensedToolResultState();
}

class _CondensedToolResultState extends State<_CondensedToolResult> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // 提取首行作为摘要
    final lines = widget.content.split('\n');
    final summary = lines.first.length > 50
        ? '${lines.first.substring(0, 50)}…'
        : lines.first;
    final hasMore = widget.content.length > summary.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: s16, vertical: s4),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: s10, vertical: s6),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(s8),
            border: Border.all(
              color: line.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 14,
                    color: textTertiary,
                  ),
                  const SizedBox(width: s4),
                  Expanded(
                    child: Text(
                      summary,
                      style: const TextStyle(
                        fontSize: 11,
                        color: textTertiary,
                      ),
                      maxLines: _expanded ? null : 1,
                      overflow:
                          _expanded ? null : TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (_expanded && hasMore) ...[
                const SizedBox(height: s6),
                Text(
                  widget.content,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
