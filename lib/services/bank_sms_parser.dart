import '../models/transaction_entry.dart';
import '../utils/money.dart';

/// Structured information extracted from an on-device bank or payment SMS.
class ParsedSms {
  const ParsedSms({
    required this.amountMinor,
    required this.type,
    required this.merchant,
    this.accountDigits,
    this.date,
    this.balanceMinor,
    this.referenceId,
    this.suggestedCategory,
    required this.rawText,
  });

  final int amountMinor;
  final TransactionType type;
  final String merchant;
  final String? accountDigits;
  final DateTime? date;
  final int? balanceMinor;
  final String? referenceId;
  final String? suggestedCategory;
  final String rawText;
}

/// 100% private, on-device regex and heuristic parser for bank transaction SMS messages.
/// No data leaves the device.
class BankSmsParser {
  const BankSmsParser();

  /// Regex patterns for matching currency and amounts:
  /// Examples: "Rs 450.00", "Rs. 1,250", "INR 3500", "₹ 500.50"
  static final _amountRegex = RegExp(
    r'(?:(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)|([\d,]+(?:\.\d{1,2})?)\s*(?:Rs\.?|INR|₹))',
    caseSensitive: false,
  );

  /// Patterns indicating debit/expense
  static final _debitKeywords = RegExp(
    r'\b(?:debited|spent|paid|charged|sent|withdrawn|deducted|txn of|debit)\b',
    caseSensitive: false,
  );

  /// Patterns indicating credit/income
  static final _creditKeywords = RegExp(
    r'\b(?:credited|received|refunded|deposited|cashback|credit|added to)\b',
    caseSensitive: false,
  );

  /// Patterns for account/card number (e.g. "A/c *1234", "Card ending 5678", "acct XX9876")
  static final _accountRegex = RegExp(
    r'(?:a\/c|acct|account|card)(?:\s*(?:no\.?|ending|ending in|\*+|x+|xx))?\s*[:\-#]?\s*\*?([0-9]{3,5})\b',
    caseSensitive: false,
  );

  /// Patterns for available balance
  static final _balanceRegex = RegExp(
    r'(?:avl\.?\s*bal\.?|available\s*balance|bal\.?|balance)\s*(?:is|:)?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  /// Patterns for reference number / UTR / UPI ref
  static final _refRegex = RegExp(
    r'(?:upi\s*ref(?:erence)?(?:\s*no\.?)?|utr(?:\s*no\.?)?|ref(?:\s*no\.?)?)\s*[:\-#]?\s*([A-Za-z0-9]+)',
    caseSensitive: false,
  );

  /// Patterns for merchant / payee extraction
  static final _merchantPatterns = [
    // "to VPA abc@okaxis" or "to merchant Swiggy"
    RegExp(r'\b(?:to|at|towards|for)\s+(?:VPA\s+)?([A-Za-z0-9@_.\- ]{2,30}?)(?:\s+(?:on|using|via|ref|bal|avl|\.|$))', caseSensitive: false),
    // "Info: ATM WDL CASH" or "Info: SWIGGY"
    RegExp(r'\binfo:\s*([A-Za-z0-9_.\- ]{2,30}?)(?:\s+(?:on|ref|bal|\.|$))', caseSensitive: false),
  ];

  /// Categorisation heuristics mapping merchant/description keywords to standard category names
  static const Map<String, List<String>> _categoryKeywords = {
    'Food & Dining': [
      'zomato', 'swiggy', 'mcdonald', 'kfc', 'starbucks', 'dominos', 'pizza',
      'burger', 'restaurant', 'cafe', 'chai', 'food', 'dine', 'bake', 'bakery',
      'eat', 'hotel'
    ],
    'Groceries': [
      'blinkit', 'zepto', 'instamart', 'bigbasket', 'dmart', 'supermarket',
      'grocer', 'mart', 'provision', 'spencer', 'more retail'
    ],
    'Shopping': [
      'amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'nykaa', 'tata cliq',
      'zara', 'h&m', 'retail', 'croma', 'reliance digital', 'store'
    ],
    'Transport': [
      'uber', 'ola', 'rapido', 'metro', 'irctc', 'railway', 'fuel', 'petrol',
      'diesel', 'hpcl', 'bpcl', 'iocl', 'shell', 'parking', 'fastag', 'toll'
    ],
    'Bills & Utilities': [
      'electricity', 'bescom', 'tata power', 'airtel', 'jio', 'vi', 'vodafone',
      'broadband', 'wifi', 'gas', 'water', 'recharge', 'bill', 'dth'
    ],
    'Entertainment': [
      'netflix', 'spotify', 'hotstar', 'prime', 'youtube', 'bookmyshow',
      'pvr', 'inox', 'cinema', 'theatre', 'gaming', 'steam'
    ],
    'Health & Fitness': [
      'apollo', 'pharmeasy', '1mg', 'netmeds', 'hospital', 'clinic',
      'pharmacy', 'chemist', 'doctor', 'cult.fit', 'gym', 'fitness'
    ],
  };

  /// Parses a bank SMS message text. Returns [ParsedSms] if an amount and transaction
  /// pattern are detected, or null if the text does not appear to be a transaction SMS.
  ParsedSms? parse(String text) {
    if (text.trim().isEmpty) return null;

    // Check if it has an amount
    final amountMatch = _amountRegex.firstMatch(text);
    if (amountMatch == null) return null;

    final amountStr = amountMatch.group(1) ?? amountMatch.group(2);
    if (amountStr == null) return null;

    final minor = Money.parseToMinor(amountStr.replaceAll(',', ''));
    if (minor == null || minor <= 0) return null;

    // Determine type: debit (expense) or credit (income)
    final isDebit = _debitKeywords.hasMatch(text);
    final isCredit = _creditKeywords.hasMatch(text);

    if (!isDebit && !isCredit) {
      // Neither keyword found, probably not a transaction SMS
      return null;
    }

    final type = isDebit ? TransactionType.expense : TransactionType.income;

    // Extract account digits
    String? accountDigits;
    final acctMatch = _accountRegex.firstMatch(text);
    if (acctMatch != null) {
      accountDigits = acctMatch.group(1);
    }

    // Extract balance if present
    int? balanceMinor;
    final balMatch = _balanceRegex.firstMatch(text);
    if (balMatch != null) {
      final balStr = balMatch.group(1);
      if (balStr != null) {
        balanceMinor = Money.parseToMinor(balStr.replaceAll(',', ''));
      }
    }

    // Extract reference / UTR
    String? refId;
    final refMatch = _refRegex.firstMatch(text);
    if (refMatch != null) {
      refId = refMatch.group(1);
    }

    // Extract merchant or payee name
    String merchant = _extractMerchant(text, isDebit: isDebit);

    // Guess category from merchant
    String? category = _suggestCategory(merchant.isNotEmpty ? merchant : text);

    return ParsedSms(
      amountMinor: minor,
      type: type,
      merchant: merchant,
      accountDigits: accountDigits,
      balanceMinor: balanceMinor,
      referenceId: refId,
      suggestedCategory: category,
      rawText: text,
      date: DateTime.now(),
    );
  }

  String _extractMerchant(String text, {required bool isDebit}) {
    for (final pattern in _merchantPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        var raw = match.group(1)?.trim() ?? '';
        // Clean up common noise
        raw = raw.replaceAll(RegExp(r'\s+using\s+.*$', caseSensitive: false), '');
        raw = raw.replaceAll(RegExp(r'\s+via\s+.*$', caseSensitive: false), '');
        raw = raw.replaceAll(RegExp(r'\s+on\s+.*$', caseSensitive: false), '');
        raw = raw.replaceAll(RegExp(r'[,;.]$'), '').trim();
        if (raw.isNotEmpty && raw.length >= 2 && !raw.toLowerCase().startsWith('your')) {
          return raw;
        }
      }
    }

    // If nothing matched, use a clean fallback
    return isDebit ? 'Bank Transaction' : 'Received Payment';
  }

  String? _suggestCategory(String input) {
    final lower = input.toLowerCase();
    for (final entry in _categoryKeywords.entries) {
      for (final kw in entry.value) {
        if (lower.contains(kw)) {
          return entry.key;
        }
      }
    }
    return null;
  }
}
