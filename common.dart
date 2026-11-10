import 'package:flutter/material.dart';

import '../models/category.dart';
import '../theme/app_theme.dart';
import '../theme/theme_ext.dart';
import '../utils/category_icons.dart';

/// Rounded surface used for every content block.
class PennyCard extends StatelessWidget {
  const PennyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.gradient,
    this.color,
    this.radius = AppTheme.radius,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? color;
  final double radius;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: gradient == null ? (color ?? context.colors.surface) : null,
          gradient: gradient,
          borderRadius: r,
          border: border && gradient == null
              ? Border.all(color: context.penny.border.withValues(alpha: 0.7))
              : null,
          boxShadow: context.isDark
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF1B1F4B).withValues(alpha: 0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Title row above a section with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleMedium),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: context.text.bodySmall),
                  ),
              ],
            ),
          ),
          ?trailing,
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Tinted rounded square with the category icon.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 44});

  final Category? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = category?.color ?? context.penny.textMuted;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.16 : 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(
        CategoryIcons.of(category?.iconKey ?? 'other'),
        color: color,
        size: size * 0.5,
      ),
    );
  }
}

/// Animated, rounded progress bar.
class PennyProgressBar extends StatelessWidget {
  const PennyProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = 8,
    this.background,
  });

  /// 0..1 (values above 1 are clamped visually).
  final double value;
  final Color? color;
  final double height;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: background ?? context.penny.surfaceHigh,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0).toDouble()),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: v,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height),
                gradient: LinearGradient(
                  colors: [c.withValues(alpha: 0.75), c],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Friendly placeholder for empty lists and charts.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 16 : 40, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 12 : 18),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.primary.withValues(alpha: 0.12),
            ),
            child: Icon(icon,
                size: compact ? 24 : 34, color: context.colors.primary),
          ),
          SizedBox(height: compact ? 10 : 16),
          Text(title,
              textAlign: TextAlign.center, style: context.text.titleMedium),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!,
                textAlign: TextAlign.center,
                style: context.text.bodyMedium
                    ?.copyWith(color: context.penny.textMuted)),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Counts up to [value] when it changes.
class AnimatedAmount extends StatelessWidget {
  const AnimatedAmount({
    super.key,
    required this.value,
    required this.format,
    this.style,
  });

  final int value;
  final String Function(int) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        format(v.round()),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (style ?? const TextStyle())
            .copyWith(fontFeatures: tabularFigures),
      ),
    );
  }
}

/// Small rounded label, e.g. "On-device".
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      // A single Text (icon as an inline span) so the pill shrinks with an
      // ellipsis inside tight rows and sizes naturally everywhere else.
      child: Text.rich(
        TextSpan(children: [
          if (icon != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(icon, size: 12, color: c),
              ),
            ),
          TextSpan(text: label),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.text.labelSmall
            ?.copyWith(color: c, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Centers content and caps its width on tablets / landscape.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Standard page padding that grows a little on wide screens.
EdgeInsets pagePadding(BuildContext context, {double top = 8, double bottom = 24}) {
  final w = MediaQuery.sizeOf(context).width;
  final h = w > 600 ? 28.0 : 20.0;
  return EdgeInsets.fromLTRB(h, top, h, bottom);
}
