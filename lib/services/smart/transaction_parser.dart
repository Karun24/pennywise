import '../../models/category.dart';
import '../../models/transaction_entry.dart';
import '../../utils/date_utils.dart';
import '../../utils/money.dart';
import 'categorizer.dart';

/// Which field a [ParseIssue] refers to.
enum ParseField { amount, type, category, date }

/// Something the parser could not decide and the user must confirm.
class ParseIssue {
  const ParseIssue(this.field, this.message);
  final ParseField field;
  final String message;
}

/// Result of parsing a free-text entry such as "spent 250 on lunch".
///
/// Nothing is saved automatically: the UI always shows this result for the
/// user to confirm or correct.
class ParsedTransaction {
  const ParsedTransaction({
    required this.input,
    required this.date,
    this.amountMinor,
    this.amountCandidates = const [],
    this.type,
    this.category,
    this.categoryAlternatives = const [],
    this.categoryReason,
    this.description = '',
    this.dateDetected = false,
    this.paymentMethod,
    this.issues = const [],
  });

  final String input;
  final int? amountMinor;

  /// When several numbers were found and it is unclear which is the amount.
  final List<int> amountCandidates;
  final TransactionType? type;
  final Category? category;
  final List<Category> categoryAlternatives;
  final String? categoryReason;
  final String description;
  final DateTime date;
  final bool dateDetected;
  final PaymentMethod? paymentMethod;
  final List<ParseIssue> issues;

  bool get isComplete =>
      amountMinor != null &&
      type != null &&
      category != null &&
      !issues.any((i) => i.field == ParseField.date);

  bool hasIssue(ParseField f) => issues.any((i) => i.field == f);
}

/// Lightweight, fully offline natural-language parser built from regular
/// expressions and keyword rules. It is *not* a generative AI model.
class TransactionParser {
  TransactionParser(this.categorizer);

  final Categorizer categorizer;

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static const _weekdays = {
    'monday': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'friday': DateTime.friday,
    'saturday': DateTime.saturday,
    'sunday': DateTime.sunday,
  };

  static const _incomeStrong = [
    'received', 'receive', 'got paid', 'paid me', 'sent me', 'credited',
    'earned', 'earn', 'salary', 'income', 'refund', 'refunded', 'cashback',
    'cash back', 'reimbursed', 'reimbursement', 'dividend', 'stipend',
    'bonus', 'won',
  ];

  static const _expenseStrong = [
    'spent', 'spend', 'paid', 'pay', 'paying', 'bought', 'buy',
    'purchased', 'purchase', 'debited', 'ordered', 'cost', 'costs', 'gave',
    'booked', 'recharged', 'donated', 'expense', 'sent', 'transferred',
  ];

  static const _incomeWeak = ['got', 'from'];

  static const _fillers = {
    'i', 'ive', "i've", 'me', 'my', 'we', 'our', 'just', 'spent', 'spend',
    'paid', 'pay', 'paying', 'bought', 'buy', 'purchased', 'purchase',
    'received', 'receive', 'got', 'get', 'earned', 'earn', 'credited',
    'debited', 'gave', 'ordered', 'cost', 'costs', 'rupees', 'rupee', 'rs',
    'inr', 'bucks', 'a', 'an', 'the', 'of', 'worth', 'some', 'around',
    'about', 'approx', 'total', 'was', 'is', 'it', 'had', 'have', 'did',
    'made', 'booked', 'expense', 'income', 'amount', 'spending', 'sent',
    'transferred',
  };

  static const _prepositions = {
    'on', 'for', 'at', 'from', 'to', 'via', 'using', 'with', 'through', 'by',
    'in', 'and',
  };

  ParsedTransaction parse(String input, {required DateTime now}) {
    final original = input.trim();
    final lower = original.toLowerCase();
    // Masking is done on both strings in parallel so the description can
    // keep the user's original capitalisation.
    final sameLength = lower.length == original.length;
    var w = lower;
    var orig = sameLength ? original : lower;

    void mask(int start, int end) {
      final pad = ' ' * (end - start);
      w = w.replaceRange(start, end, pad);
      orig = orig.replaceRange(start, end, pad);
    }

    final issues = <ParseIssue>[];
    final today = DateUtilsX.dateOnly(now);

    // ------------------------------------------------------------------ date
    DateTime? date;
    final dates = <DateTime>[];
    void addDate(DateTime d, Match m) {
      dates.add(d);
      mask(m.start, m.end);
    }

    for (final m in RegExp(r'\bday before yesterday\b').allMatches(w).toList()) {
      addDate(DateUtilsX.addDays(today, -2), m);
    }
    for (final m in RegExp(r'\byesterday\b').allMatches(w).toList()) {
      addDate(DateUtilsX.addDays(today, -1), m);
    }
    for (final m in RegExp(r'\b(today|tonight|this morning|this evening)\b')
        .allMatches(w)
        .toList()) {
      addDate(today, m);
    }
    for (final m in RegExp(r'\b(\d{1,3}) days? ago\b').allMatches(w).toList()) {
      final n = int.parse(m.group(1)!);
      addDate(DateUtilsX.addDays(today, -n), m);
    }
    for (final m in RegExp(
            r'\b(last |on |this past )?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b')
        .allMatches(w)
        .toList()) {
      final target = _weekdays[m.group(2)!]!;
      var diff = (today.weekday - target) % 7;
      if (diff == 0 && (m.group(1)?.trim() == 'last')) diff = 7;
      addDate(DateUtilsX.addDays(today, -diff), m);
    }
    for (final m in RegExp(
            r'\b(\d{1,2})(?:st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?(?:,?\s+(\d{4}))?\b')
        .allMatches(w)
        .toList()) {
      final d = _buildDate(int.parse(m.group(1)!), _months[m.group(2)!]!,
          m.group(3) == null ? null : int.parse(m.group(3)!), today);
      if (d != null) addDate(d, m);
    }
    for (final m in RegExp(
            r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s+(\d{4}))?')
        .allMatches(w)
        .toList()) {
      final d = _buildDate(int.parse(m.group(2)!), _months[m.group(1)!]!,
          m.group(3) == null ? null : int.parse(m.group(3)!), today);
      if (d != null) addDate(d, m);
    }
    for (final m in RegExp(r'\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b')
        .allMatches(w)
        .toList()) {
      int? year;
      if (m.group(3) != null) {
        year = int.parse(m.group(3)!);
        if (year < 100) year += 2000;
      }
      // Day/month order, as used in India and most of the world.
      final d = _buildDate(
          int.parse(m.group(1)!), int.parse(m.group(2)!), year, today);
      if (d != null) addDate(d, m);
    }
    for (final m in RegExp(r'\bon the (\d{1,2})(?:st|nd|rd|th)\b')
        .allMatches(w)
        .toList()) {
      final day = int.parse(m.group(1)!);
      var d = _validDate(today.year, today.month, day);
      if (d != null && d.isAfter(today)) {
        final prev = DateUtilsX.addMonths(today, -1);
        d = _validDate(prev.year, prev.month, day);
      }
      if (d != null) addDate(d, m);
    }

    final distinctDates = dates.toSet().toList();
    if (distinctDates.length == 1) {
      date = distinctDates.first;
    } else if (distinctDates.length > 1) {
      issues.add(const ParseIssue(
          ParseField.date, 'More than one date mentioned. Please pick one.'));
    }
    if (date != null && date.isAfter(today)) {
      issues.add(const ParseIssue(
          ParseField.date, 'That date is in the future. Please check it.'));
    }

    // --------------------------------------------------------------- payment
    PaymentMethod? payment;
    final paymentRules = <RegExp, PaymentMethod>{
      RegExp(r'\b(upi|gpay|google pay|phonepe|phone pe|paytm|bhim)\b'):
          PaymentMethod.upi,
      RegExp(r'\b(credit card|cc)\b'): PaymentMethod.creditCard,
      RegExp(r'\bdebit card\b'): PaymentMethod.debitCard,
      RegExp(r'\b(net ?banking|neft|imps|rtgs|bank transfer)\b'):
          PaymentMethod.netBanking,
      RegExp(r'\bcash\b(?!\s*back)'): PaymentMethod.cash,
      RegExp(r'\b(wallet|amazon pay)\b'): PaymentMethod.wallet,
    };
    paymentRules.forEach((re, method) {
      for (final m in re.allMatches(w).toList()) {
        payment ??= method;
        mask(m.start, m.end);
      }
    });

    // ---------------------------------------------------------------- amount
    final amountRe = RegExp(
      r'(?<![a-z0-9.])(?:(₹|rs\.?|inr)\s*)?(\d[\d,]*(?:\.\d+)?)'
      r'(?!\s*(?:kg|kgs|g|gm|gms|grams?|ltrs?|litres?|liters?|ml|km|kms|pcs|pieces?|items?|people|persons?|hrs?|hours?|mins?|minutes?|weeks?|months?|years?|am|pm|nights?|tickets?|plates?|x)\b)'
      r'(?:\s*(k|thousand|lakhs?|lacs?)\b)?'
      r'(?:\s*(rupees?|rs\.?|inr|bucks))?'
      r'(?![a-z0-9])',
    );
    final strong = <int>[];
    final all = <int>[];
    for (final m in amountRe.allMatches(w).toList()) {
      final digits = m.group(2)!.replaceAll(RegExp(r',+$'), '');
      final value = Money.parseToMinor(digits.replaceAll(',', ''));
      if (value == null) continue;
      var minor = value;
      final mult = m.group(3);
      if (mult != null) {
        minor = mult.startsWith('k') || mult == 'thousand'
            ? value * 1000
            : value * 100000;
      }
      if (minor <= 0 || minor > Money.maxMinor) continue;
      all.add(minor);
      if (m.group(1) != null || m.group(4) != null) strong.add(minor);
      mask(m.start, m.end);
    }
    int? amount;
    var candidates = <int>[];
    final strongSet = strong.toSet().toList();
    final allSet = all.toSet().toList();
    if (strongSet.length == 1) {
      amount = strongSet.first;
    } else if (strongSet.isEmpty && allSet.length == 1) {
      amount = allSet.first;
    } else if (allSet.isEmpty) {
      issues.add(const ParseIssue(ParseField.amount, 'How much was it?'));
    } else {
      candidates = strongSet.length > 1 ? strongSet : allSet;
      issues.add(const ParseIssue(
          ParseField.amount, 'Found more than one number. Which is the amount?'));
    }

    // ------------------------------------------------------------------ type
    bool has(String phrase) =>
        RegExp('\\b${RegExp.escape(phrase)}\\b').hasMatch(w);
    var typeText = w;
    final incomeStrong = _incomeStrong.any(has);
    // Remove income phrases that contain "paid" before checking expenses.
    for (final p in ['got paid', 'paid me', 'sent me']) {
      typeText = typeText.replaceAll(p, ' ');
    }
    final expenseStrong = _expenseStrong.any(
        (p) => RegExp('\\b${RegExp.escape(p)}\\b').hasMatch(typeText));
    final incomeWeak = _incomeWeak.any(has);

    TransactionType? type;
    var typeQuestion = false;
    if (incomeStrong && !expenseStrong) {
      type = TransactionType.income;
    } else if (expenseStrong && !incomeStrong) {
      type = TransactionType.expense;
    } else if (incomeStrong && expenseStrong) {
      typeQuestion = true;
    }

    // -------------------------------------------------------------- category
    var match = categorizer.suggest(w, type: type);
    if (type == null && !typeQuestion) {
      final first = match;
      final sameKind = first != null &&
          first.alternatives.every((c) => c.kind == first.category.kind);
      if (match != null && (match.confident || sameKind)) {
        // Either a clear match, or every candidate category is of the same
        // kind (e.g. Transport vs Bills are both expenses).
        type = match.category.kind;
      } else if (incomeWeak) {
        type = TransactionType.income;
        match = categorizer.suggest(w, type: type) ?? match;
        issues.add(const ParseIssue(
            ParseField.type, 'Assumed this is income. Please confirm.'));
      } else {
        typeQuestion = true;
      }
    }
    if (typeQuestion) {
      issues.add(const ParseIssue(
          ParseField.type, 'Is this money spent or received?'));
    }

    Category? category;
    var alternatives = <Category>[];
    if (match == null) {
      issues.add(const ParseIssue(
          ParseField.category, "Couldn't tell the category. Pick one."));
    } else if (!match.confident) {
      alternatives = [match.category, ...match.alternatives];
      issues.add(ParseIssue(ParseField.category,
          'Is it ${alternatives.map((c) => c.name).join(' or ')}?'));
    } else if (type != null && match.category.kind != type) {
      issues.add(const ParseIssue(
          ParseField.category, "Couldn't tell the category. Pick one."));
    } else {
      category = match.category;
    }

    // ----------------------------------------------------------- description
    final description = _description(orig, category);

    return ParsedTransaction(
      input: original,
      amountMinor: amount,
      amountCandidates: candidates,
      type: type,
      category: category,
      categoryAlternatives: alternatives,
      categoryReason: category == null ? null : match?.reason,
      description: description,
      date: date ?? today,
      dateDetected: date != null,
      paymentMethod: payment,
      issues: issues,
    );
  }

  static DateTime? _validDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final d = DateTime(year, month, day);
    if (d.month != month || d.day != day) return null;
    return d;
  }

  /// Builds a date; without a year, picks the most recent past occurrence.
  static DateTime? _buildDate(int day, int month, int? year, DateTime today) {
    if (year != null) return _validDate(year, month, day);
    final d = _validDate(today.year, month, day);
    if (d == null) return null;
    if (d.isAfter(today)) return _validDate(today.year - 1, month, day);
    return d;
  }

  String _description(String masked, Category? category) {
    final tokens = masked
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll(RegExp(r"^[^\w']+|[^\w']+$"), ''))
        .where((t) => t.isNotEmpty)
        .where((t) => !_fillers.contains(t.toLowerCase()))
        .toList();

    String? leadingPrep;
    while (tokens.isNotEmpty &&
        _prepositions.contains(tokens.first.toLowerCase())) {
      leadingPrep = tokens.removeAt(0).toLowerCase();
    }
    while (tokens.isNotEmpty &&
        _prepositions.contains(tokens.last.toLowerCase())) {
      tokens.removeLast();
    }
    // Collapse repeated prepositions ("for on").
    final cleaned = <String>[];
    for (final t in tokens) {
      final isPrep = _prepositions.contains(t.toLowerCase());
      if (isPrep &&
          cleaned.isNotEmpty &&
          _prepositions.contains(cleaned.last.toLowerCase())) {
        continue;
      }
      cleaned.add(t);
    }
    if (cleaned.isEmpty) return category?.name ?? '';
    if (leadingPrep == 'from' || leadingPrep == 'to') {
      cleaned.insert(0, leadingPrep!);
    }
    var text = cleaned.join(' ');
    if (text.length > 60) text = text.substring(0, 60).trim();
    return text[0].toUpperCase() + text.substring(1);
  }
}
