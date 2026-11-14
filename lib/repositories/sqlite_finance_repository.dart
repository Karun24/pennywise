import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/account.dart';
import '../models/backup_data.dart';
import '../models/category.dart';
import '../models/goal.dart';
import '../models/note.dart';
import '../models/recurring_rule.dart';
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
  static const _n = AppDatabase.tNotes;
  static const _r = AppDatabase.tRecurring;
  static const _a = AppDatabase.tAccounts;
  static const _g = AppDatabase.tGoals;

  @override
  Future<void> init() async {
    final count = Sqflite.firstIntValue(
            await _db.rawQuery('SELECT COUNT(*) FROM $_c')) ??
        0;
    if (count == 0) await AppDatabase.seedDefaultCategories(_db);

    final aCount = Sqflite.firstIntValue(
            await _db.rawQuery('SELECT COUNT(*) FROM $_a')) ??
        0;
    if (aCount == 0) await AppDatabase.seedDefaultAccounts(_db);
  }

  // ------------------------------------------------------------------ accounts

  @override
  Future<List<Account>> getAccounts() async {
    final rows = await _db.query(_a, orderBy: 'sort_order ASC, id ASC');
    return rows.map(Account.fromMap).toList();
  }

  @override
  Future<Account> insertAccount(Account account) async {
    final id = await _db.insert(_a, account.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.abort);
    return account.copyWith(id: id);
  }

  @override
  Future<void> updateAccount(Account account) async {
    await _db.update(_a, account.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [account.id]);
  }

  @override
  Future<void> deleteAccount(int id, {required int reassignTo}) async {
    await _db.transaction((txn) async {
      await txn.update(_t, {'account_id': reassignTo},
          where: 'account_id = ?', whereArgs: [id]);
      await txn.update(_t, {'to_account_id': reassignTo},
          where: 'to_account_id = ?', whereArgs: [id]);
      await txn.delete(_a, where: 'id = ? AND is_default = 0', whereArgs: [id]);
    });
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
      await txn.update(_r, {'category_id': reassignTo},
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

  // --------------------------------------------------------------------- notes

  @override
  Future<List<Note>> getNotes() async {
    final rows = await _db.query(_n, orderBy: 'updated_at DESC, id DESC');
    return rows.map(Note.fromMap).toList();
  }

  @override
  Future<Note> insertNote(Note note) async {
    final id = await _db.insert(_n, note.toMap()..remove('id'));
    return note.copyWith(id: id);
  }

  @override
  Future<void> updateNote(Note note) async {
    final changed = await _db.update(_n, note.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [note.id]);
    if (changed == 0) throw StateError('Note ${note.id} no longer exists.');
  }

  @override
  Future<void> deleteNote(int id) async {
    await _db.delete(_n, where: 'id = ?', whereArgs: [id]);
  }

  // ----------------------------------------------------------------- recurring

  @override
  Future<List<RecurringRule>> getRecurring() async {
    final rows = await _db.query(_r, orderBy: 'next_due ASC, id ASC');
    return rows.map(RecurringRule.fromMap).toList();
  }

  @override
  Future<RecurringRule> insertRecurring(RecurringRule rule) async {
    final id = await _db.insert(_r, rule.toMap()..remove('id'));
    return rule.copyWith(id: id);
  }

  @override
  Future<void> updateRecurring(RecurringRule rule) async {
    await _db.update(_r, rule.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [rule.id]);
  }

  @override
  Future<void> deleteRecurring(int id) async {
    await _db.transaction((txn) async {
      await txn.update(_t, {'recurring_id': null},
          where: 'recurring_id = ?', whereArgs: [id]);
      await txn.delete(_r, where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<void> applyRecurring(
      List<TransactionEntry> created, List<RecurringRule> updated) async {
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final t in created) {
        batch.insert(_t, t.toMap()..remove('id'));
      }
      for (final r in updated) {
        batch.update(_r, {'next_due': r.nextDue.millisecondsSinceEpoch},
            where: 'id = ?', whereArgs: [r.id]);
      }
      await batch.commit(noResult: true);
    });
  }

  // -------------------------------------------------------------------- goals

  @override
  Future<List<Goal>> getGoals() async {
    final rows = await _db.query(_g, orderBy: 'completed ASC, created_at DESC');
    return rows.map(Goal.fromMap).toList();
  }

  @override
  Future<Goal> insertGoal(Goal goal) async {
    final id = await _db.insert(_g, goal.toMap()..remove('id'));
    return goal.copyWith(id: id);
  }

  @override
  Future<void> updateGoal(Goal goal) async {
    await _db.update(_g, goal.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [goal.id]);
  }

  @override
  Future<void> deleteGoal(int id) async {
    await _db.delete(_g, where: 'id = ?', whereArgs: [id]);
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
      await txn.delete(_r);
      await txn.delete(_c);
      await txn.delete(_s);
      await txn.delete(_n);
      await txn.delete(_a);
      await txn.delete(_g);
      final batch = txn.batch();
      for (final a in data.accounts) {
        batch.insert(_a, a.toMap());
      }
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
      for (final n in data.notes) {
        batch.insert(_n, n.toMap());
      }
      for (final r in data.recurring) {
        batch.insert(_r, r.toMap());
      }
      for (final g in data.goals) {
        batch.insert(_g, g.toMap());
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> clearAll() async {
    await _db.transaction((txn) async {
      await txn.delete(_b);
      await txn.delete(_t);
      await txn.delete(_r);
      await txn.delete(_c);
      await txn.delete(_s);
      await txn.delete(_n);
      await txn.delete(_a);
      await txn.delete(_g);
      await AppDatabase.seedDefaultCategories(txn);
      await AppDatabase.seedDefaultAccounts(txn);
    });
  }
}
