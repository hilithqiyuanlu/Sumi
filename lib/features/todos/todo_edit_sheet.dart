import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../store/sumi_store.dart';
import '../../theme/app_theme.dart';
import '../shared/drag_handle.dart';

/// 底部弹出编辑面板 —— 文本编辑 + 润色/项目/定时/复制。
Future<void> showTodoEditSheet(
  BuildContext context,
  SumiStore store,
  TodoItem todo,
) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radiusCard)),
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
  bool _polishing = false;
  String? _polishedText;
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

  Future<void> _polish() async {
    setState(() => _polishing = true);
    _polishedText = null;

    final result = await _store.polishTodoTitle(_todo.id);

    if (!mounted) return;
    setState(() => _polishing = false);

    if (result == null || result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('润色失败，请检查网络或 API 配置'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _polishedText = result;
  }

  void _applyPolish() {
    if (_polishedText == null) return;
    _titleCtrl.text = _polishedText!;
    setState(() {
      _polishedText = null;
    });
  }

  void _toggleProjects() {
    setState(() => _showProjects = !_showProjects);
  }

  void _assignProject(String? projectId) {
    _store.updateTodoProject(_todo.id, projectId);
    setState(() => _showProjects = false);
  }

  Future<void> _pickReminder() async {
    // 已有定时 → 弹出选择
    if (_todo.reminderTime != null) {
      final action = await showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusCard)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(s16, s16, s16, s8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DragHandle(),
                  const SizedBox(height: s16),
                  ListTile(
                    leading: const Icon(Icons.timer_rounded, color: ink),
                    title: Text('修改定时（当前 ${_todo.reminderTime}）'),
                    onTap: () => Navigator.pop(ctx, 'edit'),
                  ),
                  ListTile(
                    leading: Icon(Icons.clear_rounded, color: danger),
                    title: Text('清除定时', style: TextStyle(color: danger)),
                    onTap: () => Navigator.pop(ctx, 'clear'),
                  ),
                  const SizedBox(height: s8),
                ],
              ),
            ),
          );
        },
      );

      if (!mounted) return;
      if (action == 'clear') {
        _clearReminder();
        return;
      }
      if (action != 'edit') return;
    }

    final initial = _todo.reminderTime != null
        ? _parseTime(_todo.reminderTime!)
        : null;

    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? const TimeOfDay(hour: 9, minute: 0),
    );

    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      _store.updateTodoReminder(_todo.id, formatted);
      if (mounted) setState(() {});
    }
  }

  void _clearReminder() {
    _store.updateTodoReminder(_todo.id, null);
    if (mounted) setState(() {});
  }

  void _copy() {
    HapticFeedback.selectionClick();
    Clipboard.setData(ClipboardData(text: _todo.title));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _save() async {
    final newTitle = _titleCtrl.text.trim();
    final newBody = _bodyCtrl.text.trim();

    // 标题为空或没有任何改动 → 直接关闭
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
      setState(() => _polishing = true);
      final condensed = await _store.polishText(newTitle);
      if (mounted) {
        setState(() => _polishing = false);
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

  TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: int.tryParse(parts[1]) ?? 0,
    );
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
        padding: EdgeInsets.fromLTRB(s16, s16, s16, bottomInset + s8),
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
                  borderSide: BorderSide(color: line.withValues(alpha: 0.4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(radiusPanel),
                  borderSide: BorderSide(color: line.withValues(alpha: 0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(radiusPanel),
                  borderSide: const BorderSide(color: ink),
                ),
                contentPadding: const EdgeInsets.all(s12),
              ),
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: s12),

            // 四个操作按钮
            Row(
              children: [
                _ActionChip(
                  icon: Icons.auto_fix_high_rounded,
                  label: '润色',
                  loading: _polishing,
                  onTap: _polish,
                ),
                const SizedBox(width: s8),
                _ActionChip(
                  icon: Icons.folder_rounded,
                  label: '项目',
                  active: todo.projectId != null,
                  onTap: _toggleProjects,
                ),
                const SizedBox(width: s8),
                _ActionChip(
                  icon: Icons.timer_rounded,
                  label: todo.reminderTime ?? '定时',
                  active: todo.reminderTime != null,
                  onTap: _pickReminder,
                ),
                const SizedBox(width: s8),
                _ActionChip(
                  icon: Icons.copy_rounded,
                  label: '复制',
                  onTap: _copy,
                ),
              ],
            ),
            const SizedBox(height: s12),

            // 润色结果预览
            if (_polishedText != null) _PolishPreview(
              original: todo.title,
              polished: _polishedText!,
              onApply: _applyPolish,
              onRetry: _polish,
            ),

            // 项目选择
            if (_showProjects) _ProjectPicker(
              store: _store,
              selectedId: todo.projectId,
              onSelect: _assignProject,
            ),

            const SizedBox(height: s8),

            // 底部按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _delete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: danger,
                    ),
                    child: const Text('删除'),
                  ),
                ),
                const SizedBox(width: s12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('保存'),
                  ),
                ),
              ],
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

/// 操作按钮 chip。
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool loading;
  final bool active;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: s12, vertical: s8),
        decoration: BoxDecoration(
          color: active ? mintDeep.withValues(alpha: 0.12) : line.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(radiusPill),
          border: active
              ? Border.all(color: mintDeep.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                : Icon(icon, size: 16, color: active ? mintDeep : ink),
            const SizedBox(width: s4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? mintDeep : ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 润色结果预览。
class _PolishPreview extends StatelessWidget {
  final String original;
  final String polished;
  final VoidCallback onApply;
  final VoidCallback onRetry;

  const _PolishPreview({
    required this.original,
    required this.polished,
    required this.onApply,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: s12),
      padding: const EdgeInsets.all(s12),
      decoration: BoxDecoration(
        color: mint.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(radiusPanel),
        boxShadow: const [...shadow1],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_fix_high_rounded, size: 16, color: mintDeep),
              const SizedBox(width: s6),
              Text(
                '润色结果',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: mintDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: s8),
          Text(
            polished,
            style: const TextStyle(fontSize: 14, color: ink, height: 1.35),
          ),
          const SizedBox(height: s8),
          Row(
            children: [
              TextButton.icon(
                onPressed: onApply,
                icon: Icon(Icons.check_rounded, size: 16, color: mintDeep),
                label: Text(
                  '应用',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: mintDeep,
                  ),
                ),
              ),
              const SizedBox(width: s4),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text(
                  '重试',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
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
        color: paper,
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
              Icon(Icons.check_rounded, size: 18, color: mintDeep),
          ],
        ),
      ),
    );
  }
}
