import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import 'project_editor.dart';

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
      height: 320,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: s16),
        physics: const BouncingScrollPhysics(),
        itemCount: cycle,
        separatorBuilder: (_, _) => const SizedBox(width: s16),
        itemBuilder: (context, index) {
          final card = cards.cast<MonthCard?>().firstWhere(
                (m) => m?.monthIndex == index,
                orElse: () => null,
              );
          final isUnlocked = index <= project.currentMonthIndex;

          if (isUnlocked) {
            return SizedBox(
              width: 280,
              child: _UnlockedCard(
                card: card,
                monthIndex: index,
                projectId: project.id,
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
  final MonthCard? card;
  final int monthIndex;
  final String projectId;
  final Color accentColor;

  const _UnlockedCard({
    required this.card,
    required this.monthIndex,
    required this.projectId,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final store = SumiScope.read(context);
    final now = DateTime.now();
    final cardDate =
        DateTime(now.year, now.month + monthIndex, 1);
    final monthLabel = '${cardDate.year}年${cardDate.month}月';
    final c = card; // 本地变量便于 null promotion

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: line.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 月份标签
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
          const SizedBox(height: s14),
          // 标题
          if (c != null)
            Text(
              c.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          else
            Text(
              '第 ${monthIndex + 1} 个月',
              style: TextStyle(
                fontSize: 14,
                color: textTertiary,
              ),
            ),
          // 摘要
          if (c?.summary != null && c!.summary!.isNotEmpty) ...[
            const SizedBox(height: s8),
            Text(
              c.summary!,
              style: const TextStyle(
                fontSize: 14,
                color: textTertiary,
                height: 1.5,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const Spacer(),
          // 操作
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (c == null)
                TextButton.icon(
                  onPressed: () => showMonthCardEditor(
                    context,
                    store,
                    projectId: projectId,
                    monthIndex: monthIndex,
                  ),
                  icon: const Icon(Icons.add_rounded, size: iconSmall),
                  label: const Text('创建月卡'),
                )
              else ...[
                TextButton.icon(
                  onPressed: () => showMonthCardEditor(
                    context,
                    store,
                    card: c,
                  ),
                  icon:
                      const Icon(Icons.edit_rounded, size: iconSmall),
                  label: const Text('编辑'),
                ),
                const SizedBox(width: s4),
                TextButton.icon(
                  onPressed: () => store.deleteMonthCard(c.id),
                  icon: Icon(Icons.delete_rounded,
                      size: iconSmall, color: Colors.red.shade400),
                  label: Text('删除',
                      style: TextStyle(color: Colors.red.shade400)),
                ),
              ],
            ],
          ),
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
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(radiusCard),
          border: Border.all(color: line.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Icon(Icons.lock_outline_rounded,
              size: 36, color: textTertiary),
        ),
      ),
    );
  }
}
