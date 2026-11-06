/// A free-form note with an optional reminder.
class Note {
  const Note({
    this.id,
    required this.title,
    required this.body,
    this.pinned = false,
    this.reminderAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final String body;
  final bool pinned;

  /// When to show a notification; null for no reminder.
  final DateTime? reminderAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const maxTitle = 80;
  static const maxBody = 5000;

  bool hasUpcomingReminder(DateTime now) =>
      reminderAt != null && reminderAt!.isAfter(now);

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
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      pinned: pinned ?? this.pinned,
      reminderAt: clearReminder ? null : (reminderAt ?? this.reminderAt),
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
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Note.fromMap(Map<String, Object?> map) {
    final reminder = (map['reminder_at'] as num?)?.toInt();
    return Note(
      id: (map['id'] as num?)?.toInt(),
      title: (map['title'] as String?) ?? '',
      body: (map['body'] as String?) ?? '',
      pinned: ((map['pinned'] as num?)?.toInt() ?? 0) == 1,
      reminderAt: reminder == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(reminder),
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
