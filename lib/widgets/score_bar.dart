import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 维度评分条 —— 标签 + 颜色填充条 + 数字。
class ScoreBar extends StatelessWidget {
  final String label;
  final double score; // 0.0-1.0
  final bool showValue;

  const ScoreBar({
    required this.label,
    required this.score,
    this.showValue = true,
    super.key,
  });

  Color get _barColor {
    if (score < 0.4) return error500;
    if (score < 0.6) return warning500;
    return success500;
  }

  @override
  Widget build(BuildContext context) {
    final clampedScore = score.clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: s6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: textTertiary),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius4),
              child: Container(
                height: 10,
                color: surfaceChip,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: clampedScore,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _barColor,
                      borderRadius: BorderRadius.circular(radius4),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showValue) ...[
            const SizedBox(width: s8),
            SizedBox(
              width: 32,
              child: Text(
                clampedScore.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _barColor,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
