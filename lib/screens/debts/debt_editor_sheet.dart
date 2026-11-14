import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/debt_entry.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/date_utils.dart';
import '../../utils/money.dart';
import '../../widgets/segmented.dart';

/// Opens the sheet to create or edit a [DebtEntry].
Future<DebtEntry?> showDebtEditor(BuildContext context, {DebtEntry? existing}) {
  return showModalBottomSheet<DebtEntry>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DebtEditor(existing: existing),
  );
}

class _DebtEditor extends StatefulWidget {
  const _DebtEditor({this.existing});

  final DebtEntry? existing;

  @override
  State<_DebtEditor> createState() => _DebtEditorState();
}

class _DebtEditorState extends State<_DebtEditor> {
  late final TextEditingController _person =
      TextEditingController(text: widget.existing?.personName ?? '');
  late final TextEditingController _amount = TextEditingController(
      text: widget.existing != null
          ? Money.toEditable(widget.existing!.amountMinor)
          : '');
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');

  late DebtType _type = widget.existing?.type ?? DebtType.lent;
  late DateTime? _dueDate = widget.existing?.dueDate;

  String? _error;
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now.add(const Duration(days: 7)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: DateTime(now.year + 10),
      helpText: 'Select due date',
    );
    if (picked == null) return;
    setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    final person = _person.text.trim();
    if (person.isEmpty) {
      setState(() => _error = 'Please enter a name.');
      return;
    }
    final amountMinor = Money.parseToMinor(_amount.text);
    if (amountMinor == null || amountMinor <= 0) {
      setState(() => _error = 'Amount must be greater than zero.');
      return;
    }

    final store = context.read<FinanceStore>();
    final navigator = Navigator.of(context);

    setState(() {
      _saving = true;
      _error = null;
    });

    final now = DateTime.now();
    try {
      final existing = widget.existing;
      DebtEntry saved;
      if (existing == null) {
        saved = await store.addDebt(DebtEntry(
          personName: person,
          amountMinor: amountMinor,
          type: _type,
          note: _note.text.trim(),
          dueDate: _dueDate,
          createdAt: now,
          updatedAt: now,
        ));
      } else {
        saved = existing.copyWith(
          personName: person,
          amountMinor: amountMinor,
          type: _type,
          note: _note.text.trim(),
          dueDate: _dueDate,
          clearDueDate: _dueDate == null,
          updatedAt: now,
        );
        await store.updateDebt(saved);
      }
      navigator.pop(saved);
    } on StoreException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    final currency = store.currency;
    final insets = MediaQuery.viewInsetsOf(context);

    // Collect existing contact names for quick suggestion chips
    final existingNames = store.debts
        .map((d) => d.personName.trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _editing ? 'Edit debt' : 'New IOU / Debt',
                style: context.text.titleLarge,
              ),
              const SizedBox(height: 16),

              // Debt Type Selector: Lent vs Borrowed
              PennySegmented<DebtType>(
                values: DebtType.values,
                selected: _type,
                labelOf: (t) => t == DebtType.lent
                    ? 'They owe me (Lent)'
                    : 'I owe them (Borrowed)',
                onChanged: (t) => setState(() => _type = t),
              ),
              const SizedBox(height: 16),

              // Person Name
              TextField(
                controller: _person,
                autofocus: !_editing,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Person name',
                  hintText: 'e.g. Alex, Mom, Rahul',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              if (existingNames.isNotEmpty && !_editing) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final name in existingNames.take(5))
                      ActionChip(
                        label: Text(name),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            _person.text = name;
                            _error = null;
                          });
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),

              // Amount
              TextField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '${currency.symbol} ',
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 14),

              // Note
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reason / Note (optional)',
                  hintText: 'e.g. Dinner, Concert tickets, Shared groceries',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 16),

              // Due date row
              InkWell(
                onTap: _pickDueDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.colors.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_rounded,
                          size: 20, color: context.colors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _dueDate != null
                              ? 'Due on ${DateUtilsX.dayMonthYear(_dueDate!)}'
                              : 'No due date (tap to set)',
                          style: context.text.bodyMedium,
                        ),
                      ),
                      if (_dueDate != null)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _dueDate = null),
                        )
                      else
                        Icon(Icons.chevron_right_rounded,
                            size: 20, color: context.penny.textMuted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Quick presets for due date
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('In 1 week'),
                    onPressed: () => setState(() =>
                        _dueDate = DateTime.now().add(const Duration(days: 7))),
                  ),
                  ActionChip(
                    label: const Text('In 1 month'),
                    onPressed: () => setState(() => _dueDate =
                        DateUtilsX.addMonths(DateTime.now(), 1)),
                  ),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(color: context.penny.expense)),
              ],
              const SizedBox(height: 20),

              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_editing ? 'Save changes' : 'Add IOU / Debt'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
