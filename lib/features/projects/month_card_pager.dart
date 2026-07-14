import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';

/// 月卡横向 pager —— 含锁定态。
class MonthCardPager extends StatelessWidget {
  final Project project;
  const MonthCardPager({required this.project, super.key});

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watch(context);
    final cards = store.monthCardsFor(project.id);
    final cycle = project.cycleMonths;

    return SizedBox(
      height: 260,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: s16),
        physics: const BouncingScrollPhysics(),
        itemCount: cycle,
        separatorBuilder: (_, _) => const SizedBox(width: s16),
        itemBuilder: (context, index) {
          final card = cards.cast<MonthCard?>().firstWhere(
                (m) => m?.monthIndex == index,
                orElse: () => MonthCard(
                  id: 'fallback',
                  projectId: project.id,
                  monthIndex: index,
                  title: '',
                ),
              )!;
          final isUnlocked = store.appSettings.showAllMonthCards ||
              index <= project.currentMonthIndex;

          if (isUnlocked) {
            return SizedBox(
              width: 280,
              child: _UnlockedCard(
                card: card,
                monthIndex: index,
                accentColor: _monthAccent(index, project.currentMonthIndex),
              ),
            );
          }
          return const SizedBox(width: 280, child: _LockedMonthCard());
        },
      ),
    );
  }
}

/// 返回月卡标签的强调色，当月突出，其他月份轮换。
Color _monthAccent(int index, int currentIndex) {
  if (index == currentIndex) return primary500; // 当月用主色（实心 indigo）
  // 其他月份轮换使用项目色
  final palette = [lemon, sky, peach, sage, lilac, cherry];
  return palette[index % palette.length];
}

/// 已解锁月卡。
class _UnlockedCard extends StatelessWidget {
  final MonthCard card;
  final int monthIndex;
  final Color accentColor;

  const _UnlockedCard({
    required this.card,
    required this.monthIndex,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cardDate =
        DateTime(now.year, now.month + monthIndex, 1);
    final monthLabel = '${cardDate.month}月';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: line.withValues(alpha: 0.15)),
        boxShadow: const [...shadow1],
      ),
      padding: const EdgeInsets.all(s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 月份标签
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: s10, vertical: s4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(radiusPill),
                ),
                child: Text(
                  monthLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: s10),
          // 可滚动内容区
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  if (card.title.isNotEmpty)
                    Text(
                      card.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  // 摘要
                  if (card.summary != null && card.summary!.isNotEmpty) ...[
                    const SizedBox(height: s8),
                    Text(
                      card.summary!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: textTertiary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: s8),
        ],
      ),
    );
  }
}

/// 锁定月卡。
class _LockedMonthCard extends StatelessWidget {
  const _LockedMonthCard();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(radiusCard)),
            ),
            title: const Text('提示', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            content:
                const Text('前方的区域还没有开放，过段时间再来探索吧', style: TextStyle(fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('好的'),
              ),
            ],
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(radiusCard),
          border: Border.all(color: line.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Icon(Icons.lock_outline,
              size: 36, color: textTertiary),
        ),
      ),
    );
  }
}
