import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// A/B/C/D 评级徽章。
class VerdictBadge extends StatelessWidget {
  final AssessmentVerdict verdict;

  const VerdictBadge({required this.verdict, super.key});

  Color get _bgColor {
    return switch (verdict) {
      AssessmentVerdict.a => success500.withValues(alpha: 0.12),
      AssessmentVerdict.b => info500.withValues(alpha: 0.12),
      AssessmentVerdict.c => warning500.withValues(alpha: 0.12),
      AssessmentVerdict.d => error500.withValues(alpha: 0.12),
    };
  }

  Color get _textColor {
    return switch (verdict) {
      AssessmentVerdict.a => success600,
      AssessmentVerdict.b => info800,
      AssessmentVerdict.c => warning600,
      AssessmentVerdict.d => error600,
    };
  }

  IconData get _icon {
    return switch (verdict) {
      AssessmentVerdict.a => Icons.check_circle,
      AssessmentVerdict.b => Icons.thumb_up_outlined,
      AssessmentVerdict.c => Icons.warning_amber,
      AssessmentVerdict.d => Icons.cancel,
    };
  }

  String get _gradeLabel {
    return switch (verdict) {
      AssessmentVerdict.a => 'A 级',
      AssessmentVerdict.b => 'B 级',
      AssessmentVerdict.c => 'C 级',
      AssessmentVerdict.d => 'D 级',
    };
  }

  String get _subtitle {
    return switch (verdict) {
      AssessmentVerdict.a => '你的目标很适合自学规划',
      AssessmentVerdict.b => '目标良好，有优化空间',
      AssessmentVerdict.c => '目标可以尝试，但请注意以下问题',
      AssessmentVerdict.d => '目标需要调整后才能规划',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(s20),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(radiusCard),
      ),
      child: Column(
        children: [
          Icon(_icon, size: 48, color: _textColor),
          const SizedBox(height: s8),
          Text(
            _gradeLabel,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _textColor,
            ),
          ),
          const SizedBox(height: s4),
          Text(
            _subtitle,
            style: const TextStyle(fontSize: 14, color: textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
