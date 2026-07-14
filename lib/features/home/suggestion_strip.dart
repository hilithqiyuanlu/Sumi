import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class SuggestionStrip extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onSelect;
  final bool enabled;

  const SuggestionStrip({
    super.key,
    required this.suggestions,
    required this.onSelect,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: s16, right: s16, top: s4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: suggestions
              .map((s) => Padding(
                    padding: const EdgeInsets.only(right: s8),
                    child: _SuggestionChip(
                      text: s,
                      onTap: enabled ? () => onSelect(s) : null,
                      enabled: enabled,
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool enabled;

  const _SuggestionChip({
    required this.text,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surfaceChip,
      borderRadius: BorderRadius.circular(radiusPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusPill),
        overlayColor: WidgetStatePropertyAll(primary500.withValues(alpha: 0.08)),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: s16, vertical: s8),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: primary600,
            ),
          ),
        ),
      ),
    );
  }
}