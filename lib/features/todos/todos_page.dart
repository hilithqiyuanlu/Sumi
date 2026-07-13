import 'package:flutter/material.dart';

import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../calendar/date_strip.dart';
import '../calendar/month_view_sheet.dart';
import 'todo_edit_sheet.dart';
import 'todo_grid.dart';
import 'todo_input.dart';

/// 事项首页 —— 日期条 + 网格 + 输入框，支持展开月视图。
class TodosPage extends StatelessWidget {
  const TodosPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watch(context);

    return Scaffold(
      body: Stack(
        children: [
          // 主内容
          Column(
            children: [
              // 安全区 + 日期条
              Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + s8,
                  left: s16,
                  right: s16,
                ),
                child: DateStrip(
                  onExpandMonth: () => store.setMonthViewExpanded(true),
                ),
              ),
              const SizedBox(height: s12),
              // 网格
              Expanded(
                child: TodoGrid(
                  onTapBody: (todo) =>
                      showTodoEditSheet(context, store, todo),
                ),
              ),
              // 输入框
              const TodoInput(),
            ],
          ),
          // 展开的月视图（覆盖层）—— 带动画滑入
          AnimatedSlide(
            offset: store.monthViewExpanded
                ? Offset.zero
                : const Offset(0, -1.05),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: store.monthViewExpanded ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
              child: const MonthViewSheet(),
            ),
          ),
        ],
      ),
    );
  }
}
