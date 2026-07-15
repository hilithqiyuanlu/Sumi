import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../models/models.dart';
import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/utils.dart';
import 'todo_card.dart';

/// Keep 风格瀑布流网格 —— 使用 MasonryGridView 实现不规则排列。
///
/// 数据源为 store.todosForSelectedDate（按选中日期筛选）。
/// 每个卡片支持 LongPressDraggable 拖拽 + DragTarget 重排。
class TodoGrid extends StatelessWidget {
  final void Function(TodoItem todo)? onTapBody;

  const TodoGrid({super.key, this.onTapBody});

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watch(context);
    final items = store.todosForSelectedDate;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 48, color: primary100),
            const SizedBox(height: s8),
            Text(
              '还没有事项，在下方输入框创建吧',
              style: TextStyle(fontSize: 15, color: textTertiary),
            ),
          ],
        ),
      );
    }

    return MasonryGridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: s8,
      crossAxisSpacing: s8,
      padding: const EdgeInsets.symmetric(horizontal: s16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final todo = items[index];
        final project = _findProject(store, todo.projectId);

        // 估算卡片高度用于 masonry
        final extent = _estimateExtent(todo, project);

        return _DraggableTodoCell(
          key: ValueKey(todo.id),
          todo: todo,
          project: project,
          store: store,
          extent: extent,
          onTapBody: onTapBody,
        );
      },
    );
  }

  Project? _findProject(SumiStore store, String? projectId) {
    if (projectId == null) return null;
    try {
      return store.projectList.firstWhere((p) => p.id == projectId);
    } catch (_) {
      return null;
    }
  }

  /// 根据内容估算卡片高度。
  double _estimateExtent(TodoItem todo, Project? project) {
    double h = s12 * 2; // padding
    // 标题行
    final titleLines = (todo.title.length / 10).ceil().clamp(1, 4);
    h += titleLines * 20;
    // 项目行
    if (project != null || todo.projectId != null) h += 22;
    // 提醒行
    if (todo.reminderTime != null && todo.reminderTime!.isNotEmpty) h += 22;
    return h.clamp(72.0, 200.0);
  }
}

/// 可拖拽的 Todo 单元格 —— LongPressDraggable + DragTarget。
/// 07 轮：过去日期禁用拖拽、滑动删除、完成标记、置顶。
class _DraggableTodoCell extends StatelessWidget {
  final TodoItem todo;
  final Project? project;
  final SumiStore store;
  final double extent;
  final void Function(TodoItem todo)? onTapBody;

  const _DraggableTodoCell({
    super.key,
    required this.todo,
    this.project,
    required this.store,
    required this.extent,
    this.onTapBody,
  });

  @override
  Widget build(BuildContext context) {
    final isReadonly = isPastDate(todo.date);

    Widget card = TodoCard(
      todo: todo,
      project: project,
      onTapDone: isReadonly ? () {} : () => store.toggleTodo(todo.id),
      onTapPin: isReadonly ? () {} : () => store.togglePin(todo.id),
      onTapBody: () => onTapBody?.call(todo),
      isReadonly: isReadonly,
    );

    if (isReadonly) {
      return Opacity(opacity: 0.7, child: SizedBox(height: extent, child: card));
    }

    return DragTarget<TodoItem>(
      onWillAcceptWithDetails: (details) {
        return details.data.id != todo.id;
      },
      onAcceptWithDetails: (details) {
        store.reorderTodos(details.data.id, todo.id);
      },
      builder: (context, candidates, rejects) {
        final hovering = candidates.isNotEmpty;

        return LongPressDraggable<TodoItem>(
          data: todo,
          delay: const Duration(milliseconds: 300),
          feedback: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(radiusCard),
            color: Colors.transparent,
            child: SizedBox(
              width: 160,
              child: TodoCard(
                todo: todo,
                project: project,
                onTapDone: () {},
                onTapPin: () {},
                onTapBody: () {},
                isDragging: true,
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: SizedBox(
              height: extent,
              child: TodoCard(
                todo: todo,
                project: project,
                onTapDone: () {},
                onTapPin: () {},
                onTapBody: () {},
              ),
            ),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: extent,
            decoration: hovering
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(radiusCard + 4),
                    border: Border.all(
                      color: mintDeep.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  )
                : null,
            child: Dismissible(
              key: ValueKey(todo.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: s16),
                decoration: BoxDecoration(
                  color: danger,
                  borderRadius: BorderRadius.circular(radiusCard),
                ),
                child: const Icon(Icons.delete_outline, color: Colors.white),
              ),
              onDismissed: (_) {
                store.deleteTodo(todo.id);
              },
              child: card,
            ),
          ),
        );
      },
    );
  }
}
