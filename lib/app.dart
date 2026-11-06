import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/app_settings.dart';
import 'shell/app_shell.dart';
import 'state/finance_store.dart';
import 'state/shell_controller.dart';
import 'theme/app_theme.dart';

class PennyWiseApp extends StatelessWidget {
  const PennyWiseApp({super.key, required this.store});

  final FinanceStore store;

  static ThemeMode _mode(AppThemePreference p) => switch (p) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      };

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<FinanceStore>.value(value: store),
        ChangeNotifierProvider<ShellController>(
            create: (_) => ShellController()),
      ],
      child: Selector<FinanceStore, AppThemePreference>(
        selector: (_, s) => s.settings.theme,
        builder: (context, theme, _) => MaterialApp(
          title: 'PennyWise',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: _mode(theme),
          // Keep layouts intact with very large accessibility font sizes.
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                  textScaler: mq.textScaler.clamp(maxScaleFactor: 1.35)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const AppShell(),
        ),
      ),
    );
  }
}
