import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/goal.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/category_icons.dart';
import '../../utils/date_utils.dart';
import '../../utils/money.dart';

/// Opens the sheet to create a new savings goal or edit [existing].
Future<Goal?> showGoalEditor(BuildContext context, {Goal? existing}) {
  return showModalBottomSheet<Goal>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _GoalEditor(existing: existing),
  );
}

class _GoalEditor extends StatefulWidget {
  const _GoalEditor({this.existing});

  final Goal? existing;

  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _target = TextEditingController(
      text: widget.existing != null
          ? Money.toEditable(widget.existing!.targetMinor)
          : '');
  late final TextEditingController _saved = TextEditingController(
      text: widget.existing != null
          ? Money.toEditable(widget.existing!.savedMinor)
          : '0');
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');

  late DateTime? _targetDate = widget.existing?.targetDate;
  late String _icon = widget.existing?.iconKey ?? 'savings';
  late int _color = widget.existing?.colorValue ?? 0xFF34D399;
  late bool _completed = widget.existing?.completed ?? false;

  String? _error;
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _saved.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? DateUtilsX.addMonths(now, 6),
      firstDate: now,
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null) return;
    setState(() => _targetDate = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a goal name.');
      return;
    }
    final targetMinor = Money.parseToMinor(_target.text);
    if (targetMinor == null || targetMinor <= 0) {
      setState(() => _error = 'Target amount must be greater than zero.');
      return;
    }
    final savedMinor = Money.parseToMinor(_saved.text) ?? 0;

    final store = context.read<FinanceStore>();
    final navigator = Navigator.of(context);

    setState(() {
      _saving = true;
      _error = null;
    });

    final now = DateTime.now();
    try {
      final existing = widget.existing;
      Goal saved;
      if (existing == null) {
        saved = await store.addGoal(Goal(
          name: name,
          targetMinor: targetMinor,
          savedMinor: savedMinor,
          targetDate: _targetDate,
          colorValue: _color,
          iconKey: _icon,
          note: _note.text.trim(),
          completed: _completed || (savedMinor >= targetMinor),
          createdAt: now,
          updatedAt: now,
        ));
      } else {
        saved = existing.copyWith(
          name: name,
          targetMinor: targetMinor,
          savedMinor: savedMinor,
          targetDate: _targetDate,
          clearTargetDate: _targetDate == null,
          colorValue: _color,
          iconKey: _icon,
          note: _note.text.trim(),
          completed: _completed || (savedMinor >= targetMinor),
          updatedAt: now,
        );
        await store.updateGoal(saved);
      }
      navigator.pop(saved);
    } on StoreException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final store = context.watch<FinanceStore>();
    final currency = store.currency;
    final now = DateTime.now();

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_editing ? 'Edit savings goal' : 'New savings goal',
                style: context.text.titleLarge),
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              autofocus: !_editing,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Goal name',
                hintText: 'e.g. Vacation in Japan, Emergency fund',
                errorText: _error,
                counterText: '',
                prefixIcon: Icon(CategoryIcons.of(_icon), color: Color(_color)),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _target,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      LengthLimitingTextInputFormatter(14),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Target amount',
                      prefixText: '${currency.symbol} ',
                      hintText: '0',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _saved,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      LengthLimitingTextInputFormatter(14),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Already saved',
                      prefixText: '${currency.symbol} ',
                      hintText: '0',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Target date (optional)', style: context.text.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('No deadline'),
                  selected: _targetDate == null,
                  onSelected: (_) => setState(() => _targetDate = null),
                ),
                ChoiceChip(
                  label: const Text('3 months'),
                  selected: _targetDate != null &&
                      DateUtilsX.isSameDay(
                          _targetDate!, DateUtilsX.addMonths(now, 3)),
                  onSelected: (_) => setState(
                      () => _targetDate = DateUtilsX.addMonths(now, 3)),
                ),
                ChoiceChip(
                  label: const Text('6 months'),
                  selected: _targetDate != null &&
                      DateUtilsX.isSameDay(
                          _targetDate!, DateUtilsX.addMonths(now, 6)),
                  onSelected: (_) => setState(
                      () => _targetDate = DateUtilsX.addMonths(now, 6)),
                ),
                ChoiceChip(
                  label: const Text('1 year'),
                  selected: _targetDate != null &&
                      DateUtilsX.isSameDay(
                          _targetDate!, DateUtilsX.addMonths(now, 12)),
                  onSelected: (_) => setState(
                      () => _targetDate = DateUtilsX.addMonths(now, 12)),
                ),
                ActionChip(
                  avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: Text(_targetDate == null
                      ? 'Pick date'
                      : DateUtilsX.dayMonthYear(_targetDate!)),
                  onPressed: _pickDate,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Colour', style: context.text.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in CategoryIcons.palette)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == _color
                              ? context.colors.onSurface
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Icon', style: context.text.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final key in const [
                  'savings',
                  'investment',
                  'bank',
                  'wallet',
                  'travel',
                  'home',
                  'transport',
                  'shopping',
                  'education',
                  'health',
                  'gift',
                  'other',
                ])
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _icon = key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: key == _icon
                            ? Color(_color).withValues(alpha: 0.2)
                            : context.penny.surfaceHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              key == _icon ? Color(_color) : Colors.transparent,
                        ),
                      ),
                      child: Icon(
                        CategoryIcons.of(key),
                        size: 22,
                        color: key == _icon
                            ? Color(_color)
                            : context.penny.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'e.g. Keep savings in HDFC fixed deposit',
                counterText: '',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            if (_editing) ...[
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mark as completed'),
                value: _completed,
                onChanged: (v) => setState(() => _completed = v),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_editing ? 'Save changes' : 'Create goal'),
            ),
          ],
        ),
      ),
    );
  }
}
