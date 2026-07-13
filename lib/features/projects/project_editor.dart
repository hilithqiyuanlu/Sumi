import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../store/sumi_store.dart';
import '../../theme/app_theme.dart';

/// 项目编辑弹窗（新建 / 编辑）。
void showProjectEditor(
  BuildContext context,
  SumiStore store, {
  Project? project,
}) {
  final isEditing = project != null;
  final nameCtrl = TextEditingController(text: project?.name ?? '');
  final goalCtrl = TextEditingController(text: project?.goal ?? '');
  final levelCtrl = TextEditingController(text: project?.level ?? '');

  // 周期选项
  const cycleLabels = [
    '1 个月', '2 个月', '3 个月', '4 个月', '5 个月',
    '6 个月', '7 个月', '8 个月', '9 个月', '10 个月', '11 个月',
    '1 年', '1.5 年', '2 年', '1 坤年',
  ];
  const cycleValues = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
    12, 18, 24, 30,
  ];

  // 投入时间选项
  const hourLabels = [
    '6 小时', '10 小时', '15 小时', '20 小时',
    '30 小时', '40 小时', '50 小时', '60 小时', '70 小时',
  ];
  const hourValues = [6, 10, 15, 20, 30, 40, 50, 60, 70];

  var timeConstraint = project?.timeConstraint ?? 0;
  if (!hourValues.contains(timeConstraint)) {
    timeConstraint = hourValues.first;
  }
  var color = project?.color ?? store.nextAvailableColor();
  var cycleMonths = project?.cycleMonths ?? 3;
  if (!cycleValues.contains(cycleMonths)) {
    cycleMonths = cycleValues.first;
  }

  showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEditing ? '编辑项目' : '新建项目'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 名称
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '项目名称',
                      hintText: '输入项目名称',
                    ),
                  ),
                  const SizedBox(height: s12),
                  // 颜色选择
                  const Text('颜色', style: TextStyle(fontSize: 13, color: textTertiary)),
                  const SizedBox(height: s8),
                  Wrap(
                    spacing: s6,
                    runSpacing: s6,
                    children: ProjectColor.values.take(7).map((c) {
                      final selected = c == color;
                      final fill = projectFillColor(c);
                      return GestureDetector(
                        onTap: () => setDialogState(() => color = c),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: fill,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? mintDeep : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: s12),
                  // 目标
                  TextField(
                    controller: goalCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '目标',
                      hintText: '描述你的学习目标',
                    ),
                  ),
                  const SizedBox(height: s12),
                  // 水平
                  TextField(
                    controller: levelCtrl,
                    decoration: const InputDecoration(
                      labelText: '当前水平',
                      hintText: '如：零基础 / 入门 / 进阶',
                    ),
                  ),
                  const SizedBox(height: s12),
                  // 周期
                  const Text('周期', style: TextStyle(fontSize: 13, color: textTertiary)),
                  const SizedBox(height: s6),
                  _ItemWheelPicker<int>(
                    value: cycleMonths,
                    items: cycleValues,
                    labels: cycleLabels,
                    onChanged: (v) => setDialogState(() => cycleMonths = v),
                  ),
                  const SizedBox(height: s12),
                  // 投入时间
                  const Text('投入时间', style: TextStyle(fontSize: 13, color: textTertiary)),
                  const SizedBox(height: s6),
                  _ItemWheelPicker<int>(
                    value: timeConstraint,
                    items: hourValues,
                    labels: hourLabels,
                    onChanged: (v) => setDialogState(() => timeConstraint = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (nameCtrl.text.trim().isEmpty) return;
                  if (isEditing) {
                    store.updateProject(
                      project.id,
                      name: nameCtrl.text.trim(),
                      color: color,
                      goal: goalCtrl.text.trim(),
                      level: levelCtrl.text.trim(),
                      cycleMonths: cycleMonths,
                      timeConstraint: timeConstraint,
                    );
                  } else {
                    store.addProject(
                      name: nameCtrl.text.trim(),
                      color: color,
                      goal: goalCtrl.text.trim(),
                      level: levelCtrl.text.trim(),
                      cycleMonths: cycleMonths,
                      timeConstraint: timeConstraint,
                    );
                  }
                  Navigator.pop(ctx);
                },
                child: Text(isEditing ? '保存' : '创建'),
              ),
            ],
          );
        },
      );
    },
  ).then((_) {
    nameCtrl.dispose();
    goalCtrl.dispose();
    levelCtrl.dispose();
  });
}

/// 通用选项滚轮选择器。
class _ItemWheelPicker<T> extends StatefulWidget {
  final T value;
  final List<T> items;
  final List<String> labels;
  final ValueChanged<T> onChanged;

  const _ItemWheelPicker({
    required this.value,
    required this.items,
    required this.labels,
    required this.onChanged,
  });

  @override
  State<_ItemWheelPicker<T>> createState() => _ItemWheelPickerState<T>();
}

class _ItemWheelPickerState<T> extends State<_ItemWheelPicker<T>> {
  late final FixedExtentScrollController _wheelCtrl;

  @override
  void initState() {
    super.initState();
    final idx = widget.items.indexOf(widget.value);
    _wheelCtrl = FixedExtentScrollController(
      initialItem: idx >= 0 ? idx : 0,
    );
  }

  @override
  void dispose() {
    _wheelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: mintDeep.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(s8),
                ),
              ),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: _wheelCtrl,
            itemExtent: 36,
            diameterRatio: 2.5,
            perspective: 0.005,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (index) {
              if (index >= 0 && index < widget.items.length) {
                widget.onChanged(widget.items[index]);
              }
            },
            childDelegate: ListWheelChildBuilderDelegate(
              builder: (context, index) {
                final label = widget.labels[index];
                final isSelected =
                    widget.items[index] == widget.value;
                return Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: isSelected ? 17 : 15,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w400,
                      color: isSelected ? mintDeep : textTertiary,
                    ),
                  ),
                );
              },
              childCount: widget.items.length,
            ),
          ),
        ],
      ),
    );
  }
}

/// 月卡编辑弹窗。
void showMonthCardEditor(
  BuildContext context,
  SumiStore store, {
  required MonthCard card,
}) {
  final titleCtrl = TextEditingController(text: card.title);
  final summaryCtrl = TextEditingController(text: card.summary ?? '');

  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('编辑月卡'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: '标题',
                hintText: '输入月卡标题',
              ),
            ),
            const SizedBox(height: s12),
            TextField(
              controller: summaryCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '摘要（可选）',
                hintText: '简短描述本月计划',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (titleCtrl.text.trim().isEmpty) return;
              store.updateMonthCard(
                card.id,
                title: titleCtrl.text.trim(),
                summary:
                    summaryCtrl.text.trim().isEmpty ? null : summaryCtrl.text.trim(),
              );
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      );
    },
  ).then((_) {
    titleCtrl.dispose();
    summaryCtrl.dispose();
  });
}
