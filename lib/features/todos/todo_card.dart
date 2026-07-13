import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/app_theme.dart';

/// 单张 Todo 卡片 —— 用户 todo 白色背景，系统 todo 按项目着色。
class TodoCard extends StatelessWidget {
  final TodoItem todo;
  final Project? project; // 仅 system todo 有值
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const TodoCard({
    required this.todo,
    this.project,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  Color _backgroundColor() {
    if (todo.source == TodoSource.user || project == null) return Colors.white;
    return projectCardBackground(project!.color);
  }

  Color? _dotColor() {
    if (todo.source == TodoSource.user || project == null) return null;
    return projectFillColor(project!.color);
  }

  @override
  Widget build(BuildContext context) {
    final bg = _backgroundColor();
    final dot = _dotColor();
    final proj = project; // 本地变量便于 flow promotion

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radiusCard),
          border: Border.all(color: line.withValues(alpha: 0.4)),
        ),
        padding: const EdgeInsets.all(s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部：系统 todo 色点 + 项目名
            if (dot != null || proj != null)
              Padding(
                padding: const EdgeInsets.only(bottom: s6),
                child: Row(
                  children: [
                    if (dot != null)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: dot,
                          shape: BoxShape.circle,
                        ),
                      ),
                    if (proj != null && dot != null)
                      const SizedBox(width: s6),
                    if (proj != null)
                      Expanded(
                        child: Text(
                          proj.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: projectTextColor(proj.color)
                                .withValues(alpha: 0.7),
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            // 标题
            Text(
              todo.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: todo.done ? textTertiary : ink,
                decoration: todo.done ? TextDecoration.lineThrough : null,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
