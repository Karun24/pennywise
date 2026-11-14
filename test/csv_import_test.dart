import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/database/default_categories.dart';
import 'package:pennywise/models/transaction_entry.dart';
import 'package:pennywise/repositories/in_memory_finance_repository.dart';
import 'package:pennywise/services/backup_service.dart';
import 'package:pennywise/services/csv_import_service.dart';
import 'package:pennywise/state/finance_store.dart';
import 'package:pennywise/utils/money.dart';

void main() {
  final now = DateTime(2026, 11, 10, 12);

  Future<FinanceStore> newStore() async {
    final s = FinanceStore(InMemoryFinanceRepository(), clock: () => now);
    await s.load();
    return s;
  }

  test('CSV export can be imported back', () async {
    final a = await newStore();
    final food = a.categories.firstWhere((c) => c.name == DefaultCategoryNames.food);
    final salary =
        a.categories.firstWhere((c) => c.name == DefaultCategoryNames.salary);
    await a.insertMany([
      TransactionEntry(
        type: TransactionType.expense,
        amountMinor: 25050,
        categoryId: food.id!,
        note: 'Lunch, with "friends"',
        date: DateTime(2026, 11, 3, 13),
        paymentMethod: PaymentMethod.upi,
        createdAt: now,
        updatedAt: now,
      ),
      TransactionEntry(
        type: TransactionType.income,
        amountMinor: 5000000,
        categoryId: salary.id!,
        note: '=SUM(A1)',
        date: DateTime(2026, 11, 1, 9),
        paymentMethod: PaymentMethod.netBanking,
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    final csv = BackupService.toCsv(
      transactions: a.transactions,
      categories: {for (final c in a.categories) c.id!: c},
      currency: CurrencyInfo.inr,
    );
    expect(CsvImportService.looksLikeCsv(csv), isTrue);

    final rows = CsvImportService.parse(csv);
    expect(rows, hasLength(2));

    final b = await newStore();
    final r1 = await b.importCsv(rows);
    expect(r1.added, 2);
    final lunch = b.transactions.firstWhere((t) => t.isExpense);
    expect(lunch.amountMinor, 25050);
    expect(lunch.note, 'Lunch, with "friends"');
    expect(lunch.paymentMethod, PaymentMethod.upi);
    expect(b.categoryById(lunch.categoryId)?.name, DefaultCategoryNames.food);
    expect(b.transactions.firstWhere((t) => t.isIncome).note, '=SUM(A1)');

    // Importing the same file again adds nothing.
    final r2 = await b.importCsv(rows);
    expect(r2.added, 0);
    expect(r2.skipped, 2);
  });

  test('spreadsheet-resaved CSV with dd/mm/yyyy dates and new category',
      () async {
    const text = 'Date,Type,Category,Description,Payment method,Amount (INR)\n'
        '05/11/2026,Expense,Pets,Dog food,Cash,"-1,200.00"\n';
    final rows = CsvImportService.parse(text);
    expect(rows.single.date, DateTime(2026, 11, 5, 12));
    expect(rows.single.amountMinor, 120000);

    final s = await newStore();
    await s.importCsv(rows);
    expect(s.categories.any((c) => c.name == 'Pets'), isTrue);
    expect(s.transactions.single.paymentMethod, PaymentMethod.cash);
  });

  test('bad CSV gives a clear error', () {
    expect(() => CsvImportService.parse('Date,Type,Category,Amount\nxx,Expense,Food,1'),
        throwsA(isA<BackupFormatException>()));
  });
}
