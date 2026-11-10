import 'dart:convert';

import '../models/backup_data.dart';
import '../models/category.dart';
import '../models/note.dart';
import '../models/recurring_rule.dart';
import '../models/transaction_entry.dart';
import '../utils/money.dart';

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Serialises data to a versioned JSON backup and validates backups before
/// they are restored. Pure Dart, no I/O.
class BackupService {
  BackupService._();

  static const formatId = 'pennywise-backup';
  /// 1 = transactions/categories/budgets/settings, 2 = + notes,
  /// 3 = + recurring rules.
  static const formatVersion = 3;

  static String encode(BackupData data) {
    final json = {
      'format': formatId,
      'version': formatVersion,
      'exportedAt': (data.exportedAt ?? DateTime.now()).toIso8601String(),
      'categories': data.categories.map((c) => c.toMap()).toList(),
      'transactions': data.transactions.map((t) => t.toMap()).toList(),
      'budgets': data.budgets.map((b) => b.toMap()).toList(),
      'settings': data.settings,
      'notes': data.notes.map((n) => n.toMap()).toList(),
      'recurring': data.recurring.map((r) => r.toMap()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  /// Parses and validates [source]. Throws [BackupFormatException] with a
  /// user-readable message when anything is wrong; nothing is partially
  /// applied because validation happens before the database is touched.
  static BackupData decode(String source) {
    final Object? root;
    try {
      root = jsonDecode(source);
    } on FormatException {
      throw const BackupFormatException('This file is not valid JSON.');
    }
    if (root is! Map<String, dynamic>) {
      throw const BackupFormatException('Unrecognised backup file.');
    }
    final Map<String, dynamic> map = root;
    if (map['format'] != formatId) {
      throw const BackupFormatException(
          'This is not a PennyWise backup file.');
    }
    final version = map['version'];
    if (version is! int || version > formatVersion) {
      throw const BackupFormatException(
          'This backup was made by a newer version of PennyWise.');
    }

    List<Map<String, Object?>> list(String key) {
      final raw = map[key];
      if (raw is! List) throw BackupFormatException('Missing "$key" section.');
      return raw.map<Map<String, Object?>>((dynamic e) {
        if (e is! Map) throw BackupFormatException('Bad entry in "$key".');
        return <String, Object?>{
          for (final entry in e.entries) entry.key.toString(): entry.value,
        };
      }).toList();
    }

    try {
      final categories = list('categories').map(Category.fromMap).toList();
      final transactions =
          list('transactions').map(TransactionEntry.fromMap).toList();
      final budgets = list('budgets').map(CategoryBudget.fromMap).toList();
      final rawSettings = map['settings'];
      final settings = <String, String>{};
      if (rawSettings is Map) {
        rawSettings.forEach((k, v) => settings[k.toString()] = '${v ?? ''}');
      }

      // Notes were added in version 2; older backups simply have none.
      final notes = map['notes'] == null
          ? <Note>[]
          : list('notes').map(Note.fromMap).toList();
      final noteIds = <int>{};
      for (final n in notes) {
        if (n.id == null || !noteIds.add(n.id!)) {
          throw const BackupFormatException('Duplicate or missing note id.');
        }
      }

      final recurring = map['recurring'] == null
          ? <RecurringRule>[]
          : list('recurring').map(RecurringRule.fromMap).toList();
      final categoryKinds = {for (final c in categories) c.id: c.kind};
      final ruleIds = <int>{};
      for (final r in recurring) {
        if (r.id == null ||
            !ruleIds.add(r.id!) ||
            r.amountMinor <= 0 ||
            categoryKinds[r.categoryId] != r.type) {
          throw const BackupFormatException('A recurring rule is invalid.');
        }
      }

      _validate(categories, transactions, budgets);
      return BackupData(
        categories: categories,
        transactions: transactions,
        budgets: budgets,
        settings: settings,
        notes: notes,
        recurring: recurring,
        exportedAt: DateTime.tryParse('${map['exportedAt']}'),
      );
    } on BackupFormatException {
      rethrow;
    } catch (_) {
      throw const BackupFormatException(
          'The backup file is damaged or incomplete.');
    }
  }

  static void _validate(
    List<Category> categories,
    List<TransactionEntry> transactions,
    List<CategoryBudget> budgets,
  ) {
    final ids = <int>{};
    final names = <String>{};
    for (final c in categories) {
      if (c.id == null || !ids.add(c.id!)) {
        throw const BackupFormatException('Duplicate or missing category id.');
      }
      if (c.name.trim().isEmpty ||
          !names.add('${c.kind.name}:${c.name.toLowerCase()}')) {
        throw BackupFormatException('Invalid category "${c.name}".');
      }
    }
    if (!categories.any((c) => c.kind == TransactionType.expense) ||
        !categories.any((c) => c.kind == TransactionType.income)) {
      throw const BackupFormatException('Backup has no categories.');
    }
    final kinds = {for (final c in categories) c.id!: c.kind};
    final txIds = <int>{};
    for (final t in transactions) {
      if (t.id == null || !txIds.add(t.id!)) {
        throw const BackupFormatException(
            'Duplicate or missing transaction id.');
      }
      if (t.amountMinor <= 0 || t.amountMinor > Money.maxMinor) {
        throw const BackupFormatException('A transaction has a bad amount.');
      }
      if (kinds[t.categoryId] == null) {
        throw const BackupFormatException(
            'A transaction refers to a missing category.');
      }
    }
    for (final b in budgets) {
      if (kinds[b.categoryId] != TransactionType.expense ||
          b.amountMinor <= 0) {
        throw const BackupFormatException('A budget is invalid.');
      }
    }
  }

  /// Spreadsheet-friendly export of transactions.
  static String toCsv({
    required List<TransactionEntry> transactions,
    required Map<int, Category> categories,
    required CurrencyInfo currency,
  }) {
    String esc(String v) {
      // Neutralise spreadsheet formula injection and quote safely.
      var s = v;
      if (s.isNotEmpty && '=+-@'.contains(s[0])) s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }

    final b = StringBuffer()
      ..writeln('Date,Type,Category,Description,Payment method,'
          'Amount (${currency.code})');
    final sorted = List<TransactionEntry>.of(transactions)
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final t in sorted) {
      final d = t.date;
      final date = '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      final amount = (t.signedMinor / Money.scale).toStringAsFixed(2);
      b.writeln([
        date,
        t.type.label,
        esc(categories[t.categoryId]?.name ?? ''),
        esc(t.note),
        t.paymentMethod.label,
        amount,
      ].join(','));
    }
    return b.toString();
  }
}
