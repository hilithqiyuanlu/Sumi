import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import 'project_card.dart';
import 'project_editor.dart';

/// 项目切换 Tab 栏 —— 横向滚动，当前项目高亮。
class ProjectTabs extends StatelessWidget {
  const ProjectTabs({super.key});

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watch(context);
    final projects = store.projects;
    final currentId = store.currentProjectId;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: s4),
      child: Row(
        children: [
          ...projects.map((p) {
            final selected = p.id == currentId;
            final fill = projectFillColor(p.color);
            final txt = projectTextColor(p.color, selected: selected);

            return Padding(
              padding: const EdgeInsets.only(right: s8),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  store.selectProject(p.id);
                },
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  confirmDeleteProject(context, store, p);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(horizontal: s16, vertical: s8),
                  decoration: BoxDecoration(
                    color: selected ? fill : fill.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? fill.withValues(alpha: 0.8)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: txt,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: s6),
                      Text(
                        p.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: txt,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          // 添加按钮
          GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                showProjectEditor(context, store);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: s12, vertical: s8),
                decoration: BoxDecoration(
                  color: surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: line.withValues(alpha: 0.3), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded,
                        size: iconSmall, color: textTertiary),
                    const SizedBox(width: s4),
                    Text(
                      '新建',
                      style: TextStyle(
                          fontSize: 13, color: textTertiary),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
