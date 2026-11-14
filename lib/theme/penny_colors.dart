import 'package:flutter/material.dart';

/// Semantic colours that Material's [ColorScheme] does not cover.
/// Access with `context.penny` (see `theme_ext.dart`).
@immutable
class PennyColors extends ThemeExtension<PennyColors> {
  const PennyColors({
    required this.income,
    required this.expense,
    required this.warning,
    required this.accent,
    required this.textMuted,
    required this.border,
    required this.surfaceHigh,
    required this.chartGrid,
    required this.heroGradient,
    required this.primaryGradient,
  });

  final Color income;
  final Color expense;
  final Color warning;

  /// Turquoise accent.
  final Color accent;
  final Color textMuted;
  final Color border;
  final Color surfaceHigh;
  final Color chartGrid;
  final List<Color> heroGradient;
  final List<Color> primaryGradient;

  static const dark = PennyColors(
    income: Color(0xFF34D399),
    expense: Color(0xFFFF7A90),
    warning: Color(0xFFFBBF24),
    accent: Color(0xFF2DD4BF),
    textMuted: Color(0xFF9AA3C7),
    border: Color(0xFF222B4D),
    surfaceHigh: Color(0xFF1A2244),
    chartGrid: Color(0xFF232C4F),
    heroGradient: [Color(0xFF2B1B7E), Color(0xFF5B3DF5), Color(0xFF9378FF)],
    primaryGradient: [Color(0xFF6D4AFF), Color(0xFFA78BFA)],
  );

  static const light = PennyColors(
    income: Color(0xFF0E9F6E),
    expense: Color(0xFFE5486A),
    warning: Color(0xFFD97706),
    accent: Color(0xFF0D9488),
    textMuted: Color(0xFF6B7194),
    border: Color(0xFFE4E7F2),
    surfaceHigh: Color(0xFFF0F1F8),
    chartGrid: Color(0xFFE8EAF4),
    heroGradient: [Color(0xFF3A22B8), Color(0xFF6246F5), Color(0xFF9C84FF)],
    primaryGradient: [Color(0xFF6246F5), Color(0xFF9C84FF)],
  );

  @override
  PennyColors copyWith({
    Color? income,
    Color? expense,
    Color? warning,
    Color? accent,
    Color? textMuted,
    Color? border,
    Color? surfaceHigh,
    Color? chartGrid,
    List<Color>? heroGradient,
    List<Color>? primaryGradient,
  }) {
    return PennyColors(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      warning: warning ?? this.warning,
      accent: accent ?? this.accent,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      chartGrid: chartGrid ?? this.chartGrid,
      heroGradient: heroGradient ?? this.heroGradient,
      primaryGradient: primaryGradient ?? this.primaryGradient,
    );
  }

  @override
  PennyColors lerp(ThemeExtension<PennyColors>? other, double t) {
    if (other is! PennyColors) return this;
    List<Color> lerpList(List<Color> a, List<Color> b) => [
          for (var i = 0; i < a.length && i < b.length; i++)
            Color.lerp(a[i], b[i], t)!,
        ];
    return PennyColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      chartGrid: Color.lerp(chartGrid, other.chartGrid, t)!,
      heroGradient: lerpList(heroGradient, other.heroGradient),
      primaryGradient: lerpList(primaryGradient, other.primaryGradient),
    );
  }
}
