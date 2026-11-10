import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/theme_ext.dart';
import 'chart_utils.dart';

/// Lightweight animated bar chart (single or grouped series) drawn with a
/// CustomPainter. Tap a bar to see its exact value.
class BarChartView extends StatefulWidget {
  const BarChartView({
    super.key,
    required this.labels,
    required this.series,
    required this.colors,
    required this.formatValue,
    required this.formatAxis,
    this.seriesNames,
    this.height = 180,
    this.highlightIndex,
    this.tooltipLabels,
  });

  /// X-axis labels, one per group.
  final List<String> labels;

  /// series[s][i] = value of series s at group i (minor units).
  final List<List<int>> series;
  final List<Color> colors;
  final List<String>? seriesNames;
  final String Function(int) formatValue;
  final String Function(int) formatAxis;
  final double height;

  /// Group to emphasise (e.g. today).
  final int? highlightIndex;

  /// Optional longer labels for tooltips (e.g. full dates).
  final List<String>? tooltipLabels;

  @override
  State<BarChartView> createState() => _BarChartViewState();
}

class _BarChartViewState extends State<BarChartView> {
  int? _selected;

  @override
  void didUpdateWidget(covariant BarChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selected != null && _selected! >= widget.labels.length) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataKey = Object.hash(
        Object.hashAll(widget.labels),
        Object.hashAll(widget.series.map(Object.hashAll)));
    final style = context.text.labelSmall!.copyWith(
      color: context.penny.textMuted,
      fontSize: 10.5,
      fontFeatures: tabularFigures,
    );
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final idx = _BarPainter.indexAt(
                d.localPosition.dx, constraints.maxWidth, widget.labels.length);
            setState(() => _selected = (idx == _selected) ? null : idx);
          },
          child: TweenAnimationBuilder<double>(
            key: ValueKey(dataKey),
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 750),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) => CustomPaint(
              size: Size(constraints.maxWidth, widget.height),
              painter: _BarPainter(
                labels: widget.labels,
                tooltipLabels: widget.tooltipLabels,
                series: widget.series,
                colors: widget.colors,
                seriesNames: widget.seriesNames,
                progress: progress,
                selected: _selected,
                highlight: widget.highlightIndex,
                formatValue: widget.formatValue,
                formatAxis: widget.formatAxis,
                labelStyle: style,
                highlightColor: context.colors.primary,
                gridColor: context.penny.chartGrid,
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

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.labels,
    required this.tooltipLabels,
    required this.series,
    required this.colors,
    required this.seriesNames,
    required this.progress,
    required this.selected,
    required this.highlight,
    required this.formatValue,
    required this.formatAxis,
    required this.labelStyle,
    required this.highlightColor,
    required this.gridColor,
    required this.tooltipBg,
    required this.tooltipStyle,
  });

  final List<String> labels;
  final List<String>? tooltipLabels;
  final List<List<int>> series;
  final List<Color> colors;
  final List<String>? seriesNames;
  final double progress;
  final int? selected;
  final int? highlight;
  final String Function(int) formatValue;
  final String Function(int) formatAxis;
  final TextStyle labelStyle;
  final Color highlightColor;
  final Color gridColor;
  final Color tooltipBg;
  final TextStyle tooltipStyle;

  static const axisWidth = 46.0;
  static const bottomHeight = 22.0;
  static const topPad = 10.0;

  static int? indexAt(double dx, double width, int count) {
    if (count == 0 || dx < axisWidth) return null;
    final groupW = (width - axisWidth) / count;
    final i = ((dx - axisWidth) / groupW).floor();
    return i.clamp(0, count - 1).toInt();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n == 0) return;
    final chart = Rect.fromLTRB(
        axisWidth, topPad, size.width, size.height - bottomHeight);
    var maxVal = 0;
    for (final s in series) {
      for (final v in s) {
        maxVal = math.max(maxVal, v);
      }
    }
    final top = niceCeil(maxVal.toDouble());

    // Grid + axis labels.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final y = chart.bottom - chart.height * g / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      final label = maxVal == 0 && g > 0 ? '' : formatAxis((top * g / 3).round());
      if (label.isEmpty) continue;
      final tp = layoutText(label, labelStyle, maxWidth: axisWidth - 6);
      tp.paint(canvas, Offset(axisWidth - 6 - tp.width, y - tp.height / 2));
    }

    final groupW = chart.width / n;
    final s = series.length;
    final barW = math.min(groupW * 0.62 / s, 22.0).clamp(2.0, 22.0).toDouble();
    const innerGap = 3.0;
    final totalW = barW * s + innerGap * (s - 1);
    final labelEvery = math.max(1, (n / 8).ceil());

    for (var i = 0; i < n; i++) {
      final gx = chart.left + groupW * i + (groupW - totalW) / 2;
      final dim = selected != null && selected != i;
      for (var j = 0; j < s; j++) {
        final value = i < series[j].length ? series[j][i] : 0;
        final color = colors[j % colors.length];
        final x = gx + j * (barW + innerGap);
        final h = value <= 0 ? 0.0 : chart.height * (value / top) * progress;
        if (h < 2) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, chart.bottom - 2, barW, 2),
                const Radius.circular(1)),
            Paint()..color = color.withValues(alpha: 0.18),
          );
          continue;
        }
        final rect = Rect.fromLTWH(x, chart.bottom - h, barW, h);
        final radius = Radius.circular(math.min(6.0, barW / 2));
        final alpha = dim ? 0.3 : 1.0;
        final paint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              color.withValues(alpha: 0.55 * alpha),
              color.withValues(alpha: alpha),
            ],
          ).createShader(rect);
        canvas.drawRRect(
          RRect.fromRectAndCorners(rect, topLeft: radius, topRight: radius),
          paint,
        );
      }
      final isHighlight = i == highlight || i == selected;
      if (i % labelEvery == 0 || isHighlight) {
        final style = isHighlight
            ? labelStyle.copyWith(
                color: highlightColor, fontWeight: FontWeight.w700)
            : labelStyle;
        final tp = layoutText(labels[i], style, maxWidth: math.max(groupW * labelEvery, 24.0));
        tp.paint(
          canvas,
          Offset(chart.left + groupW * i + groupW / 2 - tp.width / 2,
              chart.bottom + 6),
        );
      }
    }

    final sel = selected;
    if (sel != null && sel < n && progress > 0.95) {
      var maxInGroup = 0;
      for (final ser in series) {
        if (sel < ser.length) maxInGroup = math.max(maxInGroup, ser[sel]);
      }
      final barTop = chart.bottom - chart.height * (maxInGroup / top);
      final title = tooltipLabels != null && sel < tooltipLabels!.length
          ? tooltipLabels![sel]
          : labels[sel];
      paintTooltip(
        canvas,
        anchor: Offset(chart.left + groupW * sel + groupW / 2, barTop),
        bounds: Rect.fromLTWH(0, 0, size.width, size.height),
        background: tooltipBg,
        style: tooltipStyle,
        lines: [
          (title, null),
          for (var j = 0; j < series.length; j++)
            (
              '${seriesNames != null && j < seriesNames!.length ? '${seriesNames![j]}: ' : ''}'
                  '${formatValue(sel < series[j].length ? series[j][sel] : 0)}',
              series.length > 1 ? colors[j % colors.length] : null,
            ),
        ],
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.progress != progress ||
      old.selected != selected ||
      old.series != series ||
      old.labels != labels ||
      old.labelStyle != labelStyle ||
      old.gridColor != gridColor;
}
