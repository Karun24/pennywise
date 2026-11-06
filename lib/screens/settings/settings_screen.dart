import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../services/backup_file_service.dart';
import '../../services/backup_service.dart';
import '../../services/demo_data.dart';
import '../../services/update_service.dart';
import '../../state/finance_store.dart';
import '../../state/update_controller.dart';
import '../../theme/theme_ext.dart';
import '../../utils/date_utils.dart';
import '../../utils/money.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/segmented.dart';
import '../../widgets/update_widgets.dart';
import '../notes/notes_screen.dart';
import 'manage_categories_screen.dart';

/// Profile & settings: preferences, money, categories, data, privacy.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _files = BackupFileService();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final s = store.settings;
    final c = store.currency;

    return SafeArea(
      bottom: false,
      child: ResponsiveCenter(
        child: ListView(
          padding: pagePadding(context, top: 12, bottom: 40),
          children: [
            Text('Profile & settings', style: context.text.headlineSmall),
            const SizedBox(height: 16),
            _PrivacyBanner(count: store.transactions.length),
            const SizedBox(height: 22),
            const _GroupTitle('Appearance'),
            PennyCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: context.text.titleSmall),
                  const SizedBox(height: 10),
                  PennySegmented<AppThemePreference>(
                    values: AppThemePreference.values,
                    selected: s.theme,
                    labelOf: (t) => t.label,
                    onChanged: (t) => _save(context, s.copyWith(theme: t)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const _GroupTitle('Money'),
            _SettingsGroup(children: [
              _Tile(
                icon: Icons.currency_exchange_rounded,
                title: 'Currency',
                value: '${c.code} (${c.symbol.trim()})',
                onTap: () => _pickCurrency(context),
              ),
              _Tile(
                icon: Icons.account_balance_wallet_rounded,
                title: 'Monthly budget',
                value: s.monthlyBudgetMinor == null
                    ? 'Not set'
                    : Money.format(s.monthlyBudgetMinor!, c),
                onTap: () => _editBudget(context),
              ),
              _Tile(
                icon: Icons.savings_rounded,
                title: 'Starting balance',
                value: Money.format(s.startingBalanceMinor, c),
                onTap: () => _editStartingBalance(context),
              ),
              _Tile(
                icon: Icons.category_rounded,
                title: 'Manage categories',
                value: '${store.categories.length}',
                onTap: () => ManageCategoriesScreen.open(context),
              ),
              _Tile(
                icon: Icons.sticky_note_2_rounded,
                title: 'Notes & reminders',
                value: '${store.notes.length}',
                onTap: () => NotesScreen.open(context),
              ),
            ]),
            const SizedBox(height: 22),
            const _GroupTitle('Your data'),
            _SettingsGroup(children: [
              _Tile(
                icon: Icons.cloud_upload_rounded,
                title: 'Export backup',
                subtitle: 'Save a .json file anywhere you like',
                onTap: () => _exportBackup(context),
              ),
              _Tile(
                icon: Icons.table_chart_rounded,
                title: 'Export as CSV',
                subtitle: 'Open your transactions in a spreadsheet',
                onTap: () => _exportCsv(context),
              ),
              _Tile(
                icon: Icons.restore_rounded,
                title: 'Import backup',
                subtitle: 'Replace current data with a backup file',
                onTap: () => _importBackup(context),
              ),
              if (!store.hasTransactions)
                _Tile(
                  icon: Icons.science_rounded,
                  title: 'Load demo data',
                  subtitle: 'Explore the app with sample transactions',
                  onTap: () => _loadDemo(context),
                ),
              _Tile(
                icon: Icons.delete_forever_rounded,
                title: 'Clear all data',
                subtitle: 'Permanently delete everything on this device',
                danger: true,
                onTap: () => _clearAll(context),
              ),
            ]),
            const SizedBox(height: 22),
            const _GroupTitle('App updates'),
            const _UpdatesGroup(),
            const SizedBox(height: 22),
            const _GroupTitle('About'),
            _SettingsGroup(children: [
              _Tile(
                icon: Icons.auto_awesome_rounded,
                title: 'How smart features work',
                onTap: () => _explainSmart(context),
              ),
              _Tile(
                icon: Icons.info_outline_rounded,
                title: 'PennyWise',
                value: AppBuildInfo.versionLabel,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ actions

  static Future<void> _save(BuildContext context, AppSettings next) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<FinanceStore>().updateSettings(next);
    } on StoreException catch (e) {
      messenger.showSnackBar(pennySnack(e.message, error: true));
    }
  }

  Future<void> _pickCurrency(BuildContext context) async {
    final store = context.read<FinanceStore>();
    final picked = await showModalBottomSheet<CurrencyInfo>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Text('Currency', style: ctx.text.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                'Changes how amounts are displayed. Existing amounts are not '
                'converted.',
                style: ctx.text.bodySmall,
              ),
            ),
            for (final cur in CurrencyInfo.supported)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: ctx.colors.primary.withValues(alpha: 0.14),
                  child: Text(cur.symbol.trim(),
                      style: TextStyle(
                          color: ctx.colors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: cur.symbol.trim().length > 2 ? 11 : 16)),
                ),
                title: Text(cur.name),
                subtitle: Text(cur.code),
                trailing: cur.code == store.settings.currencyCode
                    ? Icon(Icons.check_rounded, color: ctx.colors.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(cur),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await _save(context, store.settings.copyWith(currencyCode: picked.code));
  }

  Future<void> _editBudget(BuildContext context) async {
    final store = context.read<FinanceStore>();
    final current = store.settings.monthlyBudgetMinor;
    final result = await showAmountSheet(
      context,
      title: 'Monthly budget',
      subtitle: 'Your total spending limit for each month.',
      currency: store.currency,
      initialMinor: current,
      removeLabel: current == null ? null : 'Remove',
    );
    if (result == null || !context.mounted) return;
    await _save(
      context,
      result.removed
          ? store.settings.copyWith(clearMonthlyBudget: true)
          : store.settings.copyWith(monthlyBudgetMinor: result.amountMinor),
    );
  }

  Future<void> _editStartingBalance(BuildContext context) async {
    final store = context.read<FinanceStore>();
    final result = await showAmountSheet(
      context,
      title: 'Starting balance',
      subtitle: 'Money you already had when you started using PennyWise. '
          'It is added to your total balance.',
      currency: store.currency,
      initialMinor: store.settings.startingBalanceMinor == 0
          ? null
          : store.settings.startingBalanceMinor,
      allowZero: true,
    );
    if (result == null || !context.mounted) return;
    await _save(context,
        store.settings.copyWith(startingBalanceMinor: result.amountMinor ?? 0));
  }

  Future<void> _exportBackup(BuildContext context) async {
    final store = context.read<FinanceStore>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _files.shareBackup(context, store.snapshot());
    } catch (e) {
      messenger.showSnackBar(
          pennySnack('Could not export the backup. $e', error: true));
    }
  }

  Future<void> _exportCsv(BuildContext context) async {
    final store = context.read<FinanceStore>();
    final messenger = ScaffoldMessenger.of(context);
    if (!store.hasTransactions) {
      messenger.showSnackBar(pennySnack('No transactions to export yet.'));
      return;
    }
    final csv = BackupService.toCsv(
      transactions: store.transactions,
      categories: {for (final c in store.categories) c.id!: c},
      currency: store.currency,
    );
    try {
      await _files.shareCsv(context, csv);
    } catch (e) {
      messenger.showSnackBar(
          pennySnack('Could not export the CSV. $e', error: true));
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    final store = context.read<FinanceStore>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await _files.pickBackup();
      if (data == null || !context.mounted) return;
      final when = data.exportedAt == null
          ? ''
          : ' from ${DateUtilsX.dayMonthYear(data.exportedAt!)}';
      final ok = await confirmAction(
        context,
        title: 'Restore backup?',
        message: 'The backup$when contains ${data.transactions.length} '
            'transactions and ${data.categories.length} categories.\n\n'
            'This will REPLACE all data currently on this device. Consider '
            'exporting a backup first.',
        confirmLabel: 'Replace & restore',
        destructive: true,
      );
      if (!ok) return;
      await store.restore(data);
      messenger.showSnackBar(pennySnack('Backup restored'));
    } on BackupFormatException catch (e) {
      messenger.showSnackBar(pennySnack(e.message, error: true));
    } on StoreException catch (e) {
      messenger.showSnackBar(pennySnack(e.message, error: true));
    } catch (e) {
      messenger.showSnackBar(
          pennySnack('Could not open that file. $e', error: true));
    }
  }

  Future<void> _loadDemo(BuildContext context) async {
    final store = context.read<FinanceStore>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmAction(
      context,
      title: 'Load demo data?',
      message: 'Adds about two months of sample transactions. Remove them '
          'any time with "Clear all data".',
      confirmLabel: 'Load demo',
    );
    if (!ok) return;
    try {
      await store.insertMany(DemoData.generate(store.categories, now: store.now));
      messenger.showSnackBar(pennySnack('Demo data loaded'));
    } on StoreException catch (e) {
      messenger.showSnackBar(pennySnack(e.message, error: true));
    }
  }

  Future<void> _clearAll(BuildContext context) async {
    final store = context.read<FinanceStore>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmAction(
      context,
      title: 'Clear all data?',
      message: 'This permanently deletes all ${store.transactions.length} '
          'transactions, ${store.notes.length} notes and their reminders, '
          'budgets, custom categories and settings on this device. This '
          'cannot be undone.',
      confirmLabel: 'Continue',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final sure = await confirmAction(
      context,
      title: 'Are you absolutely sure?',
      message: 'If you might need this data later, export a backup first.',
      confirmLabel: 'Delete everything',
      destructive: true,
    );
    if (!sure) return;
    try {
      await store.clearAll();
      messenger.showSnackBar(pennySnack('All data cleared'));
    } on StoreException catch (e) {
      messenger.showSnackBar(pennySnack(e.message, error: true));
    }
  }

  void _explainSmart(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            Text('How smart features work', style: ctx.text.titleLarge),
            const SizedBox(height: 12),
            for (final (title, body) in const [
              (
                'No cloud AI',
                'PennyWise does not use ChatGPT, Gemini, Claude or any other '
                    'generative AI service. Nothing you enter is sent anywhere.'
              ),
              (
                'Auto-categorization',
                'A dictionary of keywords and merchants (Swiggy, Uber, '
                    'BigBasket, Netflix...) plus what you chose for the same '
                    'description in the past.'
              ),
              (
                'Smart entry',
                'Regular-expression rules pick out the amount, date, payment '
                    'method and whether it is income or an expense. When '
                    'something is unclear it asks you instead of guessing, '
                    'and nothing is saved until you confirm.'
              ),
              (
                'Insights',
                'Simple arithmetic on your own transactions: month-over-month '
                    'and week-over-week changes, averages, top categories, '
                    'savings rate and budget pace.'
              ),
              (
                'Unusual spending',
                'A purchase is flagged when it is at least 3x the median '
                    'for its category and well above the usual spread '
                    '(mean + 2 standard deviations), once a category has '
                    'enough history.'
              ),
            ]) ...[
              Text(title, style: ctx.text.titleSmall),
              const SizedBox(height: 4),
              Text(body, style: ctx.text.bodyMedium),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: context.penny.heroGradient,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Private by design',
                    style: context.text.titleMedium
                        ?.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  '$count transaction${count == 1 ? '' : 's'} stored only on '
                  'this device. No account, no ads, no trackers. Your '
                  'financial data never leaves your phone.',
                  style: context.text.bodySmall
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text.toUpperCase(),
            style: context.text.labelSmall?.copyWith(
                color: context.penny.textMuted, letterSpacing: 1.2)),
      );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => PennyCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: children),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? context.penny.expense : context.colors.primary;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
      title: Text(title,
          style: context.text.titleSmall
              ?.copyWith(color: danger ? context.penny.expense : null)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: context.text.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(value!,
                style: context.text.bodyMedium
                    ?.copyWith(color: context.penny.textMuted)),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: context.penny.textMuted),
          ],
        ],
      ),
    );
  }
}

/// Version info, manual "Check for updates" and the auto-check switch.
class _UpdatesGroup extends StatelessWidget {
  const _UpdatesGroup();

  Future<void> _check(BuildContext context) async {
    final updates = context.read<UpdateController>();
    final messenger = ScaffoldMessenger.of(context);
    await updates.check();
    if (!context.mounted) return;
    switch (updates.status) {
      case UpdateStatus.available:
        showUpdateSheet(context, updates.available!);
      case UpdateStatus.upToDate:
        messenger.showSnackBar(pennySnack('You have the latest version.'));
      case UpdateStatus.error:
        messenger.showSnackBar(pennySnack(
            updates.error ?? 'Could not check for updates.',
            error: true));
      case UpdateStatus.notConfigured:
      case UpdateStatus.idle:
      case UpdateStatus.checking:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateController>();
    final store = context.watch<FinanceStore>();
    final settings = store.settings;

    if (!updates.isConfigured) {
      return const _SettingsGroup(children: [
        _Tile(
          icon: Icons.system_update_rounded,
          title: 'Updates',
          subtitle: 'Available in builds made by GitHub. This build was '
              'made on a computer, so update checks are off.',
        ),
      ]);
    }

    final String subtitle;
    switch (updates.status) {
      case UpdateStatus.checking:
        subtitle = 'Checking...';
      case UpdateStatus.available:
        subtitle =
            'Version 1.0.${updates.available!.buildNumber} is available';
      case UpdateStatus.upToDate:
        subtitle = 'You have the latest version';
      case UpdateStatus.error:
        subtitle = updates.error ?? 'Could not check for updates';
      case UpdateStatus.idle:
      case UpdateStatus.notConfigured:
        subtitle = 'Installed: ${AppBuildInfo.versionLabel}';
    }

    return _SettingsGroup(children: [
      _Tile(
        icon: updates.hasUpdate
            ? Icons.system_update_rounded
            : Icons.refresh_rounded,
        title: updates.hasUpdate ? 'Install update' : 'Check for updates',
        subtitle: subtitle,
        onTap: updates.status == UpdateStatus.checking
            ? null
            : () => updates.hasUpdate
                ? showUpdateSheet(context, updates.available!)
                : _check(context),
      ),
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.colors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.autorenew_rounded,
              size: 20, color: context.colors.primary),
        ),
        title: Text('Check automatically', style: context.text.titleSmall),
        subtitle: Text(
          'Looks for a new version on GitHub when the app opens. '
          'No personal or financial data is sent.',
          style: context.text.bodySmall,
        ),
        value: settings.autoUpdateCheck,
        onChanged: (v) => SettingsScreen._save(
            context, settings.copyWith(autoUpdateCheck: v)),
      ),
    ]);
  }
}
