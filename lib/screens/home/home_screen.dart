import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/analytics_service.dart';
import '../../services/budget_service.dart';
import '../../services/demo_data.dart';
import '../../services/reminder_service.dart';
import '../../state/finance_store.dart';
import '../../state/shell_controller.dart';
import '../../theme/theme_ext.dart';
import '../../utils/category_icons.dart';
import '../../utils/date_utils.dart';
import '../../utils/money.dart';
import '../../widgets/charts/bar_chart.dart';
import '../../widgets/charts/donut_chart.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/insight_card.dart';
import '../../widgets/transaction_tile.dart';
import '../../widgets/update_widgets.dart';
import '../add_transaction/add_transaction_screen.dart';
import '../goals/goals_screen.dart';
import '../history/history_screen.dart';
import '../notes/note_editor_screen.dart';
import '../notes/notes_screen.dart';
import '../settings/account_editor_sheet.dart';
import '../settings/manage_accounts_screen.dart';

/// The dashboard: balance, this month, insights, charts, budgets, recent.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    return SafeArea(
      bottom: false,
      child: ResponsiveCenter(
        child: ListView(
          padding: pagePadding(context, top: 12, bottom: 32),
          children: [
            const _Header(),
            const SizedBox(height: 18),
            const UpdateBanner(),
            const _BalanceCard(),
            const SizedBox(height: 16),
            const _AccountsStrip(),
            const SizedBox(height: 16),
            const _NextReminderCard(),
            if (!store.hasTransactions)
              const _WelcomeCard()
            else ...const [
              _MonthCard(),
              SizedBox(height: 24),
              _InsightsStrip(),
              SizedBox(height: 24),
              _WeeklyCard(),
              SizedBox(height: 16),
              _MonthlyCard(),
              SizedBox(height: 16),
              _CategoryCard(),
              SizedBox(height: 16),
              _BudgetCard(),
              SizedBox(height: 16),
              _GoalsHomeCard(),
              SizedBox(height: 16),
              _RecentCard(),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  String _greeting(DateTime now) {
    final h = now.hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: context.penny.primaryGradient),
          ),
          child: const Icon(Icons.savings_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting(store.now), style: context.text.bodySmall),
              Text('PennyWise', style: context.text.titleLarge),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Notes & reminders',
          onPressed: () => NotesScreen.open(context),
          icon: Badge(
            isLabelVisible: store.upcomingReminders.isNotEmpty,
            label: Text('${store.upcomingReminders.length}'),
            backgroundColor: context.penny.accent,
            child: const Icon(Icons.sticky_note_2_rounded),
          ),
        ),
        const SizedBox(width: 4),
        IconButton.filledTonal(
          tooltip: 'All transactions',
          onPressed: () => HistoryScreen.open(context),
          icon: const Icon(Icons.receipt_long_rounded),
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final life = AnalyticsService.lifetime(store.transactions);
    final balance = store.accounts.isNotEmpty
        ? store.totalBalanceMinor
        : (store.settings.startingBalanceMinor + life.netMinor);
    final c = store.currency;
    const white = Colors.white;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: context.penny.heroGradient,
        ),
        boxShadow: [
          BoxShadow(
            color: context.penny.heroGradient[1].withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -50,
            child: _Glow(size: 180, color: white.withValues(alpha: 0.10)),
          ),
          Positioned(
            left: -30,
            bottom: -70,
            child: _Glow(
                size: 160,
                color: context.penny.accent.withValues(alpha: 0.18)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Total balance',
                        style: context.text.bodyMedium
                            ?.copyWith(color: white.withValues(alpha: 0.8))),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(c.code,
                          style: context.text.labelSmall?.copyWith(
                              color: white, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AnimatedAmount(
                    value: balance,
                    format: (v) => Money.format(v, c),
                    style: context.text.displaySmall
                        ?.copyWith(color: white, fontSize: 36),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _HeroStat(
                        icon: Icons.south_west_rounded,
                        label: 'Total income',
                        value: Money.format(life.incomeMinor, c),
                        tint: const Color(0xFF6EE7B7),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _HeroStat(
                        icon: Icons.north_east_rounded,
                        label: 'Total expenses',
                        value: Money.format(life.expenseMinor, c),
                        tint: const Color(0xFFFFB4C2),
                      ),
                    ),
                  ],
                ),
                if (store.settings.startingBalanceMinor != 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Includes starting balance of '
                    '${Money.format(store.settings.startingBalanceMinor, c)}',
                    style: context.text.labelSmall
                        ?.copyWith(color: white.withValues(alpha: 0.7)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountsStrip extends StatelessWidget {
  const _AccountsStrip();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final currency = store.currency;
    final accounts = store.accounts;
    if (accounts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Accounts & Wallets', style: context.text.titleSmall),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () => ManageAccountsScreen.open(context),
              child: const Text('Manage'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: accounts.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              if (i == accounts.length) {
                return Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => showAccountEditor(context),
                    child: Container(
                      width: 56,
                      height: 84,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: context.penny.border,
                        ),
                      ),
                      child: Icon(Icons.add_rounded,
                          color: context.colors.primary),
                    ),
                  ),
                );
              }

              final a = accounts[i];
              final balance = store.accountBalance(a.id!);

              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () =>
                    HistoryScreen.open(context, initialAccountId: a.id),
                child: Container(
                  width: 154,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.penny.surfaceHigh,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: a.isDefault
                          ? a.color.withValues(alpha: 0.5)
                          : context.penny.border,
                      width: a.isDefault ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: a.color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              CategoryIcons.of(a.iconKey),
                              size: 16,
                              color: a.color,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              a.name,
                              style: context.text.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        Money.format(balance, currency),
                        style: context.text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabularFigures,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      );
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: tint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.75))),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: context.text.titleSmall?.copyWith(
                          color: Colors.white, fontFeatures: tabularFigures)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    return PennyCard(
      child: EmptyState(
        icon: Icons.auto_awesome_rounded,
        title: 'Welcome to PennyWise',
        message: 'Add your first expense or income to see your dashboard, '
            'charts and smart insights come alive. Everything stays on '
            'this device.',
        action: Column(
          children: [
            FilledButton.icon(
              onPressed: () => AddTransactionScreen.open(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add a transaction'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                final ok = await confirmAction(
                  context,
                  title: 'Load demo data?',
                  message: 'This adds about two months of sample '
                      'transactions so you can explore the app. You can '
                      'remove it later with Settings > Clear all data.',
                  confirmLabel: 'Load demo',
                );
                if (!ok) return;
                await store.insertMany(DemoData.generate(store.categories,
                    now: store.now));
              },
              child: const Text('Explore with demo data'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final now = store.now;
    final c = store.currency;
    final month = AnalyticsService.summarize(
        store.transactions, DateRange.month(now));
    final prevStart = DateUtilsX.addMonths(DateUtilsX.startOfMonth(now), -1);
    final prevSameSpan = DateRange(
        prevStart,
        DateUtilsX.addDays(prevStart,
            now.day.clamp(1, DateUtilsX.daysInMonth(prevStart)).toInt()));
    final prev =
        AnalyticsService.summarize(store.transactions, prevSameSpan).expenseMinor;
    final overview = store.budgetOverview();
    final overall = overview.overall;

    String? change;
    Color? changeColor;
    if (prev > 0) {
      final pct = ((month.expenseMinor - prev) / prev * 100).round();
      change = pct == 0
          ? 'Same as last month'
          : '${pct > 0 ? '▲' : '▼'} ${pct.abs()}% vs last month';
      changeColor = pct > 0 ? context.penny.expense : context.penny.income;
    }

    return PennyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Spent in ${DateUtilsX.monthYear(now)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall),
              ),
              if (change != null) ...[
                const SizedBox(width: 8),
                Flexible(child: Pill(label: change, color: changeColor)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          AnimatedAmount(
            value: month.expenseMinor,
            format: (v) => Money.format(v, c),
            style: context.text.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Earned ${Money.format(month.incomeMinor, c)} · '
            'Net ${Money.format(month.netMinor, c, signed: true)}',
            style: context.text.bodySmall,
          ),
          if (overall != null) ...[
            const SizedBox(height: 14),
            PennyProgressBar(
              value: overall.ratio,
              color: _levelColor(context, overall.level),
            ),
            const SizedBox(height: 8),
            Text(
              overall.remainingMinor >= 0
                  ? '${Money.format(overall.remainingMinor, c)} left of '
                      '${Money.format(overall.limitMinor, c)} budget'
                  : '${Money.format(-overall.remainingMinor, c)} over your '
                      '${Money.format(overall.limitMinor, c)} budget',
              style: context.text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

Color _levelColor(BuildContext context, BudgetLevel level) => switch (level) {
      BudgetLevel.safe => context.penny.income,
      BudgetLevel.warning => context.penny.warning,
      BudgetLevel.danger => context.penny.expense,
      BudgetLevel.exceeded => context.penny.expense,
    };

class _InsightsStrip extends StatelessWidget {
  const _InsightsStrip();

  @override
  Widget build(BuildContext context) {
    final insights = context.watch<FinanceStore>().insights;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Smart insights',
          subtitle: 'Calculated on your device from your data',
          actionLabel: insights.length > 1 ? 'See all' : null,
          onAction: () => _showAll(context),
        ),
        if (insights.isEmpty)
          PennyCard(
            child: Text(
              'Keep adding transactions - insights appear once there is '
              'enough data to compare.',
              style: context.text.bodySmall,
            ),
          )
        else
          SizedBox(
            height: 168,
            child: LayoutBuilder(builder: (context, c) {
              final cardW =
                  insights.length == 1 ? c.maxWidth : c.maxWidth * 0.82;
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: insights.length > 6 ? 6 : insights.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (_, i) =>
                    InsightCard(insight: insights[i], width: cardW),
              );
            }),
          ),
      ],
    );
  }

  void _showAll(BuildContext context) {
    final insights = context.read<FinanceStore>().insights;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('Smart insights', style: ctx.text.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Rule-based analysis of your own transactions, computed '
              'locally. No AI cloud service is used and no data leaves '
              'your phone.',
              style: ctx.text.bodySmall,
            ),
            const SizedBox(height: 16),
            for (final i in insights) ...[
              InsightCard(insight: i),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final c = store.currency;
    final range = DateRange.lastDays(7, store.now);
    final points =
        AnalyticsService.daily(store.transactions, range, weekdayLabels: true);
    final total = points.fold<int>(0, (a, p) => a + p.expenseMinor);
    return PennyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Last 7 days',
            subtitle: 'Spent ${Money.format(total, c)}',
          ),
          BarChartView(
            labels: [for (final p in points) p.label],
            tooltipLabels: [
              for (final p in points) DateUtilsX.relativeDay(p.start, now: store.now)
            ],
            series: [
              [for (final p in points) p.expenseMinor]
            ],
            colors: [context.colors.primary],
            highlightIndex: points.length - 1,
            formatValue: (v) => Money.format(v, c),
            formatAxis: (v) => Money.compact(v, c),
          ),
        ],
      ),
    );
  }
}

class _MonthlyCard extends StatelessWidget {
  const _MonthlyCard();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final c = store.currency;
    final points = AnalyticsService.monthly(store.transactions, store.now, 6);
    return PennyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Monthly spending',
            subtitle: 'Last 6 months',
            actionLabel: 'Analytics',
            onAction: () =>
                context.read<ShellController>().go(AppTab.analytics),
          ),
          BarChartView(
            labels: [for (final p in points) p.label],
            tooltipLabels: [for (final p in points) DateUtilsX.monthYear(p.start)],
            series: [
              [for (final p in points) p.expenseMinor]
            ],
            colors: [context.penny.accent],
            highlightIndex: points.length - 1,
            formatValue: (v) => Money.format(v, c),
            formatAxis: (v) => Money.compact(v, c),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final c = store.currency;
    final totals = AnalyticsService.categoryTotals(
        store.transactions, DateRange.month(store.now));
    final spent = totals.fold<int>(0, (a, t) => a + t.totalMinor);
    final top = totals.take(5).toList();
    final rest = totals.skip(5).fold<int>(0, (a, t) => a + t.totalMinor);

    return PennyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
              title: 'Spending by category', subtitle: 'This month'),
          if (totals.isEmpty)
            const EmptyState(
              compact: true,
              icon: Icons.donut_large_rounded,
              title: 'No expenses this month yet',
            )
          else
            LayoutBuilder(builder: (context, constraints) {
              final narrow = constraints.maxWidth < 330;
              final donut = DonutChart(
                size: narrow ? 120 : 136,
                thickness: 15,
                segments: [
                  for (final t in top)
                    DonutSegment(t.totalMinor.toDouble(),
                        store.categoryById(t.categoryId)?.color ?? Colors.grey),
                  if (rest > 0)
                    DonutSegment(rest.toDouble(), context.penny.textMuted),
                ],
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Total', style: context.text.labelSmall),
                    Text(Money.compact(spent, c),
                        style: context.text.titleMedium),
                  ],
                ),
              );
              final legend = Column(
                children: [
                  for (final t in top)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: store.categoryById(t.categoryId)?.color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              store.categoryById(t.categoryId)?.name ?? '-',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall
                                  ?.copyWith(color: context.colors.onSurface),
                            ),
                          ),
                          Text('${(t.share * 100).round()}%',
                              style: context.text.labelMedium?.copyWith(
                                  fontFeatures: tabularFigures)),
                        ],
                      ),
                    ),
                ],
              );
              return Row(
                children: [
                  donut,
                  const SizedBox(width: 18),
                  Expanded(child: legend),
                ],
              );
            }),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final c = store.currency;
    final o = store.budgetOverview();
    final shell = Provider.of<ShellController>(context, listen: false);
    final rows = [
      if (o.overall != null) ('Monthly budget', o.overall!),
      for (final s in o.categories.take(3))
        (store.categoryById(s.categoryId!)?.name ?? '-', s),
    ];

    return PennyCard(
      onTap: () => shell.go(AppTab.budget),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Budgets',
            subtitle: rows.isEmpty
                ? null
                : '${o.daysLeft} day${o.daysLeft == 1 ? '' : 's'} left this month',
            actionLabel: rows.isEmpty ? 'Set up' : 'Manage',
            onAction: () => shell.go(AppTab.budget),
          ),
          if (rows.isEmpty)
            Text(
              'Set a monthly budget to get pace tracking and early '
              'warnings when you approach your limit.',
              style: context.text.bodySmall,
            )
          else
            for (final (name, s) in rows) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall),
                  ),
                  Text(
                    '${Money.format(s.spentMinor, c)} / '
                    '${Money.format(s.limitMinor, c)}',
                    style: context.text.bodySmall
                        ?.copyWith(fontFeatures: tabularFigures),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              PennyProgressBar(
                  value: s.ratio, color: _levelColor(context, s.level)),
              const SizedBox(height: 14),
            ],
        ],
      ),
    );
  }
}

class _GoalsHomeCard extends StatelessWidget {
  const _GoalsHomeCard();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final goals = store.goals.where((g) => !g.isAchieved).take(2).toList();
    if (goals.isEmpty) return const SizedBox.shrink();

    final currency = store.currency;
    return PennyCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Column(
        children: [
          SectionHeader(
            title: 'Savings goals',
            actionLabel: 'See all',
            onAction: () => GoalsScreen.open(context),
          ),
          for (final g in goals) ...[
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => GoalsScreen.open(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: g.color.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            CategoryIcons.of(g.iconKey),
                            size: 16,
                            color: g.color,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            g.name,
                            style: context.text.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${g.percentage}%',
                          style: context.text.labelMedium?.copyWith(
                            color: g.color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: g.progressRatio,
                        minHeight: 6,
                        backgroundColor: context.penny.border,
                        valueColor: AlwaysStoppedAnimation<Color>(g.color),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${Money.format(g.savedMinor, currency)} of ${Money.format(g.targetMinor, currency)}',
                          style: context.text.bodySmall?.copyWith(fontSize: 11),
                        ),
                        Text(
                          '${Money.format(g.remainingMinor, currency)} left',
                          style: context.text.bodySmall?.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final recent = store.transactions.take(5).toList();
    return PennyCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Column(
        children: [
          SectionHeader(
            title: 'Recent transactions',
            actionLabel: 'See all',
            onAction: () => HistoryScreen.open(context),
          ),
          for (final t in recent)
            TransactionTile(
              entry: t,
              category: store.categoryById(t.categoryId),
              accountName: store.accountById(t.accountId)?.name,
              toAccountName: store.accountById(t.toAccountId)?.name,
              amountText: store.format(t.amountMinor),
              showDate: true,
              dateText: DateUtilsX.relativeDay(t.date, now: store.now),
              onTap: () => AddTransactionScreen.open(context, existing: t),
            ),
        ],
      ),
    );
  }
}

/// Shows the next upcoming note reminder, if there is one.
class _NextReminderCard extends StatelessWidget {
  const _NextReminderCard();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final upcoming = store.upcomingReminders;
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final next = upcoming.first;
    final accent = context.penny.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: PennyCard(
        onTap: () => NoteEditorScreen.open(context, existing: next),
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.alarm_rounded, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(next.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${reminderLabel(next.reminderAt!, store.now)}'
                    '${upcoming.length > 1 ? ' · +${upcoming.length - 1} more' : ''}',
                    style: context.text.bodySmall?.copyWith(color: accent),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => NotesScreen.open(context),
              child: const Text('All notes'),
            ),
          ],
        ),
      ),
    );
  }
}
