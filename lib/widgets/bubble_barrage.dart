import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// 弹幕气泡动画组件 —— 接收 [PlanningBubble] 流，渲染上浮消失的气泡。
class BubbleBarrage extends StatefulWidget {
  final Stream<PlanningBubble> bubbles;

  const BubbleBarrage({required this.bubbles, super.key});

  @override
  State<BubbleBarrage> createState() => _BubbleBarrageState();
}

class _BubbleBarrageState extends State<BubbleBarrage>
    with TickerProviderStateMixin {
  final List<_BubbleData> _activeBubbles = [];
  final _random = Random();
  StreamSubscription<PlanningBubble>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.bubbles.listen(_onBubble);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    for (final b in _activeBubbles) {
      b.controller.dispose();
    }
    super.dispose();
  }

  void _onBubble(PlanningBubble bubble) {
    final controller = AnimationController(
      vsync: this as TickerProvider,
      duration: const Duration(milliseconds: 5000),
    );

    final startX = 10.0 + _random.nextDouble() * 70.0; // 10%-80% 屏幕宽度
    final animation = Tween<double>(begin: 0.65, end: 0.05).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
    );

    final data = _BubbleData(
      bubble: bubble,
      controller: controller,
      animation: animation,
      startX: startX,
    );

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
        if (mounted) {
          setState(() => _activeBubbles.remove(data));
        }
      }
    });

    setState(() => _activeBubbles.add(data));

    // 限制最多 4 个气泡
    if (_activeBubbles.length > 4) {
      final oldest = _activeBubbles.removeAt(0);
      oldest.controller.dispose();
    }

    controller.forward();
  }

  Color _bubbleBg(BubbleType type) {
    return switch (type) {
      BubbleType.thinking => primary50,
      BubbleType.searching => tertiary50,
      BubbleType.validating => accent50,
      BubbleType.info => mint,
    };
  }

  @override
  Widget build(BuildContext context) {
    // 需要 TickerProvider，必须用 SingleTickerProviderStateMixin
    // StatefulWidget 不能直接当 vsync，需要加 mixin
    return Stack(
      children: _activeBubbles.map((data) {
        return AnimatedBuilder(
          animation: data.animation,
          builder: (context, child) {
            final opacity = (1.0 - data.controller.value).clamp(0.0, 1.0);
            return Positioned(
              left: MediaQuery.of(context).size.width * data.startX / 100,
              top: MediaQuery.of(context).size.height * data.animation.value,
              child: Opacity(
                opacity: opacity,
                child: child,
              ),
            );
          },
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.symmetric(horizontal: s16, vertical: s10),
            decoration: BoxDecoration(
              color: _bubbleBg(data.bubble.type),
              borderRadius: BorderRadius.circular(radiusPill),
              boxShadow: const [...shadow2],
            ),
            child: Text(
              data.bubble.text,
              style: const TextStyle(
                fontSize: 13,
                color: ink,
                height: 1.35,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _BubbleData {
  final PlanningBubble bubble;
  final AnimationController controller;
  final Animation<double> animation;
  final double startX;

  _BubbleData({
    required this.bubble,
    required this.controller,
    required this.animation,
    required this.startX,
  });
}
