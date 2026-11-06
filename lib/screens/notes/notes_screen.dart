import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/note.dart';
import '../../services/reminder_service.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import 'note_editor_screen.dart';

enum _NoteFilter { all, reminders }

/// List of notes with search, reminder filter, pin and delete.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const NotesScreen()));

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _search = TextEditingController();
  String _query = '';
  _NoteFilter _filter = _NoteFilter.all;
  final Set<int> _hidden = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<bool> _confirmDelete(Note n) => confirmAction(
        context,
        title: 'Delete note?',
        message: n.reminderAt != null
            ? 'The note and its reminder will be removed.'
            : 'This note will be removed.',
        confirmLabel: 'Delete',
        destructive: true,
      );

  Future<void> _delete(FinanceStore store, Note n) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _hidden.add(n.id!));
    try {
      await store.deleteNote(n);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(pennySnack(
          'Note deleted',
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.restoreNote(n),
          ),
        ));
    } on StoreException catch (e) {
      messenger.showSnackBar(pennySnack(e.message, error: true));
    } finally {
      if (mounted) setState(() => _hidden.remove(n.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final now = store.now;
    final q = _query.trim().toLowerCase();
    final items = store.notes.where((n) {
      if (_hidden.contains(n.id)) return false;
      if (_filter == _NoteFilter.reminders && n.reminderAt == null) {
        return false;
      }
      if (q.isEmpty) return true;
      return n.title.toLowerCase().contains(q) ||
          n.body.toLowerCase().contains(q);
    }).toList();
    if (_filter == _NoteFilter.reminders) {
      // Upcoming first (soonest), then past ones (most recent).
      items.sort((a, b) {
        final au = a.hasUpcomingReminder(now), bu = b.hasUpcomingReminder(now);
        if (au != bu) return au ? -1 : 1;
        return au
            ? a.reminderAt!.compareTo(b.reminderAt!)
            : b.reminderAt!.compareTo(a.reminderAt!);
      });
    }
    final upcoming = store.upcomingReminders.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Notes & reminders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => NoteEditorScreen.open(context),
        icon: const Icon(Icons.edit_note_rounded),
        label: const Text('New note'),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          child: ListView(
            padding: pagePadding(context, top: 4, bottom: 96),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search notes',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() {
                            _search.clear();
                            _query = '';
                          }),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('All (${store.notes.length})'),
                    selected: _filter == _NoteFilter.all,
                    onSelected: (_) =>
                        setState(() => _filter = _NoteFilter.all),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.alarm_rounded, size: 16),
                    label: Text('Reminders ($upcoming upcoming)'),
                    selected: _filter == _NoteFilter.reminders,
                    onSelected: (_) =>
                        setState(() => _filter = _NoteFilter.reminders),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                EmptyState(
                  icon: Icons.sticky_note_2_rounded,
                  title: store.notes.isEmpty
                      ? 'No notes yet'
                      : 'Nothing matches',
                  message: store.notes.isEmpty
                      ? 'Jot down anything: money you lent, bills to pay, '
                          'shopping lists. Add a reminder and PennyWise will '
                          'notify you at that time.'
                      : 'Try a different search or filter.',
                )
              else
                for (final n in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Dismissible(
                      key: ValueKey('note-${n.id}'),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => _confirmDelete(n),
                      onDismissed: (_) => _delete(store, n),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: context.penny.expense.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(Icons.delete_outline_rounded,
                            color: context.penny.expense),
                      ),
                      child: NoteCard(
                        note: n,
                        now: now,
                        onTap: () => NoteEditorScreen.open(context, existing: n),
                        onTogglePin: () => store.setNotePinned(n, !n.pinned),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact card for one note; also used on the dashboard.
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.now,
    this.onTap,
    this.onTogglePin,
  });

  final Note note;
  final DateTime now;
  final VoidCallback? onTap;
  final VoidCallback? onTogglePin;

  @override
  Widget build(BuildContext context) {
    final at = note.reminderAt;
    final upcoming = note.hasUpcomingReminder(now);
    final reminderColor =
        upcoming ? context.penny.accent : context.penny.textMuted;
    final preview = note.title.trim().isEmpty
        ? note.body.trim().split('\n').skip(1).join(' ').trim()
        : note.body.trim();

    return PennyCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  note.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
              ),
              if (onTogglePin != null)
                IconButton(
                  tooltip: note.pinned ? 'Unpin' : 'Pin',
                  visualDensity: VisualDensity.compact,
                  onPressed: onTogglePin,
                  icon: Icon(
                    note.pinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    size: 18,
                    color: note.pinned
                        ? context.colors.primary
                        : context.penny.textMuted,
                  ),
                ),
            ],
          ),
          if (preview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10, top: 2),
              child: Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(height: 1.4),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (at != null) ...[
                Icon(
                    upcoming ? Icons.alarm_rounded : Icons.alarm_off_rounded,
                    size: 15,
                    color: reminderColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    upcoming
                        ? reminderLabel(at, now)
                        : 'Reminded ${reminderLabel(at, now)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelMedium?.copyWith(
                        color: reminderColor, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Flexible(
                child: Text(
                  'Edited ${DateUtilsX.relativeDay(note.updatedAt, now: now)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall
                      ?.copyWith(color: context.penny.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
