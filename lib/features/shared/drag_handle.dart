import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 底部 Sheet 通用的拖拽把手。
class DragHandle extends StatelessWidget {
  const DragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: textTertiary.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(radius2),
        ),
      ),
    );
  }
}
