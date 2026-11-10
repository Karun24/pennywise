import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../models/transaction_entry.dart';
import '../../services/budget_service.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/date_utils.dart';
import '../../utils/money.dart';
import '../../widgets/charts/donut_chart.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';

Color budgetColor(BuildContext context, BudgetLevel level) => switch (level) {
      BudgetLevel.safe => context.penny.income,
      BudgetLevel.warning => context.penny.warning,
      BudgetLevel.danger => context.penny.expense,
      BudgetLevel.exceeded => context.penny.expense,
    };

/// Monthly + per-category budgets with pace tracking and alerts.
class BudgetScreen extends StatelessWidget {
  const BudgetScreen({super.key});

  Future<void> _editMonthly(BuildContext context) async {
    final store = context.read<FinanceStore>();
    final messenger = ScaffoldMessenger.of(context);
    final current = store.settings.monthlyBudgetMinor;
    final result = await showAmountSheet(
      context,
      title: 'Monthly budget',
      subtitle: 'Your total spending limit for each month.',
      currency: store.currency,
      initialMinor: current,
      removeLabel: current == null ? null : 'Remove',
    );
    if (result == null) return;
    try {
      await store.updateSettings(result.removed
          ? store.settings.copyWith(clearMonthlyBudget: true)
          : store.settings.copyWith(monthlyBudgetMinor: result.amountMinor));
      messenger.showSnackBar(pennySnack(
          result.removed ? 'Monthly budget removed' : 'Monthly budget saved'));
    } on StoreException catch (e) {
      messenger.showSnackBar(pennySnack(e.message, error: true));
    }
  }

  Future<void> _editCategory(BuildContext context, Category category) async {
    final store = context.read<FinanceStore>();
    final messenger = ScaffoldMessenger.of(context);
    final existing = store.budgetFor(category.id!);
    final result = await showAmountSheet(
      context,
      title: '${category.name} budget',
      subtitle: 'Monthly limit for this category.',
      currency: store.currency,
      initialMinor: existing?.amountMinor,
      removeLabel: existing == null ? null : 'Remove',
    );
    if (result == null) return;
    try {
      if (result.removed) {
        await store.removeCategoryBudget(category.id!);
      } else {
        await store.setCategoryBudget(category.id!, result.amountMinor!);
      }
      messenger.showSnackBar(pennySnack('${category.name} budget '
          '${result.removed ? 'removed' : 'saved'}'));
    } on StoreException catch (e) {
      messenger.showSnackBar(pennySnack(e.message, error: true));
    }
  }

  Future<void> _addCategoryBudget(BuildContext context) async {
    final store = context.read<FinanceStore>();
    final candidates = store
        .categoriesOf(TransactionType.expense)
        .where((c) => store.budgetFor(c.id!) == null)
        .toList();
    if (candidates.isEmpty) {
      showSnack(context, 'Every category already has a budget.');
      return;
    }
    final picked = await showModalBottomSheet<Category>(
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
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text('Choose a category', style: ctx.text.titleLarge),
            ),
            for (final c in candidates)
              ListTile(
                leading: CategoryAvatar(category: c, size: 38),
                title: Text(c.name),
                onTap: () => Navigator.of(ctx).pop(c),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await _editCategory(context, picked);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final c = store.currency;
    final o = store.budgetOverview();
    final overall = o.overall;

    return SafeArea(
      bottom: false,
      child: ResponsiveCenter(
        child: ListView(
          padding: pagePadding(context, top: 12, bottom: 32),
          children: [
            Text('Budgets', style: context.text.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '${DateUtilsX.monthYear(o.month)} · ${o.daysLeft} '
              'day${o.daysLeft == 1 ? '' : 's'} left',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: 16),
            if (overall == null)
              PennyCard(
                child: EmptyState(
                  compact: true,
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'Set a monthly budget',
                  message: 'Track your pace through the month and get a '
                      'warning at 75% and 90% of your limit.',
                  action: FilledButton(
                    onPressed: () => _editMonthly(context),
                    child: const Text('Set budget'),
                  ),
                ),
              )
            else
              _OverallCard(
                overview: o,
                status: overall,
                currency: c,
                onEdit: () => _editMonthly(context),
              ),
            if (o.alerts.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final a in o.alerts.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AlertTile(
                    status: a,
                    name: a.categoryId == null
                        ? 'Monthly budget'
                        : store.categoryById(a.categoryId!)?.name ?? '-',
                    currency: c,
                  ),
                ),
            ],
            const SizedBox(height: 24),
            SectionHeader(
              title: 'Category budgets',
              subtitle: 'Limits for individual categories',
              actionLabel: 'Add',
              onAction: () => _addCategoryBudget(context),
            ),
            if (o.categories.isEmpty)
              PennyCard(
                child: Text(
                  'No category budgets yet. Add one for categories you '
                  'want to keep an eye on, like Food & Dining or Shopping.',
                  style: context.text.bodySmall,
                ),
              )
            else
              PennyCard(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Column(
                  children: [
                    for (final s in o.categories)
                      _CategoryBudgetRow(
                        status: s,
                        category: store.categoryById(s.categoryId!),
                        currency: c,
                        onTap: () {
                          final cat = store.categoryById(s.categoryId!);
                          if (cat != null) _editCategory(context, cat);
                        },
                      ),
                  ],
                ),
              ),
            if (overall != null && o.categories.isNotEmpty) ...[
              const SizedBox(height: 12),
              _AllocationNote(overview: o, currency: c),
            ],
          ],
        ),
      ),
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({
    required this.overview,
    required this.status,
    required this.currency,
    required this.onEdit,
  });

  final BudgetOverview overview;
  final BudgetStatus status;
  final CurrencyInfo currency;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = budgetColor(context, status.level);
    final pct = (status.ratio * 100).round();
    final safe = overview.safeDailyMinor;
    final projected = overview.projectedMinor;
    String fmt(int v) => Money.format(v, currency);

    return PennyCard(
      onTap: onEdit,
      child: Column(
        children: [
          Row(
            children: [
              Text('Monthly budget', style: context.text.titleMedium),
              const Spacer(),
              Icon(Icons.edit_rounded, size: 18, color: context.penny.textMuted),
            ],
          ),
          const SizedBox(height: 16),
          DonutChart(
            size: 180,
            thickness: 16,
            total: status.limitMinor.toDouble(),
            segments: [DonutSegment(status.spentMinor.toDouble(), color)],
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$pct%',
                    style: context.text.headlineMedium?.copyWith(color: color)),
                Text('used', style: context.text.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _Stat(label: 'Spent', value: fmt(status.spentMinor)),
              _Stat(label: 'Budget', value: fmt(status.limitMinor)),
              _Stat(
                label: status.remainingMinor >= 0 ? 'Left' : 'Over by',
                value: fmt(status.remainingMinor.abs()),
                color: status.remainingMinor >= 0 ? null : context.penny.expense,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.speed_rounded, size: 18, color: context.penny.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  safe == null || safe == 0
                      ? 'No budget left for the rest of the month.'
                      : 'You can spend ${fmt(safe)} a day for the next '
                          '${overview.daysLeft} day${overview.daysLeft == 1 ? '' : 's'}.',
                  style: context.text.bodySmall
                      ?.copyWith(color: context.colors.onSurface),
                ),
              ),
            ],
          ),
          if (overview.dayOfMonth >= 3 && overview.monthSpentMinor > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.timeline_rounded,
                    size: 18,
                    color: projected > status.limitMinor
                        ? context.penny.warning
                        : context.penny.income),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'At your current pace you will spend about '
                    '${fmt(projected)} this month.',
                    style: context.text.bodySmall
                        ?.copyWith(color: context.colors.onSurface),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(label, style: context.text.bodySmall),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: context.text.titleSmall?.copyWith(
                      color: color, fontFeatures: tabularFigures)),
            ),
          ],
        ),
      );
}

class _AlertTile extends StatelessWidget {
  const _AlertTile(
      {required this.status, required this.name, required this.currency});
  final BudgetStatus status;
  final String name;
  final CurrencyInfo currency;

  @override
  Widget build(BuildContext context) {
    final color = budgetColor(context, status.level);
    final over = status.level == BudgetLevel.exceeded;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(over ? Icons.error_rounded : Icons.warning_amber_rounded,
              color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              over
                  ? '$name: exceeded by '
                      '${Money.format(-status.remainingMinor, currency)}.'
                  : '$name: ${(status.ratio * 100).round()}% used, '
                      '${Money.format(status.remainingMinor, currency)} left.',
              style: context.text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBudgetRow extends StatelessWidget {
  const _CategoryBudgetRow({
    required this.status,
    required this.category,
    required this.currency,
    required this.onTap,
  });

  final BudgetStatus status;
  final Category? category;
  final CurrencyInfo currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = budgetColor(context, status.level);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            CategoryAvatar(category: category, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(category?.name ?? '-',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleSmall),
                      ),
                      Text('${(status.ratio * 100).round()}%',
                          style:
                              context.text.labelLarge?.copyWith(color: color)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  PennyProgressBar(value: status.ratio, color: color, height: 7),
                  const SizedBox(height: 5),
                  Text(
                    '${Money.format(status.spentMinor, currency)} of '
                    '${Money.format(status.limitMinor, currency)} · '
                    '${status.remainingMinor >= 0 ? '${Money.format(status.remainingMinor, currency)} left' : '${Money.format(-status.remainingMinor, currency)} over'}',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllocationNote extends StatelessWidget {
  const _AllocationNote({required this.overview, required this.currency});
  final BudgetOverview overview;
  final CurrencyInfo currency;

  @override
  Widget build(BuildContext context) {
    final allocated =
        overview.categories.fold<int>(0, (a, s) => a + s.limitMinor);
    final limit = overview.overall!.limitMinor;
    final over = allocated > limit;
    return Text(
      over
          ? 'Category budgets add up to ${Money.format(allocated, currency)}, '
              'more than your ${Money.format(limit, currency)} monthly budget.'
          : '${Money.format(allocated, currency)} of your monthly budget is '
              'allocated to categories.',
      style: context.text.bodySmall?.copyWith(
          color: over ? context.penny.warning : context.penny.textMuted),
    );
  }
}
