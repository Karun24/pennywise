import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/debt_entry.dart';
import '../../models/transaction_entry.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/money.dart';
import '../../widgets/dialogs.dart';

/// Opens the Smart Split Bill calculator & batch debt generator.
Future<void> showSplitBillSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _SplitBillSheet(),
  );
}

class _SplitBillSheet extends StatefulWidget {
  const _SplitBillSheet();

  @override
  State<_SplitBillSheet> createState() => _SplitBillSheetState();
}

class _SplitBillSheetState extends State<_SplitBillSheet> {
  final TextEditingController _totalAmount = TextEditingController();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _newPerson = TextEditingController();

  final List<String> _people = ['Me'];
  bool _iPaid = true;
  bool _recordTransaction = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _totalAmount.dispose();
    _title.dispose();
    _newPerson.dispose();
    super.dispose();
  }

  void _addPerson() {
    final name = _newPerson.text.trim();
    if (name.isEmpty) return;
    if (_people.any((p) => p.toLowerCase() == name.toLowerCase())) {
      setState(() => _error = '$name is already in the split.');
      return;
    }
    setState(() {
      _people.add(name);
      _newPerson.clear();
      _error = null;
    });
  }

  void _removePerson(int index) {
    if (_people[index] == 'Me') return;
    setState(() {
      _people.removeAt(index);
    });
  }

  Future<void> _createSplit() async {
    final totalMinor = Money.parseToMinor(_totalAmount.text);
    if (totalMinor == null || totalMinor <= 0) {
      setState(() => _error = 'Please enter a valid bill amount.');
      return;
    }
    if (_people.length < 2) {
      setState(() => _error = 'Add at least one person to split the bill with.');
      return;
    }

    final store = context.read<FinanceStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _saving = true;
      _error = null;
    });

    final count = _people.length;
    final shareMinor = totalMinor ~/ count;
    final remainder = totalMinor % count;
    final billTitle = _title.text.trim().isEmpty ? 'Split bill' : _title.text.trim();
    final now = DateTime.now();

    try {
      if (_iPaid) {
        // I paid the bill. Everyone else owes me `shareMinor`.
        var extra = remainder;
        for (final person in _people) {
          if (person == 'Me') continue;
          final personShare = shareMinor + (extra > 0 ? 1 : 0);
          if (extra > 0) extra--;

          await store.addDebt(DebtEntry(
            personName: person,
            amountMinor: personShare,
            type: DebtType.lent,
            note: '$billTitle (Split of ${Money.format(totalMinor, store.currency)})',
            createdAt: now,
            updatedAt: now,
          ));
        }

        // Optionally record my own expense share in the ledger
        if (_recordTransaction && store.categories.isNotEmpty) {
          final myShare = shareMinor + (extra > 0 ? 1 : 0);
          final cat = store.categoriesOf(TransactionType.expense).firstOrNull ??
              store.categories.first;
          await store.addTransaction(
            TransactionEntry(
              type: TransactionType.expense,
              amountMinor: myShare,
              categoryId: cat.id!,
              accountId: store.defaultAccount.id,
              date: now,
              note: '$billTitle (My share)',
              paymentMethod: PaymentMethod.upi,
              tags: const ['split-bill'],
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      } else {
        // Someone else paid. I owe them my share.
        final payer = _people.firstWhere((p) => p != 'Me', orElse: () => 'Friend');
        final myShare = shareMinor;

        await store.addDebt(DebtEntry(
          personName: payer,
          amountMinor: myShare,
          type: DebtType.borrowed,
          note: '$billTitle (Split of ${Money.format(totalMinor, store.currency)})',
          createdAt: now,
          updatedAt: now,
        ));
      }

      navigator.pop();
      messenger.showSnackBar(
        pennySnack('Split bill created for ${_people.length - 1} friend${_people.length - 1 > 1 ? 's' : ''}'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    final currency = store.currency;
    final insets = MediaQuery.viewInsetsOf(context);

    final totalMinor = Money.parseToMinor(_totalAmount.text) ?? 0;
    final count = _people.length;
    final shareMinor = count > 0 && totalMinor > 0 ? totalMinor ~/ count : 0;

    final existingContacts = store.debts
        .map((d) => d.personName.trim())
        .where((n) => n.isNotEmpty && !_people.contains(n))
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
              Row(
                children: [
                  Icon(Icons.call_split_rounded,
                      color: context.colors.primary, size: 26),
                  const SizedBox(width: 10),
                  Text('Split a bill', style: context.text.titleLarge),
                ],
              ),
              const SizedBox(height: 16),

              // Total Bill Amount
              TextField(
                controller: _totalAmount,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: InputDecoration(
                  labelText: 'Total bill amount',
                  prefixText: '${currency.symbol} ',
                  prefixIcon: const Icon(Icons.receipt_long_rounded),
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 14),

              // Note / Description
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What was this for?',
                  hintText: 'e.g. Dinner, Movie tickets, Weekend trip',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 16),

              // Who Paid Toggle
              Text('Who paid the bill?', style: context.text.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('I paid upfront'),
                    icon: Icon(Icons.arrow_upward_rounded),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Someone else paid'),
                    icon: Icon(Icons.arrow_downward_rounded),
                  ),
                ],
                selected: {_iPaid},
                onSelectionChanged: (s) => setState(() => _iPaid = s.first),
              ),
              const SizedBox(height: 18),

              // People Involved
              Row(
                children: [
                  Text('People in split (${_people.length})',
                      style: context.text.titleSmall),
                  const Spacer(),
                  if (totalMinor > 0 && count > 0)
                    Text(
                      '~${Money.format(shareMinor, currency)} / person',
                      style: context.text.titleSmall?.copyWith(
                        color: context.colors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _people.length; i++)
                    Chip(
                      avatar: CircleAvatar(
                        backgroundColor: _people[i] == 'Me'
                            ? context.colors.primary
                            : context.colors.secondary,
                        child: Text(
                          _people[i][0].toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ),
                      label: Text(_people[i]),
                      onDeleted:
                          _people[i] == 'Me' ? null : () => _removePerson(i),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Add person input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newPerson,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Add person name…',
                        isDense: true,
                        prefixIcon: Icon(Icons.person_add_rounded, size: 20),
                      ),
                      onSubmitted: (_) => _addPerson(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _addPerson,
                    child: const Text('Add'),
                  ),
                ],
              ),

              if (existingContacts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final contact in existingContacts.take(5))
                      ActionChip(
                        label: Text('+ $contact'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            _people.add(contact);
                            _error = null;
                          });
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),

              if (_iPaid)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _recordTransaction,
                  title: const Text('Record my share as expense in ledger'),
                  subtitle: Text(
                    'Automatically logs an expense of ${Money.format(shareMinor, currency)} for you',
                    style: context.text.bodySmall,
                  ),
                  onChanged: (v) =>
                      setState(() => _recordTransaction = v ?? true),
                ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(color: context.penny.expense)),
              ],
              const SizedBox(height: 20),

              FilledButton(
                onPressed: _saving ? null : _createSplit,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'Create split debts (${_people.length - 1} people)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
