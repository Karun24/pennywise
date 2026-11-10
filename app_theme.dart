import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'penny_colors.dart';

/// PennyWise design system: midnight navy, purple/lavender gradients,
/// turquoise and green accents, generous radii and calm typography.
class AppTheme {
  AppTheme._();

  static const radius = 24.0;
  static const radiusSmall = 16.0;
  static const fontFamily = 'Inter';

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        background: const Color(0xFF0A0F1F),
        surface: const Color(0xFF121935),
        surfaceHigh: const Color(0xFF1A2244),
        onSurface: const Color(0xFFF2F3FF),
        primary: const Color(0xFF8B6CFF),
        secondary: const Color(0xFF2DD4BF),
        error: const Color(0xFFFF7A90),
        penny: PennyColors.dark,
      );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        background: const Color(0xFFF5F6FB),
        surface: Colors.white,
        surfaceHigh: const Color(0xFFF0F1F8),
        onSurface: const Color(0xFF0E1330),
        primary: const Color(0xFF6246F5),
        secondary: const Color(0xFF0D9488),
        error: const Color(0xFFE5486A),
        penny: PennyColors.light,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceHigh,
    required Color onSurface,
    required Color primary,
    required Color secondary,
    required Color error,
    required PennyColors penny,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primary.withValues(alpha: 0.18),
      onPrimaryContainer: onSurface,
      secondary: secondary,
      onSecondary: isDark ? const Color(0xFF032A26) : Colors.white,
      tertiary: penny.income,
      onTertiary: Colors.white,
      error: error,
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: penny.textMuted,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHigh,
      outline: penny.border,
      outlineVariant: penny.border,
      shadow: Colors.black,
      inverseSurface: isDark ? const Color(0xFFF2F3FF) : const Color(0xFF151B36),
      onInverseSurface:
          isDark ? const Color(0xFF0E1330) : const Color(0xFFF2F3FF),
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: background,
      canvasColor: background,
    );

    final text = base.textTheme
        .copyWith(
          displaySmall: base.textTheme.displaySmall
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1),
          headlineMedium: base.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
          headlineSmall: base.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
          titleLarge: base.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
          titleMedium: base.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.1),
          titleSmall: base.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
          labelLarge: base.textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
          bodySmall: base.textTheme.bodySmall?.copyWith(color: penny.textMuted),
        )
        .apply(bodyColor: onSurface, displayColor: onSurface);

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: c, width: w),
        );

    return base.copyWith(
      textTheme: text,
      extensions: [penny],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: TextStyle(color: penny.textMuted),
        labelStyle: TextStyle(color: penny.textMuted),
        prefixIconColor: penny.textMuted,
        suffixIconColor: penny.textMuted,
        border: border(Colors.transparent),
        enabledBorder: border(Colors.transparent),
        focusedBorder: border(primary, 1.5),
        errorBorder: border(error),
        focusedErrorBorder: border(error, 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 52),
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSmall)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          minimumSize: const Size(64, 48),
          side: BorderSide(color: penny.border),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSmall)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: text.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        selectedColor: primary.withValues(alpha: isDark ? 0.28 : 0.14),
        side: BorderSide(color: penny.border),
        labelStyle: text.labelLarge?.copyWith(fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        showCheckmark: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: penny.textMuted.withValues(alpha: 0.4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF232C55) : const Color(0xFF151B36),
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: const Color(0xFFC4B5FD),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(color: penny.border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: penny.textMuted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? primary : null),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    );
  }
}
