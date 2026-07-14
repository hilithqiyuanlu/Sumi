import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/utils.dart';
import '../shared/drag_handle.dart';

/// 折叠态日期条 —— 当月日期 chip 横向滚动 + 下拉展开月视图。
class DateStrip extends StatefulWidget {
  final VoidCallback onExpandMonth;
  const DateStrip({required this.onExpandMonth, super.key});

  @override
  State<DateStrip> createState() => _DateStripState();
}

class _DateStripState extends State<DateStrip> {
  final _scrollController = ScrollController();
  bool _programmaticScroll = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    _programmaticScroll = true;
    final store = SumiScope.read(context);
    final selected = dateOnly(store.selectedDate);
    const itemExtent = 54.0 + 8.0; // chip 宽 + 间距
    final viewport = _scrollController.position.viewportDimension;
    final dayIndex = selected.day;
    final selectedCenter = (dayIndex - 1) * itemExtent + 27.0;
    final target = (selectedCenter - viewport / 2)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutQuart,
    ).then((_) {
      if (mounted) _programmaticScroll = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watch(context);
    final selected = dateOnly(store.selectedDate);
    final daysInMonth = DateTime(selected.year, selected.month + 1, 0).day;
    final dates = List.generate(
        daysInMonth, (i) => DateTime(selected.year, selected.month, i + 1));
    final today = dateOnly(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radiusCardHeader),
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 日期条
            SizedBox(
              height: 72,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollEndNotification &&
                      !_programmaticScroll) {
                    _selectCenterDate(store, daysInMonth);
                  }
                  return false;
                },
                child: ListView.separated(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: s16),
                  itemCount: dates.length,
                  separatorBuilder: (_, _) => const SizedBox(width: s8),
                  itemBuilder: (context, index) {
                    final date = dates[index];
                    final isSelected = isSameDate(date, selected);
                    final isToday = isSameDate(date, today);
                    return _DraggableDateChip(
                      date: date,
                      store: store,
                      child: _DateChip(
                        date: date,
                        selected: isSelected,
                        isToday: isToday,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          store.selectDate(date);
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
            // 拖拽把手
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                widget.onExpandMonth();
              },
              child: Container(
                height: 48,
                alignment: const Alignment(0, 0.4),
                child: const DragHandle(),
              ),
            ),
          ],
        ),
      );
  }

  void _selectCenterDate(SumiStore store, int daysInMonth) {
    if (!_scrollController.hasClients) return;
    final selected = dateOnly(store.selectedDate);
    final offset = _scrollController.offset;
    final viewport = _scrollController.position.viewportDimension;
    final center = offset + viewport / 2;
    const itemExtent = 62.0;
    final dayIndex = (center / itemExtent).floor().clamp(0, daysInMonth - 1);
    final centerDate =
        DateTime(selected.year, selected.month, dayIndex + 1);
    if (!isSameDate(centerDate, selected)) {
      HapticFeedback.selectionClick();
      store.selectDate(centerDate);
    }
  }
}

/// 单个日期 chip。
class _DateChip extends StatelessWidget {
  final DateTime date;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  const _DateChip({
    required this.date,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  String _weekdayLabel(int weekday) {
    return ['一', '二', '三', '四', '五', '六', '日'][weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color txtColor;
    if (selected) {
      bgColor = mintDeep;
      txtColor = Colors.white;
    } else if (isToday) {
      bgColor = mint.withValues(alpha: 0.5);
      txtColor = ink;
    } else {
      bgColor = Colors.transparent;
      txtColor = ink;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 54,
        height: 72,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(radiusCard),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _weekdayLabel(date.weekday),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white70 : txtColor.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: s6),
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: txtColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 可接受 Todo 拖拽的日期 Chip 包装器。
///
/// - 拖到过去日期 → 红色反馈 + toast「不能拖到过去的日期」
/// - 拖到今天及未来日期 → 直接分配日期
class _DraggableDateChip extends StatelessWidget {
  final DateTime date;
  final SumiStore store;
  final Widget child;

  const _DraggableDateChip({
    required this.date,
    required this.store,
    required this.child,
  });

  bool get _isPastDate =>
      dateOnly(date).isBefore(dateOnly(DateTime.now()));

  @override
  Widget build(BuildContext context) {
    return DragTarget<TodoItem>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        if (_isPastDate) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('不能拖到过去的日期'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        final key = dateKey(date);
        store.updateTodoDate(details.data.id, key);
      },
      builder: (context, candidates, rejects) {
        final hovering = candidates.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radiusCard),
            color: hovering
                ? (_isPastDate
                    ? Colors.red.shade100
                    : mintDeep.withValues(alpha: 0.2))
                : Colors.transparent,
          ),
          child: child,
        );
      },
    );
  }
}
