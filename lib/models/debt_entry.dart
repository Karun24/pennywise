enum DebtType {
  lent('Owed to me', 'Lent'),
  borrowed('I owe', 'Borrowed');

  const DebtType(this.label, this.shortLabel);
  final String label;
  final String shortLabel;

  static DebtType fromName(String? name) => DebtType.values.firstWhere(
        (t) => t.name == name,
        orElse: () => DebtType.lent,
      );
}

/// A debt or split bill entry: money lent to someone ("They owe me")
/// or borrowed from someone ("I owe them").
class DebtEntry {
  const DebtEntry({
    this.id,
    required this.personName,
    required this.amountMinor,
    required this.type,
    this.note = '',
    this.dueDate,
    this.isSettled = false,
    this.settledAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String personName;
  final int amountMinor;
  final DebtType type;
  final String note;
  final DateTime? dueDate;
  final bool isSettled;
  final DateTime? settledAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isLent => type == DebtType.lent;
  bool get isBorrowed => type == DebtType.borrowed;

  bool isOverdue(DateTime now) =>
      !isSettled && dueDate != null && dueDate!.isBefore(now);

  DebtEntry copyWith({
    int? id,
    String? personName,
    int? amountMinor,
    DebtType? type,
    String? note,
    DateTime? dueDate,
    bool clearDueDate = false,
    bool? isSettled,
    DateTime? settledAt,
    bool clearSettledAt = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DebtEntry(
      id: id ?? this.id,
      personName: personName ?? this.personName,
      amountMinor: amountMinor ?? this.amountMinor,
      type: type ?? this.type,
      note: note ?? this.note,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      isSettled: isSettled ?? this.isSettled,
      settledAt: clearSettledAt ? null : (settledAt ?? this.settledAt),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'person_name': personName,
        'amount_minor': amountMinor,
        'type': type.name,
        'note': note,
        if (dueDate != null) 'due_date': dueDate!.millisecondsSinceEpoch,
        'is_settled': isSettled ? 1 : 0,
        if (settledAt != null) 'settled_at': settledAt!.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory DebtEntry.fromMap(Map<String, Object?> map) {
    final due = (map['due_date'] as num?)?.toInt();
    final settled = (map['settled_at'] as num?)?.toInt();
    return DebtEntry(
      id: (map['id'] as num?)?.toInt(),
      personName: (map['person_name'] as String?) ?? '',
      amountMinor: (map['amount_minor'] as num).toInt(),
      type: DebtType.fromName(map['type'] as String?),
      note: (map['note'] as String?) ?? '',
      dueDate: due != null ? DateTime.fromMillisecondsSinceEpoch(due) : null,
      isSettled: ((map['is_settled'] as num?)?.toInt() ?? 0) == 1,
      settledAt:
          settled != null ? DateTime.fromMillisecondsSinceEpoch(settled) : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as num?)?.toInt() ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['updated_at'] as num?)?.toInt() ?? 0),
    );
  }

  List<String> validate() => [
        if (personName.trim().isEmpty) 'Please enter a name.',
        if (amountMinor <= 0) 'Amount must be greater than zero.',
      ];
}
