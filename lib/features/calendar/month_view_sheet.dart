import 'package:flutter/material.dart';

import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../projects/month_card_pager.dart';
import '../projects/project_tabs.dart';
import '../shared/drag_handle.dart';
import 'month_calendar.dart';

/// 展开的月视图层 —— 日历 + 项目区。上下拖拽把手提供视觉引导，手势由父级处理。
class MonthViewSheet extends StatelessWidget {
  const MonthViewSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watchProjects(context);
    SumiScope.watchTodos(context);
    final project = store.currentProject;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Container(
        decoration: const BoxDecoration(
          color: paper,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(radiusCardHeader)),
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

                  // 项目选择栏
                  const ProjectTabs(),
                  const SizedBox(height: s12),

                  // 月卡 Pager
                  const SizedBox(height: s8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final slide = Tween<Offset>(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child: project == null
                        ? const SizedBox.shrink(key: ValueKey('no-project'))
                        : KeyedSubtree(
                            key: ValueKey(project.id),
                            child: MonthCardPager(project: project),
                          ),
                  ),
                  // 底部拖拽把手（上推收起）
                  const SizedBox(height: s24),
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: s24),
                      child: DragHandle(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
