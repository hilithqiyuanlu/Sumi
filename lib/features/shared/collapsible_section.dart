import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 可折叠展开的文本区域。用于思考过程、工具结果等低披露内容。
class CollapsibleSection extends StatefulWidget {
  final String title;
  final String? body;
  final Color? backgroundColor;
  final BoxBorder? border;
  final double iconSize;
  final double titleFontSize;
  final double bodyFontSize;

  const CollapsibleSection({
    super.key,
    required this.title,
    this.body,
    this.backgroundColor,
    this.border,
    this.iconSize = 16,
    this.titleFontSize = 12,
    this.bodyFontSize = 13,
  });

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasBody = widget.body != null && widget.body!.isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: s16, vertical: s12),
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          borderRadius: BorderRadius.circular(s8),
          border: widget.border,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: widget.iconSize,
                  color: textTertiary,
                ),
                const SizedBox(width: s6),
                Flexible(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: widget.titleFontSize,
                      color: textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: _expanded ? null : 1,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded && hasBody
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: s8),
                        Text(
                          widget.body!,
                          style: TextStyle(
                            fontSize: widget.bodyFontSize,
                            height: 1.45,
                            color: textTertiary,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
