import 'recurring_rule.dart';

/// A free-form note with an optional (and optionally repeating) reminder.
class Note {
  const Note({
    this.id,
    required this.title,
    required this.body,
    this.pinned = false,
    this.reminderAt,
    this.repeatFrequency,
    this.repeatUntil,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final String body;
  final bool pinned;

  /// When to show the first/next notification; null for no reminder.
  final DateTime? reminderAt;

  /// Optional repeat rule: daily, weekly, monthly. Null = does not repeat.
  final RepeatFrequency? repeatFrequency;

  /// Optional end date for the repeating reminder. Null = repeats forever.
  final DateTime? repeatUntil;

  final DateTime createdAt;
  final DateTime updatedAt;

  static const maxTitle = 80;
  static const maxBody = 5000;

  bool get isRepeating => repeatFrequency != null;

  bool hasUpcomingReminder(DateTime now) {
    if (reminderAt == null) return false;
    if (isRepeating) {
      if (repeatUntil != null && now.isAfter(repeatUntil!)) return false;
      return true;
    }
    return reminderAt!.isAfter(now);
  }

  /// Title, or the first line of the body when there is no title.
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final firstLine = body.trim().split('\n').first.trim();
    return firstLine.isEmpty ? 'Untitled note' : firstLine;
  }

  Note copyWith({
    int? id,
    String? title,
    String? body,
    bool? pinned,
    DateTime? reminderAt,
    bool clearReminder = false,
    RepeatFrequency? repeatFrequency,
    bool clearRepeat = false,
    DateTime? repeatUntil,
    bool clearRepeatUntil = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      pinned: pinned ?? this.pinned,
      reminderAt: clearReminder ? null : (reminderAt ?? this.reminderAt),
      repeatFrequency:
          clearRepeat ? null : (repeatFrequency ?? this.repeatFrequency),
      repeatUntil:
          clearRepeatUntil ? null : (repeatUntil ?? this.repeatUntil),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'body': body,
        'pinned': pinned ? 1 : 0,
        'reminder_at': reminderAt?.millisecondsSinceEpoch,
        if (repeatFrequency != null) 'repeat_frequency': repeatFrequency!.name,
        if (repeatUntil != null)
          'repeat_until': repeatUntil!.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Note.fromMap(Map<String, Object?> map) {
    final reminder = (map['reminder_at'] as num?)?.toInt();
    final repeatFreq = map['repeat_frequency'] as String?;
    final repeatUntilMs = (map['repeat_until'] as num?)?.toInt();

    return Note(
      id: (map['id'] as num?)?.toInt(),
      title: (map['title'] as String?) ?? '',
      body: (map['body'] as String?) ?? '',
      pinned: ((map['pinned'] as num?)?.toInt() ?? 0) == 1,
      reminderAt: reminder == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(reminder),
      repeatFrequency:
          repeatFreq != null ? RepeatFrequency.fromName(repeatFreq) : null,
      repeatUntil: repeatUntilMs != null
          ? DateTime.fromMillisecondsSinceEpoch(repeatUntilMs)
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as num?)?.toInt() ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['updated_at'] as num?)?.toInt() ?? 0),
    );
  }

  /// Human-readable problems; empty when valid.
  List<String> validate() => [
        if (title.trim().isEmpty && body.trim().isEmpty)
          'Write a title or some text first.',
        if (title.length > maxTitle) 'Title is too long.',
        if (body.length > maxBody) 'Note is too long.',
      ];
}
