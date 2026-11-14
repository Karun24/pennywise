import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/recurring_rule.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/date_utils.dart';
import '../../utils/money.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import '../add_transaction/add_transaction_screen.dart';

/// Lists recurring rules (rent, salary, subscriptions...) with pause/resume,
/// edit and delete.
class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const RecurringScreen()));

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final rules = store.recurring;
    var monthlyOut = 0, monthlyIn = 0;
    for (final r in rules.where((r) => r.active)) {
      final perMonth = switch (r.frequency) {
        RepeatFrequency.daily => r.amountMinor * 30,
        RepeatFrequency.weekly => (r.amountMinor * 52 / 12).round(),
        RepeatFrequency.monthly => r.amountMinor,
        RepeatFrequency.yearly => (r.amountMinor / 12).round(),
      };
      if (r.type.name == 'income') {
        monthlyIn += perMonth;
      } else {
        monthlyOut += perMonth;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring transactions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddTransactionScreen.open(context,
            initialRepeat: RepeatFrequency.monthly),
        icon: const Icon(Icons.repeat_rounded),
        label: const Text('New recurring'),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          child: ListView(
            padding: pagePadding(context, top: 4, bottom: 96),
            children: [
              if (rules.isEmpty)
                const EmptyState(
                  icon: Icons.repeat_rounded,
                  title: 'No recurring transactions',
                  message: 'Add rent, salary, subscriptions or EMIs once and '
                      'PennyWise adds them automatically on schedule. Tap '
                      '"New recurring", or choose a Repeat option when adding '
                      'any transaction.',
                )
              else ...[
                PennyCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: _Total(
                          label: 'Fixed costs / month',
                          value: store.format(monthlyOut),
                          color: context.penny.expense,
                        ),
                      ),
                      Expanded(
                        child: _Total(
                          label: 'Regular income / month',
                          value: store.format(monthlyIn),
                          color: context.penny.income,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (final r in rules)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RuleCard(rule: r),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: context.text.titleMedium?.copyWith(
                    color: color, fontFeatures: tabularFigures)),
          ),
        ],
      );
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule});
  final RecurringRule rule;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final cat = store.categoryById(rule.categoryId);
    final isIncome = rule.type.name == 'income';
    final title = rule.note.isNotEmpty ? rule.note : (cat?.name ?? 'Recurring');
    return Opacity(
      opacity: rule.active ? 1 : 0.55,
      child: PennyCard(
        onTap: () => _edit(context, rule),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            CategoryAvatar(category: cat, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall),
                  const SizedBox(height: 2),
                  Text(rule.describe(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall),
                  Text(
                    rule.active
                        ? 'Next: ${DateUtilsX.relativeDay(rule.nextDue, now: store.now)}'
                        : 'Paused',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(
                        color: rule.active
                            ? context.penny.accent
                            : context.penny.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isIncome ? '+' : '-'}${store.format(rule.amountMinor)}',
                  style: context.text.titleSmall?.copyWith(
                    color: isIncome
                        ? context.penny.income
                        : context.colors.onSurface,
                    fontFeatures: tabularFigures,
                  ),
                ),
                Switch(
                  value: rule.active,
                  onChanged: (v) => _setActive(context, rule, v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _setActive(
      BuildContext context, RecurringRule rule, bool active) async {
    final store = context.read<FinanceStore>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      var next = rule.nextDue;
      if (active) {
        // Resuming never back-fills the paused period.
        final today = DateUtilsX.dateOnly(store.now);
        while (next.isBefore(today)) {
          next = RecurringRule.advance(next, rule.frequency, rule.anchorDay);
        }
      }
      await store.updateRecurring(rule.copyWith(active: active, nextDue: next));
      messenger.showSnackBar(pennySnack(active ? 'Resumed' : 'Paused'));
    } on StoreException catch (e) {
      messenger.showSnackBar(pennySnack(e.message, error: true));
    }
  }

  static Future<void> _edit(BuildContext context, RecurringRule rule) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditRuleSheet(rule: rule),
    );
  }
}

class _EditRuleSheet extends StatefulWidget {
  const _EditRuleSheet({required this.rule});
  final RecurringRule rule;

  @override
  State<_EditRuleSheet> createState() => _EditRuleSheetState();
}

class _EditRuleSheetState extends State<_EditRuleSheet> {
  late final _amount =
      TextEditingController(text: Money.toEditable(widget.rule.amountMinor));
  late final _note = TextEditingController(text: widget.rule.note);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = context.read<FinanceStore>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final minor = Money.parseToMinor(_amount.text);
    if (minor == null) {
      setState(() => _error = 'Enter an amount greater than zero');
      return;
    }
    setState(() => _busy = true);
    try {
      await store.updateRecurring(
          widget.rule.copyWith(amountMinor: minor, note: _note.text.trim()));
      navigator.pop();
      messenger.showSnackBar(
          pennySnack('Saved. Future transactions use the new details.'));
    } on StoreException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _delete() async {
    final store = context.read<FinanceStore>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmAction(
      context,
      title: 'Stop this recurring transaction?',
      message: 'No new transactions will be added. Ones already added stay '
          'in your history.',
      confirmLabel: 'Delete rule',
      destructive: true,
    );
    if (!ok) return;
    try {
      await store.deleteRecurring(widget.rule);
      navigator.pop();
      messenger.showSnackBar(pennySnack('Recurring transaction removed'));
    } on StoreException catch (e) {
      messenger.showSnackBar(pennySnack(e.message, error: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final rule = widget.rule;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Edit recurring', style: context.text.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${rule.describe()} · '
            '${store.categoryById(rule.categoryId)?.name ?? ''}',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: context.text.headlineSmall
                ?.copyWith(fontFeatures: tabularFigures),
            decoration: InputDecoration(
              prefixText: '${store.currency.symbol} ',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Description',
              counterText: '',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: context.penny.expense),
                  onPressed: _busy ? null : _delete,
                  child: const Text('Delete'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
