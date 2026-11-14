import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;

import '../database/default_categories.dart';
import '../models/account.dart';
import '../models/app_settings.dart';
import '../models/backup_data.dart';
import '../models/category.dart';
import '../models/note.dart';
import '../models/recurring_rule.dart';
import '../models/transaction_entry.dart';
import '../repositories/finance_repository.dart';
import '../services/analytics_service.dart';
import '../services/budget_service.dart';
import '../services/csv_import_service.dart';
import '../utils/category_icons.dart';
import '../services/recurring_service.dart';
import '../services/reminder_service.dart';
import '../services/smart/categorizer.dart';
import '../services/smart/insights_engine.dart';
import '../services/smart/transaction_parser.dart';
import '../utils/money.dart';

/// A user-facing error from a store operation.
class StoreException implements Exception {
  const StoreException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Single source of truth for the UI. Holds an in-memory copy of the data
/// (fine for a personal ledger of thousands of rows) and writes through to
/// the [FinanceRepository].
class FinanceStore extends ChangeNotifier {
  FinanceStore(
    this._repo, {
    DateTime Function()? clock,
    ReminderScheduler reminders = const NoopReminderScheduler(),
  })  : _clock = clock ?? DateTime.now,
        _reminders = reminders;

  final FinanceRepository _repo;
  final DateTime Function() _clock;
  final ReminderScheduler _reminders;

  bool _loading = true;
  String? _loadError;
  List<Account> _accounts = const [];
  List<Category> _categories = const [];
  List<TransactionEntry> _transactions = const [];
  List<CategoryBudget> _budgets = const [];
  List<Note> _notes = const [];
  List<RecurringRule> _recurring = const [];
  String? _notice;
  AppSettings _settings = const AppSettings();
  Map<int, Category> _categoryIndex = const {};
  Map<int, Account> _accountIndex = const {};

  // Memoised smart helpers; rebuilt lazily after data changes.
  int _version = 0;
  int _insightsVersion = -1;
  DateTime? _insightsDay;
  List<Insight> _insights = const [];
  Categorizer? _categorizer;

  bool get isLoading => _loading;
  String? get loadError => _loadError;
  List<Account> get accounts => _accounts;
  List<Category> get categories => _categories;
  List<TransactionEntry> get transactions => _transactions;
  List<CategoryBudget> get budgets => _budgets;
  ReminderScheduler get reminders => _reminders;

  Account? accountById(int? id) => id == null ? null : _accountIndex[id];

  Account get defaultAccount {
    for (final a in _accounts) {
      if (a.isDefault) return a;
    }
    return _accounts.isNotEmpty
        ? _accounts.first
        : const Account(
            id: 1,
            name: 'Bank Account',
            iconKey: 'bank',
            colorValue: 0xFF4FC3F7,
            createdAt: null as dynamic,
            updatedAt: null as dynamic,
          );
  }

  /// Balance for a specific account considering income, expenses and transfers.
  int accountBalance(int accountId) {
    final acc = accountById(accountId);
    if (acc == null) return 0;
    var bal = acc.initialBalanceMinor;
    for (final t in _transactions) {
      if (t.accountId == accountId) {
        if (t.isIncome) {
          bal += t.amountMinor;
        } else if (t.isExpense || t.isTransfer) {
          bal -= t.amountMinor;
        }
      }
      if (t.isTransfer && t.toAccountId == accountId) {
        bal += t.amountMinor;
      }
    }
    return bal;
  }

  /// Net total balance across all accounts.
  int get totalBalanceMinor {
    if (_accounts.isEmpty) {
      return _settings.startingBalanceMinor +
          AnalyticsService.lifetime(_transactions).netMinor;
    }
    var total = 0;
    for (final a in _accounts) {
      final bal = accountBalance(a.id!);
      total += a.isCreditCard ? -bal.abs() : bal;
    }
    return total;
  }

  /// All unique tags found in transactions.
  List<String> get allTags {
    final set = <String>{};
    for (final t in _transactions) {
      set.addAll(t.tags);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Pinned first, then most recently edited.
  List<Note> get notes => _notes;

  /// Notes with a reminder still in the future, soonest first.
  List<Note> get upcomingReminders {
    final t = now;
    return _notes.where((n) => n.hasUpcomingReminder(t)).toList()
      ..sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));
  }

  Note? noteById(int id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }
  AppSettings get settings => _settings;

  /// Recurring rules, next due first.
  List<RecurringRule> get recurring => _recurring;

  RecurringRule? recurringById(int id) {
    for (final r in _recurring) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// A one-time message for the UI (e.g. "2 recurring transactions added").
  String? takeNotice() {
    final n = _notice;
    _notice = null;
    return n;
  }

  bool get hasNotice => _notice != null;
  CurrencyInfo get currency => CurrencyInfo.byCode(_settings.currencyCode);
  DateTime get now => _clock();
  bool get hasTransactions => _transactions.isNotEmpty;

  Category? categoryById(int id) => _categoryIndex[id];

  List<Category> categoriesOf(TransactionType kind) =>
      _categories.where((c) => c.kind == kind).toList();

  String format(int minor, {bool signed = false}) =>
      Money.format(minor, currency, signed: signed);

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      await _repo.init();
      await _reloadAll();
      _loadError = null;
      await runRecurring();
      await refreshDailyReminder();
    } catch (e, st) {
      debugPrint('PennyWise load failed: $e\n$st');
      _loadError = 'Could not open your data. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _reloadAll() async {
    final results = await Future.wait([
      _repo.getCategories(),
      _repo.getTransactions(),
      _repo.getBudgets(),
      _repo.getSettings(),
      _repo.getNotes(),
      _repo.getRecurring(),
      _repo.getAccounts(),
    ]);
    _categories = results[0] as List<Category>;
    _transactions = results[1] as List<TransactionEntry>;
    _budgets = results[2] as List<CategoryBudget>;
    _settings = AppSettings.fromKeyValues(results[3] as Map<String, String>);
    _notes = List<Note>.of(results[4] as List<Note>)
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    _recurring = results[5] as List<RecurringRule>;
    _accounts = results[6] as List<Account>;
    _categoryIndex = {for (final c in _categories) c.id!: c};
    _accountIndex = {for (final a in _accounts) a.id!: a};
    _version++;
    _categorizer = null;
  }

  Future<T> _guard<T>(String action, Future<T> Function() body) async {
    try {
      return await body();
    } on StoreException {
      rethrow;
    } catch (e, st) {
      debugPrint('PennyWise $action failed: $e\n$st');
      throw StoreException('Could not $action. Please try again.');
    }
  }

  // ------------------------------------------------------------------ accounts

  Future<Account> addAccount(Account account) {
    return _guard('create the account', () async {
      final problems = account.validate();
      if (problems.isNotEmpty) throw StoreException(problems.first);
      final dup = _accounts.any(
          (a) => a.name.toLowerCase() == account.name.trim().toLowerCase());
      if (dup) throw StoreException('Account "${account.name}" already exists.');
      final maxOrder =
          _accounts.fold<int>(0, (m, a) => a.sortOrder > m ? a.sortOrder : m);
      final created = await _repo.insertAccount(
        account.copyWith(
          name: account.name.trim(),
          sortOrder: maxOrder + 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _reloadAll();
      notifyListeners();
      return accountById(created.id!) ?? created;
    });
  }

  Future<void> updateAccount(Account account) {
    return _guard('update the account', () async {
      final problems = account.validate();
      if (problems.isNotEmpty) throw StoreException(problems.first);
      final dup = _accounts.any((a) =>
          a.id != account.id &&
          a.name.toLowerCase() == account.name.trim().toLowerCase());
      if (dup) throw StoreException('Account "${account.name}" already exists.');
      await _repo.updateAccount(
          account.copyWith(name: account.name.trim(), updatedAt: now));
      await _reloadAll();
      notifyListeners();
    });
  }

  Future<void> deleteAccount(Account account) {
    return _guard('delete the account', () async {
      if (account.isDefault) {
        throw const StoreException('You cannot delete the primary default account.');
      }
      final fallback = defaultAccount.id!;
      await _repo.deleteAccount(account.id!, reassignTo: fallback);
      await _reloadAll();
      notifyListeners();
    });
  }

  // ------------------------------------------------------------ transactions

  /// Saves a new transaction. Returns budgets that crossed a warning
  /// threshold because of it, so the UI can alert immediately.
  Future<List<BudgetStatus>> addTransaction(TransactionEntry entry) {
    return _guard('save the transaction', () async {
      var toSave = entry;
      if (toSave.accountId == null && _accounts.isNotEmpty) {
        toSave = toSave.copyWith(accountId: defaultAccount.id);
      }
      _validate(toSave);
      final before = budgetOverview();
      final stamp = now;
      await _repo.insertTransaction(
          toSave.copyWith(createdAt: stamp, updatedAt: stamp));
      await _reloadAll();
      notifyListeners();
      await refreshDailyReminder();
      if (!toSave.isExpense) return const <BudgetStatus>[];
      return BudgetService.newlyCrossed(before: before, after: budgetOverview());
    });
  }

  Future<void> updateTransaction(TransactionEntry entry) {
    return _guard('update the transaction', () async {
      if (entry.id == null) throw const StoreException('Unknown transaction.');
      _validate(entry);
      await _repo.updateTransaction(entry.copyWith(updatedAt: now));
      await _reloadAll();
      notifyListeners();
    });
  }

  Future<void> deleteTransaction(TransactionEntry entry) {
    return _guard('delete the transaction', () async {
      await _repo.deleteTransaction(entry.id!);
      await _reloadAll();
      notifyListeners();
    });
  }

  /// Re-inserts a deleted transaction (used by "Undo").
  Future<void> restoreTransaction(TransactionEntry entry) {
    return _guard('restore the transaction', () async {
      await _repo.insertTransaction(entry);
      await _reloadAll();
      notifyListeners();
    });
  }

  void _validate(TransactionEntry entry) {
    final errors = entry.validate();
    if (errors.isNotEmpty) throw StoreException(errors.first);
    if (entry.isTransfer) {
      if (entry.accountId == null || entry.toAccountId == null) {
        throw const StoreException('Please select source and destination accounts.');
      }
      if (entry.accountId == entry.toAccountId) {
        throw const StoreException('Source and destination accounts must be different.');
      }
      return;
    }
    final cat = categoryById(entry.categoryId);
    if (cat == null) throw const StoreException('Please choose a category.');
    if (cat.kind != entry.type) {
      throw const StoreException('Category does not match the type.');
    }
  }

  // -------------------------------------------------------------- categories

  Future<Category> addCategory(Category category) {
    return _guard('add the category', () async {
      final name = category.name.trim();
      _validateCategoryName(name, category.kind, exceptId: null);
      final maxOrder = _categories.fold<int>(
          0, (m, c) => c.sortOrder > m ? c.sortOrder : m);
      final stored = await _repo.insertCategory(
          category.copyWith(name: name, sortOrder: maxOrder + 1));
      await _reloadAll();
      notifyListeners();
      return stored;
    });
  }

  Future<void> updateCategory(Category category) {
    return _guard('update the category', () async {
      final name = category.name.trim();
      _validateCategoryName(name, category.kind, exceptId: category.id);
      await _repo.updateCategory(category.copyWith(name: name));
      await _reloadAll();
      notifyListeners();
    });
  }

  void _validateCategoryName(String name, TransactionType kind,
      {required int? exceptId}) {
    if (name.isEmpty) throw const StoreException('Please enter a name.');
    if (name.length > 30) {
      throw const StoreException('Name must be 30 characters or fewer.');
    }
    final dup = _categories.any((c) =>
        c.kind == kind &&
        c.id != exceptId &&
        c.name.toLowerCase() == name.toLowerCase());
    if (dup) throw StoreException('"$name" already exists.');
  }

  int transactionCountFor(int categoryId) =>
      _transactions.where((t) => t.categoryId == categoryId).length;

  /// The default "Other" category a deleted category's records move to.
  Category fallbackCategory(TransactionType kind) {
    final name = kind == TransactionType.expense
        ? DefaultCategoryNames.other
        : DefaultCategoryNames.otherIncome;
    return _categories.firstWhere(
      (c) => c.kind == kind && c.isDefault && c.name == name,
      orElse: () => _categories.firstWhere((c) => c.kind == kind && c.isDefault),
    );
  }

  Future<void> deleteCategory(Category category) {
    return _guard('delete the category', () async {
      if (category.isDefault) {
        throw const StoreException('Built-in categories cannot be deleted.');
      }
      final fallback = fallbackCategory(category.kind);
      await _repo.deleteCategory(category.id!, reassignTo: fallback.id!);
      await _reloadAll();
      notifyListeners();
    });
  }

  // -------------------------------------------------------------------- notes

  /// Creates or updates a note and (re)schedules its reminder.
  /// Returns false if the reminder could not be scheduled.
  Future<({Note note, bool reminderOk})> saveNote(Note note) {
    return _guard('save the note', () async {
      final errors = note.validate();
      if (errors.isNotEmpty) throw StoreException(errors.first);
      final stamp = now;
      final Note stored;
      if (note.id == null) {
        stored = await _repo.insertNote(
            note.copyWith(createdAt: stamp, updatedAt: stamp));
      } else {
        stored = note.copyWith(updatedAt: stamp);
        await _repo.updateNote(stored);
      }
      await _reloadAll();
      notifyListeners();
      final ok = await _reminders.schedule(stored);
      return (note: stored, reminderOk: ok);
    });
  }

  Future<void> setNotePinned(Note note, bool pinned) {
    return _guard('update the note', () async {
      await _repo.updateNote(note.copyWith(pinned: pinned));
      await _reloadAll();
      notifyListeners();
    });
  }

  Future<void> deleteNote(Note note) {
    return _guard('delete the note', () async {
      await _repo.deleteNote(note.id!);
      await _reminders.cancel(note.id!);
      await _reloadAll();
      notifyListeners();
    });
  }

  /// Re-creates a deleted note (used by "Undo").
  Future<void> restoreNote(Note note) async {
    await saveNote(Note(
      title: note.title,
      body: note.body,
      pinned: note.pinned,
      reminderAt: note.reminderAt,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
    ));
  }

  // ------------------------------------------------------------------ budgets

  BudgetOverview budgetOverview() => BudgetService.compute(
        transactions: _transactions,
        budgets: _budgets,
        monthlyBudgetMinor: _settings.monthlyBudgetMinor,
        now: now,
      );

  CategoryBudget? budgetFor(int categoryId) {
    for (final b in _budgets) {
      if (b.categoryId == categoryId) return b;
    }
    return null;
  }

  Future<void> setCategoryBudget(int categoryId, int amountMinor) {
    return _guard('save the budget', () async {
      if (amountMinor <= 0) {
        throw const StoreException('Budget must be greater than zero.');
      }
      await _repo.upsertBudget(
          CategoryBudget(categoryId: categoryId, amountMinor: amountMinor));
      await _reloadAll();
      notifyListeners();
    });
  }

  Future<void> removeCategoryBudget(int categoryId) {
    return _guard('remove the budget', () async {
      await _repo.deleteBudget(categoryId);
      await _reloadAll();
      notifyListeners();
    });
  }

  // ----------------------------------------------------------------- settings

  Future<void> updateSettings(AppSettings next) {
    return _guard('save settings', () async {
      final previous = _settings;
      _settings = next; // optimistic, so theme switches instantly
      notifyListeners();
      try {
        await _repo.saveSettings(next.toKeyValues());
        _version++;
        if (next.dailyReminder != previous.dailyReminder ||
            next.dailyReminderMinutes != previous.dailyReminderMinutes) {
          await refreshDailyReminder();
        }
      } catch (_) {
        _settings = previous;
        notifyListeners();
        rethrow;
      }
    });
  }

  // ---------------------------------------------------------------- recurring

  /// Adds every recurring transaction that has become due. Safe to call any
  /// time (app start, app resume). Returns how many were added.
  Future<int> runRecurring() async {
    final run = RecurringService.due(_recurring, now);
    if (run.isEmpty) return 0;
    try {
      await _repo.applyRecurring(run.created, run.updated);
      await _reloadAll();
      final n = run.created.length;
      _notice = n == 1
          ? '1 recurring transaction was added automatically.'
          : '$n recurring transactions were added automatically.';
      notifyListeners();
      return n;
    } catch (e, st) {
      debugPrint('PennyWise recurring failed: $e\n$st');
      return 0;
    }
  }

  /// Creates a recurring rule starting on [entry]'s date and adds the first
  /// transaction immediately if that date is today or earlier.
  Future<RecurringRule> addRecurring(
      TransactionEntry entry, RepeatFrequency frequency) {
    return _guard('set up the recurring transaction', () async {
      _validate(entry);
      final start = DateTime(entry.date.year, entry.date.month, entry.date.day);
      final rule = await _repo.insertRecurring(RecurringRule(
        type: entry.type,
        amountMinor: entry.amountMinor,
        categoryId: entry.categoryId,
        note: entry.note,
        paymentMethod: entry.paymentMethod,
        frequency: frequency,
        anchorDay: start.day,
        nextDue: start,
        createdAt: now,
      ));
      await _reloadAll();
      final run = RecurringService.due(_recurring, now);
      if (!run.isEmpty) {
        await _repo.applyRecurring(run.created, run.updated);
        await _reloadAll();
      }
      notifyListeners();
      await refreshDailyReminder();
      return recurringById(rule.id!) ?? rule;
    });
  }

  Future<void> updateRecurring(RecurringRule rule) {
    return _guard('update the recurring transaction', () async {
      if (rule.amountMinor <= 0 || rule.amountMinor > Money.maxMinor) {
        throw const StoreException('Enter an amount greater than zero.');
      }
      if (rule.note.length > 200) {
        throw const StoreException('Description is too long.');
      }
      await _repo.updateRecurring(rule);
      await _reloadAll();
      notifyListeners();
      if (rule.active) await runRecurring();
    });
  }

  Future<void> deleteRecurring(RecurringRule rule) {
    return _guard('delete the recurring transaction', () async {
      await _repo.deleteRecurring(rule.id!);
      await _reloadAll();
      notifyListeners();
    });
  }

  // ----------------------------------------------------------- daily reminder

  bool get loggedToday {
    final t = now;
    return _transactions.any((x) =>
        x.date.year == t.year && x.date.month == t.month && x.date.day == t.day);
  }

  /// Re-plans the daily "log your expenses" notifications. Today's is skipped
  /// once something has been logged for today.
  Future<void> refreshDailyReminder() async {
    try {
      await _reminders.scheduleDaily(_settings.dailyReminder
          ? RecurringService.dailyReminderTimes(
              now: now,
              minutesOfDay: _settings.dailyReminderMinutes,
              loggedToday: loggedToday,
            )
          : const []);
    } catch (e) {
      debugPrint('PennyWise daily reminder failed: $e');
    }
  }

  // ------------------------------------------------------------ smart helpers

  Categorizer get categorizer => _categorizer ??=
      Categorizer(categories: _categories, history: _transactions);

  TransactionParser get parser => TransactionParser(categorizer);

  List<Insight> get insights {
    final today = DateTime(now.year, now.month, now.day);
    if (_insightsVersion != _version || _insightsDay != today) {
      _insights = InsightsEngine(
        transactions: _transactions,
        categories: _categories,
        budgets: _budgets,
        monthlyBudgetMinor: _settings.monthlyBudgetMinor,
        currency: currency,
        now: now,
      ).generate();
      _insightsVersion = _version;
      _insightsDay = today;
    }
    return _insights;
  }

  // -------------------------------------------------------------- bulk data

  BackupData snapshot() => BackupData(
        accounts: _accounts,
        categories: _categories,
        transactions: _transactions,
        budgets: _budgets,
        settings: _settings.toKeyValues(),
        notes: _notes,
        recurring: _recurring,
        exportedAt: now,
      );

  Future<void> restore(BackupData data) {
    return _guard('restore the backup', () async {
      final old = _notes;
      await _repo.replaceAll(data);
      await _repo.init();
      await _reloadAll();
      notifyListeners();
      await _resyncReminders(old);
    });
  }

  Future<void> clearAll() {
    return _guard('clear your data', () async {
      final old = _notes;
      await _repo.clearAll();
      await _reloadAll();
      notifyListeners();
      await _resyncReminders(old);
    });
  }

  Future<void> _resyncReminders(List<Note> previous) async {
    for (final n in previous) {
      if (n.id != null) await _reminders.cancel(n.id!);
    }
    for (final n in _notes) {
      await _reminders.schedule(n);
    }
    await runRecurring();
    await refreshDailyReminder();
  }

  /// Adds transactions from a CSV export to the current data. Missing
  /// categories are created; rows already present are skipped, so importing
  /// the same file twice is harmless. Returns (added, skipped).
  Future<({int added, int skipped})> importCsv(List<CsvTransaction> rows) {
    return _guard('import the CSV file', () async {
      // 1. Make sure every category exists.
      var colour = 0;
      for (final r in rows) {
        final exists = _categories.any((c) =>
            c.kind == r.type &&
            c.name.toLowerCase() == r.categoryName.toLowerCase());
        if (exists) continue;
        final name = r.categoryName.length > 30
            ? r.categoryName.substring(0, 30)
            : r.categoryName;
        await _repo.insertCategory(Category(
          name: name,
          iconKey: 'other',
          colorValue:
              CategoryIcons.palette[colour++ % CategoryIcons.palette.length],
          kind: r.type,
          sortOrder: 1000 + colour,
        ));
        await _reloadAll();
      }

      // 2. Build transactions, skipping exact duplicates.
      String key(DateTime d, TransactionType t, int amount, int cat, String n) =>
          '${d.year}-${d.month}-${d.day}|${t.name}|$amount|$cat|${n.trim()}';
      final existing = {
        for (final t in _transactions)
          key(t.date, t.type, t.amountMinor, t.categoryId, t.note),
      };
      final stamp = now;
      final toAdd = <TransactionEntry>[];
      var skipped = 0;
      for (final r in rows) {
        final cat = _categories.firstWhere((c) =>
            c.kind == r.type &&
            c.name.toLowerCase() ==
                (r.categoryName.length > 30
                        ? r.categoryName.substring(0, 30)
                        : r.categoryName)
                    .toLowerCase());
        final k = key(r.date, r.type, r.amountMinor, cat.id!, r.note);
        if (!existing.add(k)) {
          skipped++;
          continue;
        }
        toAdd.add(TransactionEntry(
          type: r.type,
          amountMinor: r.amountMinor,
          categoryId: cat.id!,
          note: r.note.length > 200 ? r.note.substring(0, 200) : r.note,
          date: r.date,
          paymentMethod: r.paymentMethod,
          createdAt: stamp,
          updatedAt: stamp,
        ));
      }
      if (toAdd.isNotEmpty) await _repo.insertTransactions(toAdd);
      await _reloadAll();
      notifyListeners();
      await refreshDailyReminder();
      return (added: toAdd.length, skipped: skipped);
    });
  }

  Future<void> insertMany(List<TransactionEntry> entries) {
    return _guard('add transactions', () async {
      await _repo.insertTransactions(entries);
      await _reloadAll();
      notifyListeners();
    });
  }
}
