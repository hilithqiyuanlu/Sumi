import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';
import 'project_editor_page.dart';

/// 项目选择栏。项目仅作为月卡筛选器，不承载详情或编辑操作。
class ProjectTabs extends StatelessWidget {
  const ProjectTabs({super.key});

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watchProjects(context);
    final projects = store.projects;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: s16),
      child: Row(
        children: [
          ...projects.map((project) {
            final isCurrent = project.id == store.currentProjectId;
            final fill = projectFillColor(project.color);
            final title = _projectTitle(project);
            return Padding(
              padding: const EdgeInsets.only(right: s12),
              child: GestureDetector(
                onTap: () {
                  H.click();
                  if (!isCurrent) store.selectProject(project.id);
                },
                onLongPress: () {
                  H.medium();
                  _confirmDeleteProject(context, store, project, title);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: s16,
                    vertical: s14,
                  ),
                  decoration: BoxDecoration(
                    color: fill.withValues(alpha: isCurrent ? 0.52 : 0.24),
                    borderRadius: BorderRadius.circular(radiusCard),
                    border: Border.all(
                      color: isCurrent
                          ? primary500
                          : Colors.transparent,
                      width: isCurrent ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    title,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? ink : ink.withValues(alpha: 0.72),
                    ),
                  ),
                ),
              ),
            );
          }),
          _CreateNewCard(onTap: () => _openEditor(context)),
        ],
      ),
    );
  }

  static String _projectTitle(Project project) {
    final raw = project.goalSummary.trim().isNotEmpty
        ? project.goalSummary.trim()
        : project.name.trim();
    if (raw.isEmpty) return '项目';
    return raw.length <= 16 ? raw : raw.substring(0, 16);
  }

  static void _openEditor(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const ProjectEditorPage(),
      ),
    );
  }

  static Future<void> _confirmDeleteProject(
    BuildContext context,
    SumiStore store,
    Project project,
    String title,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusCard)),
        ),
        title: const Text(
          '删除这个项目？',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: Text(
          '「$title」及其全部月卡和系统事项都会被删除。',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) store.deleteProject(project.id);
  }
}

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
          padding: const EdgeInsets.symmetric(horizontal: s24, vertical: s14),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(radiusCard),
            border: Border.all(color: neutral300),
          ),
          child: const Text(
            '新建项目',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ),
      ),
    );
  }
}
