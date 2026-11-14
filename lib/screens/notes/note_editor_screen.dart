import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/note.dart';
import '../../models/recurring_rule.dart';
import '../../services/reminder_service.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';

/// Create or edit a note, with an optional date & time reminder.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, this.existing});

  final Note? existing;

  static Future<void> open(BuildContext context, {Note? existing}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: existing == null,
        builder: (_) => NoteEditorScreen(existing: existing),
      ));

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.existing?.body ?? '');
  late DateTime? _reminder = widget.existing?.reminderAt;
  late RepeatFrequency? _repeatFrequency = widget.existing?.repeatFrequency;
  late DateTime? _repeatUntil = widget.existing?.repeatUntil;
  late bool _pinned = widget.existing?.pinned ?? false;
  bool _saving = false;
  bool _dirty = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _title.addListener(_markDirty);
    _body.addListener(_markDirty);
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _setReminder(DateTime? at) {
    setState(() {
      _reminder = at;
      if (at == null) {
        _repeatFrequency = null;
        _repeatUntil = null;
      }
      _dirty = true;
    });
  }

  /// Quick presets: in 30 min, in 1 hour, this evening, tomorrow morning.
  List<(String, DateTime)> _presets(DateTime now) {
    final today = DateUtilsX.dateOnly(now);
    final evening = today.add(const Duration(hours: 20));
    final tomorrow9 = DateUtilsX.addDays(today, 1).add(const Duration(hours: 9));
    return [
      ('In 30 min', now.add(const Duration(minutes: 30))),
      ('In 1 hour', now.add(const Duration(hours: 1))),
      if (evening.isAfter(now.add(const Duration(minutes: 5))))
        ('Today 8 PM', evening),
      ('Tomorrow 9 AM', tomorrow9),
      ('Next week', DateUtilsX.addDays(today, 7).add(const Duration(hours: 9))),
    ];
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final initial = _reminder != null && _reminder!.isAfter(now)
        ? _reminder!
        : now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateUtilsX.dateOnly(now),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Reminder date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Reminder time',
    );
    if (time == null || !mounted) return;
    final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!at.isAfter(DateTime.now())) {
      showSnack(context, 'Pick a time in the future.', error: true);
      return;
    }
    _setReminder(at);
  }

  Future<void> _save() async {
    final store = context.read<FinanceStore>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final at = _reminder;
    final existing = widget.existing;
    final reminderChanged = at != existing?.reminderAt;
    if (at != null && reminderChanged && !at.isAfter(DateTime.now())) {
      showSnack(context, 'The reminder time has already passed.',
          error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      var permissionOk = true;
      if (at != null && at.isAfter(DateTime.now())) {
        permissionOk = await store.reminders.requestPermission();
      }
      final now = DateTime.now();
      final draft = (existing ??
              Note(title: '', body: '', createdAt: now, updatedAt: now))
          .copyWith(
        title: _title.text.trim(),
        body: _body.text.trim(),
        pinned: _pinned,
        reminderAt: at,
        clearReminder: at == null,
        repeatFrequency: at != null ? _repeatFrequency : null,
        clearRepeat: at == null || _repeatFrequency == null,
        repeatUntil:
            at != null && _repeatFrequency != null ? _repeatUntil : null,
        clearRepeatUntil: at == null ||
            _repeatFrequency == null ||
            _repeatUntil == null,
      );
      final result = await store.saveNote(draft);
      navigator.pop();
      final upcoming = at != null &&
          (at.isAfter(DateTime.now()) || _repeatFrequency != null);
      if (upcoming && (!permissionOk || !result.reminderOk)) {
        messenger.showSnackBar(pennySnack(
          'Note saved, but notifications are off for PennyWise. Turn them '
          'on in your phone settings to get the reminder.',
          error: true,
        ));
      } else if (upcoming) {
        messenger.showSnackBar(pennySnack(
            'Reminder set for ${reminderLabel(at, DateTime.now(), repeat: _repeatFrequency, repeatUntil: _repeatUntil)}'));
      } else {
        messenger.showSnackBar(pennySnack('Note saved'));
      }
    } on StoreException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, e.message, error: true);
    }
  }

  Future<void> _delete() async {
    final store = context.read<FinanceStore>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmAction(
      context,
      title: 'Delete note?',
      message: 'The note and any reminder will be removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    final note = widget.existing!;
    setState(() => _saving = true);
    try {
      await store.deleteNote(note);
      navigator.pop();
      messenger.showSnackBar(pennySnack(
        'Note deleted',
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => store.restoreNote(note),
        ),
      ));
    } on StoreException catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(pennySnack(e.message, error: true));
    }
  }

  Future<void> _maybeLeave() async {
    final navigator = Navigator.of(context);
    final leave = await confirmAction(
      context,
      title: 'Discard changes?',
      message: 'Your changes to this note have not been saved.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (!leave || !mounted) return;
    setState(() => _dirty = false);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final at = _reminder;
    final upcoming = at != null && at.isAfter(now);

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _maybeLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editing ? 'Edit note' : 'New note'),
          actions: [
            IconButton(
              tooltip: _pinned ? 'Unpin' : 'Pin to top',
              onPressed: () => setState(() {
                _pinned = !_pinned;
                _dirty = true;
              }),
              icon: Icon(
                _pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                color: _pinned ? context.colors.primary : null,
              ),
            ),
            if (_editing)
              IconButton(
                tooltip: 'Delete',
                onPressed: _saving ? null : _delete,
                icon: Icon(Icons.delete_outline_rounded,
                    color: context.penny.expense),
              ),
          ],
        ),
        body: SafeArea(
          child: ResponsiveCenter(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: pagePadding(context, top: 4, bottom: 24),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      TextField(
                        controller: _title,
                        autofocus: !_editing,
                        maxLength: Note.maxTitle,
                        textCapitalization: TextCapitalization.sentences,
                        style: context.text.titleLarge,
                        decoration: const InputDecoration(
                          hintText: 'Title',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _body,
                        maxLength: Note.maxBody,
                        minLines: 6,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        style: context.text.bodyLarge?.copyWith(height: 1.45),
                        decoration: const InputDecoration(
                          hintText: 'Write your note…\n\ne.g. Lent ₹2,000 to '
                              'Ravi, get it back by the 15th',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 20),
                      PennyCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.alarm_rounded,
                                    size: 20,
                                    color: upcoming
                                        ? context.penny.accent
                                        : context.penny.textMuted),
                                const SizedBox(width: 8),
                                Text('Reminder',
                                    style: context.text.titleSmall),
                                const Spacer(),
                                if (at != null)
                                  TextButton(
                                    onPressed: () => _setReminder(null),
                                    child: const Text('Remove'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (at != null) ...[
                              Text(
                                upcoming
                                    ? reminderLabel(at, now,
                                        repeat: _repeatFrequency,
                                        repeatUntil: _repeatUntil)
                                    : 'Was ${reminderLabel(at, now, repeat: _repeatFrequency, repeatUntil: _repeatUntil)} (passed)',
                                style: context.text.titleMedium?.copyWith(
                                    color: upcoming
                                        ? context.penny.accent
                                        : context.penny.textMuted),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                upcoming
                                    ? 'You will get a notification at this time, '
                                        'even if PennyWise is closed.'
                                    : 'Pick a new time to be reminded again.',
                                style: context.text.bodySmall,
                              ),
                              const SizedBox(height: 12),
                            ] else ...[
                              Text(
                                'Get a notification at a date and time.',
                                style: context.text.bodySmall,
                              ),
                              const SizedBox(height: 12),
                            ],
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final (label, time) in _presets(now))
                                  ActionChip(
                                    label: Text(label),
                                    onPressed: () => _setReminder(time),
                                  ),
                                ActionChip(
                                  avatar: const Icon(
                                      Icons.calendar_month_rounded,
                                      size: 18),
                                  label: const Text('Pick date & time'),
                                  onPressed: _pickDateTime,
                                ),
                              ],
                            ),
                            if (at != null) ...[
                              const SizedBox(height: 14),
                              const Divider(height: 1),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(Icons.repeat_rounded,
                                      size: 18,
                                      color: context.penny.textMuted),
                                  const SizedBox(width: 8),
                                  Text('Repeat reminder',
                                      style: context.text.titleSmall),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: const Text('Does not repeat'),
                                    selected: _repeatFrequency == null,
                                    onSelected: (sel) {
                                      if (sel) {
                                        setState(() {
                                          _repeatFrequency = null;
                                          _repeatUntil = null;
                                          _dirty = true;
                                        });
                                      }
                                    },
                                  ),
                                  ChoiceChip(
                                    label: const Text('Every day'),
                                    selected: _repeatFrequency ==
                                        RepeatFrequency.daily,
                                    onSelected: (sel) {
                                      if (sel) {
                                        setState(() {
                                          _repeatFrequency =
                                              RepeatFrequency.daily;
                                          _dirty = true;
                                        });
                                      }
                                    },
                                  ),
                                  ChoiceChip(
                                    label: const Text('Every week'),
                                    selected: _repeatFrequency ==
                                        RepeatFrequency.weekly,
                                    onSelected: (sel) {
                                      if (sel) {
                                        setState(() {
                                          _repeatFrequency =
                                              RepeatFrequency.weekly;
                                          _dirty = true;
                                        });
                                      }
                                    },
                                  ),
                                  ChoiceChip(
                                    label: const Text('Every month'),
                                    selected: _repeatFrequency ==
                                        RepeatFrequency.monthly,
                                    onSelected: (sel) {
                                      if (sel) {
                                        setState(() {
                                          _repeatFrequency =
                                              RepeatFrequency.monthly;
                                          _dirty = true;
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                              if (_repeatFrequency != null) ...[
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Icon(Icons.event_busy_rounded,
                                        size: 18,
                                        color: context.penny.textMuted),
                                    const SizedBox(width: 8),
                                    Text('Repeat until (end date)',
                                        style: context.text.titleSmall),
                                    const Spacer(),
                                    if (_repeatUntil != null)
                                      TextButton(
                                        onPressed: () => setState(() {
                                          _repeatUntil = null;
                                          _dirty = true;
                                        }),
                                        child: const Text('Forever'),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () async {
                                    final baseDate = DateTime.now();
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _repeatUntil ??
                                          baseDate.add(const Duration(days: 30)),
                                      firstDate:
                                          DateUtilsX.dateOnly(baseDate),
                                      lastDate:
                                          DateTime(baseDate.year + 5, 12, 31),
                                      helpText:
                                          'Select end date for repeat',
                                    );
                                    if (picked != null && mounted) {
                                      setState(() {
                                        _repeatUntil = DateTime(
                                            picked.year,
                                            picked.month,
                                            picked.day,
                                            23,
                                            59,
                                            59);
                                        _dirty = true;
                                      });
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: context
                                          .colors.surfaceContainerHighest
                                          .withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color:
                                              context.colors.outlineVariant),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.calendar_today_rounded,
                                            size: 16,
                                            color: context.colors.primary),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _repeatUntil != null
                                                ? 'Ends on ${DateUtilsX.dayMonth(_repeatUntil!)}'
                                                : 'Repeats forever (tap to set end date)',
                                            style: context.text.bodyMedium,
                                          ),
                                        ),
                                        Icon(Icons.edit_calendar_rounded,
                                            size: 18,
                                            color: context.penny.textMuted),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: pagePadding(context, top: 8, bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white),
                            )
                          : Text(upcoming ? 'Save & set reminder' : 'Save note'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
