import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../theme/app_theme.dart';

/// 聊天气泡组件 —— 支持用户（右侧 mint）和 AI（左侧白色）两种样式。
class ChatBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final bool isStreaming;
  final String? reasoningContent; // AI 思考过程
  final String? toolCallsJson; // 工具调用 JSON

  const ChatBubble({
    super.key,
    required this.content,
    required this.isUser,
    this.isStreaming = false,
    this.reasoningContent,
    this.toolCallsJson,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: s16, vertical: s6),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          // 角色标签
          Padding(
            padding: const EdgeInsets.only(bottom: s4),
            child: Text(
              isUser ? '你' : 'Sumi',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textTertiary,
              ),
            ),
          ),
          // 思考过程（仅 AI 且有内容时显示折叠区域）
          if (!isUser &&
              reasoningContent != null &&
              reasoningContent!.isNotEmpty)
            _ThinkingSection(reasoning: reasoningContent!),
          // 工具调用指示（仅 AI 且有 tool_calls 时显示，简洁样式）
          if (!isUser &&
              toolCallsJson != null &&
              toolCallsJson!.isNotEmpty)
            _ToolCallIndicator(toolCallsJson: toolCallsJson!),
          // 气泡（长按复制）
          GestureDetector(
            onLongPress: () {
              HapticFeedback.selectionClick();
              Clipboard.setData(ClipboardData(text: content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: s14, vertical: s10),
              decoration: BoxDecoration(
                color: isUser ? mint : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(radiusCard),
                  topRight: const Radius.circular(radiusCard),
                  bottomLeft:
                      Radius.circular(isUser ? radiusCard : s4),
                  bottomRight:
                      Radius.circular(isUser ? s4 : radiusCard),
                ),
                border: Border.all(
                  color: isUser
                      ? Colors.transparent
                      : line.withValues(alpha: 0.4),
                ),
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
        backgroundColor: Colors.grey.shade100,
        fontFamily: 'monospace'),
    codeblockDecoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(s8),
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

class _ThinkingSection extends StatefulWidget {
  final String reasoning;
  const _ThinkingSection({required this.reasoning});

  @override
  State<_ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<_ThinkingSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: s4),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: s10, vertical: s6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(s8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 16,
                    color: textTertiary,
                  ),
                  const SizedBox(width: s4),
                  Text(
                    '思考过程',
                    style: TextStyle(
                      fontSize: 12,
                      color: textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: s6),
                Text(
                  widget.reasoning,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
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
            names.add(_toolDisplayName(name));
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
            '🔧 ${names.join(" · ")}',
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

  String _toolDisplayName(String name) => switch (name) {
    'search_web' => '搜索',
    'read_memory' => '读取记忆',
    'write_memory' => '写入记忆',
    'read_todos' => '查看事项',
    'write_todo' => '创建事项',
    _ => name,
  };
}
