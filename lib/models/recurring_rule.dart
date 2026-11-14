import 'transaction_entry.dart';

/// How often a recurring transaction repeats.
enum RepeatFrequency {
  daily('Daily', 'day'),
  weekly('Weekly', 'week'),
  monthly('Monthly', 'month'),
  yearly('Yearly', 'year');

  const RepeatFrequency(this.label, this.unit);
  final String label;
  final String unit;

  static RepeatFrequency fromName(String? v) => RepeatFrequency.values
      .firstWhere((f) => f.name == v, orElse: () => RepeatFrequency.monthly);
}

/// A template that adds a transaction automatically on a schedule,
/// e.g. rent on the 1st of every month.
class RecurringRule {
  const RecurringRule({
    this.id,
    required this.type,
    required this.amountMinor,
    required this.categoryId,
    required this.note,
    required this.paymentMethod,
    required this.frequency,
    required this.anchorDay,
    required this.nextDue,
    this.active = true,
    required this.createdAt,
  });

  final int? id;
  final TransactionType type;
  final int amountMinor;
  final int categoryId;
  final String note;
  final PaymentMethod paymentMethod;
  final RepeatFrequency frequency;

  /// Day of the month the rule started on. Monthly/yearly rules return to
  /// this day (e.g. the 31st) even after a shorter month.
  final int anchorDay;

  /// Date (no time) of the next transaction to add.
  final DateTime nextDue;
  final bool active;
  final DateTime createdAt;

  /// The occurrence after [from], keeping [anchorDay] for months.
  static DateTime advance(DateTime from, RepeatFrequency f, int anchorDay) {
    int clampDay(int y, int m) {
      final last = DateTime(y, m + 1, 0).day;
      return anchorDay > last ? last : anchorDay;
    }

    switch (f) {
      case RepeatFrequency.daily:
        return DateTime(from.year, from.month, from.day + 1);
      case RepeatFrequency.weekly:
        return DateTime(from.year, from.month, from.day + 7);
      case RepeatFrequency.monthly:
        final first = DateTime(from.year, from.month + 1);
        return DateTime(first.year, first.month, clampDay(first.year, first.month));
      case RepeatFrequency.yearly:
        final y = from.year + 1;
        return DateTime(y, from.month, clampDay(y, from.month));
    }
  }

  /// "Every month on the 5th", "Every week on Monday", ...
  String describe() {
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
      'Sunday',
    ];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
      'Nov', 'Dec',
    ];
    String ordinal(int n) {
      if (n >= 11 && n <= 13) return '${n}th';
      return switch (n % 10) {
        1 => '${n}st',
        2 => '${n}nd',
        3 => '${n}rd',
        _ => '${n}th',
      };
    }

    return switch (frequency) {
      RepeatFrequency.daily => 'Every day',
      RepeatFrequency.weekly => 'Every ${weekdays[nextDue.weekday - 1]}',
      RepeatFrequency.monthly => 'Every month on the ${ordinal(anchorDay)}',
      RepeatFrequency.yearly =>
        'Every year on ${ordinal(anchorDay)} ${months[nextDue.month - 1]}',
    };
  }

  RecurringRule copyWith({
    int? id,
    int? amountMinor,
    int? categoryId,
    String? note,
    PaymentMethod? paymentMethod,
    DateTime? nextDue,
    bool? active,
  }) {
    return RecurringRule(
      id: id ?? this.id,
      type: type,
      amountMinor: amountMinor ?? this.amountMinor,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      frequency: frequency,
      anchorDay: anchorDay,
      nextDue: nextDue ?? this.nextDue,
      active: active ?? this.active,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'type': type.name,
        'amount_minor': amountMinor,
        'category_id': categoryId,
        'note': note,
        'payment_method': paymentMethod.name,
        'frequency': frequency.name,
        'anchor_day': anchorDay,
        'next_due': nextDue.millisecondsSinceEpoch,
        'active': active ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory RecurringRule.fromMap(Map<String, Object?> map) {
    final next = DateTime.fromMillisecondsSinceEpoch(
        (map['next_due'] as num).toInt());
    return RecurringRule(
      id: (map['id'] as num?)?.toInt(),
      type: TransactionType.fromName(map['type'] as String?),
      amountMinor: (map['amount_minor'] as num).toInt(),
      categoryId: (map['category_id'] as num).toInt(),
      note: (map['note'] as String?) ?? '',
      paymentMethod: PaymentMethod.fromName(map['payment_method'] as String?),
      frequency: RepeatFrequency.fromName(map['frequency'] as String?),
      anchorDay: (map['anchor_day'] as num?)?.toInt() ?? next.day,
      nextDue: DateTime(next.year, next.month, next.day),
      active: ((map['active'] as num?)?.toInt() ?? 1) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as num?)?.toInt() ?? 0),
    );
  }
}
