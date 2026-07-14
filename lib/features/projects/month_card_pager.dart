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
          final isUnlocked = index <= project.currentMonthIndex;

          if (isUnlocked) {
            return SizedBox(
              width: 280,
              child: _UnlockedCard(
                card: card,
                monthIndex: index,
                accentColor: index == project.currentMonthIndex
                    ? lemon
                    : mint,
              ),
            );
          }
          return const SizedBox(width: 280, child: _LockedMonthCard());
        },
      ),
    );
  }
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
        color: paper,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: line.withValues(alpha: 0.3)),
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
              if (card.aiGenerated) ...[
                const SizedBox(width: s6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: s8, vertical: s2),
                  decoration: BoxDecoration(
                    color: mintDeep.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(radiusPill),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          size: 11, color: mintDeep),
                      SizedBox(width: s4),
                      Text(
                        'AI 规划',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: mintDeep,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
            title: const Text('提示'),
            content:
                const Text('前方的区域还没有开放，过段时间再来探索吧'),
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
          child: Icon(Icons.lock_outline_rounded,
              size: 36, color: textTertiary),
        ),
      ),
    );
  }
}
