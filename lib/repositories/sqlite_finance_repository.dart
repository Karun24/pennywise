import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/backup_data.dart';
import '../models/category.dart';
import '../models/transaction_entry.dart';
import 'finance_repository.dart';

/// SQLite-backed implementation of [FinanceRepository].
class SqliteFinanceRepository implements FinanceRepository {
  SqliteFinanceRepository(this._db);

  final Database _db;

  static const _c = AppDatabase.tCategories;
  static const _t = AppDatabase.tTransactions;
  static const _b = AppDatabase.tBudgets;
  static const _s = AppDatabase.tSettings;

  @override
  Future<void> init() async {
    final count = Sqflite.firstIntValue(
            await _db.rawQuery('SELECT COUNT(*) FROM $_c')) ??
        0;
    if (count == 0) await AppDatabase.seedDefaultCategories(_db);
  }

  // ---------------------------------------------------------------- categories

  @override
  Future<List<Category>> getCategories() async {
    final rows = await _db.query(_c, orderBy: 'sort_order ASC, id ASC');
    return rows.map(Category.fromMap).toList();
  }

  @override
  Future<Category> insertCategory(Category category) async {
    final id = await _db.insert(_c, category.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.abort);
    return category.copyWith(id: id);
  }

  @override
  Future<void> updateCategory(Category category) async {
    await _db.update(_c, category.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [category.id]);
  }

  @override
  Future<void> deleteCategory(int id, {required int reassignTo}) async {
    await _db.transaction((txn) async {
      await txn.update(_t, {'category_id': reassignTo},
          where: 'category_id = ?', whereArgs: [id]);
      await txn.delete(_b, where: 'category_id = ?', whereArgs: [id]);
      await txn.delete(_c, where: 'id = ? AND is_default = 0', whereArgs: [id]);
    });
  }

  // -------------------------------------------------------------- transactions

  @override
  Future<List<TransactionEntry>> getTransactions() async {
    final rows = await _db.query(_t, orderBy: 'occurred_at DESC, id DESC');
    return rows.map(TransactionEntry.fromMap).toList();
  }

  @override
  Future<TransactionEntry> insertTransaction(TransactionEntry entry) async {
    final id = await _db.insert(_t, entry.toMap()..remove('id'));
    return entry.copyWith(id: id);
  }

  @override
  Future<void> insertTransactions(List<TransactionEntry> entries) async {
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final e in entries) {
        batch.insert(_t, e.toMap()..remove('id'));
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> updateTransaction(TransactionEntry entry) async {
    final changed = await _db.update(_t, entry.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [entry.id]);
    if (changed == 0) {
      throw StateError('Transaction ${entry.id} no longer exists.');
    }
  }

  @override
  Future<void> deleteTransaction(int id) async {
    await _db.delete(_t, where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------- budgets

  @override
  Future<List<CategoryBudget>> getBudgets() async {
    final rows = await _db.query(_b);
    return rows.map(CategoryBudget.fromMap).toList();
  }

  @override
  Future<void> upsertBudget(CategoryBudget budget) async {
    await _db.insert(_b, budget.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteBudget(int categoryId) async {
    await _db.delete(_b, where: 'category_id = ?', whereArgs: [categoryId]);
  }

  // ------------------------------------------------------------------ settings

  @override
  Future<Map<String, String>> getSettings() async {
    final rows = await _db.query(_s);
    return {
      for (final r in rows) r['key'] as String: (r['value'] as String?) ?? '',
    };
  }

  @override
  Future<void> saveSettings(Map<String, String> values) async {
    await _db.transaction((txn) async {
      final batch = txn.batch();
      values.forEach((k, v) {
        batch.insert(_s, {'key': k, 'value': v},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });
      await batch.commit(noResult: true);
    });
  }

  // ------------------------------------------------------------- bulk actions

  @override
  Future<void> replaceAll(BackupData data) async {
    await _db.transaction((txn) async {
      await txn.delete(_b);
      await txn.delete(_t);
      await txn.delete(_c);
      await txn.delete(_s);
      final batch = txn.batch();
      for (final c in data.categories) {
        batch.insert(_c, c.toMap());
      }
      for (final t in data.transactions) {
        batch.insert(_t, t.toMap());
      }
      for (final b in data.budgets) {
        batch.insert(_b, b.toMap());
      }
      data.settings.forEach((k, v) {
        batch.insert(_s, {'key': k, 'value': v});
      });
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> clearAll() async {
    await _db.transaction((txn) async {
      await txn.delete(_b);
      await txn.delete(_t);
      await txn.delete(_c);
      await txn.delete(_s);
      await AppDatabase.seedDefaultCategories(txn);
    });
  }
}
