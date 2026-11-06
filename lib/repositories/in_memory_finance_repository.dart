import '../database/default_categories.dart';
import '../models/backup_data.dart';
import '../models/category.dart';
import '../models/note.dart';
import '../models/transaction_entry.dart';
import 'finance_repository.dart';

/// Volatile implementation used by tests (and usable as a fallback).
class InMemoryFinanceRepository implements FinanceRepository {
  final List<Category> _categories = [];
  final List<TransactionEntry> _transactions = [];
  final Map<int, CategoryBudget> _budgets = {};
  final Map<String, String> _settings = {};
  final List<Note> _notes = [];
  int _nextCategoryId = 1;
  int _nextTransactionId = 1;
  int _nextNoteId = 1;

  @override
  Future<void> init() async {
    if (_categories.isEmpty) _seed();
  }

  void _seed() {
    for (final c in buildDefaultCategories()) {
      _categories.add(c.copyWith(id: _nextCategoryId++));
    }
  }

  @override
  Future<List<Category>> getCategories() async {
    final list = List<Category>.of(_categories)
      ..sort((a, b) => a.sortOrder != b.sortOrder
          ? a.sortOrder.compareTo(b.sortOrder)
          : a.id!.compareTo(b.id!));
    return list;
  }

  @override
  Future<Category> insertCategory(Category category) async {
    final dup = _categories.any((c) =>
        c.kind == category.kind &&
        c.name.toLowerCase() == category.name.toLowerCase());
    if (dup) throw StateError('Category already exists');
    final stored = category.copyWith(id: _nextCategoryId++);
    _categories.add(stored);
    return stored;
  }

  @override
  Future<void> updateCategory(Category category) async {
    final i = _categories.indexWhere((c) => c.id == category.id);
    if (i >= 0) _categories[i] = category;
  }

  @override
  Future<void> deleteCategory(int id, {required int reassignTo}) async {
    for (var i = 0; i < _transactions.length; i++) {
      if (_transactions[i].categoryId == id) {
        _transactions[i] = _transactions[i].copyWith(categoryId: reassignTo);
      }
    }
    _budgets.remove(id);
    _categories.removeWhere((c) => c.id == id && !c.isDefault);
  }

  @override
  Future<List<TransactionEntry>> getTransactions() async {
    final list = List<TransactionEntry>.of(_transactions)
      ..sort((a, b) {
        final d = b.date.compareTo(a.date);
        return d != 0 ? d : b.id!.compareTo(a.id!);
      });
    return list;
  }

  @override
  Future<TransactionEntry> insertTransaction(TransactionEntry entry) async {
    final stored = entry.copyWith(id: _nextTransactionId++);
    _transactions.add(stored);
    return stored;
  }

  @override
  Future<void> insertTransactions(List<TransactionEntry> entries) async {
    for (final e in entries) {
      await insertTransaction(e);
    }
  }

  @override
  Future<void> updateTransaction(TransactionEntry entry) async {
    final i = _transactions.indexWhere((t) => t.id == entry.id);
    if (i < 0) throw StateError('Transaction ${entry.id} no longer exists.');
    _transactions[i] = entry;
  }

  @override
  Future<void> deleteTransaction(int id) async {
    _transactions.removeWhere((t) => t.id == id);
  }

  @override
  Future<List<CategoryBudget>> getBudgets() async => _budgets.values.toList();

  @override
  Future<void> upsertBudget(CategoryBudget budget) async {
    _budgets[budget.categoryId] = budget;
  }

  @override
  Future<void> deleteBudget(int categoryId) async {
    _budgets.remove(categoryId);
  }

  @override
  Future<List<Note>> getNotes() async => List<Note>.of(_notes)
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<Note> insertNote(Note note) async {
    final stored = note.copyWith(id: _nextNoteId++);
    _notes.add(stored);
    return stored;
  }

  @override
  Future<void> updateNote(Note note) async {
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i < 0) throw StateError('Note ${note.id} no longer exists.');
    _notes[i] = note;
  }

  @override
  Future<void> deleteNote(int id) async {
    _notes.removeWhere((n) => n.id == id);
  }

  @override
  Future<Map<String, String>> getSettings() async => Map.of(_settings);

  @override
  Future<void> saveSettings(Map<String, String> values) async {
    _settings.addAll(values);
  }

  @override
  Future<void> replaceAll(BackupData data) async {
    _categories
      ..clear()
      ..addAll(data.categories);
    _transactions
      ..clear()
      ..addAll(data.transactions);
    _budgets
      ..clear()
      ..addEntries(data.budgets.map((b) => MapEntry(b.categoryId, b)));
    _settings
      ..clear()
      ..addAll(data.settings);
    _notes
      ..clear()
      ..addAll(data.notes);
    int maxId(Iterable<int?> ids) =>
        ids.fold<int>(0, (m, id) => (id ?? 0) > m ? id! : m);
    _nextCategoryId = maxId(_categories.map((c) => c.id)) + 1;
    _nextTransactionId = maxId(_transactions.map((t) => t.id)) + 1;
    _nextNoteId = maxId(_notes.map((n) => n.id)) + 1;
  }

  @override
  Future<void> clearAll() async {
    _categories.clear();
    _transactions.clear();
    _budgets.clear();
    _settings.clear();
    _notes.clear();
    _nextCategoryId = 1;
    _nextTransactionId = 1;
    _nextNoteId = 1;
    _seed();
  }
}
