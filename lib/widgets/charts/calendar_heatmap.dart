import 'package:flutter/material.dart';

import '../../models/transaction_entry.dart';
import '../../screens/add_transaction/add_transaction_screen.dart';
import '../../theme/theme_ext.dart';
import '../../utils/date_utils.dart';
import '../../utils/money.dart';
import '../transaction_tile.dart';

/// Interactive monthly calendar heatmap visualizing daily spending intensity.
class CalendarHeatmap extends StatelessWidget {
  const CalendarHeatmap({
    super.key,
    required this.month,
    required this.now,
    required this.transactions,
    required this.currency,
  });

  final DateTime month;
  final DateTime now;
  final List<TransactionEntry> transactions;
  final CurrencyInfo currency;

  void _showDayDetails(BuildContext context, int day, int spend,
      List<TransactionEntry> dayTxs) {
    final date = DateTime(month.year, month.month, day);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        builder: (ctx, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateUtilsX.dayMonthYear(date),
                          style: ctx.text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          spend > 0
                              ? 'Spent ${Money.format(spend, currency)} · ${dayTxs.length} transaction${dayTxs.length == 1 ? '' : 's'}'
                              : 'No spending recorded on this day',
                          style: ctx.text.bodySmall?.copyWith(
                            color: spend > 0
                                ? ctx.penny.expense
                                : ctx.penny.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add transaction',
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      AddTransactionScreen.open(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: dayTxs.isEmpty
                  ? Center(
                      child: Text(
                        'No transactions on this day',
                        style: ctx.text.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: dayTxs.length,
                      itemBuilder: (ctx, i) {
                        final t = dayTxs[i];
                        return TransactionTile(
                          entry: t,
                          category: null,
                          amountText: Money.format(t.amountMinor, currency),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            AddTransactionScreen.open(context, existing: t);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtilsX.daysInMonth(month);
    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // 1 = Mon, 7 = Sun
    final leadingBlanks = firstWeekday - 1;

    // Collect daily spend and transactions
    final spendByDay = <int, int>{};
    final txsByDay = <int, List<TransactionEntry>>{};

    for (final t in transactions) {
      if (t.date.year == month.year && t.date.month == month.month) {
        final d = t.date.day;
        txsByDay.putIfAbsent(d, () => []).add(t);
        if (t.isExpense) {
          spendByDay[d] = (spendByDay[d] ?? 0) + t.amountMinor;
        }
      }
    }

    final isCurrentMonth =
        now.year == month.year && now.month == month.month;
    final elapsedDays = isCurrentMonth ? now.day : daysInMonth;
    final totalSpend = spendByDay.values.fold<int>(0, (a, b) => a + b);
    final avgDaily =
        elapsedDays > 0 ? (totalSpend / elapsedDays).round() : 0;

    Color cellColor(int spend) {
      if (spend <= 0) return context.penny.surfaceHigh;
      if (avgDaily <= 0) {
        return context.penny.income.withValues(alpha: 0.25);
      }
      final ratio = spend / avgDaily;
      if (ratio <= 0.6) {
        return const Color(0xFF34D399).withValues(alpha: 0.32);
      } else if (ratio <= 1.2) {
        return const Color(0xFFFBBF24).withValues(alpha: 0.38);
      } else if (ratio <= 2.0) {
        return const Color(0xFFFB923C).withValues(alpha: 0.44);
      } else {
        return const Color(0xFFF43F5E).withValues(alpha: 0.50);
      }
    }

    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final w in weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: context.text.labelSmall?.copyWith(
                      color: context.penny.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.05,
          ),
          itemCount: leadingBlanks + daysInMonth,
          itemBuilder: (context, i) {
            if (i < leadingBlanks) {
              return const SizedBox.shrink();
            }
            final day = i - leadingBlanks + 1;
            final isToday = isCurrentMonth && day == now.day;
            final isFuture = isCurrentMonth && day > now.day;
            final spend = spendByDay[day] ?? 0;
            final dayTxs = txsByDay[day] ?? const [];
            final color = isFuture
                ? context.penny.surfaceHigh.withValues(alpha: 0.4)
                : cellColor(spend);

            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: isFuture
                  ? null
                  : () => _showDayDetails(context, day, spend, dayTxs),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isToday
                        ? context.colors.primary
                        : Colors.transparent,
                    width: isToday ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$day',
                      style: context.text.labelMedium?.copyWith(
                        fontWeight: isToday
                            ? FontWeight.w800
                            : (spend > 0 ? FontWeight.w600 : FontWeight.w400),
                        color: isFuture
                            ? context.penny.textMuted.withValues(alpha: 0.5)
                            : (isToday
                                ? context.colors.primary
                                : context.colors.onSurface),
                      ),
                    ),
                    if (spend > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: spend > avgDaily
                              ? context.penny.expense
                              : context.penny.income,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Less',
                style: context.text.labelSmall?.copyWith(fontSize: 10)),
            const SizedBox(width: 4),
            _LegendSquare(color: context.penny.surfaceHigh),
            const SizedBox(width: 3),
            _LegendSquare(
                color: const Color(0xFF34D399).withValues(alpha: 0.32)),
            const SizedBox(width: 3),
            _LegendSquare(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.38)),
            const SizedBox(width: 3),
            _LegendSquare(
                color: const Color(0xFFFB923C).withValues(alpha: 0.44)),
            const SizedBox(width: 3),
            _LegendSquare(
                color: const Color(0xFFF43F5E).withValues(alpha: 0.50)),
            const SizedBox(width: 4),
            Text('More',
                style: context.text.labelSmall?.copyWith(fontSize: 10)),
          ],
        ),
      ],
    );
  }
}

class _LegendSquare extends StatelessWidget {
  const _LegendSquare({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
