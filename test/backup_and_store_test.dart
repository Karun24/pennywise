import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/database/default_categories.dart';
import 'package:pennywise/models/account.dart';
import 'package:pennywise/models/app_settings.dart';
import 'package:pennywise/models/category.dart';
import 'package:pennywise/models/debt_entry.dart';
import 'package:pennywise/models/goal.dart';
import 'package:pennywise/models/note.dart';
import 'package:pennywise/models/recurring_rule.dart';
import 'package:pennywise/models/transaction_entry.dart';
import 'package:pennywise/repositories/in_memory_finance_repository.dart';
import 'package:pennywise/services/backup_service.dart';
import 'package:pennywise/services/crypto_backup_service.dart';
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

      // A version-1 backup has no "notes", "recurring", "accounts", or "goals" section.
      final jsonMap = jsonDecode(BackupService.encode(s.snapshot())) as Map<String, dynamic>;
      jsonMap['version'] = 1;
      jsonMap.remove('notes');
      jsonMap.remove('accounts');
      jsonMap.remove('recurring');
      jsonMap.remove('goals');
      jsonMap.remove('debts');
      final old = BackupService.decode(jsonEncode(jsonMap));
      expect(old.notes, isEmpty);
      expect(old.debts, isEmpty);
    });
  });

  group('accounts, transfers and tags', () {
    test('seeds default accounts', () async {
      final s = await newStore();
      expect(s.accounts.length, 2);
      expect(s.defaultAccount.name, 'Bank Account');
    });

    test('add, update and delete account with fallback reassignment', () async {
      final s = await newStore();
      final wallet = await s.addAccount(Account(
        name: 'Amazon Pay',
        type: AccountType.other,
        iconKey: 'wallet',
        colorValue: 0xFF81C784,
        initialBalanceMinor: 50000,
        createdAt: now,
        updatedAt: now,
      ));
      expect(s.accounts.any((a) => a.name == 'Amazon Pay'), isTrue);
      expect(s.accountBalance(wallet.id!), 50000);

      // Rejects duplicates
      await expectLater(
        s.addAccount(wallet.copyWith(name: 'amazon pay')),
        throwsA(isA<StoreException>()),
      );

      // Add transaction to wallet
      await s.addTransaction(expense(s, 10000, DefaultCategoryNames.food)
          .copyWith(accountId: wallet.id));
      expect(s.accountBalance(wallet.id!), 40000);

      // Delete wallet reassigns transactions to default account
      await s.deleteAccount(wallet);
      expect(s.accounts.any((a) => a.name == 'Amazon Pay'), isFalse);
      expect(s.transactions.single.accountId, s.defaultAccount.id);
    });

    test('transfers correctly update source and target balances', () async {
      final s = await newStore();
      final bank = s.defaultAccount;
      final cash = s.accounts.firstWhere((a) => a.name == 'Cash');

      // Set initial balance on bank
      await s.updateAccount(bank.copyWith(initialBalanceMinor: 100000));
      expect(s.accountBalance(bank.id!), 100000);
      expect(s.accountBalance(cash.id!), 0);
      expect(s.totalBalanceMinor, 100000);

      // Transfer 200 from bank to cash
      final transfer = TransactionEntry(
        type: TransactionType.transfer,
        amountMinor: 20000,
        categoryId: s.categories.first.id!,
        note: 'ATM cash withdrawal',
        date: now,
        paymentMethod: PaymentMethod.other,
        createdAt: now,
        updatedAt: now,
        accountId: bank.id,
        toAccountId: cash.id,
        tag: 'ATM',
      );
      await s.addTransaction(transfer);

      // Bank has 800, Cash has 200, Total is still 1000
      expect(s.accountBalance(bank.id!), 80000);
      expect(s.accountBalance(cash.id!), 20000);
      expect(s.totalBalanceMinor, 100000);
    });

    test('tags are extracted from tag property and note hashtags', () async {
      final s = await newStore();
      await s.addTransaction(expense(s, 1500, DefaultCategoryNames.food,
              note: 'Dinner at shack #Goa2026 #Beach')
          .copyWith(tag: 'Vacation'));

      expect(s.allTags, containsAll(['Vacation', 'Goa2026', 'Beach']));
    });
  });

  group('savings goals', () {
    test('create, update, add savings and delete a goal', () async {
      final s = await newStore();
      final deadline = DateTime(2027, 5, 6);
      final goal = await s.addGoal(Goal(
        name: 'Japan Trip',
        targetMinor: 15000000, // 1,50,000
        savedMinor: 3000000, // 30,000
        targetDate: deadline,
        colorValue: 0xFF34D399,
        iconKey: 'travel',
        createdAt: now,
        updatedAt: now,
      ));

      expect(s.goals.single.name, 'Japan Trip');
      expect(s.goals.single.percentage, 20);
      expect(s.goals.single.remainingMinor, 12000000);
      expect(s.totalSavedInGoals, 3000000);

      // Remaining 6 months: suggested contribution should be 120000 / 6 = 20000
      final suggested = s.goals.single.suggestedMonthlyMinor(now);
      expect(suggested, isNotNull);
      expect(suggested!, 2000000);

      // Add savings
      await s.addGoalSavings(goal, 2000000);
      expect(s.goals.single.savedMinor, 5000000);
      expect(s.goals.single.isAchieved, isFalse);

      // Complete goal
      await s.addGoalSavings(s.goals.single, 10000000);
      expect(s.goals.single.savedMinor, 15000000);
      expect(s.goals.single.isAchieved, isTrue);

      // Delete goal
      await s.deleteGoal(s.goals.single);
      expect(s.goals, isEmpty);
    });

    test('goals are preserved in backup roundtrip', () async {
      final s = await newStore();
      await s.addGoal(Goal(
        name: 'MacBook Pro',
        targetMinor: 20000000,
        savedMinor: 5000000,
        colorValue: 0xFF4FC3F7,
        iconKey: 'laptop',
        createdAt: now,
        updatedAt: now,
      ));

      final json = BackupService.encode(s.snapshot());
      final decoded = BackupService.decode(json);
      expect(decoded.goals.single.name, 'MacBook Pro');
      expect(decoded.goals.single.targetMinor, 20000000);

      final other = await newStore();
      await other.restore(decoded);
      expect(other.goals.single.name, 'MacBook Pro');
      expect(other.goals.single.savedMinor, 5000000);
    });
  });

  group('CryptoBackupService', () {
    test('encrypt and decrypt roundtrip matches original data', () {
      const crypto = CryptoBackupService();
      const original = '{"version": 5, "hello": "world"}';
      const password = 'my-secret-password-123';

      final encrypted = crypto.encrypt(original, password);
      expect(CryptoBackupService.isEncrypted(encrypted), isTrue);
      expect(encrypted.contains('pennywise-encrypted-backup'), isTrue);

      final decrypted = crypto.decrypt(encrypted, password);
      expect(decrypted, original);
    });

    test('decrypt with wrong password throws CryptoBackupException', () {
      const crypto = CryptoBackupService();
      const original = '{"test": true}';
      final encrypted = crypto.encrypt(original, 'correct-pass');

      expect(
        () => crypto.decrypt(encrypted, 'wrong-pass'),
        throwsA(isA<CryptoBackupException>()),
      );
    });

    test('encrypt with empty password throws CryptoBackupException', () {
      const crypto = CryptoBackupService();
      expect(
        () => crypto.encrypt('{}', '   '),
        throwsA(isA<CryptoBackupException>()),
      );
    });
  });

  group('TransactionEntry receipt support', () {
    test('receiptPath is copied and serialized properly', () {
      final entry = TransactionEntry(
        type: TransactionType.expense,
        amountMinor: 5000,
        categoryId: 1,
        note: 'Groceries with receipt',
        date: now,
        paymentMethod: PaymentMethod.upi,
        receiptPath: '/app/receipts/bill_123.jpg',
        createdAt: now,
        updatedAt: now,
      );

      expect(entry.hasReceipt, isTrue);
      expect(entry.receiptPath, '/app/receipts/bill_123.jpg');

      final map = entry.toMap();
      expect(map['receipt_path'], '/app/receipts/bill_123.jpg');

      final restored = TransactionEntry.fromMap(map);
      expect(restored.hasReceipt, isTrue);
      expect(restored.receiptPath, '/app/receipts/bill_123.jpg');

      final cleared = entry.copyWith(clearReceipt: true);
      expect(cleared.hasReceipt, isFalse);
      expect(cleared.receiptPath, isNull);
    });
  });

  group('Repeating Note Reminders & End Dates', () {
    test('repeating note reminder fields and serialization', () {
      final repeatUntil = DateTime(2026, 12, 31, 23, 59, 59);
      final note = Note(
        title: 'Rent payment reminder',
        body: 'Pay rent on 1st of every month',
        reminderAt: DateTime(2026, 11, 1, 9, 0),
        repeatFrequency: RepeatFrequency.monthly,
        repeatUntil: repeatUntil,
        createdAt: now,
        updatedAt: now,
      );

      expect(note.isRepeating, isTrue);
      expect(note.repeatFrequency, RepeatFrequency.monthly);
      expect(note.repeatUntil, repeatUntil);
      expect(note.hasUpcomingReminder(DateTime(2026, 11, 15)), isTrue);
      expect(note.hasUpcomingReminder(DateTime(2027, 1, 1)), isFalse);

      final map = note.toMap();
      expect(map['repeat_frequency'], 'monthly');
      expect(map['repeat_until'], repeatUntil.millisecondsSinceEpoch);

      final restored = Note.fromMap(map);
      expect(restored.isRepeating, isTrue);
      expect(restored.repeatFrequency, RepeatFrequency.monthly);
      expect(restored.repeatUntil, repeatUntil);

      final cleared = note.copyWith(clearRepeat: true, clearRepeatUntil: true);
      expect(cleared.isRepeating, isFalse);
      expect(cleared.repeatFrequency, isNull);
      expect(cleared.repeatUntil, isNull);
    });
  });

  group('DebtEntry & Split Bill Store', () {
    test('debt validation and serialization', () {
      final debt = DebtEntry(
        personName: 'Ravi',
        amountMinor: 50000,
        type: DebtType.lent,
        note: 'Dinner split',
        dueDate: DateTime(2026, 11, 20),
        createdAt: now,
        updatedAt: now,
      );

      expect(debt.validate(), isEmpty);
      expect(debt.isLent, isTrue);
      expect(debt.isBorrowed, isFalse);
      expect(debt.isOverdue(DateTime(2026, 11, 25)), isTrue);
      expect(debt.isOverdue(DateTime(2026, 11, 15)), isFalse);

      final map = debt.toMap();
      final restored = DebtEntry.fromMap(map);
      expect(restored.personName, 'Ravi');
      expect(restored.amountMinor, 50000);
      expect(restored.type, DebtType.lent);
      expect(restored.note, 'Dinner split');
      expect(restored.dueDate, DateTime(2026, 11, 20));
      expect(restored.isSettled, isFalse);
    });

    test('add, update, settle and delete debts in store', () async {
      final s = await newStore();

      // Add a lent debt
      final lent = await s.addDebt(DebtEntry(
        personName: 'Sneha',
        amountMinor: 150000,
        type: DebtType.lent,
        note: 'Concert ticket',
        createdAt: now,
        updatedAt: now,
      ));

      // Add a borrowed debt
      final borrowed = await s.addDebt(DebtEntry(
        personName: 'Vikram',
        amountMinor: 50000,
        type: DebtType.borrowed,
        note: 'Cab share',
        createdAt: now,
        updatedAt: now,
      ));

      expect(s.debts.length, 2);
      expect(s.pendingDebts.length, 2);
      expect(s.settledDebts.length, 0);
      expect(s.totalOwedToMeMinor, 150000);
      expect(s.totalIOweMinor, 50000);

      // Settle lent debt with auto transaction recording
      final txCountBefore = s.transactions.length;
      await s.settleDebt(lent, recordTransaction: true);

      expect(s.pendingDebts.length, 1);
      expect(s.settledDebts.length, 1);
      expect(s.totalOwedToMeMinor, 0);
      expect(s.transactions.length, txCountBefore + 1);
      expect(s.transactions.first.isIncome, isTrue);
      expect(s.transactions.first.amountMinor, 150000);

      // Settle borrowed debt with expense transaction
      await s.settleDebt(borrowed, recordTransaction: true);
      expect(s.pendingDebts.length, 0);
      expect(s.settledDebts.length, 2);
      expect(s.transactions.first.isExpense, isTrue);
      expect(s.transactions.first.amountMinor, 50000);

      // Delete debt
      await s.deleteDebt(lent);
      expect(s.debts.length, 1);
    });
  });

  group('AppSettings theme customizer', () {
    test('amoled and accent color serialization', () {
      const settings = AppSettings(
        amoledDark: true,
        accentColor: AppAccentColor.emerald,
      );

      final kvs = settings.toKeyValues();
      expect(kvs['amoled_dark'], '1');
      expect(kvs['accent_color'], 'emerald');

      final restored = AppSettings.fromKeyValues(kvs);
      expect(restored.amoledDark, isTrue);
      expect(restored.accentColor, AppAccentColor.emerald);
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
