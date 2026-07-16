import 'package:flutter/material.dart';
import '../../utils/haptics.dart';

import '../../models/models.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';

/// 月卡横向 pager —— 含锁定态。
class MonthCardPager extends StatelessWidget {
  final Project project;
  const MonthCardPager({required this.project, super.key});

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.watchProjects(context);
    SumiScope.watchMilestones(context);
    SumiScope.watchSettings(context);
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
          final isUnlocked =
              store.appSettings.showAllMonthCards ||
              index <= project.currentMonthIndex;
          final isCurrent = index == project.currentMonthIndex;

          if (isUnlocked) {
            return SizedBox(
              width: 280,
              child: _UnlockedCard(
                card: card,
                monthIndex: index,
                isCurrent: isCurrent,
                projectCreatedAt: project.createdAt,
                milestones: store.milestones.forProjectMonth(project.id, index),
              ),
            );
          }
          return SizedBox(
            width: 280,
            child: _LockedMonthCard(monthIndex: index),
          );
        },
      ),
    );
  }
}

/// 已解锁月卡。
class _UnlockedCard extends StatelessWidget {
  final MonthCard card;
  final int monthIndex;
  final bool isCurrent;
  final DateTime projectCreatedAt;
  final Future<List<Milestone>> milestones;

  const _UnlockedCard({
    required this.card,
    required this.monthIndex,
    required this.isCurrent,
    required this.projectCreatedAt,
    required this.milestones,
  });

  @override
  Widget build(BuildContext context) {
    final cardDate = DateTime(
      projectCreatedAt.year,
      projectCreatedAt.month + monthIndex,
      1,
    );
    final monthLabel = '${cardDate.month}月';

    return Container(
      decoration: BoxDecoration(
        color: isCurrent
            ? mint.withValues(alpha: 0.5)
            : primary50.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: line.withValues(alpha: 0.15)),
      ),
      padding: const EdgeInsets.all(s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 月份标签
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: s10,
                  vertical: s4,
                ),
                decoration: BoxDecoration(
                  color: isCurrent ? mintDeep : primary100,
                  borderRadius: BorderRadius.circular(radiusPill),
                ),
                child: Text(
                  monthLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isCurrent ? Colors.white : ink,
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
          FutureBuilder<List<Milestone>>(
            future: milestones,
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <Milestone>[];
              final latest = items.isEmpty ? null : items.first;
              return SizedBox(
                height: 40,
                child: latest == null
                    ? const SizedBox.shrink()
                    : Row(
                        children: [
                          const Icon(
                            Icons.bookmark_added_outlined,
                            size: 16,
                            color: primary500,
                          ),
                          const SizedBox(width: s6),
                          Expanded(
                            child: Text(
                              '“${latest.quote}” · ${latest.todoTitle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: textSecondary,
                              ),
                            ),
                          ),
                          if (items.length > 1)
                            Text(
                              '+${items.length - 1}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: primary500,
                              ),
                            ),
                        ],
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 锁定月卡。
class _LockedMonthCard extends StatelessWidget {
  final int monthIndex;

  const _LockedMonthCard({required this.monthIndex});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cardDate = DateTime(now.year, now.month + monthIndex, 1);
    final monthLabel = '${cardDate.month}月';

    return GestureDetector(
      onTap: () {
        H.light();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(radiusCard)),
            ),
            title: const Text(
              '提示',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            content: const Text(
              '前方的区域还没有开放，过段时间再来探索吧',
              style: TextStyle(fontSize: 14),
            ),
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
        padding: const EdgeInsets.all(s16),
        decoration: BoxDecoration(
          color: primary50.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(radiusCard),
          border: Border.all(color: line.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: s10,
                vertical: s4,
              ),
              decoration: BoxDecoration(
                color: primary100,
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
            const Expanded(
              child: Center(
                child: Icon(Icons.lock_outline, size: 36, color: textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
