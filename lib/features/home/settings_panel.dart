import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../settings/settings_body.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key});

  static void show(BuildContext context) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, secondaryAnimation) => const SettingsPanel(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel>
    with SingleTickerProviderStateMixin {
  double _swipeOffset = 0;
  bool _isEdgeSwipe = false;
  double _snapTargetWidth = 0;
  late final AnimationController _snapController;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _snapController.addListener(() {
      setState(() => _swipeOffset = _snapController.value * _snapTargetWidth);
    });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    _isEdgeSwipe = details.localPosition.dx < 40;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isEdgeSwipe) return;
    setState(() {
      _swipeOffset = (_swipeOffset + details.delta.dx).clamp(0.0, double.infinity);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    _isEdgeSwipe = false;
    final screenWidth = MediaQuery.of(context).size.width;
    final shouldPop = _swipeOffset > screenWidth * 0.3 ||
        details.velocity.pixelsPerSecond.dx > 500;

    if (shouldPop) {
      Navigator.pop(context);
    } else {
      // 弹簧回弹
      _snapTargetWidth = screenWidth;
      _snapController.value = (_swipeOffset / screenWidth).clamp(0.0, 1.0);
      _snapController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(_swipeOffset, 0),
        child: Stack(
          children: [
            Scaffold(
              body: Stack(
                children: [
                  const SettingsBody(),
                  // 顶部渐变遮罩
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: topPadding + 56,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white,
                              Colors.white.withValues(alpha: 0.92),
                              Colors.white.withValues(alpha: 0),
                            ],
                            stops: const [0.0, 0.55, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 返回 + 标题
                  Positioned(
                    top: topPadding,
                    left: 4,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Text(
                          '设置',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
