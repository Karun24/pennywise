import 'package:flutter/foundation.dart' show ChangeNotifier;

/// Tabs of the bottom navigation bar. "Add" is an action, not a tab.
enum AppTab { home, analytics, budget, settings }

/// Lets any screen switch tabs (e.g. "See budgets" on the dashboard).
class ShellController extends ChangeNotifier {
  AppTab _tab = AppTab.home;

  AppTab get tab => _tab;

  void go(AppTab tab) {
    if (tab == _tab) return;
    _tab = tab;
    notifyListeners();
  }
}
