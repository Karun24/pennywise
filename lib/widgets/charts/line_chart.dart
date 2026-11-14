import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/theme_ext.dart';
import 'chart_utils.dart';

class LineSeries {
  const LineSeries({
    required this.name,
    required this.values,
    required this.color,
    this.filled = false,
    this.dashed = false,
  });

  final String name;

  /// Null values are not drawn (e.g. future days).
  final List<int?> values;
  final Color color;
  final bool filled;
  final bool dashed;
}

/// Smooth animated line chart. Touch and drag to inspect values.
class LineChartView extends StatefulWidget {
  const LineChartView({
    super.key,
    required this.series,
    required this.xLabels,
    required this.formatValue,
    required this.formatAxis,
    this.height = 190,
    this.tooltipLabels,
  });

  final List<LineSeries> series;
  final List<String> xLabels;
  final List<String>? tooltipLabels;
  final String Function(int) formatValue;
  final String Function(int) formatAxis;
  final double height;

  @override
  State<LineChartView> createState() => _LineChartViewState();
}

class _LineChartViewState extends State<LineChartView> {
  int? _selected;

  void _select(double dx, double width) {
    final i = _LinePainter.indexAt(dx, width, widget.xLabels.length);
    if (i != _selected) setState(() => _selected = i);
  }

  @override
  Widget build(BuildContext context) {
    final style = context.text.labelSmall!.copyWith(
      color: context.penny.textMuted,
      fontSize: 10.5,
      fontFeatures: tabularFigures,
    );
    final dataKey = Object.hashAll(
        widget.series.map((s) => Object.hashAll(s.values)));
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, c) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _select(d.localPosition.dx, c.maxWidth),
          onHorizontalDragUpdate: (d) =>
              _select(d.localPosition.dx, c.maxWidth),
          onHorizontalDragEnd: (_) => setState(() => _selected = null),
          child: TweenAnimationBuilder<double>(
            key: ValueKey(dataKey),
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) => CustomPaint(
              size: Size(c.maxWidth, widget.height),
              painter: _LinePainter(
                series: widget.series,
                labels: widget.xLabels,
                tooltipLabels: widget.tooltipLabels,
                progress: progress,
                selected: _selected,
                formatValue: widget.formatValue,
                formatAxis: widget.formatAxis,
                labelStyle: style,
                gridColor: context.penny.chartGrid,
                surface: context.colors.surface,
                tooltipBg: context.colors.inverseSurface,
                tooltipStyle: style.copyWith(
                  color: context.colors.onInverseSurface,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.series,
    required this.labels,
    required this.tooltipLabels,
    required this.progress,
    required this.selected,
    required this.formatValue,
    required this.formatAxis,
    required this.labelStyle,
    required this.gridColor,
    required this.surface,
    required this.tooltipBg,
    required this.tooltipStyle,
  });

  final List<LineSeries> series;
  final List<String> labels;
  final List<String>? tooltipLabels;
  final double progress;
  final int? selected;
  final String Function(int) formatValue;
  final String Function(int) formatAxis;
  final TextStyle labelStyle;
  final Color gridColor;
  final Color surface;
  final Color tooltipBg;
  final TextStyle tooltipStyle;

  static const axisWidth = 46.0;
  static const bottomHeight = 22.0;
  static const topPad = 12.0;
  static const rightPad = 8.0;

  static int? indexAt(double dx, double width, int count) {
    if (count < 2) return count == 1 ? 0 : null;
    final w = width - axisWidth - rightPad;
    final step = w / (count - 1);
    final i = ((dx - axisWidth) / step).round();
    return i.clamp(0, count - 1).toInt();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n == 0) return;
    final chart = Rect.fromLTRB(axisWidth, topPad, size.width - rightPad,
        size.height - bottomHeight);
    var maxVal = 0;
    for (final s in series) {
      for (final v in s.values) {
        if (v != null) maxVal = math.max(maxVal, v);
      }
    }
    final top = niceCeil(maxVal.toDouble());

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final y = chart.bottom - chart.height * g / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      if (maxVal == 0 && g > 0) continue;
      final tp = layoutText(formatAxis((top * g / 3).round()), labelStyle,
          maxWidth: axisWidth - 6);
      tp.paint(canvas, Offset(axisWidth - 6 - tp.width, y - tp.height / 2));
    }

    final step = n == 1 ? 0.0 : chart.width / (n - 1);
    Offset point(int i, int v) => Offset(chart.left + step * i,
        chart.bottom - chart.height * (v / top) * progress);

    // X labels.
    final every = math.max(1, (n / 6).ceil());
    for (var i = 0; i < n; i += every) {
      final tp = layoutText(labels[i], labelStyle, maxWidth: 60);
      final x = (chart.left + step * i - tp.width / 2)
          .clamp(0.0, math.max(0.0, size.width - tp.width))
          .toDouble();
      tp.paint(canvas, Offset(x, chart.bottom + 6));
    }

    // Draw series back to front so the first series sits on top.
    for (final s in series.reversed) {
      final pts = <Offset>[];
      for (var i = 0; i < s.values.length && i < n; i++) {
        final v = s.values[i];
        if (v == null) break;
        pts.add(point(i, v));
      }
      if (pts.isEmpty) continue;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        final a = pts[i - 1], b = pts[i];
        final mx = (a.dx + b.dx) / 2;
        path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
      }
      if (s.filled && pts.length > 1) {
        final fill = Path.from(path)
          ..lineTo(pts.last.dx, chart.bottom)
          ..lineTo(pts.first.dx, chart.bottom)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(0, chart.top),
              Offset(0, chart.bottom),
              [s.color.withValues(alpha: 0.28), s.color.withValues(alpha: 0.0)],
            ),
        );
      }
      final stroke = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.dashed ? 2 : 2.6
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(s.dashed ? _dash(path) : path, stroke);
      if (selected == null) {
        canvas.drawCircle(pts.last, 4.5, Paint()..color = surface);
        canvas.drawCircle(pts.last, 3, Paint()..color = s.color);
      }
    }

    final sel = selected;
    if (sel != null && sel < n) {
      final x = chart.left + step * sel;
      canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom),
          Paint()
            ..color = gridColor
            ..strokeWidth = 1.5);
      var anchorY = chart.bottom;
      final lines = <(String, Color?)>[
        (
          tooltipLabels != null && sel < tooltipLabels!.length
              ? tooltipLabels![sel]
              : labels[sel],
          null
        ),
      ];
      for (final s in series) {
        if (sel >= s.values.length) continue;
        final v = s.values[sel];
        if (v == null) continue;
        final p = point(sel, v);
        anchorY = math.min(anchorY, p.dy);
        canvas.drawCircle(p, 5, Paint()..color = surface);
        canvas.drawCircle(p, 3.5, Paint()..color = s.color);
        lines.add(('${s.name}: ${formatValue(v)}', s.color));
      }
      paintTooltip(
        canvas,
        anchor: Offset(x, anchorY),
        bounds: Rect.fromLTWH(0, 0, size.width, size.height),
        lines: lines,
        background: tooltipBg,
        style: tooltipStyle,
      );
    }
  }

  Path _dash(Path source) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        out.addPath(metric.extractPath(d, math.min(d + 6, metric.length)),
            Offset.zero);
        d += 11;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.progress != progress ||
      old.selected != selected ||
      old.series != series ||
      old.labelStyle != labelStyle ||
      old.gridColor != gridColor;
}
