import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/utils.dart';

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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 300) {
          HapticFeedback.mediumImpact();
          widget.onExpandMonth();
        }
      },
      child: Container(
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
                    _selectCenterDate(store);
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
                    return _DateChip(
                      date: date,
                      selected: isSelected,
                      isToday: isToday,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        store.selectDate(date);
                      },
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
                height: 36,
                alignment: Alignment.center,
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: textTertiary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectCenterDate(SumiStore store) {
    if (!_scrollController.hasClients) return;
    final selected = dateOnly(store.selectedDate);
    final daysInMonth =
        DateTime(selected.year, selected.month + 1, 0).day;
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
