import 'dart:math';

import '../database/default_categories.dart';
import '../models/category.dart';
import '../models/transaction_entry.dart';
import '../utils/date_utils.dart';
import '../utils/money.dart';

/// Generates clearly-labelled sample data so a new user can explore the app.
/// Offered only while there are no real transactions; "Clear all data"
/// removes it.
class DemoData {
  DemoData._();

  static List<TransactionEntry> generate(List<Category> categories,
      {required DateTime now, int seed = 42}) {
    final rnd = Random(seed);
    int? id(String name) {
      for (final c in categories) {
        if (c.isDefault && c.name == name) return c.id;
      }
      return null;
    }

    final out = <TransactionEntry>[];
    void add(TransactionType type, String category, num amount, String note,
        DateTime date, PaymentMethod method) {
      final cid = id(category);
      if (cid == null) return;
      final at = DateTime(date.year, date.month, date.day,
          9 + rnd.nextInt(12), rnd.nextInt(60));
      out.add(TransactionEntry(
        type: type,
        amountMinor: Money.fromMajor(amount),
        categoryId: cid,
        note: note,
        date: at,
        paymentMethod: method,
        createdAt: at,
        updatedAt: at,
      ));
    }

    num around(num base) => (base * (0.75 + rnd.nextDouble() * 0.5)).round();
    T pick<T>(List<T> items) => items[rnd.nextInt(items.length)];

    final today = DateUtilsX.dateOnly(now);
    final start = DateUtilsX.addMonths(DateUtilsX.startOfMonth(today), -2);
    const e = TransactionType.expense;
    const i = TransactionType.income;
    const n = DefaultCategoryNames.food;

    for (var d = start;
        !d.isAfter(today);
        d = DateUtilsX.addDays(d, 1)) {
      if (d.day == 1) {
        add(i, DefaultCategoryNames.salary, 65000, 'Salary', d,
            PaymentMethod.netBanking);
        add(e, DefaultCategoryNames.bills, 15000, 'Rent', d,
            PaymentMethod.netBanking);
      }
      if (d.day == 5) {
        add(e, DefaultCategoryNames.bills, around(1400), 'Electricity bill', d,
            PaymentMethod.upi);
        add(e, DefaultCategoryNames.bills, 599, 'Broadband', d,
            PaymentMethod.upi);
      }
      if (d.day == 12) {
        add(e, DefaultCategoryNames.entertainment, 649, 'Netflix', d,
            PaymentMethod.creditCard);
      }
      if (d.day == 18 && rnd.nextBool()) {
        add(i, DefaultCategoryNames.freelance, around(12000),
            'Freelance project', d, PaymentMethod.netBanking);
      }
      // Daily habits.
      if (rnd.nextDouble() < 0.7) {
        add(e, n, around(160), pick(['Lunch', 'Swiggy order', 'Canteen lunch']),
            d, PaymentMethod.upi);
      }
      if (rnd.nextDouble() < 0.45) {
        add(e, n, around(90), pick(['Coffee', 'Chai and snacks']), d,
            PaymentMethod.upi);
      }
      if (rnd.nextDouble() < 0.5) {
        add(e, DefaultCategoryNames.transport, around(140),
            pick(['Uber', 'Metro card', 'Auto', 'Rapido']), d,
            PaymentMethod.upi);
      }
      if (d.weekday == DateTime.saturday) {
        add(e, DefaultCategoryNames.groceries, around(1300),
            pick(['BigBasket order', 'DMart groceries', 'Blinkit']), d,
            PaymentMethod.upi);
        if (rnd.nextBool()) {
          add(e, n, around(900), 'Dinner with friends', d,
              PaymentMethod.creditCard);
        }
      }
      if (d.weekday == DateTime.sunday && rnd.nextDouble() < 0.4) {
        add(e, DefaultCategoryNames.entertainment, around(450), 'Movie', d,
            PaymentMethod.upi);
      }
      if (rnd.nextDouble() < 0.08) {
        add(e, DefaultCategoryNames.shopping, around(1800),
            pick(['Amazon order', 'Myntra clothes', 'Flipkart']), d,
            PaymentMethod.creditCard);
      }
      if (rnd.nextDouble() < 0.05) {
        add(e, DefaultCategoryNames.health, around(500), 'Pharmacy', d,
            PaymentMethod.cash);
      }
      if (d.day == 20) {
        add(e, DefaultCategoryNames.transport, around(2200), 'Petrol', d,
            PaymentMethod.debitCard);
      }
    }
    // One clearly unusual purchase this month to demonstrate detection.
    final spike = DateUtilsX.addDays(today, -2);
    if (!spike.isBefore(start)) {
      add(e, DefaultCategoryNames.shopping, 7999, 'New headphones', spike,
          PaymentMethod.creditCard);
    }
    return out;
  }
}
