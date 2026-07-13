import 'package:flutter/material.dart';

import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../calendar/date_strip.dart';
import '../calendar/month_view_sheet.dart';
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
              const Expanded(child: TodoGrid()),
              // 输入框
              const TodoInput(),
            ],
          ),
          // 展开的月视图（覆盖层）
          if (store.monthViewExpanded)
            const MonthViewSheet(),
        ],
      ),
    );
  }
}
