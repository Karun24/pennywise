import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/database/default_categories.dart';
import 'package:pennywise/models/category.dart';
import 'package:pennywise/models/transaction_entry.dart';
import 'package:pennywise/services/analytics_service.dart';
import 'package:pennywise/services/budget_service.dart';
import 'package:pennywise/services/smart/insights_engine.dart';
import 'package:pennywise/utils/date_utils.dart';
import 'package:pennywise/utils/money.dart';

final _cats = () {
  var id = 1;
  return [for (final c in buildDefaultCategories()) c.copyWith(id: id++)];
}();

int _id(String name) => _cats.firstWhere((c) => c.name == name).id!;

var _seq = 1;
TransactionEntry _tx(
  DateTime date,
  num amount, {
  String category = DefaultCategoryNames.food,
  TransactionType type = TransactionType.expense,
  String note = '',
}) {
  return TransactionEntry(
    id: _seq++,
    type: type,
    amountMinor: Money.fromMajor(amount),
    categoryId: _id(category),
    note: note,
    date: date,
    paymentMethod: PaymentMethod.upi,
    createdAt: date,
    updatedAt: date,
  );
}

void main() {
  // Friday 20 Nov 2026.
  final now = DateTime(2026, 11, 20, 18);

  group('AnalyticsService', () {
    final txs = [
      _tx(DateTime(2026, 11, 2), 100),
      _tx(DateTime(2026, 11, 3), 300, category: DefaultCategoryNames.shopping),
      _tx(DateTime(2026, 11, 1), 50000,
          category: DefaultCategoryNames.salary, type: TransactionType.income),
      _tx(DateTime(2026, 10, 15), 999),
    ];

    test('summarize a month', () {
      final s = AnalyticsService.summarize(txs, DateRange.month(now));
      expect(s.expenseMinor, 40000);
      expect(s.incomeMinor, 5000000);
      expect(s.netMinor, 5000000 - 40000);
      expect(s.count, 3);
    });

    test('category totals sorted with shares', () {
      final t = AnalyticsService.categoryTotals(txs, DateRange.month(now));
      expect(t.first.categoryId, _id(DefaultCategoryNames.shopping));
      expect(t.first.share, closeTo(0.75, 1e-9));
    });

    test('daily buckets cover every day of the month', () {
      final d = AnalyticsService.daily(txs, DateRange.month(now));
      expect(d.length, 30);
      expect(d[1].expenseMinor, 10000);
      expect(d[2].expenseMinor, 30000);
    });

    test('monthly series ends with current month', () {
      final m = AnalyticsService.monthly(txs, now, 6);
      expect(m.length, 6);
      expect(m.last.expenseMinor, 40000);
      expect(m[4].expenseMinor, 99900);
    });

    test('average daily spend uses elapsed days only', () {
      final avg =
          AnalyticsService.averageDailySpend(txs, DateRange.month(now), now);
      expect(avg, (40000 / 20).round());
    });

    test('cumulative month spend stops after today', () {
      final c = AnalyticsService.cumulativeMonthSpend(txs, now, upTo: now);
      expect(c[0], 0);
      expect(c[2], 40000);
      expect(c[19], 40000);
      expect(c[20], isNull);
    });
  });

  group('BudgetService', () {
    test('levels and pace', () {
      final txs = [_tx(DateTime(2026, 11, 10), 8000)];
      final o = BudgetService.compute(
        transactions: txs,
        budgets: [
          CategoryBudget(
              categoryId: _id(DefaultCategoryNames.food), amountMinor: 700000),
        ],
        monthlyBudgetMinor: 1000000,
        now: now,
      );
      expect(o.overall!.ratio, closeTo(0.8, 1e-9));
      expect(o.overall!.level, BudgetLevel.warning);
      expect(o.categories.single.level, BudgetLevel.exceeded);
      expect(o.daysLeft, 11);
      expect(o.safeDailyMinor, (200000 / 11).floor());
      expect(o.alerts.first.categoryId, _id(DefaultCategoryNames.food));
    });

    test('newlyCrossed detects threshold crossings', () {
      List<TransactionEntry> base() => [_tx(DateTime(2026, 11, 5), 700)];
      BudgetOverview at(List<TransactionEntry> t) => BudgetService.compute(
            transactions: t,
            budgets: const [],
            monthlyBudgetMinor: 100000,
            now: now,
          );
      final before = at(base());
      final after = at([...base(), _tx(DateTime(2026, 11, 6), 100)]);
      final crossed = BudgetService.newlyCrossed(before: before, after: after);
      expect(crossed.single.level, BudgetLevel.warning);
    });
  });

  group('InsightsEngine', () {
    InsightsEngine engine(List<TransactionEntry> txs, {int? budget}) =>
        InsightsEngine(
          transactions: txs,
          categories: _cats,
          budgets: const [],
          monthlyBudgetMinor: budget,
          currency: CurrencyInfo.inr,
          now: now,
        );

    test('no data -> no insights (never invents numbers)', () {
      expect(engine(const []).generate(), isEmpty);
    });

    test('top category, average and month trend come from real data', () {
      final txs = [
        for (var d = 1; d <= 20; d++) _tx(DateTime(2026, 11, d), 200),
        _tx(DateTime(2026, 11, 4), 3000, category: DefaultCategoryNames.shopping),
        for (var d = 1; d <= 20; d++) _tx(DateTime(2026, 10, d), 100),
      ];
      final ids = engine(txs).generate().map((i) => i.id).toList();
      expect(ids, contains('top-category'));
      expect(ids, contains('avg-daily'));
      expect(ids, contains('month-trend-up'));
      final avg =
          engine(txs).generate().firstWhere((i) => i.id == 'avg-daily');
      // (20 x 200 + 3000) / 20 days = 350
      expect(avg.message, contains('₹350'));
    });

    test('budget usage insight at 75%+', () {
      final txs = [_tx(DateTime(2026, 11, 2), 7600)];
      final insights = engine(txs, budget: 1000000).generate();
      final budget =
          insights.firstWhere((i) => i.topic == InsightTopic.budget);
      expect(budget.tone, isNot(InsightTone.positive));
      expect(budget.message, contains('76%'));
    });

    test('unusual spending detection', () {
      final txs = [
        for (var d = 1; d <= 8; d++)
          _tx(DateTime(2026, 10, d), 500,
              category: DefaultCategoryNames.shopping),
        _tx(DateTime(2026, 11, 18), 6000,
            category: DefaultCategoryNames.shopping, note: 'Headphones'),
      ];
      final ids = engine(txs).generate().map((i) => i.id);
      expect(ids.any((id) => id.startsWith('anomaly-')), isTrue);
    });

    test('alerts sort before positive and info', () {
      final txs = [
        _tx(DateTime(2026, 11, 2), 20000),
        _tx(DateTime(2026, 11, 1), 1000,
            category: DefaultCategoryNames.salary,
            type: TransactionType.income),
      ];
      final list = engine(txs, budget: 1000000).generate();
      expect(list.first.tone, InsightTone.alert);
    });
  });
}
