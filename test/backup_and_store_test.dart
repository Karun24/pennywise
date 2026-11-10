import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/database/default_categories.dart';
import 'package:pennywise/models/category.dart';
import 'package:pennywise/models/note.dart';
import 'package:pennywise/models/transaction_entry.dart';
import 'package:pennywise/repositories/in_memory_finance_repository.dart';
import 'package:pennywise/services/backup_service.dart';
import 'package:pennywise/services/reminder_service.dart';
import 'package:pennywise/state/finance_store.dart';
import 'package:pennywise/utils/money.dart';

void main() {
  final now = DateTime(2026, 11, 6, 12);

  Future<FinanceStore> newStore() async {
    final store = FinanceStore(InMemoryFinanceRepository(), clock: () => now);
    await store.load();
    return store;
  }

  TransactionEntry expense(FinanceStore s, int minor, String category,
      {String note = ''}) {
    final cat = s.categories.firstWhere((c) => c.name == category);
    return TransactionEntry(
      type: TransactionType.expense,
      amountMinor: minor,
      categoryId: cat.id!,
      note: note,
      date: now,
      paymentMethod: PaymentMethod.cash,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('seeds default categories', () async {
    final s = await newStore();
    expect(s.categories.length, buildDefaultCategories().length);
    expect(s.loadError, isNull);
  });

  test('add, edit and delete a transaction', () async {
    final s = await newStore();
    await s.addTransaction(
        expense(s, 25000, DefaultCategoryNames.food, note: 'Lunch'));
    expect(s.transactions.single.note, 'Lunch');

    final edited = s.transactions.single.copyWith(amountMinor: 30000);
    await s.updateTransaction(edited);
    expect(s.transactions.single.amountMinor, 30000);

    final deleted = s.transactions.single;
    await s.deleteTransaction(deleted);
    expect(s.transactions, isEmpty);

    await s.restoreTransaction(deleted);
    expect(s.transactions.length, 1);
  });

  test('validation rejects bad input', () async {
    final s = await newStore();
    await expectLater(
      s.addTransaction(expense(s, 0, DefaultCategoryNames.food)),
      throwsA(isA<StoreException>()),
    );
    final income = s.categories.firstWhere((c) => c.name == 'Salary');
    final mismatched =
        expense(s, 100, DefaultCategoryNames.food).copyWith(categoryId: income.id);
    await expectLater(
        s.addTransaction(mismatched), throwsA(isA<StoreException>()));
  });

  test('budget alert is returned when a threshold is crossed', () async {
    final s = await newStore();
    await s.updateSettings(s.settings.copyWith(monthlyBudgetMinor: 100000));
    final crossed =
        await s.addTransaction(expense(s, 80000, DefaultCategoryNames.food));
    expect(crossed, isNotEmpty);
  });

  test('custom category: duplicate names rejected, delete reassigns', () async {
    final s = await newStore();
    final pets = await s.addCategory(const Category(
        name: 'Pets',
        iconKey: 'pets',
        colorValue: 0xFF81C784,
        kind: TransactionType.expense));
    expect(pets.name, 'Pets');
    await expectLater(
      s.addCategory(pets.copyWith(name: 'pets')),
      throwsA(isA<StoreException>()),
    );
    final created = s.categories.firstWhere((c) => c.name == 'Pets');
    await s.addTransaction(expense(s, 5000, 'Pets'));
    await s.deleteCategory(created);
    expect(s.categories.any((c) => c.name == 'Pets'), isFalse);
    expect(s.transactions.single.categoryId,
        s.fallbackCategory(TransactionType.expense).id);
  });

  test('backup round trip restores everything', () async {
    final s = await newStore();
    await s.addTransaction(
        expense(s, 12345, DefaultCategoryNames.groceries, note: 'Milk "A2"'));
    await s.setCategoryBudget(
        s.categories.firstWhere((c) => c.name == DefaultCategoryNames.food).id!,
        500000);
    await s.updateSettings(s.settings.copyWith(currencyCode: 'USD'));

    final json = BackupService.encode(s.snapshot());
    final decoded = BackupService.decode(json);

    final other = await newStore();
    await other.restore(decoded);
    expect(other.transactions.single.amountMinor, 12345);
    expect(other.transactions.single.note, 'Milk "A2"');
    expect(other.budgets.single.amountMinor, 500000);
    expect(other.settings.currencyCode, 'USD');
  });

  test('invalid backups are rejected with a clear message', () {
    expect(() => BackupService.decode('not json'),
        throwsA(isA<BackupFormatException>()));
    expect(() => BackupService.decode('{"format":"other"}'),
        throwsA(isA<BackupFormatException>()));
    expect(
      () => BackupService.decode(
          '{"format":"pennywise-backup","version":1,"categories":[],'
          '"transactions":[],"budgets":[],"settings":{}}'),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('CSV export escapes quotes and formula characters', () async {
    final s = await newStore();
    await s.addTransaction(
        expense(s, 10000, DefaultCategoryNames.food, note: '=cmd "x"'));
    final csv = BackupService.toCsv(
      transactions: s.transactions,
      categories: {for (final c in s.categories) c.id!: c},
      currency: CurrencyInfo.inr,
    );
    expect(csv, contains('"\'=cmd ""x"""'));
    expect(csv, contains('-100.00'));
  });

  test('clear all wipes data and reseeds categories', () async {
    final s = await newStore();
    await s.addTransaction(expense(s, 100, DefaultCategoryNames.food));
    await s.clearAll();
    expect(s.transactions, isEmpty);
    expect(s.categories.length, buildDefaultCategories().length);
  });

  group('notes', () {
    Note draft({String title = 'Rent', DateTime? at}) => Note(
          title: title,
          body: 'Pay landlord',
          reminderAt: at,
          createdAt: now,
          updatedAt: now,
        );

    test('save, edit, pin and delete a note; reminder is scheduled', () async {
      final reminders = _FakeReminders();
      final s = FinanceStore(InMemoryFinanceRepository(),
          clock: () => now, reminders: reminders);
      await s.load();

      final at = now.add(const Duration(days: 1));
      final saved = (await s.saveNote(draft(at: at))).note;
      expect(s.notes.single.title, 'Rent');
      expect(s.upcomingReminders.single.reminderAt, at);
      expect(reminders.scheduled, [saved.id]);

      await s.saveNote(saved.copyWith(title: 'Rent due'));
      expect(s.notes.single.title, 'Rent due');

      await s.setNotePinned(s.notes.single, true);
      expect(s.notes.single.pinned, isTrue);

      await s.deleteNote(s.notes.single);
      expect(s.notes, isEmpty);
      expect(reminders.cancelled, contains(saved.id));
    });

    test('empty notes are rejected', () async {
      final s = await newStore();
      await expectLater(s.saveNote(draft(title: '').copyWith(body: '')),
          throwsA(isA<StoreException>()));
    });

    test('notes are included in backups; old backups still restore',
        () async {
      final s = await newStore();
      await s.saveNote(draft(at: now.add(const Duration(hours: 2))));
      final decoded = BackupService.decode(BackupService.encode(s.snapshot()));
      expect(decoded.notes.single.title, 'Rent');

      final other = await newStore();
      await other.restore(decoded);
      expect(other.notes.single.body, 'Pay landlord');

      // A version-1 backup has no "notes" section.
      final v1 = BackupService.encode(s.snapshot())
          .replaceFirst('"version": 3', '"version": 1');
      final old = BackupService.decode(v1.replaceAll(
          RegExp(r',\s*"notes": \[[\s\S]*\]\s*}\s*$'), '\n}'));
      expect(old.notes, isEmpty);
    });
  });
}

class _FakeReminders implements ReminderScheduler {
  final scheduled = <int>[];
  final cancelled = <int>[];

  final daily = <List<DateTime>>[];

  @override
  Future<void> init({void Function(String payload)? onTap}) async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> schedule(Note note) async {
    if (note.reminderAt != null) scheduled.add(note.id!);
    return true;
  }

  @override
  Future<void> cancel(int noteId) async => cancelled.add(noteId);

  @override
  Future<void> scheduleDaily(List<DateTime> times) async => daily.add(times);

  @override
  Future<String?> launchedPayload() async => null;
}
