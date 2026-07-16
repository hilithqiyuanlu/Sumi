import 'package:flutter/material.dart';

import '../../services/daily_reflection.dart';
import '../../store/sumi_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/utils.dart';

class DailyReflectionSlot extends StatefulWidget {
  final AppStore store;
  final DateTime date;
  final int revision;

  const DailyReflectionSlot({
    required this.store,
    required this.date,
    required this.revision,
    super.key,
  });

  @override
  State<DailyReflectionSlot> createState() => _DailyReflectionSlotState();
}

class _DailyReflectionSlotState extends State<DailyReflectionSlot> {
  late Future<DailyReflection?> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant DailyReflectionSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!isSameDate(oldWidget.date, widget.date) ||
        oldWidget.revision != widget.revision) {
      _reload();
    }
  }

  void _reload() {
    _future = widget.store.dailyReflectionFor(widget.date);
  }

  Future<void> _retry() async {
    await widget.store.retryDailyReflection(widget.date);
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DailyReflection?>(
      future: _future,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null || item.status == DailyReflectionStatus.skipped) {
          return const SizedBox.shrink();
        }
        final isReady = item.status == DailyReflectionStatus.ready;
        final isFailed = item.status == DailyReflectionStatus.failed;
        final apiUnavailable = widget.store.structuredAi == null;
        final label = isReady
            ? item.shortSummary!
            : isFailed
            ? '整理这一天'
            : apiUnavailable
            ? '整理这一天'
            : '正在整理这一天';
        return Padding(
          padding: const EdgeInsets.fromLTRB(s16, s8, s16, s12),
          child: Material(
            color: primary50.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(radius24),
            child: InkWell(
              borderRadius: BorderRadius.circular(radius24),
              onTap: isReady
                  ? () => _showDetail(context, item)
                  : isFailed
                  ? _retry
                  : apiUnavailable
                  ? () => _showMissingApiHint(context)
                  : null,
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 58),
                padding: const EdgeInsets.symmetric(
                  horizontal: s16,
                  vertical: s12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius24),
                  border: Border.all(color: primary100),
                ),
                child: Row(
                  children: [
                    Icon(
                      isReady
                          ? Icons.auto_awesome_outlined
                          : isFailed || apiUnavailable
                          ? Icons.refresh_rounded
                          : Icons.hourglass_top_rounded,
                      color: primary500,
                      size: iconMedium,
                    ),
                    const SizedBox(width: s10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: ink,
                        ),
                      ),
                    ),
                    if (isReady)
                      const Icon(Icons.chevron_right, color: textTertiary),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showMissingApiHint(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('请先在“API 接口”中配置密钥，再整理这一天')));
  }

  void _showDetail(BuildContext context, DailyReflection item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius24)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .54,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(s20, s10, s20, s20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(
                      color: neutral300,
                      borderRadius: BorderRadius.circular(radiusPill),
                    ),
                  ),
                ),
                const SizedBox(height: s20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.dateKey} 的回顾',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: s12),
                Text(
                  item.reflection ?? '',
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.65,
                    color: ink,
                  ),
                ),
                if (item.highlights.isNotEmpty) ...[
                  const SizedBox(height: s20),
                  ...item.highlights.map(
                    (value) => Padding(
                      padding: const EdgeInsets.only(bottom: s10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 7),
                            child: Icon(
                              Icons.circle,
                              size: 6,
                              color: primary500,
                            ),
                          ),
                          const SizedBox(width: s10),
                          Expanded(
                            child: Text(
                              value,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
