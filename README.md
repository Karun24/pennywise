# PennyWise

A private, offline, "smart" personal expense tracker for Android and iOS, built with Flutter.

- **Zero cost to run** – no accounts, no servers, no paid APIs, no ads, no trackers.
- **Your data stays on your phone** – stored in a local SQLite database in the app's private storage. The release app requests no Android permissions (none of the plugins add any).
- **Smart, but honest** – auto-categorisation, natural-language entry, insights and unusual-spend detection are **rule-based and statistical, running on the device**. No generative AI or cloud model is used, and the app says so.

---

## Features

| Area | What you get |
|---|---|
| Dashboard | Total balance (with optional starting balance), total income/expenses, this month's spend vs last month, smart insights carousel, last-7-days chart, 6-month chart, category donut, budget progress, recent transactions |
| Add / edit | Expense ↔ income toggle, amount, category grid (+ create custom), description with live auto-categorisation, date (Today / Yesterday / calendar), payment method (UPI, cash, cards, net banking, wallet), delete with undo |
| Smart entry | Type `spent 250 on lunch yesterday via UPI` → amount, type, category, date, payment and description are extracted. Ambiguities (two amounts, unclear category or type) are flagged and **you confirm before anything is saved** |
| History | Search (description, category, amount), type filter, period filter (this/last month, 30 days, year, custom range), multi-category filter, grouped by day with daily totals, swipe to delete (with confirm + undo), tap to edit |
| Analytics | Week / Month / Year with previous/next navigation, spent / earned / net / average-per-day, daily or monthly trend, income vs expenses (6 months), cumulative this-month vs last-month line, weekly totals (8 weeks), category breakdown, income by source, largest expenses. Tap or drag charts to see exact values |
| Budgets | Monthly budget ring with % used, remaining, safe daily spend and month-end projection; per-category budgets; warnings at 75 % and 90 %, alert when exceeded, instant alert after saving an expense that crosses a threshold |
| Insights | Month-to-date vs same period last month, week-over-week category increases, top category, average daily spend, savings rate, budget pace, unusual transactions (≥3× median and > mean + 2σ), many small discretionary purchases, no-spend days. Every number comes from your data; with no data there are no insights |
| Settings | Theme (System / Light / Dark), currency (INR default + 8 others, display only), monthly budget, starting balance, manage categories, export JSON backup, export CSV, import backup (validated before anything is replaced), demo data, clear all data (double confirmation) |

## Architecture

```
lib/
  main.dart                 Opens the database, loads the store, runs the app
  app.dart                  MaterialApp, themes, providers
  models/                   TransactionEntry, Category, CategoryBudget, AppSettings, BackupData
  database/                 SQLite schema, migrations, default categories
  repositories/             FinanceRepository interface + SQLite and in-memory implementations
  services/                 Pure Dart logic (no Flutter): analytics, budgets, backup/CSV, demo data
    smart/                  Categorizer, TransactionParser (NL entry), InsightsEngine
  state/                    FinanceStore (ChangeNotifier, single source of truth), ShellController
  theme/                    Design tokens, light/dark ThemeData, ThemeExtension for semantic colours
  shell/                    App shell + custom bottom navigation with raised Add button
  screens/                  home, add_transaction, history, analytics, budget, settings
  widgets/                  Reusable cards, tiles, dialogs, segmented control, custom-painted charts
  utils/                    Money (integer minor units, Indian grouping), dates, category icons
test/                       Unit tests for parser, categorizer, money, analytics, budgets,
                            insights, backup/restore, store; widget tests for the main flows
```

Key decisions:

- **Money is stored as integers (paise/cents)** – no floating-point rounding errors.
- **Charts are drawn with `CustomPainter`** – no chart dependency to break, fully themed, animated, touch-to-inspect.
- **`provider` + one `FinanceStore`** – simple, testable state management appropriate for this size of app.
- **Repository interface** – the UI never touches SQLite. Cloud sync can be added later as another `FinanceRepository` (or a wrapper around the local one) without touching screens.
- **Optional AI later** – the smart layer is three pure classes (`Categorizer`, `TransactionParser`, `InsightsEngine`). A future AI-backed implementation can sit beside them behind `FinanceStore` and fall back to the local rules when offline or not configured.
- **Schema versioning** – `AppDatabase.schemaVersion` + `_onUpgrade` for safe migrations; backups carry a `format` and `version` and are fully validated before restore.

Dependencies (all free, open source): `provider`, `sqflite`, `path`, `path_provider`, `intl`, `share_plus`, `file_picker`. Font: Inter (SIL Open Font License, bundled).

## Requirements

- Flutter **3.38 or newer** (stable). Check with `flutter --version`; update with `flutter upgrade`.
- Android Studio (for the Android SDK) or the Android command-line tools.
- An Android phone with **USB debugging** enabled.

## Run it on your Android phone (Windows)

1. **Install Flutter** (once): follow <https://docs.flutter.dev/get-started/install/windows/mobile>, then run `flutter doctor` and fix anything it reports for Android (accept licences with `flutter doctor --android-licenses`).
2. **Enable USB debugging** on the phone: Settings → About phone → tap *Build number* 7 times → Settings → Developer options → *USB debugging* on. Connect by USB and accept the prompt on the phone.
3. **One-time project setup** – open PowerShell in this folder and run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```

   This generates the `android/` and `ios/` platform folders (keeping every existing file, including the PennyWise launcher icon), names the app "PennyWise", then runs `flutter pub get`, `dart format`, `flutter analyze` and `flutter test`.
4. **Run**: `flutter devices` (your phone should be listed), then `flutter run`.
5. **Install a standalone build** (so it stays on the phone without the cable):

   ```powershell
   flutter build apk --release
   flutter install
   ```

   The APK is at `build\app\outputs\flutter-apk\app-release.apk` if you prefer to copy it to the phone yourself.

Tip: in the app, *Profile → Load demo data* (only shown when there are no transactions) lets you explore all screens; *Clear all data* removes it.

### If something fails

- `pub get` complains about versions → `flutter upgrade`, then `flutter pub upgrade --major-versions`.
- Gradle/Kotlin errors on first build → make sure `flutter doctor` is clean and Android Studio is up to date; then `flutter clean` and try again.
- Analyzer or test failures → copy the output and send it back; they are quick to fix.

### iOS

The code is iOS-ready (all packages support iOS), but building requires a Mac with Xcode. `file_picker` needs iOS 14+: set `platform :ios, '14.0'` in `ios/Podfile` (or the deployment target in Xcode).

## Privacy

- No analytics, ads, crash reporters or network calls.
- Backups are only created when you tap *Export*, and go only where you choose in the share sheet.
- Imported backups are validated (format, version, ids, amounts, category references) before the existing data is replaced in a single database transaction.
- CSV export neutralises spreadsheet formula injection.

## Roadmap ideas

Recurring transactions and reminders (local notifications), multiple accounts/wallets, savings goals, home-screen widget, app lock (biometrics), optional encrypted cloud backup, and optional AI insights via a free/local model behind the existing smart-layer seam.
