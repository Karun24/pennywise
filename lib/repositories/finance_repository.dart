import '../models/backup_data.dart';
import '../models/category.dart';
import '../models/note.dart';
import '../models/transaction_entry.dart';

/// Storage abstraction used by the app's state layer.
///
/// The UI never talks to SQLite directly. This keeps a clean seam for
/// adding cloud sync later (e.g. a `SyncingFinanceRepository` that wraps the
/// local one) and lets tests use [InMemoryFinanceRepository].
abstract class FinanceRepository {
  /// Prepares storage and seeds default categories on first run.
  Future<void> init();

  Future<List<Category>> getCategories();
  Future<Category> insertCategory(Category category);
  Future<void> updateCategory(Category category);

  /// Deletes a custom category, first moving its transactions to
  /// [reassignTo] and dropping its budget. Runs atomically.
  Future<void> deleteCategory(int id, {required int reassignTo});

  Future<List<TransactionEntry>> getTransactions();
  Future<TransactionEntry> insertTransaction(TransactionEntry entry);
  Future<void> insertTransactions(List<TransactionEntry> entries);
  Future<void> updateTransaction(TransactionEntry entry);
  Future<void> deleteTransaction(int id);

  Future<List<CategoryBudget>> getBudgets();
  Future<void> upsertBudget(CategoryBudget budget);
  Future<void> deleteBudget(int categoryId);

  Future<List<Note>> getNotes();
  Future<Note> insertNote(Note note);
  Future<void> updateNote(Note note);
  Future<void> deleteNote(int id);

  Future<Map<String, String>> getSettings();
  Future<void> saveSettings(Map<String, String> values);

  /// Atomically replaces every record with [data] (used by restore).
  Future<void> replaceAll(BackupData data);

  /// Deletes all user data and re-seeds default categories.
  Future<void> clearAll();
}
