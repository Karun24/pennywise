import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/theme_ext.dart';

class DonutSegment {
  const DonutSegment(this.value, this.color);
  final double value;
  final Color color;
}

/// Animated donut / progress ring with an optional centre widget.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.segments,
    this.size = 150,
    this.thickness = 16,
    this.center,
    this.total,
    this.gapRadians = 0.04,
  });

  final List<DonutSegment> segments;
  final double size;
  final double thickness;
  final Widget? center;

  /// When set, segments are drawn relative to this total (progress ring).
  final double? total;
  final double gapRadians;

  @override
  Widget build(BuildContext context) {
    final key = Object.hashAll(segments.map((s) => s.value));
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(key),
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, progress, child) => CustomPaint(
          painter: _DonutPainter(
            segments: segments,
            thickness: thickness,
            progress: progress,
            track: context.penny.surfaceHigh,
            total: total,
            gap: gapRadians,
          ),
          child: child,
        ),
        child: center == null ? null : Center(child: center),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segments,
    required this.thickness,
    required this.progress,
    required this.track,
    required this.total,
    required this.gap,
  });

  final List<DonutSegment> segments;
  final double thickness;
  final double progress;
  final Color track;
  final double? total;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (math.min(size.width, size.height) - thickness) / 2,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness,
    );
    final sum = segments.fold<double>(0, (a, s) => a + s.value);
    final denom = total ?? sum;
    if (denom <= 0) return;
    final visible = segments.where((s) => s.value > 0).toList();
    final useGap = total == null && visible.length > 1;
    var start = -math.pi / 2;
    for (final s in visible) {
      final fraction = math.min(s.value / denom, 1.0);
      var sweep = fraction * math.pi * 2 * progress;
      if (useGap) sweep = math.max(0.0, sweep - gap);
      if (sweep > 0) {
        canvas.drawArc(
          rect,
          start + (useGap ? gap / 2 : 0),
          sweep,
          false,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = thickness
            ..strokeCap = useGap ? StrokeCap.butt : StrokeCap.round,
        );
      }
      start += fraction * math.pi * 2 * progress;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress ||
      old.segments != segments ||
      old.track != track ||
      old.total != total;
}
