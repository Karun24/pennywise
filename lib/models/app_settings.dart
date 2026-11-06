/// User preferences, persisted as key/value rows in the `settings` table.
enum AppThemePreference {
  system('System'),
  light('Light'),
  dark('Dark');

  const AppThemePreference(this.label);
  final String label;

  static AppThemePreference fromName(String? v) => AppThemePreference.values
      .firstWhere((e) => e.name == v, orElse: () => AppThemePreference.dark);
}

class AppSettings {
  const AppSettings({
    this.theme = AppThemePreference.dark,
    this.currencyCode = 'INR',
    this.monthlyBudgetMinor,
    this.startingBalanceMinor = 0,
  });

  final AppThemePreference theme;
  final String currencyCode;

  /// Overall monthly spending limit; null when not set.
  final int? monthlyBudgetMinor;

  /// Money the user already had before they started tracking.
  final int startingBalanceMinor;

  static const keyTheme = 'theme';
  static const keyCurrency = 'currency';
  static const keyMonthlyBudget = 'monthly_budget_minor';
  static const keyStartingBalance = 'starting_balance_minor';

  AppSettings copyWith({
    AppThemePreference? theme,
    String? currencyCode,
    int? monthlyBudgetMinor,
    bool clearMonthlyBudget = false,
    int? startingBalanceMinor,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      currencyCode: currencyCode ?? this.currencyCode,
      monthlyBudgetMinor: clearMonthlyBudget
          ? null
          : (monthlyBudgetMinor ?? this.monthlyBudgetMinor),
      startingBalanceMinor: startingBalanceMinor ?? this.startingBalanceMinor,
    );
  }

  Map<String, String> toKeyValues() => {
        keyTheme: theme.name,
        keyCurrency: currencyCode,
        keyMonthlyBudget: monthlyBudgetMinor?.toString() ?? '',
        keyStartingBalance: startingBalanceMinor.toString(),
      };

  factory AppSettings.fromKeyValues(Map<String, String> kv) {
    final budget = int.tryParse(kv[keyMonthlyBudget] ?? '');
    return AppSettings(
      theme: AppThemePreference.fromName(kv[keyTheme]),
      currencyCode: (kv[keyCurrency]?.isNotEmpty ?? false)
          ? kv[keyCurrency]!
          : 'INR',
      monthlyBudgetMinor: (budget != null && budget > 0) ? budget : null,
      startingBalanceMinor: int.tryParse(kv[keyStartingBalance] ?? '') ?? 0,
    );
  }
}
