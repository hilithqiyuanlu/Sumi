import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../theme/app_theme.dart';
import '../../utils/utils.dart';
import '../shared/collapsible_section.dart';

/// 聊天气泡组件 —— 支持用户（右侧 mint）和 AI（左侧白色）两种样式。
class ChatBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final bool isStreaming;
  final DateTime? timestamp;
  final String? reasoningContent;
  final String? toolCallsJson;
  final VoidCallback? onDelete;

  const ChatBubble({
    super.key,
    required this.content,
    required this.isUser,
    this.isStreaming = false,
    this.timestamp,
    this.reasoningContent,
    this.toolCallsJson,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: s16, vertical: s6),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          // 用户消息时间坐标（居中显示）
          if (isUser && timestamp != null)
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(bottom: s4),
                child: Text(
                  '${timestamp!.month}/${timestamp!.day} ${timestamp!.hour.toString().padLeft(2, '0')}:${timestamp!.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: textTertiary,
                  ),
                ),
              ),
            ),
          // 思考过程（仅 AI 且有内容时显示折叠区域）
          if (!isUser &&
              reasoningContent != null &&
              reasoningContent!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: s4),
              child: CollapsibleSection(
                title: '思考过程',
                body: reasoningContent!,
                backgroundColor: surfaceAlt,
              ),
            ),
          // 工具调用指示（仅 AI 且有 tool_calls 时显示，简洁样式）
          if (!isUser &&
              toolCallsJson != null &&
              toolCallsJson!.isNotEmpty)
            _ToolCallIndicator(toolCallsJson: toolCallsJson!),
          // 气泡（长按删除或复制）
          GestureDetector(
            onLongPress: () {
              HapticFeedback.selectionClick();
              if (onDelete != null) {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(radiusCard)),
                    ),
                    title: const Text('删除这条对话？',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    content: const Text('将同时删除这一来一回的全部内容，包括思考过程和工具信息。',
                        style: TextStyle(fontSize: 14)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: danger,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          onDelete!.call();
                        },
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
              } else {
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: s12, vertical: s10),
              decoration: BoxDecoration(
                color: isUser ? mint : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isUser ? radius20 : s4),
                  topRight: Radius.circular(isUser ? s4 : radius20),
                  bottomLeft: const Radius.circular(radius20),
                  bottomRight: const Radius.circular(radius20),
                ),
                border: Border.all(
                  color: isUser
                      ? Colors.transparent
                      : line.withValues(alpha: 0.3),
                ),
                boxShadow: isUser
                    ? null
                    : const [
                        BoxShadow(
                          color: Color(0x080E1115),
                          offset: Offset(0, 1),
                          blurRadius: 3,
                        ),
                      ],
              ),
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (content.isEmpty && isStreaming) {
      return const SizedBox(
        width: 24,
        height: 20,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: mintDeep,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 用户消息保持纯文本，AI 消息用 Markdown 渲染
        if (isUser)
          Text(
            content,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: ink,
            ),
          )
        else
          MarkdownBody(
            data: content,
            selectable: true,
            styleSheet: _mdStyleSheet,
          ),
        if (isStreaming)
          const Padding(
            padding: EdgeInsets.only(top: s2),
            child: _Cursor(),
          ),
      ],
    );
  }

  static final MarkdownStyleSheet _mdStyleSheet = MarkdownStyleSheet(
    p: const TextStyle(fontSize: 15, height: 1.5, color: ink),
    strong: const TextStyle(
        fontSize: 15,
        height: 1.5,
        color: ink,
        fontWeight: FontWeight.w600),
    code: TextStyle(
        fontSize: 13,
        color: textTertiary,
        backgroundColor: surfaceAlt,
        fontFamily: 'monospace'),
    codeblockDecoration: BoxDecoration(
      color: surfaceAlt,
      borderRadius: BorderRadius.circular(radius8),
    ),
    h1: const TextStyle(
        fontSize: 18, fontWeight: FontWeight.w700, color: ink),
    h2: const TextStyle(
        fontSize: 16, fontWeight: FontWeight.w700, color: ink),
    h3: const TextStyle(
        fontSize: 15, fontWeight: FontWeight.w600, color: ink),
    listBullet: const TextStyle(fontSize: 15, color: ink),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: line.withValues(alpha: 0.5), width: 1),
      ),
    ),
  );
}

/// 流式输出光标。
class _Cursor extends StatefulWidget {
  const _Cursor();

  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _controller.value,
          child: Container(
            width: 2,
            height: 16,
            decoration: BoxDecoration(
              color: mintDeep,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 思考过程折叠区域
// ---------------------------------------------------------------------------


// ---------------------------------------------------------------------------
// 工具调用指示（简洁版）
// ---------------------------------------------------------------------------

class _ToolCallIndicator extends StatelessWidget {
  final String toolCallsJson;
  const _ToolCallIndicator({required this.toolCallsJson});

  @override
  Widget build(BuildContext context) {
    List<String> names = [];
    try {
      final list = jsonDecode(toolCallsJson) as List<Object?>;
      for (final item in list) {
        if (item is Map<String, Object?>) {
          final func = item['function'] as Map<String, Object?>?;
          final name = func?['name'] as String?;
          if (name != null) {
            names.add(toolDisplayName(name));
          }
        }
      }
    } catch (_) {}

    if (names.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: s4),
      child: GestureDetector(
        onTap: () {}, // 无操作，仅视觉提示
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: s8, vertical: s4),
          decoration: BoxDecoration(
            color: mint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(s6),
          ),
          child: Text(
            '${names.join(" · ")}',
            style: const TextStyle(
              fontSize: 11,
              color: mintDeep,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
