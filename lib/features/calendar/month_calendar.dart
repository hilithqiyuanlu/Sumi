import 'package:flutter/material.dart';

import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/utils.dart';

/// 7 列月历网格。
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({super.key});

  static const _weekdayHeaders = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watch(context);
    final selected = dateOnly(store.selectedDate);
    final today = dateOnly(DateTime.now());

    // 当月第一天和最后一天
    final firstOfMonth = DateTime(selected.year, selected.month, 1);
    final lastOfMonth = DateTime(selected.year, selected.month + 1, 0);
    final daysInMonth = lastOfMonth.day;

    // 第一天是周几（周一=1, 周日=7）
    final firstWeekday = firstOfMonth.weekday; // 1=Mon

    // 构建日期列表，前面补空白
    final cells = <DateTime?>[];
    for (var i = 1; i < firstWeekday; i++) {
      cells.add(null); // 空白占位
    }
    for (var d = 1; d <= daysInMonth; d++) {
      cells.add(DateTime(selected.year, selected.month, d));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 星期标题
        Row(
          children: _weekdayHeaders.map((h) {
            return Expanded(
              child: Center(
                child: Text(
                  h,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textTertiary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: s8),
        // 日期单元格
        Wrap(
          children: cells.map((date) {
            if (date == null) {
              return const _CalendarCell.empty();
            }
            final isSelected = isSameDate(date, selected);
            final isTodayDate = isSameDate(date, today);
            final isPast = date.isBefore(today) && !isTodayDate;

            return _CalendarCell(
              day: date.day,
              isSelected: isSelected,
              isToday: isTodayDate,
              isPast: isPast,
              onTap: () => store.selectDate(date),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _CalendarCell extends StatelessWidget {
  final int? day;
  final bool isSelected;
  final bool isToday;
  final bool isPast;
  final VoidCallback? onTap;

  const _CalendarCell({
    this.day,
    this.isSelected = false,
    this.isToday = false,
    this.isPast = false,
    this.onTap,
  });

  const _CalendarCell.empty()
      : day = null,
        isSelected = false,
        isToday = false,
        isPast = false,
        onTap = null;

  @override
  Widget build(BuildContext context) {
    // 计算宽度：7 列等分
    final screenWidth = MediaQuery.of(context).size.width - s16 * 2;
    final cellWidth = screenWidth / 7;

    if (day == null) {
      return SizedBox(width: cellWidth, height: cellWidth * 0.85);
    }

    Color bgColor;
    Color txtColor;
    if (isSelected) {
      bgColor = mintDeep;
      txtColor = Colors.white;
    } else if (isToday) {
      bgColor = mint.withValues(alpha: 0.4);
      txtColor = ink;
    } else {
      bgColor = Colors.transparent;
      txtColor = isPast ? textTertiary : ink;
    }

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: cellWidth,
        height: cellWidth * 0.85,
        child: Center(
          child: Container(
            width: cellWidth * 0.7,
            height: cellWidth * 0.7,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.w400,
                  color: txtColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
