import '../models/transaction_entry.dart';
import '../utils/date_utils.dart';

/// Totals for a period.
class PeriodSummary {
  const PeriodSummary({
    required this.incomeMinor,
    required this.expenseMinor,
    required this.count,
  });

  final int incomeMinor;
  final int expenseMinor;
  final int count;

  int get netMinor => incomeMinor - expenseMinor;

  static const empty = PeriodSummary(incomeMinor: 0, expenseMinor: 0, count: 0);
}

/// Total for one category within a period.
class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.totalMinor,
    required this.count,
    required this.share,
  });

  final int categoryId;
  final int totalMinor;
  final int count;

  /// 0..1 share of the period total.
  final double share;
}

/// One bucket on a time-series chart.
class SeriesPoint {
  const SeriesPoint({
    required this.start,
    required this.label,
    this.expenseMinor = 0,
    this.incomeMinor = 0,
  });

  final DateTime start;
  final String label;
  final int expenseMinor;
  final int incomeMinor;
}

/// Pure functions that aggregate transactions. No Flutter, no I/O, so they
/// are cheap to unit test and safe to call from build methods.
class AnalyticsService {
  AnalyticsService._();

  static Iterable<TransactionEntry> inRange(
          Iterable<TransactionEntry> txs, DateRange range) =>
      txs.where((t) => range.contains(t.date));

  static PeriodSummary summarize(
      Iterable<TransactionEntry> txs, DateRange range) {
    var income = 0, expense = 0, count = 0;
    for (final t in txs) {
      if (!range.contains(t.date)) continue;
      count++;
      if (t.isIncome) {
        income += t.amountMinor;
      } else {
        expense += t.amountMinor;
      }
    }
    return PeriodSummary(
        incomeMinor: income, expenseMinor: expense, count: count);
  }

  /// All-time totals.
  static PeriodSummary lifetime(Iterable<TransactionEntry> txs) {
    var income = 0, expense = 0, count = 0;
    for (final t in txs) {
      count++;
      if (t.isIncome) {
        income += t.amountMinor;
      } else {
        expense += t.amountMinor;
      }
    }
    return PeriodSummary(
        incomeMinor: income, expenseMinor: expense, count: count);
  }

  /// Totals per category, highest first.
  static List<CategoryTotal> categoryTotals(
    Iterable<TransactionEntry> txs,
    DateRange range, {
    TransactionType type = TransactionType.expense,
  }) {
    final totals = <int, int>{};
    final counts = <int, int>{};
    var grand = 0;
    for (final t in txs) {
      if (t.type != type || !range.contains(t.date)) continue;
      totals[t.categoryId] = (totals[t.categoryId] ?? 0) + t.amountMinor;
      counts[t.categoryId] = (counts[t.categoryId] ?? 0) + 1;
      grand += t.amountMinor;
    }
    final list = totals.entries
        .map((e) => CategoryTotal(
              categoryId: e.key,
              totalMinor: e.value,
              count: counts[e.key] ?? 0,
              share: grand == 0 ? 0 : e.value / grand,
            ))
        .toList()
      ..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));
    return list;
  }

  /// One point per day in [range].
  static List<SeriesPoint> daily(
    Iterable<TransactionEntry> txs,
    DateRange range, {
    bool weekdayLabels = false,
  }) {
    final days = range.dayCount;
    final exp = List<int>.filled(days, 0);
    final inc = List<int>.filled(days, 0);
    for (final t in txs) {
      if (!range.contains(t.date)) continue;
      // Rounding keeps the index correct across DST transitions.
      final index =
          (DateUtilsX.dateOnly(t.date).difference(range.start).inHours / 24)
              .round();
      if (index < 0 || index >= days) continue;
      if (t.isIncome) {
        inc[index] += t.amountMinor;
      } else {
        exp[index] += t.amountMinor;
      }
    }
    return [
      for (var i = 0; i < days; i++)
        () {
          final d = DateUtilsX.addDays(range.start, i);
          return SeriesPoint(
            start: d,
            label: weekdayLabels
                ? DateUtilsX.weekdayShort(d)
                : '${d.day}',
            expenseMinor: exp[i],
            incomeMinor: inc[i],
          );
        }(),
    ];
  }

  /// The last [count] Monday-based weeks ending with the week of [now].
  static List<SeriesPoint> weekly(
      Iterable<TransactionEntry> txs, DateTime now, int count) {
    final thisWeek = DateUtilsX.startOfWeek(now);
    return [
      for (var i = count - 1; i >= 0; i--)
        () {
          final start = DateUtilsX.addDays(thisWeek, -7 * i);
          final s = summarize(txs, DateRange.week(start));
          return SeriesPoint(
            start: start,
            label: DateUtilsX.dayMonth(start),
            expenseMinor: s.expenseMinor,
            incomeMinor: s.incomeMinor,
          );
        }(),
    ];
  }

  /// The last [count] calendar months ending with the month of [now].
  static List<SeriesPoint> monthly(
      Iterable<TransactionEntry> txs, DateTime now, int count) {
    final exp = <int, int>{};
    final inc = <int, int>{};
    int key(DateTime d) => d.year * 12 + d.month;
    for (final t in txs) {
      final k = key(t.date);
      if (t.isIncome) {
        inc[k] = (inc[k] ?? 0) + t.amountMinor;
      } else {
        exp[k] = (exp[k] ?? 0) + t.amountMinor;
      }
    }
    final current = DateUtilsX.startOfMonth(now);
    return [
      for (var i = count - 1; i >= 0; i--)
        () {
          final m = DateUtilsX.addMonths(current, -i);
          return SeriesPoint(
            start: m,
            label: DateUtilsX.monthShort(m),
            expenseMinor: exp[key(m)] ?? 0,
            incomeMinor: inc[key(m)] ?? 0,
          );
        }(),
    ];
  }

  /// Running total of expenses for each day of [month]. Days after
  /// [upTo] (exclusive of future) are returned as null.
  static List<int?> cumulativeMonthSpend(
    Iterable<TransactionEntry> txs,
    DateTime month, {
    DateTime? upTo,
  }) {
    final range = DateRange.month(month);
    final days = DateUtilsX.daysInMonth(month);
    final perDay = List<int>.filled(days, 0);
    for (final t in txs) {
      if (t.isIncome || !range.contains(t.date)) continue;
      perDay[t.date.day - 1] += t.amountMinor;
    }
    final result = <int?>[];
    var running = 0;
    for (var i = 0; i < days; i++) {
      running += perDay[i];
      final day = DateTime(month.year, month.month, i + 1);
      if (upTo != null && day.isAfter(DateUtilsX.dateOnly(upTo))) {
        result.add(null);
      } else {
        result.add(running);
      }
    }
    return result;
  }

  /// Average expense per elapsed day of the period containing [now].
  static int averageDailySpend(
      Iterable<TransactionEntry> txs, DateRange range, DateTime now) {
    final end = DateUtilsX.addDays(DateUtilsX.dateOnly(now), 1);
    final effectiveEnd = end.isBefore(range.end) ? end : range.end;
    if (!effectiveEnd.isAfter(range.start)) return 0;
    final days = DateRange(range.start, effectiveEnd).dayCount;
    if (days <= 0) return 0;
    final spent = summarize(txs, range).expenseMinor;
    return (spent / days).round();
  }

  /// Largest expenses in [range].
  static List<TransactionEntry> topExpenses(
      Iterable<TransactionEntry> txs, DateRange range,
      {int limit = 5}) {
    final list = txs.where((t) => t.isExpense && range.contains(t.date)).toList()
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    return list.take(limit).toList();
  }
}
