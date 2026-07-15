import 'package:flutter/material.dart';
import '../../utils/haptics.dart';

import '../../models/models.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import 'project_card.dart';
import 'project_editor_page.dart';

/// 项目选择卡片栏 —— 左对齐横向滚动。
/// 单击展开/收起项目详情，最右为新建入口。
class ProjectTabs extends StatefulWidget {
  const ProjectTabs({super.key});

  @override
  State<ProjectTabs> createState() => _ProjectTabsState();
}

class _ProjectTabsState extends State<ProjectTabs> {
  String? _expandedProjectId;

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watch(context);
    final projects = store.projects;

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: _expandedProjectId != null ? 240 : 60,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: s16),
          children: [
            // 已有项目卡片
            ...projects.map((p) {
              final isExpanded = _expandedProjectId == p.id;
              final isCurrent = p.id == store.currentProjectId;
              final fill = projectFillColor(p.color);

              return Padding(
                padding: const EdgeInsets.only(right: s12),
                child: GestureDetector(
                  onTap: () {
                    H.click();
                    setState(() {
                      _expandedProjectId = isExpanded ? null : p.id;
                    });
                    store.selectProject(p.id);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: 280,
                    decoration: BoxDecoration(
                      color: fill.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(radiusCard),
                      boxShadow: const [...shadow1],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(s16, s14, s10, s14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.goalSummary.isNotEmpty
                                      ? p.goalSummary
                                      : (p.name.isNotEmpty ? p.name : '新项目'),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isCurrent ? ink : ink.withValues(alpha: 0.8),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              AnimatedRotation(
                                turns: isExpanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(Icons.keyboard_arrow_down,
                                    size: 20, color: ink.withValues(alpha: 0.45)),
                              ),
                            ],
                          ),
                          // 展开内容
                          ClipRect(
                            child: AnimatedAlign(
                              alignment: Alignment.topCenter,
                              heightFactor: isExpanded ? 1 : 0,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOutCubic,
                              child: Padding(
                                padding: const EdgeInsets.only(top: s10),
                                child: _ExpandedInfo(
                                  project: p,
                                  onEdit: () => _openEditor(context, project: p),
                                  onDelete: () =>
                                      confirmDeleteProject(context, store, p),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            // 新建项目卡片
            _CreateNewCard(
              onTap: () => _openEditor(context),
            ),
          ],
        ),
      ),
    );
  }

  void _openEditor(BuildContext context, {Project? project}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProjectEditorPage(project: project),
      ),
    );
  }
}

/// 展开后显示的项目详情。
class _ExpandedInfo extends StatelessWidget {
  final Project project;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ExpandedInfo({
    required this.project,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = project;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
        const SizedBox(height: s10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit, size: iconSmall),
              label: const Text('编辑'),
            ),
            const SizedBox(width: s8),
            TextButton.icon(
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline,
                  size: iconSmall, color: danger),
              label: Text('删除', style: TextStyle(color: danger)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value, {bool multiline = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: ink,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: ink),
            maxLines: multiline ? null : 1,
            overflow: multiline ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 新建项目入口卡片。
class _CreateNewCard extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateNewCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: s16),
      child: GestureDetector(
        onTap: () {
          H.click();
          onTap();
        },
        child: Container(
          width: 160,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radiusCard),
            border: Border.all(
              color: line.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: const [...shadow1],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: surfaceAlt,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, size: 20, color: textTertiary),
              ),
              const SizedBox(height: s8),
              const Text(
                '新建项目',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}