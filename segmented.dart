import 'package:flutter/material.dart';

import '../theme/theme_ext.dart';

/// Pill-style segmented control with an animated thumb.
class PennySegmented<T> extends StatelessWidget {
  const PennySegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.colorOf,
    this.height = 44,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  /// Optional per-value thumb colour (e.g. red for expense).
  final Color Function(T)? colorOf;
  final double height;

  @override
  Widget build(BuildContext context) {
    final index = values.indexOf(selected).clamp(0, values.length - 1);
    final thumbColor = colorOf?.call(selected) ?? context.colors.primary;
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.penny.surfaceHigh,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / values.length;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              left: w * index,
              top: 0,
              bottom: 0,
              width: w,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                decoration: BoxDecoration(
                  color: thumbColor,
                  borderRadius: BorderRadius.circular(height / 2),
                  boxShadow: [
                    BoxShadow(
                      color: thumbColor.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                for (final v in values)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: v == selected,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(height / 2),
                        onTap: () => onChanged(v),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: context.text.labelLarge!.copyWith(
                              color: v == selected
                                  ? Colors.white
                                  : context.penny.textMuted,
                            ),
                            child: Text(labelOf(v),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }
}
