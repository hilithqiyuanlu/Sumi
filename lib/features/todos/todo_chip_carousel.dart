import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/utils.dart';
import 'todo_edit_sheet.dart';

/// 横向 Todo chip 条 —— 单行手动滚动 + 点击弹出菜单 + 长按拖拽到日期。
class TodoChipCarousel extends StatefulWidget {
  const TodoChipCarousel({super.key});

  @override
  State<TodoChipCarousel> createState() => _TodoChipCarouselState();
}

class _TodoChipCarouselState extends State<TodoChipCarousel> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<TodoItem> _getFilteredTodos(SumiStore store) {
    final selectedDate = dateKey(dateOnly(store.selectedDate));
    final todayKey = dateKey(dateOnly(DateTime.now()));
    final todos = store.todoItems
        .where((t) => TodoItem.belongsToDate(t, selectedDate, todayKey))
        .toList();

    todos.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.sortOrder.compareTo(a.sortOrder);
    });

    return todos;
  }

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watch(context);
    final todos = _getFilteredTodos(store);

    if (todos.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 52,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: s16),
        itemCount: todos.length,
        itemBuilder: (context, index) {
          final todo = todos[index];
          return Padding(
            padding: EdgeInsets.only(left: index == 0 ? 0 : s8),
            child: _TodoChip(todo: todo),
          );
        },
      ),
    );
  }
}

class _TodoChip extends StatelessWidget {
  final TodoItem todo;

  const _TodoChip({required this.todo});

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.read(context);
    final isDone = todo.done;

    return LongPressDraggable<TodoItem>(
      data: todo,
      delay: const Duration(milliseconds: 300),
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: _TodoChipView(todo: todo, isDone: isDone, isDragging: true),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _TodoChipView(todo: todo, isDone: isDone),
      ),
      onDragStarted: () => HapticFeedback.mediumImpact(),
      child: GestureDetector(
        onTap: () => showTodoEditSheet(context, store, todo),
        child: _TodoChipView(todo: todo, isDone: isDone),
      ),
    );
  }
}

/// 纯展示 chip，不包含交互逻辑。
class _TodoChipView extends StatelessWidget {
  final TodoItem todo;
  final bool isDone;
  final bool isDragging;

  const _TodoChipView({
    required this.todo,
    required this.isDone,
    this.isDragging = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: s10),
      decoration: BoxDecoration(
        color: isDone ? neutral200 : surfaceChip,
        borderRadius: BorderRadius.circular(radiusPill),
        border: isDragging
            ? Border.all(color: primary500, width: 1.5)
            : null,
        boxShadow: isDragging ? const [...shadow2] : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.circle_outlined,
            size: 18,
            color: isDone ? textTertiary : primary500,
          ),
          const SizedBox(width: s6),
          Text(
            todo.title,
            style: TextStyle(
              fontSize: 15,
              color: isDone ? textTertiary : ink,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
