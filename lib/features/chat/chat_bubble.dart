import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 聊天气泡组件 —— 支持用户（右侧 mint）和 AI（左侧白色）两种样式。
class ChatBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final bool isStreaming;

  const ChatBubble({
    super.key,
    required this.content,
    required this.isUser,
    this.isStreaming = false,
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
          // 气泡
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: s14, vertical: s10),
            decoration: BoxDecoration(
              color: isUser ? mint : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(radiusCard),
                topRight: const Radius.circular(radiusCard),
                bottomLeft: Radius.circular(isUser ? radiusCard : s4),
                bottomRight: Radius.circular(isUser ? s4 : radiusCard),
              ),
              border: Border.all(
                color: isUser ? Colors.transparent : line.withValues(alpha: 0.4),
              ),
            ),
            child: _buildContent(),
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

    // 简单的格式化处理
    final formatted = _formatContent(content);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...formatted.map((span) => Padding(
              padding: EdgeInsets.only(
                bottom: span.style == _SpanStyle.bold ? s2 : 0,
                top: span.style == _SpanStyle.bold && formatted.indexOf(span) > 0
                    ? s6
                    : 0,
              ),
              child: Text(
                span.text,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: ink,
                  fontWeight: span.style == _SpanStyle.bold
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            )),
        if (isStreaming)
          const Padding(
            padding: EdgeInsets.only(top: s2),
            child: _Cursor(),
          ),
      ],
    );
  }

  List<_FormattedSpan> _formatContent(String text) {
    // 基础处理：**bold** → bold
    final spans = <_FormattedSpan>[];
    final regex = RegExp(r'\*\*(.+?)\*\*');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(_FormattedSpan(
          text.substring(lastEnd, match.start),
          _SpanStyle.normal,
        ));
      }
      spans.add(_FormattedSpan(match.group(1)!, _SpanStyle.bold));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(_FormattedSpan(text.substring(lastEnd), _SpanStyle.normal));
    }

    if (spans.isEmpty) {
      spans.add(_FormattedSpan(text, _SpanStyle.normal));
    }

    return spans;
  }
}

/// 流式输出光标。
class _Cursor extends StatefulWidget {
  const _Cursor();

  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor> with SingleTickerProviderStateMixin {
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

enum _SpanStyle { normal, bold }

class _FormattedSpan {
  final String text;
  final _SpanStyle style;
  const _FormattedSpan(this.text, this.style);
}
