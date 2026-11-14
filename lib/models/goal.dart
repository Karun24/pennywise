import 'dart:math';
import 'dart:ui' show Color;

/// A savings target with an optional deadline and progress tracking.
class Goal {
  const Goal({
    this.id,
    required this.name,
    required this.targetMinor,
    this.savedMinor = 0,
    this.targetDate,
    required this.colorValue,
    required this.iconKey,
    this.note = '',
    this.completed = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final int targetMinor;
  final int savedMinor;
  final DateTime? targetDate;
  final int colorValue;
  final String iconKey;
  final String note;
  final bool completed;
  final DateTime createdAt;
  final DateTime updatedAt;

  Color get color => Color(colorValue);

  /// Clamped between 0.0 and 1.0.
  double get progressRatio {
    if (targetMinor <= 0) return 0.0;
    return (savedMinor / targetMinor).clamp(0.0, 1.0);
  }

  /// Whole percentage (0 - 100+).
  int get percentage {
    if (targetMinor <= 0) return 0;
    return ((savedMinor / targetMinor) * 100).round();
  }

  /// Remaining amount needed to reach target.
  int get remainingMinor => max(0, targetMinor - savedMinor);

  /// True if savedMinor >= targetMinor or marked completed.
  bool get isAchieved => savedMinor >= targetMinor || completed;

  /// Suggested monthly contribution based on remaining months until [targetDate].
  /// Returns null if no targetDate or if targetDate has already passed or achieved.
  int? suggestedMonthlyMinor(DateTime now) {
    if (targetDate == null || isAchieved) return null;
    if (targetDate!.isBefore(now)) return remainingMinor;

    final months = max(
      1,
      (targetDate!.year - now.year) * 12 + targetDate!.month - now.month,
    );
    return (remainingMinor / months).ceil();
  }

  Goal copyWith({
    int? id,
    String? name,
    int? targetMinor,
    int? savedMinor,
    DateTime? targetDate,
    bool clearTargetDate = false,
    int? colorValue,
    String? iconKey,
    String? note,
    bool? completed,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Goal(
      id: id ?? this.id,
      name: name ?? this.name,
      targetMinor: targetMinor ?? this.targetMinor,
      savedMinor: savedMinor ?? this.savedMinor,
      targetDate: clearTargetDate ? null : (targetDate ?? this.targetDate),
      colorValue: colorValue ?? this.colorValue,
      iconKey: iconKey ?? this.iconKey,
      note: note ?? this.note,
      completed: completed ?? this.completed,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'target_minor': targetMinor,
        'saved_minor': savedMinor,
        'target_date': targetDate?.millisecondsSinceEpoch,
        'color': colorValue,
        'icon_key': iconKey,
        'note': note,
        'completed': completed ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Goal.fromMap(Map<String, Object?> map) {
    return Goal(
      id: (map['id'] as num?)?.toInt(),
      name: (map['name'] as String?) ?? 'Goal',
      targetMinor: (map['target_minor'] as num?)?.toInt() ?? 0,
      savedMinor: (map['saved_minor'] as num?)?.toInt() ?? 0,
      targetDate: map['target_date'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (map['target_date'] as num).toInt()),
      colorValue: (map['color'] as num?)?.toInt() ?? 0xFF34D399,
      iconKey: (map['icon_key'] as String?) ?? 'savings',
      note: (map['note'] as String?) ?? '',
      completed: ((map['completed'] as num?)?.toInt() ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as num?)?.toInt() ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['updated_at'] as num?)?.toInt() ?? 0),
    );
  }

  List<String> validate() {
    final errors = <String>[];
    if (name.trim().isEmpty) errors.add('Goal name cannot be empty.');
    if (name.length > 50) errors.add('Goal name is too long.');
    if (targetMinor <= 0) errors.add('Target amount must be greater than zero.');
    if (savedMinor < 0) errors.add('Saved amount cannot be negative.');
    return errors;
  }
}
