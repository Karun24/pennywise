import '../models/category.dart';
import '../models/transaction_entry.dart';
import '../utils/date_utils.dart';
import 'analytics_service.dart';

enum BudgetLevel { safe, warning, danger, exceeded }

/// Usage of one budget (overall or per category) for the current month.
class BudgetStatus {
  const BudgetStatus({
    required this.limitMinor,
    required this.spentMinor,
    this.categoryId,
  });

  /// Null for the overall monthly budget.
  final int? categoryId;
  final int limitMinor;
  final int spentMinor;

  /// Usage thresholds used for alerts.
  static const warningAt = 0.75;
  static const dangerAt = 0.9;

  int get remainingMinor => limitMinor - spentMinor;
  double get ratio => limitMinor <= 0 ? 0 : spentMinor / limitMinor;

  BudgetLevel get level {
    final r = ratio;
    if (r > 1.0) return BudgetLevel.exceeded;
    if (r >= dangerAt) return BudgetLevel.danger;
    if (r >= warningAt) return BudgetLevel.warning;
    return BudgetLevel.safe;
  }
}

/// Everything the Budget screen and alerts need for one month.
class BudgetOverview {
  const BudgetOverview({
    required this.month,
    required this.overall,
    required this.categories,
    required this.monthSpentMinor,
    required this.daysLeft,
    required this.daysInMonth,
    required this.dayOfMonth,
  });

  final DateTime month;
  final BudgetStatus? overall;
  final List<BudgetStatus> categories;
  final int monthSpentMinor;

  /// Days remaining including today.
  final int daysLeft;
  final int daysInMonth;
  final int dayOfMonth;

  double get monthElapsed => dayOfMonth / daysInMonth;

  /// Spend projected to month end at the current daily pace.
  int get projectedMinor =>
      dayOfMonth == 0 ? 0 : (monthSpentMinor / dayOfMonth * daysInMonth).round();

  /// What can still be spent per day without exceeding the overall budget.
  int? get safeDailyMinor {
    final o = overall;
    if (o == null || daysLeft <= 0) return null;
    if (o.remainingMinor <= 0) return 0;
    return (o.remainingMinor / daysLeft).floor();
  }

  /// Budgets at or above the warning threshold, most severe first.
  List<BudgetStatus> get alerts {
    final list = [
      if (overall != null && overall!.level != BudgetLevel.safe) overall!,
      ...categories.where((c) => c.level != BudgetLevel.safe),
    ]..sort((a, b) => b.ratio.compareTo(a.ratio));
    return list;
  }
}

class BudgetService {
  BudgetService._();

  static BudgetOverview compute({
    required List<TransactionEntry> transactions,
    required List<CategoryBudget> budgets,
    required int? monthlyBudgetMinor,
    required DateTime now,
  }) {
    final range = DateRange.month(now);
    final summary = AnalyticsService.summarize(transactions, range);
    final byCategory = <int, int>{
      for (final c in AnalyticsService.categoryTotals(transactions, range))
        c.categoryId: c.totalMinor,
    };
    final days = DateUtilsX.daysInMonth(now);
    final statuses = budgets
        .map((b) => BudgetStatus(
              categoryId: b.categoryId,
              limitMinor: b.amountMinor,
              spentMinor: byCategory[b.categoryId] ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.ratio.compareTo(a.ratio));

    return BudgetOverview(
      month: DateUtilsX.startOfMonth(now),
      overall: monthlyBudgetMinor == null
          ? null
          : BudgetStatus(
              limitMinor: monthlyBudgetMinor,
              spentMinor: summary.expenseMinor,
            ),
      categories: statuses,
      monthSpentMinor: summary.expenseMinor,
      daysLeft: days - now.day + 1,
      daysInMonth: days,
      dayOfMonth: now.day,
    );
  }

  /// Returns budgets that crossed a threshold because of [added].
  /// Used to show an immediate alert after saving an expense.
  static List<BudgetStatus> newlyCrossed({
    required BudgetOverview before,
    required BudgetOverview after,
  }) {
    final crossed = <BudgetStatus>[];
    BudgetStatus? find(BudgetOverview o, int? id) {
      if (id == null) return o.overall;
      for (final c in o.categories) {
        if (c.categoryId == id) return c;
      }
      return null;
    }

    final afterAll = [
      if (after.overall != null) after.overall!,
      ...after.categories,
    ];
    for (final a in afterAll) {
      final b = find(before, a.categoryId);
      if (b == null) continue;
      if (a.level.index > b.level.index && a.level != BudgetLevel.safe) {
        crossed.add(a);
      }
    }
    return crossed;
  }
}
