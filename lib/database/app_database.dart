import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/account.dart';
import 'default_categories.dart';

/// Owns the SQLite schema and migrations.
///
/// The database file lives in the app's private storage, which other apps
/// cannot read and which requires no Android permissions.
class AppDatabase {
  AppDatabase._();

  static const fileName = 'pennywise.db';

  /// Bump this and add a step in [_onUpgrade] whenever the schema changes.
  static const schemaVersion = 7;

  static const tCategories = 'categories';
  static const tTransactions = 'transactions';
  static const tBudgets = 'category_budgets';
  static const tSettings = 'settings';
  static const tNotes = 'notes';
  static const tRecurring = 'recurring';
  static const tAccounts = 'accounts';
  static const tGoals = 'goals';
  static const tDebts = 'debts';

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
        await seedDefaultAccounts(db);
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
    await _createAccounts(db);
    await db.execute('''
      CREATE TABLE $tTransactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL CHECK (type IN ('expense', 'income', 'transfer')),
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        category_id INTEGER NOT NULL
          REFERENCES $tCategories(id) ON DELETE RESTRICT,
        note TEXT NOT NULL DEFAULT '',
        payment_method TEXT NOT NULL DEFAULT 'other',
        occurred_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        recurring_id INTEGER,
        account_id INTEGER
          REFERENCES $tAccounts(id) ON DELETE SET NULL,
        to_account_id INTEGER
          REFERENCES $tAccounts(id) ON DELETE SET NULL,
        tag TEXT NOT NULL DEFAULT '',
        receipt_path TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_tx_occurred_at ON $tTransactions(occurred_at)');
    await db.execute(
        'CREATE INDEX idx_tx_category ON $tTransactions(category_id)');
    await db.execute(
        'CREATE INDEX idx_tx_account ON $tTransactions(account_id)');
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
    await _createNotes(db);
    await _createRecurring(db);
    await _createGoals(db);
    await _createDebts(db);
  }

  /// Added in schema version 7.
  static Future<void> _createDebts(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tDebts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        person_name TEXT NOT NULL,
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        type TEXT NOT NULL CHECK (type IN ('lent', 'borrowed')),
        note TEXT NOT NULL DEFAULT '',
        due_date INTEGER,
        is_settled INTEGER NOT NULL DEFAULT 0,
        settled_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  /// Added in schema version 5.
  static Future<void> _createGoals(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tGoals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE,
        target_minor INTEGER NOT NULL CHECK (target_minor > 0),
        saved_minor INTEGER NOT NULL DEFAULT 0,
        target_date INTEGER,
        color INTEGER NOT NULL,
        icon_key TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        completed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  /// Added in schema version 4.
  static Future<void> _createAccounts(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tAccounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE,
        type TEXT NOT NULL,
        icon_key TEXT NOT NULL,
        color INTEGER NOT NULL,
        initial_balance_minor INTEGER NOT NULL DEFAULT 0,
        is_default INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        UNIQUE (name)
      )
    ''');
  }

  /// Added in schema version 3.
  static Future<void> _createRecurring(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tRecurring (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL CHECK (type IN ('expense', 'income')),
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        category_id INTEGER NOT NULL
          REFERENCES $tCategories(id) ON DELETE RESTRICT,
        note TEXT NOT NULL DEFAULT '',
        payment_method TEXT NOT NULL DEFAULT 'other',
        frequency TEXT NOT NULL,
        anchor_day INTEGER NOT NULL,
        next_due INTEGER NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  /// Added in schema version 2.
  static Future<void> _createNotes(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tNotes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        pinned INTEGER NOT NULL DEFAULT 0,
        reminder_at INTEGER,
        repeat_frequency TEXT,
        repeat_until INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    // Each step upgrades existing users' data without losing anything.
    if (oldVersion < 2) await _createNotes(db);
    if (oldVersion < 3) {
      await db.execute(
          'ALTER TABLE $tTransactions ADD COLUMN recurring_id INTEGER');
      await _createRecurring(db);
    }
    if (oldVersion < 4) {
      await _createAccounts(db);
      await seedDefaultAccounts(db);
      // Migrate transactions table to support 'transfer' type and account columns.
      await db.execute('''
        CREATE TABLE new_tx (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL CHECK (type IN ('expense', 'income', 'transfer')),
          amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
          category_id INTEGER NOT NULL
            REFERENCES $tCategories(id) ON DELETE RESTRICT,
          note TEXT NOT NULL DEFAULT '',
          payment_method TEXT NOT NULL DEFAULT 'other',
          occurred_at INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          recurring_id INTEGER,
          account_id INTEGER
            REFERENCES $tAccounts(id) ON DELETE SET NULL,
          to_account_id INTEGER
            REFERENCES $tAccounts(id) ON DELETE SET NULL,
          tag TEXT NOT NULL DEFAULT ''
        )
      ''');
      await db.execute('''
        INSERT INTO new_tx (id, type, amount_minor, category_id, note, payment_method, occurred_at, created_at, updated_at, recurring_id, account_id, to_account_id, tag)
        SELECT id, type, amount_minor, category_id, note, payment_method, occurred_at, created_at, updated_at, recurring_id, 1, NULL, ''
        FROM $tTransactions
      ''');
      await db.execute('DROP TABLE $tTransactions');
      await db.execute('ALTER TABLE new_tx RENAME TO $tTransactions');
      await db.execute(
          'CREATE INDEX idx_tx_occurred_at ON $tTransactions(occurred_at)');
      await db.execute(
          'CREATE INDEX idx_tx_category ON $tTransactions(category_id)');
      await db.execute(
          'CREATE INDEX idx_tx_account ON $tTransactions(account_id)');
    }
    if (oldVersion < 5) {
      await _createGoals(db);
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE $tTransactions ADD COLUMN receipt_path TEXT');
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE $tNotes ADD COLUMN repeat_frequency TEXT');
      await db.execute('ALTER TABLE $tNotes ADD COLUMN repeat_until INTEGER');
      await _createDebts(db);
    }
  }

  static List<Account> buildDefaultAccounts({int startingBalanceMinor = 0}) {
    final now = DateTime.now();
    return [
      Account(
        name: 'Bank Account',
        type: AccountType.regular,
        iconKey: 'bank',
        colorValue: 0xFF4FC3F7,
        initialBalanceMinor: startingBalanceMinor,
        isDefault: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
      Account(
        name: 'Cash',
        type: AccountType.cash,
        iconKey: 'wallet',
        colorValue: 0xFF81C784,
        initialBalanceMinor: 0,
        isDefault: false,
        sortOrder: 1,
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  static Future<void> seedDefaultAccounts(DatabaseExecutor db) async {
    final batch = db.batch();
    for (final a in buildDefaultAccounts()) {
      batch.insert(tAccounts, a.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
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
