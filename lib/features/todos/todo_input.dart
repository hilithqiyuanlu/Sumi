import 'package:flutter/material.dart';

import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import 'split_confirm_sheet.dart';

/// 底部输入栏 —— 创建用户 todo，>16 字触发 AI 拆分。
class TodoInput extends StatefulWidget {
  const TodoInput({super.key});

  @override
  State<TodoInput> createState() => _TodoInputState();
}

class _TodoInputState extends State<TodoInput> {
  final _controller = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final store = SumiScope.read(context);

    // ≤16 字：直接创建
    if (text.length <= 16) {
      store.addUserTodo(text);
      _controller.clear();
      return;
    }

    // >16 字：走 AI 拆分流程
    setState(() => _loading = true);

    try {
      final result = await store.splitAndAddTodo(text);

      if (!mounted) return;

      if (result == null) {
        // 降级：已在 store 内直接创建，或 API Key 为空
        if (store.appSettings.deepseekApiKey.isEmpty) {
          _showToast('请先在设置中配置 API Key');
        } else {
          _showToast('网络异常，已直接添加');
        }
      } else if (!result.split) {
        // AI 判断无需拆分，已在 store 内直接创建
        _showToast('已直接添加');
      } else {
        // 需要拆分确认
        await showSplitConfirmSheet(context, store, result.items);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }

    _controller.clear();
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: paper,
        border: Border(top: BorderSide(color: line)),
      ),
      padding: EdgeInsets.fromLTRB(
        s16,
        s10,
        s8,
        MediaQuery.of(context).padding.bottom + s10,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              enabled: !_loading,
              decoration: const InputDecoration(
                hintText: '添加新事项...',
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: s8),
          _loading
              ? const Padding(
                  padding: EdgeInsets.all(s10),
                  child: SizedBox(
                    width: iconSection,
                    height: iconSection,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  onPressed: _submit,
                  icon: const Icon(Icons.send_rounded, size: iconSection),
                  color: mintDeep,
                ),
        ],
      ),
    );
  }
}
