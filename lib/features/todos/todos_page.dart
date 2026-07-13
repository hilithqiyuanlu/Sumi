import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../calendar/date_strip.dart';
import '../calendar/month_view_sheet.dart';
import 'todo_edit_sheet.dart';
import 'todo_grid.dart';
import 'todo_input.dart';

/// 事项首页 —— 日期条 + 网格 + 输入框，支持展开月视图。
class TodosPage extends StatefulWidget {
  const TodosPage({super.key});

  @override
  State<TodosPage> createState() => _TodosPageState();
}

class _TodosPageState extends State<TodosPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 320,
    damping: 28,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 手势
  // ---------------------------------------------------------------------------

  void _onDragUpdate(DragUpdateDetails d) {
    final h = MediaQuery.of(context).size.height;
    _controller.value =
        (_controller.value + d.delta.dy / h).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    final shouldOpen = _controller.value > 0.25 || velocity > 500;
    final target = shouldOpen ? 1.0 : 0.0;

    _controller.animateWith(SpringSimulation(
      _spring,
      _controller.value,
      target,
      velocity / MediaQuery.of(context).size.height,
    ));
  }

  void _openMonth() {
    _controller.animateTo(1.0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic);
  }

  void _closeMonth() {
    _controller.animateTo(0.0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  int _lastNavigateSignal = 0;

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watch(context);
    final screenH = MediaQuery.of(context).size.height;

    // 响应 MainShell 二次点击 Tab 的回退信号
    if (_lastNavigateSignal != store.navigateToTodaySignal) {
      _lastNavigateSignal = store.navigateToTodaySignal;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _closeMonth();
        store.selectDate(DateTime.now());
      });
    }

    return Scaffold(
      body: Stack(
        children: [
          // 主内容
          Column(
            children: [
              // 安全区 + 日期条（含垂直拖拽手势）
              Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + s8,
                  left: s16,
                  right: s16,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                  child: DateStrip(onExpandMonth: _openMonth),
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
          // 月视图覆盖层 —— 跟手 + 弹簧吸附
          IgnorePointer(
            ignoring: _controller.value < 0.01,
            child: Transform.translate(
              offset: Offset(0, (_controller.value - 1) * screenH),
              child: MonthViewSheet(onClose: _closeMonth),
            ),
          ),
        ],
      ),
    );
  }
}
