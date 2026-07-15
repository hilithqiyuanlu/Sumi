import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import 'project_editor_page.dart';

/// 共享删除确认对话框（project_card 和 project_tabs 共用）。
void confirmDeleteProject(BuildContext context, SumiStore store, Project p) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusCard)),
      ),
      title: const Text('删除项目', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      content: Text('确定要删除「${p.name}」吗？\n\n该项目的所有月卡和系统事项将一并删除。', style: const TextStyle(fontSize: 14)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: danger),
          onPressed: () {
            store.deleteProject(p.id);
            Navigator.pop(ctx);
          },
          child: const Text('删除'),
        ),
      ],
    ),
  );
}

/// 可折叠项目信息卡 —— 显示目标 / 水平 / 周期 / 约束。
class ProjectCard extends StatefulWidget {
  final Project project;
  const ProjectCard({required this.project, super.key});

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.read(context);
    final p = widget.project;
    final fill = projectFillColor(p.color);

    return Container(
      decoration: BoxDecoration(
        color: fill.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(radiusCard),
        boxShadow: const [...shadow1],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            borderRadius: BorderRadius.circular(radiusCard),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(s16, s10, s12, s10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p.goalSummary.isNotEmpty ? p.goalSummary : p.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down,
                        color: textTertiary),
                  ),
                ],
              ),
            ),
          ),
          // 展开内容
          ClipRect(
            child: AnimatedAlign(
              alignment: Alignment.topCenter,
              heightFactor: _expanded ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOutCubic,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(s16, 0, s16, s10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.goal.isNotEmpty) ...[
                      _detailRow('目标', p.goal, multiline: true),
                      const SizedBox(height: s6),
                    ],
                    if (p.level.isNotEmpty) ...[
                      _detailRow('水平', p.level),
                      const SizedBox(height: s6),
                    ],
                    _detailRow('周期', '${p.cycleMonths} 个月'),
                    if (p.timeConstraint > 0) ...[
                      const SizedBox(height: s6),
                      _detailRow('投入', '${p.timeConstraint} 小时/周'),
                    ],
                    const SizedBox(height: s8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              fullscreenDialog: true,
                              builder: (_) => ProjectEditorPage(project: p),
                            ),
                          ),
                          icon:
                              const Icon(Icons.edit, size: iconSmall),
                          label: const Text('编辑'),
                        ),
                        const SizedBox(width: s8),
                        TextButton.icon(
                          onPressed: () => confirmDeleteProject(context, store, p),
                          icon: Icon(Icons.delete_outline,
                              size: iconSmall, color: danger),
                          label: Text('删除',
                              style: TextStyle(color: danger)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool multiline = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: textTertiary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, color: ink),
            maxLines: multiline ? null : 1,
            overflow: multiline ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
