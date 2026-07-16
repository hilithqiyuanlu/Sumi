import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';
import '../../models/models.dart';

class SuggestionStrip extends StatelessWidget {
  final List<SuggestionQuestion> suggestions;
  final ValueChanged<SuggestionQuestion> onSelect;
  final Future<void> Function(
    SuggestionQuestion suggestion,
    bool disableTopic,
  )
  onFeedback;
  final bool enabled;

  const SuggestionStrip({
    super.key,
    required this.suggestions,
    required this.onSelect,
    required this.onFeedback,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: Padding(
        key: ValueKey(suggestions.map((s) => s.id).join(',')),
        padding: const EdgeInsets.only(left: s16, right: s16, top: s4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: suggestions
                .map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(right: s8),
                    child: _SuggestionChip(
                      text: s.text,
                      onTap: enabled
                          ? () {
                              H.light();
                              onSelect(s);
                            }
                          : null,
                      onLongPress: enabled
                          ? () => _showFeedback(context, s)
                          : null,
                      enabled: enabled,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  void _showFeedback(BuildContext context, SuggestionQuestion suggestion) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.thumb_down_outlined),
              title: const Text('不适合'),
              onTap: () async {
                Navigator.pop(context);
                await onFeedback(suggestion, false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: const Text('不再推荐此类'),
              onTap: () async {
                Navigator.pop(context);
                await onFeedback(suggestion, true);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  const _SuggestionChip({
    required this.text,
    required this.onTap,
    this.onLongPress,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surfaceChip,
      borderRadius: BorderRadius.circular(radiusPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusPill),
        overlayColor: WidgetStatePropertyAll(
          primary500.withValues(alpha: 0.08),
        ),
        onTap: onTap,
        onLongPress: onLongPress,
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
