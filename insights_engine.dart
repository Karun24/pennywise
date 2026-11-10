import 'dart:math' as math;

import '../../database/default_categories.dart';
import '../../models/category.dart';
import '../../models/transaction_entry.dart';
import '../../utils/date_utils.dart';
import '../../utils/money.dart';
import '../analytics_service.dart';
import '../budget_service.dart';

enum InsightTone { positive, info, warning, alert }

enum InsightTopic { trend, category, average, budget, anomaly, savings, habit }

/// A single, data-backed observation. Every number in [message] is computed
/// from the user's own transactions; nothing is invented.
class Insight {
  const Insight({
    required this.id,
    required this.title,
    required this.message,
    required this.tone,
    required this.topic,
    this.priority = 0,
    this.relatedTransactionId,
  });

  final String id;
  final String title;
  final String message;
  final InsightTone tone;
  final InsightTopic topic;

  /// Higher shows first within the same tone.
  final int priority;
  final int? relatedTransactionId;
}

/// Rule-based insights engine. Runs locally with simple statistics.
class InsightsEngine {
  InsightsEngine({
    required this.transactions,
    required this.categories,
    required this.budgets,
    required this.monthlyBudgetMinor,
    required this.currency,
    required this.now,
  });

  final List<TransactionEntry> transactions;
  final List<Category> categories;
  final List<CategoryBudget> budgets;
  final int? monthlyBudgetMinor;
  final CurrencyInfo currency;
  final DateTime now;

  String _m(int minor) => Money.format(minor, currency);

  String _name(int categoryId) {
    for (final c in categories) {
      if (c.id == categoryId) return c.name;
    }
    return 'Uncategorised';
  }

  static String _pct(double ratio) => '${(ratio * 100).round()}%';

  List<Insight> generate() {
    if (transactions.isEmpty) return const [];
    final out = <Insight>[
      ..._budgetPace(),
      ..._categoryBudgets(),
      ..._monthTrend(),
      ..._weekCategoryChange(),
      ..._topCategory(),
      ..._averageDaily(),
      ..._savingsRate(),
      ..._anomalies(),
      ..._smallFrequentSpends(),
      ..._noSpendDays(),
    ];
    int toneRank(InsightTone t) => switch (t) {
          InsightTone.alert => 3,
          InsightTone.warning => 2,
          InsightTone.positive => 1,
          InsightTone.info => 0,
        };
    out.sort((a, b) {
      final t = toneRank(b.tone).compareTo(toneRank(a.tone));
      return t != 0 ? t : b.priority.compareTo(a.priority);
    });
    return out;
  }

  DateRange get _month => DateRange.month(now);

  /// Same span of days in the previous month, for fair comparison.
  DateRange get _lastMonthToDate {
    final prev = DateUtilsX.addMonths(DateUtilsX.startOfMonth(now), -1);
    final days = math.min(now.day, DateUtilsX.daysInMonth(prev));
    return DateRange(prev, DateUtilsX.addDays(prev, days));
  }

  DateRange get _monthToDate => DateRange(
      DateUtilsX.startOfMonth(now), DateUtilsX.addDays(DateUtilsX.dateOnly(now), 1));

  // ------------------------------------------------------------------ rules

  Iterable<Insight> _budgetPace() sync* {
    final budget = monthlyBudgetMinor;
    if (budget == null) return;
    final overview = BudgetService.compute(
      transactions: transactions,
      budgets: budgets,
      monthlyBudgetMinor: budget,
      now: now,
    );
    final o = overview.overall!;
    if (o.spentMinor == 0) return;
    if (o.ratio > 1) {
      yield Insight(
        id: 'budget-exceeded',
        title: 'Monthly budget exceeded',
        message: 'You have spent ${_m(o.spentMinor)}, which is '
            '${_m(-o.remainingMinor)} over your ${_m(budget)} budget.',
        tone: InsightTone.alert,
        topic: InsightTopic.budget,
        priority: 100,
      );
      return;
    }
    final projected = overview.projectedMinor;
    final usedText = 'You have used ${_pct(o.ratio)} of your monthly budget '
        'with ${_pct(overview.monthElapsed)} of the month gone.';
    if (projected > budget && overview.dayOfMonth >= 3) {
      yield Insight(
        id: 'budget-pace',
        title: 'On pace to overspend',
        message: '$usedText At this pace you will spend about '
            '${_m(projected)} this month, ${_m(projected - budget)} over budget.',
        tone: o.ratio >= BudgetStatus.warningAt
            ? InsightTone.alert
            : InsightTone.warning,
        topic: InsightTopic.budget,
        priority: 90,
      );
    } else if (o.ratio >= BudgetStatus.warningAt) {
      yield Insight(
        id: 'budget-usage',
        title: '${_pct(o.ratio)} of budget used',
        message: '$usedText ${_m(o.remainingMinor)} left for '
            '${overview.daysLeft} day${overview.daysLeft == 1 ? '' : 's'}.',
        tone: InsightTone.warning,
        topic: InsightTopic.budget,
        priority: 80,
      );
    } else {
      yield Insight(
        id: 'budget-ok',
        title: 'Budget on track',
        message: '$usedText You can spend about '
            '${_m(overview.safeDailyMinor ?? 0)} a day and stay within budget.',
        tone: InsightTone.positive,
        topic: InsightTopic.budget,
        priority: 50,
      );
    }
  }

  Iterable<Insight> _categoryBudgets() sync* {
    if (budgets.isEmpty) return;
    final overview = BudgetService.compute(
      transactions: transactions,
      budgets: budgets,
      monthlyBudgetMinor: monthlyBudgetMinor,
      now: now,
    );
    var shown = 0;
    for (final s in overview.categories) {
      if (shown >= 2) break;
      if (s.level == BudgetLevel.safe) continue;
      shown++;
      final name = _name(s.categoryId!);
      final over = s.ratio > 1;
      yield Insight(
        id: 'cat-budget-${s.categoryId}',
        title: over ? '$name budget exceeded' : '$name budget ${_pct(s.ratio)} used',
        message: over
            ? 'You have spent ${_m(s.spentMinor)} on $name, '
                '${_m(-s.remainingMinor)} over its ${_m(s.limitMinor)} limit.'
            : 'You have spent ${_m(s.spentMinor)} of ${_m(s.limitMinor)} on '
                '$name. ${_m(s.remainingMinor)} remaining this month.',
        tone: over ? InsightTone.alert : InsightTone.warning,
        topic: InsightTopic.budget,
        priority: over ? 85 : 70,
      );
    }
  }

  Iterable<Insight> _monthTrend() sync* {
    final thisMonth =
        AnalyticsService.summarize(transactions, _monthToDate).expenseMinor;
    final lastMonth =
        AnalyticsService.summarize(transactions, _lastMonthToDate).expenseMinor;
    if (thisMonth == 0 || lastMonth == 0) return;
    final change = (thisMonth - lastMonth) / lastMonth;
    final span = 'by day ${now.day}';
    if (change >= 0.15) {
      yield Insight(
        id: 'month-trend-up',
        title: 'Spending up ${_pct(change)}',
        message: 'You have spent ${_m(thisMonth)} this month vs '
            '${_m(lastMonth)} $span last month.',
        tone: InsightTone.warning,
        topic: InsightTopic.trend,
        priority: 60,
      );
    } else if (change <= -0.10) {
      yield Insight(
        id: 'month-trend-down',
        title: 'Spending down ${_pct(-change)}',
        message: 'Nice! ${_m(thisMonth)} spent so far vs ${_m(lastMonth)} '
            '$span last month.',
        tone: InsightTone.positive,
        topic: InsightTopic.trend,
        priority: 60,
      );
    } else {
      yield Insight(
        id: 'month-trend-flat',
        title: 'Steady spending',
        message: 'You have spent ${_m(thisMonth)} this month, close to '
            '${_m(lastMonth)} $span last month.',
        tone: InsightTone.info,
        topic: InsightTopic.trend,
        priority: 20,
      );
    }
  }

  Iterable<Insight> _weekCategoryChange() sync* {
    final weekStart = DateUtilsX.startOfWeek(now);
    final elapsed = DateUtilsX.dateOnly(now).difference(weekStart).inHours ~/ 24 + 1;
    final thisWeek = DateRange(weekStart, DateUtilsX.addDays(weekStart, elapsed));
    final lastStart = DateUtilsX.addDays(weekStart, -7);
    final lastWeek = DateRange(lastStart, DateUtilsX.addDays(lastStart, elapsed));

    final thisTotals = {
      for (final c in AnalyticsService.categoryTotals(transactions, thisWeek))
        c.categoryId: c.totalMinor,
    };
    final lastTotals = {
      for (final c in AnalyticsService.categoryTotals(transactions, lastWeek))
        c.categoryId: c.totalMinor,
    };
    final lastWeekTotal = lastTotals.values.fold<int>(0, (a, b) => a + b);
    if (lastWeekTotal == 0) return;

    int? bestId;
    var bestDiff = 0;
    thisTotals.forEach((id, amount) {
      final prev = lastTotals[id] ?? 0;
      if (prev == 0) return;
      final diff = amount - prev;
      final meaningful = diff >= prev * 0.25 && diff >= lastWeekTotal * 0.1;
      if (meaningful && diff > bestDiff) {
        bestDiff = diff;
        bestId = id;
      }
    });
    final dayText = elapsed == 7 ? 'last week' : 'the same days last week';
    if (bestId != null) {
      final id = bestId!;
      yield Insight(
        id: 'week-cat-up-$id',
        title: 'More on ${_name(id)} this week',
        message: 'You spent ${_m(thisTotals[id]!)} on ${_name(id)} this week, '
            '${_m(bestDiff)} more than $dayText.',
        tone: InsightTone.warning,
        topic: InsightTopic.trend,
        priority: 55,
      );
    }

    final thisWeekTotal = thisTotals.values.fold<int>(0, (a, b) => a + b);
    if (thisWeekTotal > 0 && thisWeekTotal <= lastWeekTotal * 0.8) {
      yield Insight(
        id: 'week-down',
        title: 'A lighter week',
        message: 'You have spent ${_m(thisWeekTotal)} this week, '
            '${_m(lastWeekTotal - thisWeekTotal)} less than $dayText.',
        tone: InsightTone.positive,
        topic: InsightTopic.trend,
        priority: 40,
      );
    }
  }

  Iterable<Insight> _topCategory() sync* {
    final totals = AnalyticsService.categoryTotals(transactions, _month);
    if (totals.isEmpty) return;
    final top = totals.first;
    if (totals.length == 1 && top.count < 2) return;
    yield Insight(
      id: 'top-category',
      title: '${_name(top.categoryId)} leads',
      message: '${_name(top.categoryId)} is your highest expense category this '
          'month: ${_m(top.totalMinor)} (${_pct(top.share)} of spending).',
      tone: InsightTone.info,
      topic: InsightTopic.category,
      priority: 45,
    );
  }

  Iterable<Insight> _averageDaily() sync* {
    final avg = AnalyticsService.averageDailySpend(transactions, _month, now);
    if (avg == 0) return;
    final prevMonth = DateUtilsX.addMonths(DateUtilsX.startOfMonth(now), -1);
    final prevRange = DateRange.month(prevMonth);
    final prevSpent =
        AnalyticsService.summarize(transactions, prevRange).expenseMinor;
    final prevAvg = prevSpent == 0
        ? 0
        : (prevSpent / DateUtilsX.daysInMonth(prevMonth)).round();
    yield Insight(
      id: 'avg-daily',
      title: 'Average ${_m(avg)} a day',
      message: prevAvg == 0
          ? 'Your average daily spending this month is ${_m(avg)}.'
          : 'Your average daily spending this month is ${_m(avg)} '
              '(last month: ${_m(prevAvg)} a day).',
      tone: InsightTone.info,
      topic: InsightTopic.average,
      priority: 30,
    );
  }

  Iterable<Insight> _savingsRate() sync* {
    final s = AnalyticsService.summarize(transactions, _month);
    if (s.incomeMinor == 0) return;
    final rate = s.netMinor / s.incomeMinor;
    if (rate < 0) {
      yield Insight(
        id: 'savings-negative',
        title: 'Spending more than earning',
        message: 'This month you have spent ${_m(-s.netMinor)} more than '
            'you earned (${_m(s.incomeMinor)} in, ${_m(s.expenseMinor)} out).',
        tone: InsightTone.alert,
        topic: InsightTopic.savings,
        priority: 75,
      );
    } else if (rate >= 0.2) {
      yield Insight(
        id: 'savings-good',
        title: 'Saving ${_pct(rate)} of income',
        message: 'You have kept ${_m(s.netMinor)} of the ${_m(s.incomeMinor)} '
            'you earned this month. Keep it up!',
        tone: InsightTone.positive,
        topic: InsightTopic.savings,
        priority: 50,
      );
    } else {
      yield Insight(
        id: 'savings-low',
        title: 'Saving ${_pct(rate)} of income',
        message: 'You have kept ${_m(s.netMinor)} of the ${_m(s.incomeMinor)} '
            'earned this month. A common target is 20% or more.',
        tone: InsightTone.info,
        topic: InsightTopic.savings,
        priority: 35,
      );
    }
  }

  /// Flags recent expenses far above the user's typical amount for that
  /// category (median-based, robust to outliers).
  Iterable<Insight> _anomalies() sync* {
    final recentStart = DateUtilsX.addDays(DateUtilsX.dateOnly(now), -13);
    final byCategory = <int, List<TransactionEntry>>{};
    for (final t in transactions) {
      if (t.isExpense) byCategory.putIfAbsent(t.categoryId, () => []).add(t);
    }
    final found = <Insight>[];
    byCategory.forEach((categoryId, list) {
      if (list.length < 6) return;
      for (final t in list) {
        if (t.date.isBefore(recentStart)) continue;
        final others = list
            .where((o) => o.id != t.id)
            .map((o) => o.amountMinor)
            .toList()
          ..sort();
        final median = _median(others);
        if (median <= 0) continue;
        final mean = others.reduce((a, b) => a + b) / others.length;
        final variance = others
                .map((v) => (v - mean) * (v - mean))
                .reduce((a, b) => a + b) /
            others.length;
        final std = math.sqrt(variance);
        if (t.amountMinor >= median * 3 && t.amountMinor >= mean + 2 * std) {
          found.add(Insight(
            id: 'anomaly-${t.id}',
            title: 'Unusually high: ${_name(categoryId)}',
            message: '${_m(t.amountMinor)} on ${DateUtilsX.dayMonth(t.date)}'
                '${t.note.isEmpty ? '' : ' (${t.note})'} is about '
                '${(t.amountMinor / median).toStringAsFixed(1)}x your typical '
                '${_name(categoryId)} spend of ${_m(median.round())}.',
            tone: InsightTone.warning,
            topic: InsightTopic.anomaly,
            priority: 65,
            relatedTransactionId: t.id,
          ));
        }
      }
    });
    found.sort((a, b) => b.priority.compareTo(a.priority));
    yield* found.take(2);
  }

  static double _median(List<int> sorted) {
    if (sorted.isEmpty) return 0;
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid].toDouble()
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Many small purchases in discretionary categories add up.
  Iterable<Insight> _smallFrequentSpends() sync* {
    const discretionary = {
      DefaultCategoryNames.food,
      DefaultCategoryNames.shopping,
      DefaultCategoryNames.entertainment,
    };
    final range = DateRange.lastDays(30, now);
    final recent = transactions
        .where((t) => t.isExpense && range.contains(t.date))
        .toList();
    if (recent.length < 8) return;
    final amounts = recent.map((t) => t.amountMinor).toList()..sort();
    final smallLimit = _median(amounts);
    final counts = <int, int>{};
    final sums = <int, int>{};
    for (final t in recent) {
      if (t.amountMinor > smallLimit) continue;
      if (!discretionary.contains(_name(t.categoryId))) continue;
      counts[t.categoryId] = (counts[t.categoryId] ?? 0) + 1;
      sums[t.categoryId] = (sums[t.categoryId] ?? 0) + t.amountMinor;
    }
    if (counts.isEmpty) return;
    final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (best.value < 6) return;
    final total = sums[best.key]!;
    yield Insight(
      id: 'small-spends-${best.key}',
      title: 'Small ${_name(best.key)} spends add up',
      message: 'You made ${best.value} small ${_name(best.key)} purchases '
          'totalling ${_m(total)} in the last 30 days. Halving them would '
          'save about ${_m(total ~/ 2)} a month.',
      tone: InsightTone.info,
      topic: InsightTopic.habit,
      priority: 40,
    );
  }

  Iterable<Insight> _noSpendDays() sync* {
    if (now.day < 5) return;
    final days = <int>{};
    for (final t in transactions) {
      if (t.isExpense && _monthToDate.contains(t.date)) days.add(t.date.day);
    }
    if (days.isEmpty) return;
    final noSpend = now.day - days.length;
    if (noSpend >= 3) {
      yield Insight(
        id: 'no-spend-days',
        title: '$noSpend no-spend days',
        message: 'You did not spend anything on $noSpend of the ${now.day} '
            'days so far this month.',
        tone: InsightTone.positive,
        topic: InsightTopic.habit,
        priority: 25,
      );
    }
  }
}
