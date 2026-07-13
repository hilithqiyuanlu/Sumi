import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 底部输入栏 —— 圆角输入框 + 发送按钮。
class ChatInput extends StatefulWidget {
  final ValueChanged<String> onSend;
  final bool enabled;

  const ChatInput({
    super.key,
    required this.onSend,
    this.enabled = true,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    _controller.clear();
    _hasText = false;
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: line.withValues(alpha: 0.3)),
        ),
      ),
      padding: EdgeInsets.only(
        left: s16,
        right: s16,
        top: s10,
        bottom: MediaQuery.of(context).padding.bottom + s10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: line.withValues(alpha: 0.5)),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '和 Sumi 聊聊…',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: s16,
                    vertical: s10,
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: s8),
          Material(
            color: _hasText && widget.enabled ? mintDeep : line,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: (_hasText && widget.enabled) ? _send : null,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                child: Icon(
                  Icons.send_rounded,
                  size: 20,
                  color: _hasText && widget.enabled ? Colors.white : textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
