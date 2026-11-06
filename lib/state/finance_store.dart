import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;

import '../database/default_categories.dart';
import '../models/app_settings.dart';
import '../models/backup_data.dart';
import '../models/category.dart';
import '../models/note.dart';
import '../models/transaction_entry.dart';
import '../repositories/finance_repository.dart';
import '../services/budget_service.dart';
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
  List<Category> _categories = const [];
  List<TransactionEntry> _transactions = const [];
  List<CategoryBudget> _budgets = const [];
  List<Note> _notes = const [];
  AppSettings _settings = const AppSettings();
  Map<int, Category> _categoryIndex = const {};

  // Memoised smart helpers; rebuilt lazily after data changes.
  int _version = 0;
  int _insightsVersion = -1;
  DateTime? _insightsDay;
  List<Insight> _insights = const [];
  Categorizer? _categorizer;

  bool get isLoading => _loading;
  String? get loadError => _loadError;
  List<Category> get categories => _categories;
  List<TransactionEntry> get transactions => _transactions;
  List<CategoryBudget> get budgets => _budgets;
  ReminderScheduler get reminders => _reminders;

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
    _categoryIndex = {for (final c in _categories) c.id!: c};
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

  // ------------------------------------------------------------ transactions

  /// Saves a new transaction. Returns budgets that crossed a warning
  /// threshold because of it, so the UI can alert immediately.
  Future<List<BudgetStatus>> addTransaction(TransactionEntry entry) {
    return _guard('save the transaction', () async {
      _validate(entry);
      final before = budgetOverview();
      final stamp = now;
      await _repo.insertTransaction(
          entry.copyWith(createdAt: stamp, updatedAt: stamp));
      await _reloadAll();
      notifyListeners();
      if (!entry.isExpense) return const <BudgetStatus>[];
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
      } catch (_) {
        _settings = previous;
        notifyListeners();
        rethrow;
      }
    });
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
        categories: _categories,
        transactions: _transactions,
        budgets: _budgets,
        settings: _settings.toKeyValues(),
        notes: _notes,
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
  }

  Future<void> insertMany(List<TransactionEntry> entries) {
    return _guard('add transactions', () async {
      await _repo.insertTransactions(entries);
      await _reloadAll();
      notifyListeners();
    });
  }
}
