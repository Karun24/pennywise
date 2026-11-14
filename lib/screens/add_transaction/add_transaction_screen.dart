import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/account.dart';
import '../../models/category.dart';
import '../../models/recurring_rule.dart';
import '../../models/transaction_entry.dart';
import '../../services/budget_service.dart';
import '../../services/receipt_service.dart';
import '../../services/smart/transaction_parser.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/category_icons.dart';
import '../../utils/date_utils.dart';
import '../../utils/money.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/segmented.dart';
import '../settings/category_editor_sheet.dart';
import '../sms/sms_import_sheet.dart';
import 'smart_entry_card.dart';

/// What happened on the add/edit screen, reported back to the caller.
class _ScreenResult {
  const _ScreenResult(this.message, {this.alerts = const [], this.deleted});
  final String message;
  final List<String> alerts;
  final TransactionEntry? deleted;
}

/// Add or edit an income/expense.
class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({
    super.key,
    this.existing,
    this.initialRepeat,
    this.initialType,
  });

  final TransactionEntry? existing;

  /// Pre-selects a repeat frequency (used by "New recurring").
  final RepeatFrequency? initialRepeat;

  /// Pre-selects a transaction type (e.g. from launcher shortcuts).
  final TransactionType? initialType;

  /// Opens the screen and shows the outcome (and any budget alert) as a
  /// snack bar on the calling screen.
  static Future<void> open(
    BuildContext context, {
    TransactionEntry? existing,
    RepeatFrequency? initialRepeat,
    TransactionType? initialType,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final store = context.read<FinanceStore>();
    final result = await Navigator.of(context).push<_ScreenResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AddTransactionScreen(
          existing: existing,
          initialRepeat: initialRepeat,
          initialType: initialType,
        ),
      ),
    );
    if (result == null) return;
    messenger.hideCurrentSnackBar();
    final deleted = result.deleted;
    if (deleted != null) {
      messenger.showSnackBar(pennySnack(
        result.message,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => store.restoreTransaction(deleted),
        ),
      ));
      return;
    }
    if (result.alerts.isNotEmpty) {
      messenger.showSnackBar(
          pennySnack('${result.message} ${result.alerts.first}', error: true));
    } else {
      messenger.showSnackBar(pennySnack(result.message));
    }
  }

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _tag = TextEditingController();
  late TransactionType _type;
  int? _categoryId;
  bool _categoryManual = false;
  String? _autoReason;
  late DateTime _date;
  PaymentMethod _payment = PaymentMethod.upi;
  int? _accountId;
  int? _toAccountId;
  String? _receiptPath;

  /// Null = does not repeat.
  late RepeatFrequency? _repeat = widget.initialRepeat;
  String? _amountError;
  bool _saving = false;

  /// Shown under Smart entry after it fills the form (a snack bar would
  /// cover the Save button).
  String? _smartMessage;
  bool _smartMessageIsWarning = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _type = e.type;
      _amount.text = Money.toEditable(e.amountMinor);
      _note.text = e.note;
      _tag.text = e.tag;
      _categoryId = e.categoryId;
      _categoryManual = true;
      _date = e.date;
      _payment = e.paymentMethod;
      _accountId = e.accountId;
      _toAccountId = e.toAccountId;
      _receiptPath = e.receiptPath;
    } else {
      _type = widget.initialType ?? TransactionType.expense;
      _date = DateTime.now();
    }
    _note.addListener(_autoCategorize);
  }

  @override
  void dispose() {
    _note.removeListener(_autoCategorize);
    _amount.dispose();
    _note.dispose();
    _tag.dispose();
    super.dispose();
  }

  /// Rule-based auto-categorisation while typing the description. Only
  /// applies while the user has not picked a category themselves.
  void _autoCategorize() {
    if (_categoryManual || _type == TransactionType.transfer) return;
    final store = context.read<FinanceStore>();
    final match = store.categorizer.suggest(_note.text, type: _type);
    if (match != null && match.confident) {
      if (_categoryId != match.category.id) {
        setState(() {
          _categoryId = match.category.id;
          _autoReason = match.reason;
        });
      }
    } else if (_autoReason != null) {
      setState(() {
        _categoryId = null;
        _autoReason = null;
      });
    }
  }

  void _setType(TransactionType t) {
    if (t == _type) return;
    final store = context.read<FinanceStore>();
    setState(() {
      _type = t;
      if (t == TransactionType.transfer) {
        if (_toAccountId == null && store.accounts.length > 1) {
          _toAccountId = store.accounts
              .firstWhere((a) => a.id != _accountId,
                  orElse: () => store.accounts.last)
              .id;
        }
      } else {
        final current =
            _categoryId == null ? null : store.categoryById(_categoryId!);
        if (current != null && current.kind != t) {
          _categoryId = null;
          _categoryManual = false;
          _autoReason = null;
        }
      }
    });
    if (t != TransactionType.transfer) {
      _autoCategorize();
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() => _setDay(picked));
  }

  void _setDay(DateTime day) {
    // Keep the time of day so ordering within a day stays natural.
    final t = _editing ? _date : DateTime.now();
    _date = DateTime(day.year, day.month, day.day, t.hour, t.minute, t.second);
  }

  /// Fills the form from a confirmed smart-entry parse.
  void _applyParsed(ParsedTransaction p) {
    setState(() {
      if (p.type != null) _type = p.type!;
      if (p.amountMinor != null) {
        _amount.text = Money.toEditable(p.amountMinor!);
        _amountError = null;
      }
      if (p.category != null && p.category!.kind == _type) {
        _categoryId = p.category!.id;
        _categoryManual = true;
        _autoReason = null;
      } else {
        _categoryId = null;
        _categoryManual = false;
      }
      if (p.dateDetected) _setDay(p.date);
      if (p.paymentMethod != null) _payment = p.paymentMethod!;
    });
    _note.removeListener(_autoCategorize);
    _note.text = p.description;
    _note.addListener(_autoCategorize);
    if (_categoryId == null) _autoCategorize();
    final missing = <String>[
      if (p.amountMinor == null) 'amount',
      if (p.type == null) 'type',
      if (_categoryId == null && _type != TransactionType.transfer) 'category',
    ];
    setState(() {
      _smartMessageIsWarning = missing.isNotEmpty;
      _smartMessage = missing.isEmpty
          ? 'Details filled in. Review them, then tap Save.'
          : 'Filled what I could. Please choose the ${missing.join(', ')}.';
    });
  }

  Future<void> _save() async {
    final store = context.read<FinanceStore>();
    final navigator = Navigator.of(context);
    final minor = Money.parseToMinor(_amount.text);
    if (minor == null) {
      setState(() => _amountError = 'Enter an amount greater than zero');
      return;
    }

    final isTransfer = _type == TransactionType.transfer;

    if (isTransfer) {
      if (_accountId == null || _toAccountId == null) {
        showSnack(context, 'Please choose both source and destination accounts.',
            error: true);
        return;
      }
      if (_accountId == _toAccountId) {
        showSnack(context, 'Cannot transfer money to the same account.',
            error: true);
        return;
      }
      _categoryId ??= store.categories.firstOrNull?.id ?? 1;
    } else {
      if (_categoryId == null) {
        showSnack(context, 'Please choose a category.', error: true);
        return;
      }
      _accountId ??= store.defaultAccount.id ?? store.accounts.firstOrNull?.id;
    }

    setState(() {
      _amountError = null;
      _saving = true;
    });
    final now = DateTime.now();
    final entry = TransactionEntry(
      id: widget.existing?.id,
      type: _type,
      amountMinor: minor,
      categoryId: _categoryId!,
      note: _note.text.trim(),
      date: _date,
      paymentMethod: isTransfer ? PaymentMethod.other : _payment,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
      recurringId: widget.existing?.recurringId,
      accountId: _accountId,
      toAccountId: isTransfer ? _toAccountId : null,
      tag: _tag.text.trim().replaceAll('#', ''),
      receiptPath: _receiptPath,
    );
    try {
      final repeat = _repeat;
      if (!_editing && repeat != null && !isTransfer) {
        final rule = await store.addRecurring(entry, repeat);
        final started = !rule.nextDue.isAtSameMomentAs(
            DateTime(_date.year, _date.month, _date.day));
        navigator.pop(_ScreenResult(
          '${repeat.label} ${_type.label.toLowerCase()} of '
          '${store.format(minor)} set up. '
          '${started ? 'First one added; next' : 'First one'} on '
          '${DateUtilsX.dayMonthYear(rule.nextDue)}.',
        ));
        return;
      }
      if (_editing) {
        await store.updateTransaction(entry);
        navigator.pop(const _ScreenResult('Transaction updated'));
      } else {
        final crossed = await store.addTransaction(entry);
        navigator.pop(_ScreenResult(
          isTransfer
              ? 'Transfer of ${store.format(minor)} saved.'
              : '${_type.label} of ${store.format(minor)} saved.',
          alerts: crossed.map((s) => _alertText(store, s)).toList(),
        ));
      }
    } on StoreException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, e.message, error: true);
    }
  }

  static String _alertText(FinanceStore store, BudgetStatus s) {
    final name = s.categoryId == null
        ? 'monthly budget'
        : '${store.categoryById(s.categoryId!)?.name ?? ''} budget';
    if (s.level == BudgetLevel.exceeded) return 'You have exceeded your $name.';
    return 'You have used ${(s.ratio * 100).round()}% of your $name.';
  }

  Future<void> _pickReceipt() async {
    final path = await const ReceiptService().pickAndSaveReceipt();
    if (path != null && mounted) {
      setState(() => _receiptPath = path);
    }
  }

  void _removeReceipt() {
    setState(() => _receiptPath = null);
  }

  Future<void> _delete() async {
    final store = context.read<FinanceStore>();
    final navigator = Navigator.of(context);
    final ok = await confirmAction(
      context,
      title: 'Delete transaction?',
      message: 'This removes it from your history and all totals.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      final e = widget.existing!;
      if (e.hasReceipt) {
        await const ReceiptService().deleteReceipt(e.receiptPath);
      }
      await store.deleteTransaction(e);
      navigator.pop(_ScreenResult('Transaction deleted', deleted: e));
    } on StoreException catch (e) {
      if (!mounted) return;
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final currency = store.currency;
    final typeColor = switch (_type) {
      TransactionType.expense => context.penny.expense,
      TransactionType.income => context.penny.income,
      TransactionType.transfer => context.penny.accent,
    };

    if (_accountId == null && store.accounts.isNotEmpty) {
      _accountId = store.defaultAccount.id ?? store.accounts.first.id;
    }
    if (_type == TransactionType.transfer &&
        _toAccountId == null &&
        store.accounts.length > 1) {
      _toAccountId = store.accounts
          .firstWhere((a) => a.id != _accountId,
              orElse: () => store.accounts.last)
          .id;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(_editing ? 'Edit transaction' : 'Add transaction'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline_rounded,
                  color: context.penny.expense),
              onPressed: _saving ? null : _delete,
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
                    if (!_editing) ...[
                      SmartEntryCard(onApply: _applyParsed),
                      if (_smartMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _smartMessageIsWarning
                                    ? Icons.info_outline_rounded
                                    : Icons.check_circle_rounded,
                                size: 18,
                                color: _smartMessageIsWarning
                                    ? context.penny.warning
                                    : context.penny.income,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _smartMessage!,
                                  style: context.text.bodySmall?.copyWith(
                                    color: _smartMessageIsWarning
                                        ? context.penny.warning
                                        : context.penny.income,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () => SmsImportSheet.show(context),
                            icon: const Icon(Icons.sms_outlined, size: 16),
                            label: const Text('Import from Bank SMS'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    PennySegmented<TransactionType>(
                      values: TransactionType.values,
                      selected: _type,
                      labelOf: (t) => t.label,
                      colorOf: (t) => switch (t) {
                        TransactionType.expense => context.penny.expense,
                        TransactionType.income => context.penny.income,
                        TransactionType.transfer => context.penny.accent,
                      },
                      onChanged: _setType,
                    ),
                    const SizedBox(height: 20),
                    _Label('Amount'),
                    TextField(
                      controller: _amount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        LengthLimitingTextInputFormatter(14),
                      ],
                      style: context.text.headlineMedium?.copyWith(
                        color: typeColor,
                        fontFeatures: tabularFigures,
                      ),
                      decoration: InputDecoration(
                        prefixText: '${currency.symbol} ',
                        prefixStyle: context.text.headlineMedium
                            ?.copyWith(color: typeColor),
                        hintText: '0',
                        errorText: _amountError,
                      ),
                      onChanged: (_) {
                        if (_amountError != null) {
                          setState(() => _amountError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 18),
                    if (_type == TransactionType.transfer) ...[
                      _Label('Transfer from'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final a in store.accounts)
                            ChoiceChip(
                              avatar: Icon(CategoryIcons.of(a.iconKey),
                                  size: 16, color: a.color),
                              label: Text(a.name),
                              selected: _accountId == a.id,
                              onSelected: (_) =>
                                  setState(() => _accountId = a.id),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _Label('Transfer to'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final a in store.accounts)
                            ChoiceChip(
                              avatar: Icon(CategoryIcons.of(a.iconKey),
                                  size: 16, color: a.color),
                              label: Text(a.name),
                              selected: _toAccountId == a.id,
                              onSelected: (_) =>
                                  setState(() => _toAccountId = a.id),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _Label('Description (optional)'),
                      TextField(
                        controller: _note,
                        maxLength: 120,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'e.g. ATM withdrawal, Credit card payment',
                          counterText: '',
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                    ] else ...[
                      if (store.accounts.isNotEmpty) ...[
                        _Label(_type == TransactionType.expense
                            ? 'Paid from account'
                            : 'Deposit into account'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final a in store.accounts)
                              ChoiceChip(
                                avatar: Icon(CategoryIcons.of(a.iconKey),
                                    size: 16, color: a.color),
                                label: Text(a.name),
                                selected: _accountId == a.id,
                                onSelected: (_) =>
                                    setState(() => _accountId = a.id),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],
                      _Label('Description'),
                      TextField(
                        controller: _note,
                        maxLength: 120,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Lunch at Swiggy',
                          counterText: '',
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(child: _Label('Category')),
                          if (_autoReason != null && !_categoryManual)
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Pill(
                                  icon: Icons.auto_awesome_rounded,
                                  label: 'Auto · $_autoReason',
                                  color: context.penny.accent,
                                ),
                              ),
                            ),
                        ],
                      ),
                      _CategoryGrid(
                        categories: store.categoriesOf(_type),
                        selectedId: _categoryId,
                        onSelect: (c) => setState(() {
                          _categoryId = c.id;
                          _categoryManual = true;
                          _autoReason = null;
                        }),
                        onCreate: () async {
                          final created = await showCategoryEditor(context,
                              initialKind: _type);
                          if (created != null && mounted) {
                            setState(() {
                              _type = created.kind;
                              _categoryId = created.id;
                              _categoryManual = true;
                              _autoReason = null;
                            });
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 18),
                    _Label('Event / Trip tag (optional)'),
                    TextField(
                      controller: _tag,
                      maxLength: 30,
                      decoration: const InputDecoration(
                        hintText: 'e.g. GoaTrip, Diwali, Vacation',
                        counterText: '',
                        prefixIcon: Icon(Icons.tag_rounded),
                      ),
                    ),
                    if (store.allTags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in store.allTags)
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              label: Text('#$t'),
                              onPressed: () => setState(() => _tag.text = t),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    _Label('Date'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _DateChip(
                          label: 'Today',
                          selected: DateUtilsX.isSameDay(_date, DateTime.now()),
                          onTap: () => setState(() => _setDay(DateTime.now())),
                        ),
                        _DateChip(
                          label: 'Yesterday',
                          selected: DateUtilsX.isSameDay(
                              _date, DateUtilsX.addDays(DateTime.now(), -1)),
                          onTap: () => setState(() =>
                              _setDay(DateUtilsX.addDays(DateTime.now(), -1))),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.calendar_month_rounded,
                              size: 18),
                          label: Text(DateUtilsX.dayMonthYear(_date)),
                          onPressed: _pickDate,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _Label('Receipt / Bill (optional)'),
                    if (_receiptPath == null)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        onPressed: _pickReceipt,
                        icon: const Icon(Icons.receipt_long_rounded),
                        label: const Text('Attach receipt or invoice photo'),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.penny.surfaceHigh,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: context.penny.border),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(_receiptPath!),
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.receipt_rounded,
                                    size: 32),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Receipt attached',
                                      style: context.text.titleSmall),
                                  const SizedBox(height: 2),
                                  Text('Tap to replace',
                                      style: context.text.bodySmall),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Replace receipt',
                              icon: const Icon(Icons.refresh_rounded, size: 20),
                              onPressed: _pickReceipt,
                            ),
                            IconButton(
                              tooltip: 'Remove receipt',
                              icon: Icon(Icons.close_rounded,
                                  color: context.penny.expense, size: 20),
                              onPressed: _removeReceipt,
                            ),
                          ],
                        ),
                      ),
                    if (_type != TransactionType.transfer) ...[
                      const SizedBox(height: 18),
                      _Label('Payment method'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final m in PaymentMethod.values)
                            ChoiceChip(
                              label: Text(m.label),
                              selected: _payment == m,
                              onSelected: (_) => setState(() => _payment = m),
                            ),
                        ],
                      ),
                      if (!_editing) ...[
                        const SizedBox(height: 18),
                        _Label('Repeat'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Never'),
                              selected: _repeat == null,
                              onSelected: (_) => setState(() => _repeat = null),
                            ),
                            for (final f in RepeatFrequency.values)
                              ChoiceChip(
                                avatar: _repeat == f
                                    ? const Icon(Icons.repeat_rounded, size: 16)
                                    : null,
                                label: Text(f.label),
                                selected: _repeat == f,
                                onSelected: (_) => setState(() => _repeat = f),
                              ),
                          ],
                        ),
                        if (_repeat != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 2),
                            child: Text(
                              'PennyWise will add this automatically '
                              '${_repeatHint(_repeat!, _date)}, starting '
                              '${DateUtilsX.dayMonthYear(_date)}. Manage it in '
                              'Profile > Recurring transactions.',
                              style: context.text.bodySmall,
                            ),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
              Padding(
                padding: pagePadding(context, top: 8, bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: typeColor),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : Text(_editing
                            ? 'Save changes'
                            : _type == TransactionType.transfer
                                ? 'Save transfer'
                                : _repeat != null
                                    ? 'Save ${_repeat!.label.toLowerCase()} '
                                        '${_type.label.toLowerCase()}'
                                    : 'Save ${_type.label.toLowerCase()}'),
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

String _repeatHint(RepeatFrequency f, DateTime start) {
  final rule = RecurringRule(
    type: TransactionType.expense,
    amountMinor: 1,
    categoryId: 0,
    note: '',
    paymentMethod: PaymentMethod.other,
    frequency: f,
    anchorDay: start.day,
    nextDue: start,
    createdAt: start,
  );
  final d = rule.describe();
  return d[0].toLowerCase() + d.substring(1);
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: context.text.labelLarge
                ?.copyWith(color: context.penny.textMuted)),
      );
}

class _DateChip extends StatelessWidget {
  const _DateChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      );
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    required this.onCreate,
  });

  final List<Category> categories;
  final int? selectedId;
  final ValueChanged<Category> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 520 ? 5 : 4;
      const spacing = 8.0;
      final w = (c.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final cat in categories)
            _CategoryTile(
              width: w,
              category: cat,
              selected: cat.id == selectedId,
              onTap: () => onSelect(cat),
            ),
          SizedBox(
            width: w,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onCreate,
              child: Container(
                height: 84,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.penny.border),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, color: context.colors.primary),
                    const SizedBox(height: 6),
                    Text('New',
                        style: context.text.labelMedium
                            ?.copyWith(color: context.colors.primary)),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.width,
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = category.color;
    return SizedBox(
      width: width,
      child: Semantics(
        selected: selected,
        button: true,
        label: category.name,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 84,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: selected
                  ? color.withValues(alpha: context.isDark ? 0.22 : 0.16)
                  : context.penny.surfaceHigh,
              border: Border.all(
                color: selected ? color : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CategoryAvatar(category: category, size: 34),
                const SizedBox(height: 6),
                Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.text.labelSmall?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
