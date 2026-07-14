import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import 'split_confirm_sheet.dart';

/// 底部输入栏 —— 创建用户 todo，>18 字触发 AI 拆分 / 凝练。
class TodoInput extends StatefulWidget {
  const TodoInput({super.key});

  @override
  State<TodoInput> createState() => _TodoInputState();
}

class _TodoInputState extends State<TodoInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final store = SumiScope.read(context);

    // ≤18 字：直接创建
    if (text.length <= 18) {
      store.addUserTodo(text);
      _controller.clear();
      return;
    }

    // >18 字：走 AI 拆分/凝练流程
    setState(() => _loading = true);

    try {
      final result = await store.splitAndAddTodo(text);

      if (!mounted) return;

      if (result != null && result.split) {
        await showSplitConfirmSheet(context, store, result.items);
      }
      _controller.clear();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: paper,
        border: Border(
          top: BorderSide(color: line.withValues(alpha: 0.5)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        s16,
        s10,
        s16,
        MediaQuery.of(context).padding.bottom + s10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(radiusPill),
                border: Border.all(
                  color: line.withValues(alpha: 0.3),
                ),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                enabled: !_loading,
                decoration: InputDecoration(
                  hintText: '添加新事项...',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: s16,
                    vertical: s10,
                  ),
                ),
              ),
            ),
          ),
          if (_hasText || _loading) ...[
            const SizedBox(width: s8),
            if (_loading)
              Padding(
                padding: const EdgeInsets.all(s10),
                child: SizedBox(
                  width: sizeButtonMd,
                  height: sizeButtonMd,
                  child: const CircularProgressIndicator(strokeWidth: 2, color: primary500),
                ),
              )
            else
              Material(
                color: primary500,
                borderRadius: BorderRadius.circular(radiusPill),
                child: InkWell(
                  onTap: _submit,
                  borderRadius: BorderRadius.circular(radiusPill),
                  child: Container(
                    width: sizeButtonMd,
                    height: sizeButtonMd,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.send,
                      size: iconMedium,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
