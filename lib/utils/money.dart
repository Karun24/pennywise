import 'package:intl/intl.dart';

/// A display currency. PennyWise does not convert between currencies; the
/// selected currency only controls how stored amounts are displayed.
class CurrencyInfo {
  const CurrencyInfo({
    required this.code,
    required this.symbol,
    required this.name,
    required this.locale,
    this.decimals = 2,
  });

  final String code;
  final String symbol;
  final String name;
  final String locale;
  final int decimals;

  static const inr = CurrencyInfo(
      code: 'INR', symbol: '₹', name: 'Indian Rupee', locale: 'en_IN');

  static const supported = <CurrencyInfo>[
    inr,
    CurrencyInfo(code: 'USD', symbol: r'$', name: 'US Dollar', locale: 'en_US'),
    CurrencyInfo(code: 'EUR', symbol: '€', name: 'Euro', locale: 'en_IE'),
    CurrencyInfo(
        code: 'GBP', symbol: '£', name: 'British Pound', locale: 'en_GB'),
    CurrencyInfo(code: 'AED', symbol: 'AED ', name: 'UAE Dirham', locale: 'en_US'),
    CurrencyInfo(
        code: 'SGD', symbol: r'S$', name: 'Singapore Dollar', locale: 'en_SG'),
    CurrencyInfo(
        code: 'AUD', symbol: r'A$', name: 'Australian Dollar', locale: 'en_AU'),
    CurrencyInfo(
        code: 'CAD', symbol: r'C$', name: 'Canadian Dollar', locale: 'en_CA'),
    CurrencyInfo(
        code: 'JPY',
        symbol: '¥',
        name: 'Japanese Yen',
        locale: 'en_US',
        decimals: 0),
  ];

  static CurrencyInfo byCode(String? code) => supported.firstWhere(
        (c) => c.code == code,
        orElse: () => inr,
      );
}

/// Money helpers. All amounts are stored as integer *minor units*
/// (hundredths) to avoid floating point rounding errors.
class Money {
  Money._();

  static const int scale = 100;

  /// Largest accepted single amount (100 crore / 1 billion units).
  static const int maxMinor = 1000000000 * scale;

  static double toMajor(int minor) => minor / scale;

  static int fromMajor(num major) => (major * scale).round();

  /// Parses user input such as "1,250.50", "₹ 300" or "2k".
  /// Returns null for empty, negative, zero or invalid input.
  static int? parseToMinor(String input) {
    var s = input.trim().toLowerCase();
    if (s.isEmpty) return null;
    s = s.replaceAll(RegExp(r'[₹$€£¥,\s]'), '');
    s = s.replaceAll(RegExp(r'^(rs\.?|inr)'), '');
    var multiplier = 1.0;
    if (s.endsWith('k')) {
      multiplier = 1000;
      s = s.substring(0, s.length - 1);
    }
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) {
      // Allow longer decimals for "k" shorthand like 1.25k.
      if (!(multiplier > 1 && RegExp(r'^\d+(\.\d+)?$').hasMatch(s))) {
        return null;
      }
    }
    final value = double.tryParse(s);
    if (value == null) return null;
    final minor = fromMajor(value * multiplier);
    if (minor <= 0 || minor > maxMinor) return null;
    return minor;
  }

  static final Map<String, NumberFormat> _cache = {};

  static NumberFormat _formatter(CurrencyInfo c, int decimals) {
    final key = '${c.code}-$decimals';
    return _cache.putIfAbsent(
      key,
      () => NumberFormat.currency(
        locale: c.locale,
        symbol: c.symbol,
        decimalDigits: decimals,
      ),
    );
  }

  /// Formats [minor] units. Decimals are only shown when the amount has a
  /// fractional part (keeps the UI clean) unless [forceDecimals] is true.
  static String format(
    int minor,
    CurrencyInfo currency, {
    bool forceDecimals = false,
    bool signed = false,
  }) {
    final abs = minor.abs();
    final hasFraction = abs % scale != 0;
    final decimals =
        currency.decimals == 0 ? 0 : (forceDecimals || hasFraction ? 2 : 0);
    final text = _formatter(currency, decimals).format(abs / scale);
    if (minor < 0) return '-$text';
    if (signed && minor > 0) return '+$text';
    return text;
  }

  /// Short form for chart axes: ₹1.2K, ₹3.4L, ₹1.1Cr (INR) or $1.2M.
  static String compact(int minor, CurrencyInfo currency) {
    final major = minor.abs() / scale;
    final sign = minor < 0 ? '-' : '';
    String fmt(double v, String suffix) {
      final s = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
      final cleaned = s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
      return '$sign${currency.symbol}$cleaned$suffix';
    }

    if (currency.code == 'INR') {
      if (major >= 10000000) return fmt(major / 10000000, 'Cr');
      if (major >= 100000) return fmt(major / 100000, 'L');
      if (major >= 1000) return fmt(major / 1000, 'K');
    } else {
      if (major >= 1000000000) return fmt(major / 1000000000, 'B');
      if (major >= 1000000) return fmt(major / 1000000, 'M');
      if (major >= 1000) return fmt(major / 1000, 'K');
    }
    return '$sign${currency.symbol}${major.toStringAsFixed(0)}';
  }

  /// Plain editable text for an amount, e.g. 125050 -> "1250.5".
  static String toEditable(int minor) {
    final major = minor / scale;
    if (minor % scale == 0) return (minor ~/ scale).toString();
    return major.toStringAsFixed(2);
  }
}
