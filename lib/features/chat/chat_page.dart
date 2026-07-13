import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import 'chat_bubble.dart';
import 'chat_input.dart';
import 'conversation_list.dart';

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
  void dispose() {
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          store.currentConversationTitle.isNotEmpty
              ? store.currentConversationTitle
              : 'Sumi',
          style: const TextStyle(fontSize: 17),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => ConversationList.show(context, store),
        ),
        actions: [
          if (store.currentConversationId != null && messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 22),
              tooltip: '重新生成',
              onPressed: isStreaming ? null : () => store.regenerateLast(),
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
                                      _scrollController.position.maxScrollExtent - 100;
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

                            return ChatBubble(
                              content: msg.content,
                              isUser: msg.role == 'user',
                              isStreaming: isLastAi && isStreaming,
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
                                      color: Colors.black.withValues(alpha: 0.1),
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
