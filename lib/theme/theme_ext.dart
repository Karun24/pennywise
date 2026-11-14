import 'package:flutter/material.dart';

import 'penny_colors.dart';

/// Short-hands for theme access: `context.penny`, `context.colors`,
/// `context.text`.
extension ThemeContextX on BuildContext {
  PennyColors get penny =>
      Theme.of(this).extension<PennyColors>() ?? PennyColors.dark;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// Tabular figures keep columns of amounts aligned.
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];
