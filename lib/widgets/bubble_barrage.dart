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

  static const _maxBubbles = 3;

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
      duration: const Duration(milliseconds: 8000),
    );

    // 水平位置：15%-75% 屏幕宽度
    final startX = 15.0 + _random.nextDouble() * 60.0;

    // 上浮动画：从底部 80% 到顶部 3%
    final floatAnimation = Tween<double>(begin: 0.80, end: 0.03).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOutQuart),
    );

    // 缩放动画：从 0.92 到 1.0，制造"冒泡"感
    final scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: controller,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOutBack),
      ),
    );

    final data = _BubbleData(
      bubble: bubble,
      controller: controller,
      floatAnimation: floatAnimation,
      scaleAnimation: scaleAnimation,
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

    if (_activeBubbles.length > _maxBubbles) {
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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Stack(
      children: _activeBubbles.map((data) {
        return AnimatedBuilder(
          animation: data.floatAnimation,
          builder: (context, child) {
            // 透明度：使用 easeInSine 更慢地淡出
            final opacity =
                (1.0 - Curves.easeInSine.transform(data.controller.value))
                    .clamp(0.0, 1.0);
            return Positioned(
              left: screenWidth * data.startX / 100,
              top: screenHeight * data.floatAnimation.value,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: data.scaleAnimation.value,
                  child: child,
                ),
              ),
            );
          },
          child: Container(
            constraints: BoxConstraints(
              maxWidth: screenWidth * 0.75,
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: s16, vertical: s10),
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
  final Animation<double> floatAnimation;
  final Animation<double> scaleAnimation;
  final double startX;

  _BubbleData({
    required this.bubble,
    required this.controller,
    required this.floatAnimation,
    required this.scaleAnimation,
    required this.startX,
  });
}
