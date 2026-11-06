import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'default_categories.dart';

/// Owns the SQLite schema and migrations.
///
/// The database file lives in the app's private storage, which other apps
/// cannot read and which requires no Android permissions.
class AppDatabase {
  AppDatabase._();

  static const fileName = 'pennywise.db';

  /// Bump this and add a step in [_onUpgrade] whenever the schema changes.
  static const schemaVersion = 1;

  static const tCategories = 'categories';
  static const tTransactions = 'transactions';
  static const tBudgets = 'category_budgets';
  static const tSettings = 'settings';

  static Future<Database> open({String? overridePath}) async {
    final path = overridePath ?? p.join(await getDatabasesPath(), fileName);
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
        await seedDefaultCategories(db);
      },
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE $tCategories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE,
        icon_key TEXT NOT NULL,
        color INTEGER NOT NULL,
        kind TEXT NOT NULL CHECK (kind IN ('expense', 'income')),
        is_default INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        UNIQUE (name, kind)
      )
    ''');
    await db.execute('''
      CREATE TABLE $tTransactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL CHECK (type IN ('expense', 'income')),
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        category_id INTEGER NOT NULL
          REFERENCES $tCategories(id) ON DELETE RESTRICT,
        note TEXT NOT NULL DEFAULT '',
        payment_method TEXT NOT NULL DEFAULT 'other',
        occurred_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_tx_occurred_at ON $tTransactions(occurred_at)');
    await db.execute(
        'CREATE INDEX idx_tx_category ON $tTransactions(category_id)');
    await db.execute('''
      CREATE TABLE $tBudgets (
        category_id INTEGER PRIMARY KEY
          REFERENCES $tCategories(id) ON DELETE CASCADE,
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0)
      )
    ''');
    await db.execute('''
      CREATE TABLE $tSettings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    // Example for the future:
    // if (oldVersion < 2) { await db.execute('ALTER TABLE ...'); }
  }

  static Future<void> seedDefaultCategories(DatabaseExecutor db) async {
    final batch = db.batch();
    for (final c in buildDefaultCategories()) {
      batch.insert(tCategories, c.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }
}
