import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/transaction_entry.dart';
import '../../services/bank_sms_parser.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../widgets/dialogs.dart';
import '../add_transaction/add_transaction_screen.dart';

/// Modal sheet for parsing bank/UPI SMS messages into transactions on-device.
class SmsImportSheet extends StatefulWidget {
  const SmsImportSheet({
    super.key,
    this.initialText,
  });

  final String? initialText;

  static Future<void> show(BuildContext context, {String? initialText}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: SmsImportSheet(initialText: initialText),
      ),
    );
  }

  @override
  State<SmsImportSheet> createState() => _SmsImportSheetState();
}

class _SmsImportSheetState extends State<SmsImportSheet> {
  final _smsController = TextEditingController();
  final _merchantController = TextEditingController();
  final _parser = const BankSmsParser();

  ParsedSms? _parsed;
  TransactionType _type = TransactionType.expense;
  int? _selectedCategoryId;
  int? _selectedAccountId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _smsController.text = widget.initialText!;
      _parseText(widget.initialText!);
    }
  }

  @override
  void dispose() {
    _smsController.dispose();
    _merchantController.dispose();
    super.dispose();
  }

  void _parseText(String text) {
    final parsed = _parser.parse(text);
    if (parsed == null) {
      setState(() => _parsed = null);
      return;
    }

    final store = context.read<FinanceStore>();
    _merchantController.text = parsed.merchant;
    _type = parsed.type;

    // Try to find matching category
    int? catId;
    if (parsed.suggestedCategory != null) {
      final match = store.categories.firstWhere(
        (c) =>
            c.kind == _type &&
            c.name.toLowerCase() == parsed.suggestedCategory!.toLowerCase(),
        orElse: () => store.fallbackCategory(_type),
      );
      catId = match.id;
    } else {
      catId = store.fallbackCategory(_type).id;
    }

    // Try to match account by ending digits
    int? acctId;
    if (parsed.accountDigits != null && parsed.accountDigits!.isNotEmpty) {
      for (final a in store.accounts) {
        if (a.name.contains(parsed.accountDigits!)) {
          acctId = a.id;
          break;
        }
      }
    }
    acctId ??= store.defaultAccount.id;

    setState(() {
      _parsed = parsed;
      _selectedCategoryId = catId;
      _selectedAccountId = acctId;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      _smsController.text = text;
      _parseText(text);
    }
  }

  Future<void> _save() async {
    final parsed = _parsed;
    if (parsed == null || _selectedCategoryId == null) return;

    final store = context.read<FinanceStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _saving = true);
    final now = DateTime.now();
    final entry = TransactionEntry(
      type: _type,
      amountMinor: parsed.amountMinor,
      categoryId: _selectedCategoryId!,
      note: _merchantController.text.trim(),
      date: parsed.date ?? now,
      paymentMethod: PaymentMethod.upi,
      createdAt: now,
      updatedAt: now,
      accountId: _selectedAccountId,
    );

    try {
      await store.addTransaction(entry);
      navigator.pop();
      messenger.showSnackBar(pennySnack(
        'Transaction recorded: ${store.format(entry.amountMinor)} (${entry.note})',
      ));
    } catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(pennySnack('Failed to save: $e', error: true));
    }
  }

  void _openFullEditor() {
    final parsed = _parsed;
    final nav = Navigator.of(context);
    nav.pop();

    if (parsed != null) {
      final now = DateTime.now();
      final draft = TransactionEntry(
        type: _type,
        amountMinor: parsed.amountMinor,
        categoryId: _selectedCategoryId ??
            context.read<FinanceStore>().fallbackCategory(_type).id ??
            1,
        note: _merchantController.text.trim(),
        date: parsed.date ?? now,
        paymentMethod: PaymentMethod.upi,
        createdAt: now,
        updatedAt: now,
        accountId: _selectedAccountId,
      );
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AddTransactionScreen(existing: draft),
      ));
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const AddTransactionScreen(),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final parsed = _parsed;

    final availableCategories =
        store.categories.where((c) => c.kind == _type).toList();

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.penny.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.penny.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.sms_outlined,
                      color: context.penny.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bank SMS Assistant',
                          style: context.text.titleMedium),
                      const SizedBox(height: 2),
                      Text('100% on-device & private parser',
                          style: context.text.bodySmall),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.paste_rounded, size: 16),
                  label: const Text('Paste'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // SMS input field
            TextField(
              controller: _smsController,
              maxLines: 3,
              style: context.text.bodySmall,
              onChanged: _parseText,
              decoration: InputDecoration(
                hintText:
                    'Paste bank or UPI SMS message here (e.g. "Debited by Rs 450 to Zomato...")',
                hintStyle: context.text.bodySmall?.copyWith(
                  color: context.penny.textMuted,
                ),
                filled: true,
                fillColor: context.penny.surfaceHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: context.penny.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: context.penny.border),
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (parsed == null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.penny.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined,
                        size: 20, color: context.penny.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'PennyWise parses SMS messages strictly on your device. No SMS text is ever sent to any server.',
                        style: context.text.bodySmall,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              // Parsed Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.penny.surfaceHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _type == TransactionType.expense
                        ? context.penny.expense.withValues(alpha: 0.3)
                        : context.penny.income.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Amount and Type toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DETECTED AMOUNT',
                              style: context.text.labelSmall?.copyWith(
                                color: context.penny.textMuted,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              store.format(parsed.amountMinor),
                              style: context.text.headlineSmall?.copyWith(
                                color: _type == TransactionType.expense
                                    ? context.penny.expense
                                    : context.penny.income,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        SegmentedButton<TransactionType>(
                          segments: const [
                            ButtonSegment(
                              value: TransactionType.expense,
                              label: Text('Expense'),
                            ),
                            ButtonSegment(
                              value: TransactionType.income,
                              label: Text('Income'),
                            ),
                          ],
                          selected: {_type},
                          onSelectionChanged: (s) {
                            setState(() {
                              _type = s.first;
                              _selectedCategoryId =
                                  store.fallbackCategory(_type).id;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Merchant field
                    Text(
                      'DESCRIPTION / PAYEE',
                      style: context.text.labelSmall?.copyWith(
                        color: context.penny.textMuted,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _merchantController,
                      style: context.text.bodyMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        filled: true,
                        fillColor: context.colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: context.penny.border),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Account selector
                    Text(
                      'ACCOUNT',
                      style: context.text.labelSmall?.copyWith(
                        color: context.penny.textMuted,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: store.accounts.map((a) {
                          final selected = a.id == _selectedAccountId;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(a.name),
                              selected: selected,
                              onSelected: (_) =>
                                  setState(() => _selectedAccountId = a.id),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Category selector
                    Text(
                      'CATEGORY',
                      style: context.text.labelSmall?.copyWith(
                        color: context.penny.textMuted,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: availableCategories.map((c) {
                          final selected = c.id == _selectedCategoryId;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(c.name),
                              selected: selected,
                              onSelected: (_) =>
                                  setState(() => _selectedCategoryId = c.id),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    if (parsed.balanceMinor != null ||
                        parsed.referenceId != null) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (parsed.balanceMinor != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: context.colors.surface,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Remaining Bal: ${store.format(parsed.balanceMinor!)}',
                                style: context.text.bodySmall?.copyWith(
                                  color: context.penny.textMuted,
                                ),
                              ),
                            ),
                          if (parsed.referenceId != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: context.colors.surface,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Ref: ${parsed.referenceId}',
                                style: context.text.bodySmall?.copyWith(
                                  color: context.penny.textMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Action buttons
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check_rounded),
                label: Text(_saving ? 'Saving...' : 'Save Transaction'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _openFullEditor,
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Open in Full Editor'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
