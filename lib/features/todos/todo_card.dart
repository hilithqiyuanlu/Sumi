import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/app_theme.dart';

/// 单张 Todo 卡片 —— 支持 pin/done 交互、项目归属、提醒显示。
///
/// 点击分区：
/// - 左上角 done 图标 → onTapDone
/// - 右上角 pin 图标 → onTapPin
/// - 卡片主体 → onTapBody（打开编辑面板）
///
/// 拖拽由外层 LongPressDraggable 处理，不在本组件内。
class TodoCard extends StatefulWidget {
  final TodoItem todo;
  final Project? project;
  final VoidCallback onTapDone;
  final VoidCallback onTapPin;
  final VoidCallback onTapBody;
  final bool isDragging; // 是否正被拖拽（反馈用）
  final bool isReadonly; // 07 轮：过去日期只读

  const TodoCard({
    required this.todo,
    this.project,
    required this.onTapDone,
    required this.onTapPin,
    required this.onTapBody,
    this.isDragging = false,
    this.isReadonly = false,
    super.key,
  });

  @override
  State<TodoCard> createState() => _TodoCardState();
}

class _TodoCardState extends State<TodoCard> {
  bool _pressed = false;

  Color _backgroundColor() {
    if (widget.project != null) return projectCardBackground(widget.project!.color);
    return Colors.white; // design spec: --color-card is white
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.todo.done;
    final pinned = widget.todo.pinned;
    final bg = _backgroundColor();

    return Opacity(
      opacity: done ? 0.6 : 1.0,
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(
          _pressed
              ? const <double>[0.97, 0, 0, 0, 0, 0, 0.97, 0, 0, 0, 0, 0, 0.97, 0, 0, 0, 0, 0, 1, 0]
              : const <double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0],
        ),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: widget.isDragging ? 1.02 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(radiusCard),
                boxShadow: widget.isDragging
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : (widget.project == null ? shadow1 : null),
                border: Border.all(color: line.withValues(alpha: 0.15), width: 0.5),
              ),
              padding: const EdgeInsets.all(s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 第一行：done 图标 + 标题 + pin 图标
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 左上角 done toggle
                      GestureDetector(
                        onTap: widget.isReadonly ? null : widget.onTapDone,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.only(right: s8, top: s2),
                          child: Icon(
                            done ? Icons.check_circle : Icons.circle_outlined,
                            size: iconSection,
                            color: widget.isReadonly
                                ? (done ? textTertiary : line)
                                : (done ? mintDeep : line),
                          ),
                        ),
                      ),
                      // 标题（点击打开编辑面板，固定 2 行）
                      Expanded(
                        child: GestureDetector(
                          onTap: widget.onTapBody,
                          behavior: HitTestBehavior.opaque,
                          child: Text(
                            widget.todo.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: done ? textTertiary : ink,
                              decoration:
                                  done ? TextDecoration.lineThrough : null,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                      // 右上角 pin toggle（过去日期隐藏）
                      if (!widget.isReadonly)
                        GestureDetector(
                          onTap: widget.onTapPin,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.only(left: s4),
                            child: Icon(
                              pinned ? Icons.push_pin : Icons.push_pin,
                              size: iconSection,
                              color: pinned ? mintDeep : textTertiary.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                    ],
                  ),
                  // 第二行：项目归属（系统 todo 不显示，仅用户 todo 显示）
                  if (widget.todo.source != TodoSource.system &&
                      (widget.todo.projectId != null || widget.project != null)) ...[
                    const SizedBox(height: s6),
                    _ProjectRow(project: widget.project, todo: widget.todo),
                  ],
                  // 第三行：提醒时间（仅当设置了提醒时显示）
                  if (widget.todo.reminderTime != null && widget.todo.reminderTime!.isNotEmpty) ...[
                    const SizedBox(height: s6),
                    _ReminderRow(time: widget.todo.reminderTime!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 项目归属行。
class _ProjectRow extends StatelessWidget {
  final Project? project;
  final TodoItem todo;

  const _ProjectRow({this.project, required this.todo});

  @override
  Widget build(BuildContext context) {
    final projColor = project?.color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (projColor != null) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: projectFillColor(projColor),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: s6),
        ],
        Flexible(
          child: Text(
            project?.name ?? '',
            style: TextStyle(
              fontSize: 11,
              color: projColor != null
                  ? projectTextColor(projColor).withValues(alpha: 0.7)
                  : textTertiary,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 提醒时间行。
class _ReminderRow extends StatelessWidget {
  final String time;

  const _ReminderRow({required this.time});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule, size: 14, color: textTertiary.withValues(alpha: 0.6)),
        const SizedBox(width: s4),
        Text(
          time,
          style: TextStyle(
            fontSize: 12,
            color: textTertiary.withValues(alpha: 0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
