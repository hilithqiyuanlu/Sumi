import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import 'todo_card.dart';

/// Keep 风格不规则网格 —— 使用 Wrap + 估算宽度模拟 masonry 效果。
class TodoGrid extends StatelessWidget {
  const TodoGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watch(context);
    final allTodos = store.todos;

    if (allTodos.isEmpty) {
      return Center(
        child: Text(
          '还没有事项，在下方输入框创建吧',
          style: TextStyle(fontSize: 14, color: textTertiary),
        ),
      );
    }

    final userList = store.userTodos;
    final systemList = store.systemTodos;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 用户 todo
          if (userList.isNotEmpty)
            _TodoWrap(
              items: userList,
              store: store,
              isUser: true,
            ),
          // 分隔
          if (systemList.isNotEmpty && userList.isNotEmpty)
            const SizedBox(height: s16),
          // 系统 todo
          if (systemList.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(left: s4, bottom: s8),
              child: Text(
                '系统事项',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textTertiary,
                ),
              ),
            ),
            _TodoWrap(
              items: systemList,
              store: store,
              isUser: false,
            ),
          ],
          const SizedBox(height: s16),
        ],
      ),
    );
  }
}

/// 用 Wrap 实现的不规则网格。
class _TodoWrap extends StatelessWidget {
  final List<TodoItem> items;
  final SumiStore store;
  final bool isUser;

  const _TodoWrap({
    required this.items,
    required this.store,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width - s16 * 2;
    final singleWidth = (screenWidth - s8) / 2;

    return Wrap(
      spacing: s8,
      runSpacing: s8,
      children: items.map((todo) {
        final span = _estimateSpan(todo.title);
        final width = span == 2 ? screenWidth : singleWidth;
        final project = !isUser && todo.projectId != null
            ? _findProject(todo.projectId!)
            : null;

        return SizedBox(
          width: width,
          child: TodoCard(
            todo: todo,
            project: project,
            onTap: () => store.toggleTodo(todo.id),
            onLongPress: () =>
                _showTodoActions(context, store, todo),
          ),
        );
      }).toList(),
    );
  }

  Project? _findProject(String projectId) {
    try {
      return store.projectList.firstWhere((p) => p.id == projectId);
    } catch (_) {
      return null;
    }
  }

  /// 简单估算标题占用的网格列数。
  int _estimateSpan(String title) {
    if (title.length <= 6) return 1; // 半宽
    if (title.length <= 16) return 2; // 全宽
    return 2; // 长文本也全宽
  }

  void _showTodoActions(
      BuildContext context, SumiStore store, TodoItem todo) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('编辑'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditDialog(context, store, todo);
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.delete_rounded, color: Colors.red.shade400),
                title: Text('删除',
                    style: TextStyle(color: Colors.red.shade400)),
                onTap: () {
                  Navigator.pop(ctx);
                  store.deleteTodo(todo.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditDialog(
      BuildContext context, SumiStore store, TodoItem todo) {
    final controller = TextEditingController(text: todo.title);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('编辑事项'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '输入新标题'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                store.updateTodoTitle(todo.id, controller.text);
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }
}
