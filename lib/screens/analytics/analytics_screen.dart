import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/transaction_entry.dart';
import '../../services/analytics_service.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/date_utils.dart';
import '../../utils/money.dart';
import '../../widgets/charts/bar_chart.dart';
import '../../widgets/charts/donut_chart.dart';
import '../../widgets/charts/line_chart.dart';
import '../../widgets/common.dart';
import '../../widgets/segmented.dart';
import '../../widgets/transaction_tile.dart';
import '../add_transaction/add_transaction_screen.dart';

enum _Period {
  week('Week'),
  month('Month'),
  year('Year');

  const _Period(this.label);
  final String label;
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  _Period _period = _Period.month;
  DateTime? _anchor;

  DateRange _rangeFor(DateTime anchor) => switch (_period) {
        _Period.week => DateRange.week(anchor),
        _Period.month => DateRange.month(anchor),
        _Period.year => DateRange.year(anchor),
      };

  DateTime _shift(DateTime anchor, int dir) => switch (_period) {
        _Period.week => DateUtilsX.addDays(anchor, 7 * dir),
        _Period.month => DateUtilsX.addMonths(anchor, dir),
        _Period.year => DateTime(anchor.year + dir, anchor.month),
      };

  String _label(DateRange r) => switch (_period) {
        _Period.week =>
          '${DateUtilsX.dayMonth(r.start)} – ${DateUtilsX.dayMonth(DateUtilsX.addDays(r.end, -1))}',
        _Period.month => DateUtilsX.monthYear(r.start),
        _Period.year => '${r.start.year}',
      };

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final now = store.now;
    final anchor = _anchor ?? now;
    final range = _rangeFor(anchor);
    final isCurrent = range.contains(now);
    final c = store.currency;
    final txs = store.transactions;
    final summary = AnalyticsService.summarize(txs, range);

    return SafeArea(
      bottom: false,
      child: ResponsiveCenter(
        child: ListView(
          padding: pagePadding(context, top: 12, bottom: 32),
          children: [
            Text('Analytics', style: context.text.headlineSmall),
            const SizedBox(height: 14),
            PennySegmented<_Period>(
              values: _Period.values,
              selected: _period,
              labelOf: (p) => p.label,
              onChanged: (p) => setState(() {
                _period = p;
                _anchor = null;
              }),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous',
                  onPressed: () =>
                      setState(() => _anchor = _shift(anchor, -1)),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    _label(range),
                    textAlign: TextAlign.center,
                    style: context.text.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Next',
                  onPressed: isCurrent
                      ? null
                      : () => setState(() {
                            final next = _shift(anchor, 1);
                            _anchor = _rangeFor(next).contains(now) ? null : next;
                          }),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _SummaryGrid(
              items: [
                ('Spent', Money.format(summary.expenseMinor, c),
                    context.penny.expense, Icons.north_east_rounded),
                ('Earned', Money.format(summary.incomeMinor, c),
                    context.penny.income, Icons.south_west_rounded),
                ('Net', Money.format(summary.netMinor, c, signed: true),
                    context.colors.primary, Icons.account_balance_rounded),
                (
                  'Avg / day',
                  Money.format(
                      AnalyticsService.averageDailySpend(txs, range, now), c),
                  context.penny.accent,
                  Icons.calendar_today_rounded
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (summary.count == 0)
              PennyCard(
                child: EmptyState(
                  icon: Icons.insights_rounded,
                  title: 'No transactions in this period',
                  message: store.hasTransactions
                      ? 'Use the arrows to look at another period.'
                      : 'Add a few transactions to unlock analytics.',
                ),
              )
            else ...[
              _TrendCard(period: _period, range: range, now: now),
              const SizedBox(height: 16),
              _IncomeVsExpenseCard(anchor: range.start, now: now),
              if (_period == _Period.month) ...[
                const SizedBox(height: 16),
                _CumulativeCard(month: range.start, now: now),
              ],
              if (_period != _Period.week) ...[
                const SizedBox(height: 16),
                _WeeklyCard(
                    end: isCurrent ? now : DateUtilsX.addDays(range.end, -1)),
              ],
              const SizedBox(height: 16),
              _CategoryBreakdown(range: range, type: TransactionType.expense),
              const SizedBox(height: 16),
              _TopExpenses(range: range),
              if (summary.incomeMinor > 0) ...[
                const SizedBox(height: 16),
                _CategoryBreakdown(range: range, type: TransactionType.income),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.items});

  final List<(String, String, Color, IconData)> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 12.0;
      final w = (c.maxWidth - gap) / 2;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final (label, value, color, icon) in items)
            SizedBox(
              width: w,
              child: PennyCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 16, color: color),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value,
                          style: context.text.titleMedium
                              ?.copyWith(fontFeatures: tabularFigures)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard(
      {required this.period, required this.range, required this.now});

  final _Period period;
  final DateRange range;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final c = store.currency;
    final List<SeriesPoint> points;
    final List<String> tooltips;
    final int highlight;
    final String subtitle;
    switch (period) {
      case _Period.week:
        points = AnalyticsService.daily(store.transactions, range,
            weekdayLabels: true);
        tooltips = [for (final p in points) DateUtilsX.fullDay(p.start)];
        highlight = points.indexWhere((p) => DateUtilsX.isSameDay(p.start, now));
        subtitle = 'Daily spending';
      case _Period.month:
        points = AnalyticsService.daily(store.transactions, range);
        tooltips = [for (final p in points) DateUtilsX.fullDay(p.start)];
        highlight = points.indexWhere((p) => DateUtilsX.isSameDay(p.start, now));
        subtitle = 'Daily spending';
      case _Period.year:
        points = AnalyticsService.monthly(
            store.transactions, DateTime(range.start.year, 12), 12);
        tooltips = [for (final p in points) DateUtilsX.monthYear(p.start)];
        highlight =
            points.indexWhere((p) => DateUtilsX.isSameMonth(p.start, now));
        subtitle = 'Monthly spending';
    }
    final values = [for (final p in points) p.expenseMinor];
    final active = values.where((v) => v > 0).length;
    final peak = values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);

    return PennyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Spending trend',
            subtitle: '$subtitle · peak ${Money.format(peak, c)}'
                ' · $active active ${period == _Period.year ? 'months' : 'days'}',
          ),
          BarChartView(
            labels: [for (final p in points) p.label],
            tooltipLabels: tooltips,
            series: [values],
            colors: [context.colors.primary],
            highlightIndex: highlight < 0 ? null : highlight,
            formatValue: (v) => Money.format(v, c),
            formatAxis: (v) => Money.compact(v, c),
            height: 200,
          ),
        ],
      ),
    );
  }
}

class _IncomeVsExpenseCard extends StatelessWidget {
  const _IncomeVsExpenseCard({required this.anchor, required this.now});

  final DateTime anchor;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final c = store.currency;
    final points = AnalyticsService.monthly(store.transactions, anchor, 6);
    final income = context.penny.income;
    final expense = context.penny.expense;
    return PennyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Income vs expenses',
            subtitle: '6 months to ${DateUtilsX.monthYear(anchor)}',
          ),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _Legend(color: income, label: 'Income'),
              _Legend(color: expense, label: 'Expenses'),
            ],
          ),
          const SizedBox(height: 12),
          BarChartView(
            labels: [for (final p in points) p.label],
            tooltipLabels: [for (final p in points) DateUtilsX.monthYear(p.start)],
            series: [
              [for (final p in points) p.incomeMinor],
              [for (final p in points) p.expenseMinor],
            ],
            seriesNames: const ['Income', 'Expenses'],
            colors: [income, expense],
            formatValue: (v) => Money.format(v, c),
            formatAxis: (v) => Money.compact(v, c),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.dashed = false});
  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dashed ? 14 : 10,
            height: dashed ? 3 : 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: context.text.bodySmall),
        ],
      );
}

class _CumulativeCard extends StatelessWidget {
  const _CumulativeCard({required this.month, required this.now});

  final DateTime month;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final c = store.currency;
    final prevMonth = DateUtilsX.addMonths(month, -1);
    final current = AnalyticsService.cumulativeMonthSpend(
        store.transactions, month,
        upTo: now);
    final previous =
        AnalyticsService.cumulativeMonthSpend(store.transactions, prevMonth);
    final days = DateUtilsX.daysInMonth(month);
    final prevAligned = <int?>[
      for (var i = 0; i < days; i++)
        i < previous.length ? previous[i] : previous.last,
    ];
    return PennyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Cumulative spending',
            subtitle: 'How this month compares to last month, day by day',
          ),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _Legend(
                  color: context.colors.primary,
                  label: DateUtilsX.monthShort(month)),
              _Legend(
                  color: context.penny.textMuted,
                  label: DateUtilsX.monthShort(prevMonth),
                  dashed: true),
            ],
          ),
          const SizedBox(height: 12),
          LineChartView(
            xLabels: [for (var i = 1; i <= days; i++) '$i'],
            tooltipLabels: [
              for (var i = 1; i <= days; i++)
                'Day $i'
            ],
            series: [
              LineSeries(
                name: DateUtilsX.monthShort(month),
                values: current,
                color: context.colors.primary,
                filled: true,
              ),
              LineSeries(
                name: DateUtilsX.monthShort(prevMonth),
                values: prevAligned,
                color: context.penny.textMuted,
                dashed: true,
              ),
            ],
            formatValue: (v) => Money.format(v, c),
            formatAxis: (v) => Money.compact(v, c),
          ),
        ],
      ),
    );
  }
}

class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard({required this.end});

  final DateTime end;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final c = store.currency;
    final points = AnalyticsService.weekly(store.transactions, end, 8);
    return PennyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
              title: 'Weekly spending', subtitle: 'Last 8 weeks (Mon–Sun)'),
          BarChartView(
            labels: [for (final p in points) p.label],
            tooltipLabels: [
              for (final p in points) 'Week of ${DateUtilsX.dayMonth(p.start)}'
            ],
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

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.range, required this.type});

  final DateRange range;
  final TransactionType type;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final c = store.currency;
    final totals = AnalyticsService.categoryTotals(store.transactions, range,
        type: type);
    if (totals.isEmpty) return const SizedBox.shrink();
    final sum = totals.fold<int>(0, (a, t) => a + t.totalMinor);
    final isExpense = type == TransactionType.expense;

    return PennyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: isExpense ? 'Spending by category' : 'Income by source',
            subtitle: isExpense
                ? 'Highest spending categories first'
                : 'Where your money came from',
          ),
          Center(
            child: DonutChart(
              size: 170,
              thickness: 18,
              segments: [
                for (final t in totals)
                  DonutSegment(t.totalMinor.toDouble(),
                      store.categoryById(t.categoryId)?.color ?? Colors.grey),
              ],
              center: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isExpense ? 'Spent' : 'Earned',
                      style: context.text.labelSmall),
                  const SizedBox(height: 2),
                  Text(Money.compact(sum, c), style: context.text.titleLarge),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < totals.length; i++) ...[
            _CategoryRow(
              rank: i + 1,
              categoryId: totals[i].categoryId,
              total: Money.format(totals[i].totalMinor, c),
              share: totals[i].share,
              count: totals[i].count,
            ),
            if (i < totals.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.rank,
    required this.categoryId,
    required this.total,
    required this.share,
    required this.count,
  });

  final int rank;
  final int categoryId;
  final String total;
  final double share;
  final int count;

  @override
  Widget build(BuildContext context) {
    final cat = context.watch<FinanceStore>().categoryById(categoryId);
    return Row(
      children: [
        CategoryAvatar(category: cat, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(cat?.name ?? 'Unknown',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall),
                  ),
                  Text(total,
                      style: context.text.titleSmall
                          ?.copyWith(fontFeatures: tabularFigures)),
                ],
              ),
              const SizedBox(height: 6),
              PennyProgressBar(
                  value: share,
                  height: 6,
                  color: cat?.color ?? context.colors.primary),
              const SizedBox(height: 4),
              Text(
                '${(share * 100).toStringAsFixed(share < 0.1 ? 1 : 0)}% · '
                '$count transaction${count == 1 ? '' : 's'}',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopExpenses extends StatelessWidget {
  const _TopExpenses({required this.range});

  final DateRange range;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final top = AnalyticsService.topExpenses(store.transactions, range);
    if (top.isEmpty) return const SizedBox.shrink();
    return PennyCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Column(
        children: [
          const SectionHeader(title: 'Largest expenses'),
          for (final t in top)
            TransactionTile(
              entry: t,
              category: store.categoryById(t.categoryId),
              amountText: store.format(t.amountMinor),
              showDate: true,
              dateText: DateUtilsX.dayMonth(t.date),
              onTap: () => AddTransactionScreen.open(context, existing: t),
            ),
        ],
      ),
    );
  }
}
