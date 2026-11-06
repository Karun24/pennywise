import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Rounds [value] up to a "nice" axis maximum (1, 1.2, 1.5, 2, 2.5 ... x10^n).
double niceCeil(double value) {
  if (value <= 0) return 1;
  final exponent = (math.log(value) / math.ln10).floor();
  final magnitude = math.pow(10, exponent).toDouble();
  final normalized = value / magnitude;
  const steps = [1.0, 1.2, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0];
  for (final s in steps) {
    if (normalized <= s + 1e-9) return s * magnitude;
  }
  return 10 * magnitude;
}

TextPainter layoutText(String text, TextStyle style, {double maxWidth = 200}) {
  return TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
}

/// Draws a rounded tooltip bubble with [lines] near [anchor], kept inside
/// [bounds].
void paintTooltip(
  Canvas canvas, {
  required Offset anchor,
  required Rect bounds,
  required List<(String, Color?)> lines,
  required Color background,
  required TextStyle style,
}) {
  final painters = [
    for (final (text, dot) in lines)
      (layoutText(text, style.copyWith(color: style.color), maxWidth: 220), dot),
  ];
  const padH = 10.0, padV = 7.0, gap = 3.0, dotSize = 7.0;
  var width = 0.0, height = 0.0;
  for (final (p, dot) in painters) {
    width = math.max(width, p.width + (dot != null ? dotSize + 6 : 0));
    height += p.height + gap;
  }
  height -= gap;
  final w = width + padH * 2, h = height + padV * 2;
  var left = anchor.dx - w / 2;
  left = left.clamp(bounds.left, math.max(bounds.left, bounds.right - w)).toDouble();
  var top = anchor.dy - h - 8;
  if (top < bounds.top) top = bounds.top;
  final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w, h), const Radius.circular(10));
  canvas.drawRRect(rect, Paint()..color = background);
  var y = top + padV;
  for (final (p, dot) in painters) {
    var x = left + padH;
    if (dot != null) {
      canvas.drawCircle(
          Offset(x + dotSize / 2, y + p.height / 2), dotSize / 2, Paint()..color = dot);
      x += dotSize + 6;
    }
    p.paint(canvas, Offset(x, y));
    y += p.height + gap;
  }
}
