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
    this.autoUpdateCheck = true,
    this.dailyReminder = false,
    this.dailyReminderMinutes = 21 * 60,
    this.appLock = false,
  });

  final AppThemePreference theme;
  final String currencyCode;

  /// Overall monthly spending limit; null when not set.
  final int? monthlyBudgetMinor;

  /// Money the user already had before they started tracking.
  final int startingBalanceMinor;

  /// Check GitHub for a newer version when the app starts.
  final bool autoUpdateCheck;

  /// Notify once a day to log expenses (skipped if already logged).
  final bool dailyReminder;

  /// Time of the daily reminder in minutes after midnight (default 9 PM).
  final int dailyReminderMinutes;

  /// Require fingerprint / face / phone PIN to open the app.
  final bool appLock;

  static const keyTheme = 'theme';
  static const keyCurrency = 'currency';
  static const keyMonthlyBudget = 'monthly_budget_minor';
  static const keyStartingBalance = 'starting_balance_minor';
  static const keyAutoUpdateCheck = 'auto_update_check';
  static const keyDailyReminder = 'daily_reminder';
  static const keyDailyReminderMinutes = 'daily_reminder_minutes';
  static const keyAppLock = 'app_lock';

  AppSettings copyWith({
    AppThemePreference? theme,
    String? currencyCode,
    int? monthlyBudgetMinor,
    bool clearMonthlyBudget = false,
    int? startingBalanceMinor,
    bool? autoUpdateCheck,
    bool? dailyReminder,
    int? dailyReminderMinutes,
    bool? appLock,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      currencyCode: currencyCode ?? this.currencyCode,
      monthlyBudgetMinor: clearMonthlyBudget
          ? null
          : (monthlyBudgetMinor ?? this.monthlyBudgetMinor),
      startingBalanceMinor: startingBalanceMinor ?? this.startingBalanceMinor,
      autoUpdateCheck: autoUpdateCheck ?? this.autoUpdateCheck,
      dailyReminder: dailyReminder ?? this.dailyReminder,
      dailyReminderMinutes: dailyReminderMinutes ?? this.dailyReminderMinutes,
      appLock: appLock ?? this.appLock,
    );
  }

  Map<String, String> toKeyValues() => {
        keyTheme: theme.name,
        keyCurrency: currencyCode,
        keyMonthlyBudget: monthlyBudgetMinor?.toString() ?? '',
        keyStartingBalance: startingBalanceMinor.toString(),
        keyAutoUpdateCheck: autoUpdateCheck ? '1' : '0',
        keyDailyReminder: dailyReminder ? '1' : '0',
        keyDailyReminderMinutes: dailyReminderMinutes.toString(),
        keyAppLock: appLock ? '1' : '0',
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
      autoUpdateCheck: kv[keyAutoUpdateCheck] != '0',
      dailyReminder: kv[keyDailyReminder] == '1',
      dailyReminderMinutes:
          (int.tryParse(kv[keyDailyReminderMinutes] ?? '') ?? 21 * 60)
              .clamp(0, 24 * 60 - 1),
      appLock: kv[keyAppLock] == '1',
    );
  }
}
