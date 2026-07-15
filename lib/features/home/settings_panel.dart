import 'package:flutter/material.dart';

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
    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(_swipeOffset, 0),
        child: Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: const SettingsBody(),
        ),
      ),
    );
  }
}
