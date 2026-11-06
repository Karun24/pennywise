import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../screens/add_transaction/add_transaction_screen.dart';
import '../screens/analytics/analytics_screen.dart';
import '../screens/budget/budget_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../state/finance_store.dart';
import '../state/shell_controller.dart';
import '../theme/theme_ext.dart';
import '../widgets/common.dart';
import 'penny_bottom_bar.dart';

/// Root scaffold with the bottom navigation. Tabs keep their scroll state
/// via [IndexedStack].
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();
    final store = context.watch<FinanceStore>();

    final overlay = context.isDark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: context.colors.surface,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: context.colors.surface,
          );

    Widget body;
    if (store.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (store.loadError != null) {
      body = EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Something went wrong',
        message: store.loadError,
        action: FilledButton(
          onPressed: store.load,
          child: const Text('Try again'),
        ),
      );
    } else {
      body = IndexedStack(
        index: shell.tab.index,
        children: const [
          HomeScreen(),
          AnalyticsScreen(),
          BudgetScreen(),
          SettingsScreen(),
        ],
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: PopScope(
        canPop: shell.tab == AppTab.home,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) shell.go(AppTab.home);
        },
        child: Scaffold(
          body: body,
          bottomNavigationBar: PennyBottomBar(
            current: shell.tab,
            onSelect: shell.go,
            onAdd: () => AddTransactionScreen.open(context),
          ),
        ),
      ),
    );
  }
}
