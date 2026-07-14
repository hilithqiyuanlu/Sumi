import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../projects/month_card_pager.dart';
import '../projects/project_card.dart';
import '../projects/project_editor_page.dart';
import '../projects/project_tabs.dart';
import '../shared/drag_handle.dart';
import 'month_calendar.dart';

/// 展开的月视图层 —— 日历 + 项目区。上下拖拽把手提供视觉引导，手势由父级处理。
class MonthViewSheet extends StatelessWidget {
  const MonthViewSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watch(context);
    final project = store.currentProject;

    return Container(
      decoration: const BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(radiusCardHeader)),
      ),
      child: Column(
        children: [
          // 系统状态栏避开
          SizedBox(height: MediaQuery.of(context).padding.top),
          // 月份标题（居中）
          Padding(
            padding: const EdgeInsets.only(top: s16, bottom: s8),
            child: Center(
              child: Text(
                '${store.selectedDate.month}月',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
          ),
          // 可滚动内容
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 月历
                  const MonthCalendar(),
                  const SizedBox(height: s20),

                  // 项目 Tab 栏
                  const ProjectTabs(),
                  const SizedBox(height: s12),

                  // 项目卡
                  if (project != null) ...[
                    const SizedBox(height: s4),
                    ProjectCard(project: project),
                    const SizedBox(height: s16),

                    // 月卡 Pager
                    MonthCardPager(project: project),
                  ] else ...[
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) => const ProjectEditorPage(),
                          ),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(s24),
                        decoration: BoxDecoration(
                          color: paper,
                          borderRadius: BorderRadius.circular(radiusCard),
                          border: Border.all(color: line.withValues(alpha: 0.3)),
                        ),
                        child: const Center(
                          child: Text(
                            '点击此处创建第一个项目',
                            style: TextStyle(color: textTertiary),
                          ),
                        ),
                      ),
                    ),
                  ],
                  // 底部拖拽把手（上推收起）
                  const SizedBox(height: s12),
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: s16),
                      child: DragHandle(),
                    ),
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
