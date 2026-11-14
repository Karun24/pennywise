import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/database/default_categories.dart';
import 'package:pennywise/models/category.dart';
import 'package:pennywise/models/transaction_entry.dart';
import 'package:pennywise/services/smart/categorizer.dart';
import 'package:pennywise/utils/money.dart';

List<Category> _categories() {
  var id = 1;
  return [for (final c in buildDefaultCategories()) c.copyWith(id: id++)];
}

Category _named(List<Category> cats, String name) =>
    cats.firstWhere((c) => c.name == name);

void main() {
  group('Categorizer', () {
    final cats = _categories();

    test('maps Indian merchants to categories', () {
      final c = Categorizer(categories: cats);
      expect(c.suggest('Swiggy order')?.category.name,
          DefaultCategoryNames.food);
      expect(c.suggest('BigBasket')?.category.name,
          DefaultCategoryNames.groceries);
      expect(c.suggest('Rapido to office')?.category.name,
          DefaultCategoryNames.transport);
      expect(c.suggest('Netflix renewal')?.category.name,
          DefaultCategoryNames.entertainment);
      expect(c.suggest('IRCTC train ticket')?.category.name,
          DefaultCategoryNames.travel);
      expect(c.suggest('Apollo pharmacy')?.category.name,
          DefaultCategoryNames.health);
    });

    test('respects the requested type', () {
      final c = Categorizer(categories: cats);
      final m = c.suggest('salary', type: TransactionType.expense);
      expect(m, isNull);
    });

    test('learns from the user\'s own history', () {
      final shopping = _named(cats, DefaultCategoryNames.shopping);
      final history = [
        TransactionEntry(
          id: 1,
          type: TransactionType.expense,
          amountMinor: 50000,
          categoryId: shopping.id!,
          note: 'Weekend haul',
          date: DateTime(2026, 11, 1),
          paymentMethod: PaymentMethod.upi,
          createdAt: DateTime(2026, 11, 1),
          updatedAt: DateTime(2026, 11, 1),
        ),
      ];
      final c = Categorizer(categories: cats, history: history);
      final m = c.suggest('weekend haul');
      expect(m?.category.name, DefaultCategoryNames.shopping);
      expect(m?.source, MatchSource.history);
    });

    test('unknown text returns null rather than guessing', () {
      final c = Categorizer(categories: cats);
      expect(c.suggest('xyzzy'), isNull);
    });
  });

  group('Money', () {
    test('parses user input to minor units', () {
      expect(Money.parseToMinor('250'), 25000);
      expect(Money.parseToMinor('1,250.50'), 125050);
      expect(Money.parseToMinor('₹ 99'), 9900);
      expect(Money.parseToMinor('2k'), 200000);
      expect(Money.parseToMinor('0'), isNull);
      expect(Money.parseToMinor('-5'), isNull);
      expect(Money.parseToMinor('abc'), isNull);
      expect(Money.parseToMinor('1.234'), isNull);
    });

    test('formats INR with Indian digit grouping', () {
      expect(Money.format(12345600, CurrencyInfo.inr), '₹1,23,456');
      expect(Money.format(25050, CurrencyInfo.inr), '₹250.50');
      expect(Money.format(-5000, CurrencyInfo.inr), '-₹50');
    });

    test('compact axis labels', () {
      expect(Money.compact(250000, CurrencyInfo.inr), '₹2.5K');
      expect(Money.compact(15000000, CurrencyInfo.inr), '₹1.5L');
      expect(Money.compact(9900, CurrencyInfo.inr), '₹99');
    });

    test('editable text round-trips', () {
      expect(Money.toEditable(25000), '250');
      expect(Money.toEditable(125050), '1250.50');
      expect(Money.parseToMinor(Money.toEditable(125050)), 125050);
    });
  });
}
