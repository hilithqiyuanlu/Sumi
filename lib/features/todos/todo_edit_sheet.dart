import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../store/sumi_store.dart';
import '../../theme/app_theme.dart';
import '../shared/drag_handle.dart';

/// 底部弹出编辑面板 —— 标题 + 备注编辑，标记/项目/定时操作，删除/保存。
Future<void> showTodoEditSheet(
  BuildContext context,
  SumiStore store,
  TodoItem todo,
) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radiusCardHeader)),
    ),
    builder: (ctx) => _TodoEditSheet(store: store, todo: todo),
  );
}

class _TodoEditSheet extends StatefulWidget {
  final SumiStore store;
  final TodoItem todo;

  const _TodoEditSheet({required this.store, required this.todo});

  @override
  State<_TodoEditSheet> createState() => _TodoEditSheetState();
}

class _TodoEditSheetState extends State<_TodoEditSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  bool _saving = false;
  bool _showProjects = false;

  SumiStore get _store => widget.store;
  TodoItem get _todo => _store.todoItems.firstWhere(
        (t) => t.id == widget.todo.id,
        orElse: () => widget.todo,
      );

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: _todo.title);
    _bodyCtrl = TextEditingController(text: _todo.body ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _toggleProjects() {
    setState(() => _showProjects = !_showProjects);
  }

  void _assignProject(String? projectId) {
    _store.updateTodoProject(_todo.id, projectId);
    setState(() => _showProjects = false);
  }

  Future<void> _save() async {
    final newTitle = _titleCtrl.text.trim();
    final newBody = _bodyCtrl.text.trim();

    if (newTitle.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final titleChanged = newTitle != _todo.title;
    final bodyChanged = newBody != (_todo.body ?? '');

    if (!titleChanged && !bodyChanged) {
      Navigator.pop(context);
      return;
    }

    // 标题 >18 字触发 AI 凝练
    if (titleChanged && newTitle.length > 18) {
      setState(() => _saving = true);
      final condensed = await _store.polishText(newTitle);
      if (mounted) {
        setState(() => _saving = false);
        _store.updateTodo(
          _todo.id,
          title: condensed ?? newTitle,
          body: bodyChanged ? newBody : null,
        );
        Navigator.pop(context);
      }
    } else {
      _store.updateTodo(
        _todo.id,
        title: titleChanged ? newTitle : null,
        body: bodyChanged ? newBody : null,
      );
      Navigator.pop(context);
    }
  }

  void _delete() {
    _store.deleteTodo(_todo.id);
    Navigator.pop(context);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final todo = _todo; // 使用最新数据
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(s16, s16, s16, bottomInset + s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖拽把手
            const DragHandle(),
            const SizedBox(height: s16),

            // 标题输入
            TextField(
              controller: _titleCtrl,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: '编辑事项标题',
              ),
            ),
            const SizedBox(height: s12),

            // 备注（纯用户笔记，不参与 AI）
            TextField(
              controller: _bodyCtrl,
              maxLines: 8,
              minLines: 2,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: '备注',
                filled: true,
                fillColor: surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(radiusPanel),
                  borderSide: BorderSide(color: line.withValues(alpha: 0.2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(radiusPanel),
                  borderSide: BorderSide(color: line.withValues(alpha: 0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(radiusPanel),
                  borderSide: const BorderSide(color: primary500),
                ),
                contentPadding: const EdgeInsets.all(s12),
              ),
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: s12),

            // 操作栏：左侧 chips + 右侧按钮
            Row(
              children: [
                _ActionChip(
                  icon: todo.done ? Icons.radio_button_unchecked : Icons.check_circle_outline,
                  label: todo.done ? '标记未完成' : '标记完成',
                  active: todo.done,
                  onTap: () {
                    _store.toggleTodo(_todo.id);
                    if (mounted) setState(() {});
                  },
                ),
                const SizedBox(width: s6),
                _ActionChip(
                  icon: Icons.folder_outlined,
                  label: '项目',
                  active: todo.projectId != null,
                  onTap: _toggleProjects,
                ),
                const Spacer(),
                _TextButton(
                  label: '删除',
                  color: danger,
                  onTap: _delete,
                ),
                const SizedBox(width: s8),
                _FilledButton(
                  label: '保存',
                  loading: _saving,
                  onTap: _save,
                ),
              ],
            ),
            const SizedBox(height: s12),

            // 项目选择
            if (_showProjects) _ProjectPicker(
              store: _store,
              selectedId: todo.projectId,
              onSelect: _assignProject,
            ),
            const SizedBox(height: s8),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

/// 紧凑文字按钮。
class _TextButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _TextButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: s12, vertical: s8),
        decoration: BoxDecoration(
          color: surfaceAlt,
          borderRadius: BorderRadius.circular(radiusPill),
          border: Border.all(color: line.withValues(alpha: 0.2), width: 0.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// 紧凑实心按钮。
class _FilledButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;

  const _FilledButton({
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: s16, vertical: s8),
        decoration: BoxDecoration(
          color: primary500,
          borderRadius: BorderRadius.circular(radiusPill),
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}

/// 操作按钮 chip。
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? color;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color;
    final iconColor = c ?? (active ? mintDeep : ink);
    final textColor = c ?? (active ? mintDeep : ink);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: s12, vertical: s8),
        decoration: BoxDecoration(
          color: active && c == null ? mintDeep.withValues(alpha: 0.12) : surfaceAlt,
          borderRadius: BorderRadius.circular(radiusPill),
          border: active && c == null
              ? Border.all(color: mintDeep.withValues(alpha: 0.4))
              : Border.all(color: line.withValues(alpha: 0.2), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: s4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 项目选择器。
class _ProjectPicker extends StatelessWidget {
  final SumiStore store;
  final String? selectedId;
  final void Function(String? projectId) onSelect;

  const _ProjectPicker({
    required this.store,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final projects = store.projectList;

    return Container(
      margin: const EdgeInsets.only(bottom: s12),
      padding: const EdgeInsets.all(s12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radiusPanel),
        border: Border.all(color: line.withValues(alpha: 0.3)),
        boxShadow: const [...shadow1],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '归属项目',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textTertiary,
            ),
          ),
          const SizedBox(height: s8),
          // 无项目选项
          _ProjectOption(
            name: '无项目（白色）',
            color: null,
            selected: selectedId == null,
            onTap: () => onSelect(null),
          ),
          // 已有项目
          ...projects.map((p) => _ProjectOption(
                name: p.name,
                color: p.color,
                selected: selectedId == p.id,
                onTap: () => onSelect(p.id),
              )),
        ],
      ),
    );
  }
}

/// 单个项目选项。
class _ProjectOption extends StatelessWidget {
  final String name;
  final ProjectColor? color;
  final bool selected;
  final VoidCallback onTap;

  const _ProjectOption({
    required this.name,
    this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: s4),
        padding: const EdgeInsets.symmetric(horizontal: s10, vertical: s8),
        decoration: BoxDecoration(
          color: selected
              ? (color != null
                  ? projectCardBackground(color!)
                  : line.withValues(alpha: 0.2))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(s8),
        ),
        child: Row(
          children: [
            if (color != null) ...[
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: projectFillColor(color!),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: s8),
            ] else ...[
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: paper,
                  shape: BoxShape.circle,
                  border: Border.all(color: line),
                ),
              ),
              const SizedBox(width: s8),
            ],
            Text(
              name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: ink,
              ),
            ),
            const Spacer(),
            if (selected)
              Icon(Icons.check, size: 18, color: mintDeep),
          ],
        ),
      ),
    );
  }
}
