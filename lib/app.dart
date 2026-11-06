import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/app_settings.dart';
import 'shell/app_shell.dart';
import 'state/finance_store.dart';
import 'state/shell_controller.dart';
import 'state/update_controller.dart';
import 'theme/app_theme.dart';

class PennyWiseApp extends StatelessWidget {
  const PennyWiseApp({
    super.key,
    required this.store,
    this.updates,
    this.navigatorKey,
  });

  /// Lets code outside the widget tree (e.g. a tapped notification) navigate.
  final GlobalKey<NavigatorState>? navigatorKey;

  final FinanceStore store;

  /// Injected so tests never touch the network.
  final UpdateController? updates;

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
        if (updates != null)
          ChangeNotifierProvider<UpdateController>.value(value: updates!)
        else
          ChangeNotifierProvider<UpdateController>(
              create: (_) => UpdateController(configured: false)),
      ],
      child: Selector<FinanceStore, AppThemePreference>(
        selector: (_, s) => s.settings.theme,
        builder: (context, theme, _) => MaterialApp(
          title: 'PennyWise',
          navigatorKey: navigatorKey,
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
