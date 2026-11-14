import '../models/transaction_entry.dart';
import '../utils/money.dart';
import 'backup_service.dart';

/// One transaction read from a PennyWise CSV export.
class CsvTransaction {
  const CsvTransaction({
    required this.date,
    required this.type,
    required this.categoryName,
    required this.note,
    required this.paymentMethod,
    required this.amountMinor,
  });

  final DateTime date;
  final TransactionType type;
  final String categoryName;
  final String note;
  final PaymentMethod paymentMethod;
  final int amountMinor;
}

/// Reads the CSV produced by "Export as CSV" (also after it has been opened
/// and re-saved in Excel / Google Sheets). Only transactions can be
/// recovered from a CSV; notes, budgets and settings are not in it.
class CsvImportService {
  CsvImportService._();

  static bool looksLikeCsv(String text) {
    final first = text.trimLeft().split(RegExp(r'\r?\n')).first.toLowerCase();
    return first.contains('date') &&
        first.contains('type') &&
        first.contains('amount');
  }

  /// Splits CSV text into rows of fields (handles quotes, "" escapes,
  /// commas and line breaks inside quotes, and ; or tab separators).
  static List<List<String>> parseRows(String text) {
    var src = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (src.startsWith('﻿')) src = src.substring(1);
    final header = src.split('\n').first;
    final sep = header.contains(',')
        ? ','
        : header.contains(';')
            ? ';'
            : '\t';
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < src.length; i++) {
      final ch = src[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < src.length && src[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == sep) {
        row.add(field.toString());
        field.clear();
      } else if (ch == '\n') {
        row.add(field.toString());
        field.clear();
        if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(ch);
      }
    }
    row.add(field.toString());
    if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
    return rows;
  }

  static DateTime? _parseDate(String raw) {
    final s = raw.trim();
    var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (m != null) {
      return _valid(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    }
    // Spreadsheets in India usually re-save dates as dd/mm/yyyy.
    m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})').firstMatch(s);
    if (m != null) {
      var y = int.parse(m[3]!);
      if (y < 100) y += 2000;
      return _valid(y, int.parse(m[2]!), int.parse(m[1]!));
    }
    return null;
  }

  static DateTime? _valid(int y, int mo, int d) {
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, mo, d, 12);
    return dt.month == mo ? dt : null;
  }

  static String _unescape(String v) {
    final s = v.trim();
    // Undo the formula-injection guard added on export ('=..., '+..., ...).
    if (s.length > 1 && s.startsWith("'") && '=+-@'.contains(s[1])) {
      return s.substring(1);
    }
    return s;
  }

  static PaymentMethod _payment(String raw) {
    final s = raw.trim().toLowerCase();
    for (final m in PaymentMethod.values) {
      if (m.label.toLowerCase() == s || m.name.toLowerCase() == s) return m;
    }
    return PaymentMethod.other;
  }

  /// Parses a PennyWise CSV export. Throws [BackupFormatException] with a
  /// readable message if the file is not usable.
  static List<CsvTransaction> parse(String text) {
    final rows = parseRows(text);
    if (rows.length < 2) {
      throw const BackupFormatException('This CSV file has no transactions.');
    }
    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    int col(String name) => header.indexWhere((h) => h.startsWith(name));
    final iDate = col('date'),
        iType = col('type'),
        iCat = col('category'),
        iNote = col('description'),
        iPay = col('payment'),
        iAmount = col('amount');
    if (iDate < 0 || iType < 0 || iAmount < 0 || iCat < 0) {
      throw const BackupFormatException(
          'This CSV is not a PennyWise export (missing Date, Type, Category '
          'or Amount columns).');
    }
    String at(List<String> r, int i) => i >= 0 && i < r.length ? r[i] : '';

    final out = <CsvTransaction>[];
    for (var n = 1; n < rows.length; n++) {
      final r = rows[n];
      final date = _parseDate(at(r, iDate));
      final amount = Money.parseToMinor(
          at(r, iAmount).replaceAll('-', '').replaceAll('+', ''));
      if (date == null || amount == null) {
        throw BackupFormatException(
            'Row ${n + 1} of the CSV has an invalid date or amount.');
      }
      final typeText = at(r, iType).trim().toLowerCase();
      final type = typeText.startsWith('inc')
          ? TransactionType.income
          : TransactionType.expense;
      final category = _unescape(at(r, iCat));
      out.add(CsvTransaction(
        date: date,
        type: type,
        categoryName: category.isEmpty ? 'Other' : category,
        note: _unescape(at(r, iNote)),
        paymentMethod: _payment(at(r, iPay)),
        amountMinor: amount,
      ));
    }
    return out;
  }
}
