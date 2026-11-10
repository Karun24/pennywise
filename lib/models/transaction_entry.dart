/// Whether money went out (expense) or came in (income).
enum TransactionType {
  expense,
  income;

  static TransactionType fromName(String? value) =>
      value == 'income' ? TransactionType.income : TransactionType.expense;

  String get label => this == expense ? 'Expense' : 'Income';
}

/// How a transaction was paid. UPI first because it is the most common
/// payment rail for personal spending in India.
enum PaymentMethod {
  upi('UPI'),
  cash('Cash'),
  debitCard('Debit card'),
  creditCard('Credit card'),
  netBanking('Net banking'),
  wallet('Wallet'),
  other('Other');

  const PaymentMethod(this.label);

  final String label;

  static PaymentMethod fromName(String? value) => PaymentMethod.values
      .firstWhere((m) => m.name == value, orElse: () => PaymentMethod.other);
}

/// A single income or expense record.
class TransactionEntry {
  const TransactionEntry({
    this.id,
    required this.type,
    required this.amountMinor,
    required this.categoryId,
    required this.note,
    required this.date,
    required this.paymentMethod,
    required this.createdAt,
    required this.updatedAt,
    this.recurringId,
  });

  /// Null until the transaction has been stored.
  final int? id;
  final TransactionType type;

  /// Amount in minor units (hundredths). Always positive; [type] gives sign.
  final int amountMinor;
  final int categoryId;
  final String note;
  final DateTime date;
  final PaymentMethod paymentMethod;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set when the transaction was added automatically by a recurring rule.
  final int? recurringId;

  bool get isRecurring => recurringId != null;

  bool get isExpense => type == TransactionType.expense;
  bool get isIncome => type == TransactionType.income;

  /// Positive for income, negative for expense.
  int get signedMinor => isIncome ? amountMinor : -amountMinor;

  TransactionEntry copyWith({
    int? id,
    TransactionType? type,
    int? amountMinor,
    int? categoryId,
    String? note,
    DateTime? date,
    PaymentMethod? paymentMethod,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? recurringId,
  }) {
    return TransactionEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      amountMinor: amountMinor ?? this.amountMinor,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      date: date ?? this.date,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      recurringId: recurringId ?? this.recurringId,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'type': type.name,
        'amount_minor': amountMinor,
        'category_id': categoryId,
        'note': note,
        'occurred_at': date.millisecondsSinceEpoch,
        'payment_method': paymentMethod.name,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        if (recurringId != null) 'recurring_id': recurringId,
      };

  factory TransactionEntry.fromMap(Map<String, Object?> map) {
    return TransactionEntry(
      id: (map['id'] as num?)?.toInt(),
      type: TransactionType.fromName(map['type'] as String?),
      amountMinor: (map['amount_minor'] as num).toInt(),
      categoryId: (map['category_id'] as num).toInt(),
      note: (map['note'] as String?) ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(
          (map['occurred_at'] as num).toInt()),
      paymentMethod: PaymentMethod.fromName(map['payment_method'] as String?),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as num?)?.toInt() ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['updated_at'] as num?)?.toInt() ?? 0),
      recurringId: (map['recurring_id'] as num?)?.toInt(),
    );
  }

  /// Returns a list of human-readable problems, empty when valid.
  List<String> validate() {
    final errors = <String>[];
    if (amountMinor <= 0) errors.add('Amount must be greater than zero.');
    if (amountMinor > 1000000000 * 100) errors.add('Amount is too large.');
    if (note.length > 200) errors.add('Description is too long.');
    final now = DateTime.now();
    if (date.isAfter(DateTime(now.year + 1, now.month, now.day))) {
      errors.add('Date is too far in the future.');
    }
    if (date.isBefore(DateTime(1970))) errors.add('Date is invalid.');
    return errors;
  }
}
