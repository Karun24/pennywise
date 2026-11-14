import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/app_settings.dart';
import 'services/app_lock_service.dart';
import 'shell/app_shell.dart';
import 'state/finance_store.dart';
import 'state/shell_controller.dart';
import 'state/update_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/app_lock_gate.dart';

class PennyWiseApp extends StatelessWidget {
  const PennyWiseApp({
    super.key,
    required this.store,
    this.updates,
    this.navigatorKey,
    this.authenticator,
  });

  /// Fingerprint / PIN check for App lock (a fake is injected in tests).
  final AppLockAuthenticator? authenticator;

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
        Provider<AppLockAuthenticator>(
            create: (_) => authenticator ?? DeviceAppLockAuthenticator()),
      ],
      child: Selector<FinanceStore, (AppThemePreference, bool, AppAccentColor)>(
        selector: (_, s) => (
          s.settings.theme,
          s.settings.amoledDark,
          s.settings.accentColor,
        ),
        builder: (context, themeData, _) => MaterialApp(
          title: 'PennyWise',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(accent: themeData.$3),
          darkTheme: AppTheme.dark(
            amoled: themeData.$2,
            accent: themeData.$3,
          ),
          themeMode: _mode(themeData.$1),
          // Keep layouts intact with very large accessibility font sizes.
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                  textScaler: mq.textScaler.clamp(maxScaleFactor: 1.35)),
              child: AppLockGate(child: child ?? const SizedBox.shrink()),
            );
          },
          home: const AppShell(),
        ),
      ),
    );
  }
}
