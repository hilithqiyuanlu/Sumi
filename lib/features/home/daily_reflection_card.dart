import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/daily_reflection.dart';
import '../../store/sumi_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/utils.dart';

/// 过去某天的总结卡片 —— 始终展开，类似灵动岛展开的大卡片。
/// 底色浅灰蓝，圆角矩形，内部可滚动。
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
  bool _isRetrying = false;

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
    setState(() => _isRetrying = true);
    await widget.store.retryDailyReflection(widget.date);
    if (mounted) {
      setState(() => _isRetrying = false);
      _reload();
    }
  }

  Future<void> _showActions() async {
    final action = await showModalBottomSheet<_ReflectionAction>(
      context: context,
      backgroundColor: paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radiusCardHeader)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(s20, s10, s20, s8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖拽手柄
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
              const SizedBox(height: s16),
              // 重新生成
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radiusCard),
                ),
                leading: const Icon(Icons.refresh, color: primary500),
                title: const Text('重新生成'),
                subtitle: const Text('基于今天的对话重新整理',
                    style: TextStyle(fontSize: 12, color: textTertiary)),
                onTap: () => Navigator.pop(context, _ReflectionAction.refresh),
              ),
              const SizedBox(height: s8),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    setState(() => _isRetrying = true);
    if (action == _ReflectionAction.refresh) {
      await widget.store.regenerateDailyReflection(widget.date);
    } else if (action == _ReflectionAction.remove) {
      await widget.store.removeDailyReflection(widget.date);
    }
    if (!mounted) return;
    setState(() => _isRetrying = false);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return FutureBuilder<DailyReflection?>(
      future: _future,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null || item.status == DailyReflectionStatus.skipped) {
          return const SizedBox.shrink();
        }

        final isReady = item.status == DailyReflectionStatus.ready;
        final isBusy =
            item.status == DailyReflectionStatus.pending ||
            item.status == DailyReflectionStatus.generating;
        final apiUnavailable = widget.store.structuredAi == null;
        final isLoading = isBusy || _isRetrying;

        return Padding(
          padding: EdgeInsets.fromLTRB(s16, s6, s16, bottomPadding + s8),
          child: GestureDetector(
            onLongPress: isReady ? _showActions : null,
            child: Container(
              height: screenHeight * 0.17,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: primary50,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 16,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: isLoading
                  ? _LoadingInline()
                  : isReady
                  ? _ReadyBody(item: item)
                  : _FailedBody(
                      category: item.failureCategory,
                      onTap: apiUnavailable
                          ? () => _showMissingApiHint(context)
                          : _retry,
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
    ).showSnackBar(const SnackBar(content: Text('请先在"API 接口"中配置密钥，再整理这一天')));
  }
}

enum _ReflectionAction { refresh, remove }

// ---------------------------------------------------------------------------
// Loading (inline, no card)
// ---------------------------------------------------------------------------

class _LoadingInline extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(s20, s16, s20, s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 36, height: 36, child: _SpinningIcon()),
              const SizedBox(width: s10),
              const Text(
                '正在整理这一天……',
                style: TextStyle(fontSize: 14, height: 1.4, color: textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ready
// ---------------------------------------------------------------------------

class _ReadyBody extends StatefulWidget {
  final DailyReflection item;

  const _ReadyBody({required this.item});

  @override
  State<_ReadyBody> createState() => _ReadyBodyState();
}

class _ReadyBodyState extends State<_ReadyBody> {
  bool _canScrollMore = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(s20, s16, s20, s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification) {
                      final m = notification.metrics;
                      setState(() {
                        _canScrollMore =
                            m.maxScrollExtent > 0 &&
                            m.pixels < m.maxScrollExtent - 8;
                      });
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.reflection ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.65,
                            color: ink,
                          ),
                        ),
                        if (widget.item.highlights.isNotEmpty) ...[
                          const SizedBox(height: s14),
                          ...widget.item.highlights.map(
                            (value) => Padding(
                              padding: const EdgeInsets.only(bottom: s8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Icon(Icons.circle,
                                        size: 5, color: primary500),
                                  ),
                                  const SizedBox(width: s8),
                                  Expanded(
                                    child: Text(
                                      value,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        height: 1.45,
                                        color: ink,
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
                if (_canScrollMore)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              primary50.withValues(alpha: 0),
                              primary50,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Failed
// ---------------------------------------------------------------------------

class _FailedBody extends StatelessWidget {
  final String? category;
  final VoidCallback onTap;

  const _FailedBody({required this.category, required this.onTap});

  String get _text => switch (category) {
    'authentication' => '请检查 API 密钥后重试',
    'rateLimited' => '服务暂时繁忙，点按后重试',
    'timeout' => '整理超时，点按后重试',
    'network' => '网络连接不稳定，点按后重试',
    'validation' => '返回内容未完成，点按后重试',
    _ => '整理未完成，点按后重试',
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(s20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primary100.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.refresh, size: 20, color: primary500),
              ),
              const SizedBox(height: s12),
              Text(
                _text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 1.4, color: ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spinning icon
// ---------------------------------------------------------------------------

class _SpinningIcon extends StatefulWidget {
  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: primary100.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.refresh, size: 20, color: primary500),
      ),
    );
  }
}
