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
  final timeCtrl =
      TextEditingController(text: project?.timeConstraint ?? '');
  var color = project?.color ?? store.nextAvailableColor();
  var cycleMonths = project?.cycleMonths ?? 3;

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
                  Row(
                    children: ProjectColor.values.map((c) {
                      final selected = c == color;
                      final fill = projectFillColor(c);
                      return Padding(
                        padding: const EdgeInsets.only(right: s8),
                        child: GestureDetector(
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
                  DropdownButtonFormField<int>(
                    initialValue: cycleMonths,
                    decoration: const InputDecoration(labelText: '周期（月）'),
                    items: List.generate(12, (i) => i + 1)
                        .map((m) => DropdownMenuItem(
                            value: m, child: Text('$m 个月')))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => cycleMonths = v);
                    },
                  ),
                  const SizedBox(height: s12),
                  // 投入时间
                  TextField(
                    controller: timeCtrl,
                    decoration: const InputDecoration(
                      labelText: '投入时间',
                      hintText: '如：每天 1h / 周末 3h',
                    ),
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
                      timeConstraint: timeCtrl.text.trim(),
                    );
                  } else {
                    store.addProject(
                      name: nameCtrl.text.trim(),
                      color: color,
                      goal: goalCtrl.text.trim(),
                      level: levelCtrl.text.trim(),
                      cycleMonths: cycleMonths,
                      timeConstraint: timeCtrl.text.trim(),
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
    timeCtrl.dispose();
  });
}

/// 月卡编辑弹窗。
void showMonthCardEditor(
  BuildContext context,
  SumiStore store, {
  MonthCard? card,
  String? projectId,
  int? monthIndex,
}) {
  final isEditing = card != null;
  final titleCtrl = TextEditingController(text: card?.title ?? '');
  final summaryCtrl = TextEditingController(text: card?.summary ?? '');

  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(isEditing ? '编辑月卡' : '创建月卡'),
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
              if (isEditing) {
                store.updateMonthCard(
                  card.id,
                  title: titleCtrl.text.trim(),
                  summary:
                      summaryCtrl.text.trim().isEmpty ? null : summaryCtrl.text.trim(),
                );
              } else {
                store.addMonthCard(
                  projectId: projectId!,
                  monthIndex: monthIndex!,
                  title: titleCtrl.text.trim(),
                  summary:
                      summaryCtrl.text.trim().isEmpty ? null : summaryCtrl.text.trim(),
                );
              }
              Navigator.pop(ctx);
            },
            child: Text(isEditing ? '保存' : '创建'),
          ),
        ],
      );
    },
  ).then((_) {
    titleCtrl.dispose();
    summaryCtrl.dispose();
  });
}
