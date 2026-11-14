import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/debt_entry.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/date_utils.dart';
import '../../utils/money.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import 'debt_editor_sheet.dart';
import 'split_bill_sheet.dart';

/// Full screen to track IOUs, money lent, money borrowed, and split bills.
class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const DebtsScreen()));

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF6366F1), // Indigo
      Color(0xFF10B981), // Emerald
      Color(0xFFF59E0B), // Amber
      Color(0xFF06B6D4), // Cyan
      Color(0xFFEC4899), // Pink
      Color(0xFF8B5CF6), // Violet
      Color(0xFF3B82F6), // Blue
      Color(0xFF14B8A6), // Teal
    ];
    final hash = name.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    return colors[hash % colors.length];
  }

  Future<void> _settleDebt(BuildContext context, DebtEntry debt) async {
    final store = context.read<FinanceStore>();
    final currency = store.currency;
    var recordTx = true;
    var selectedAcc = store.defaultAccount.id;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Settle with ${debt.personName}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                debt.isLent
                    ? '${debt.personName} paid back ${Money.format(debt.amountMinor, currency)}.'
                    : 'You paid back ${Money.format(debt.amountMinor, currency)} to ${debt.personName}.',
                style: ctx.text.bodyMedium,
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: recordTx,
                title: Text(
                  debt.isLent
                      ? 'Record as income in account'
                      : 'Record as expense in account',
                  style: ctx.text.bodyMedium,
                ),
                onChanged: (v) => setDialog(() => recordTx = v ?? true),
              ),
              if (recordTx && store.accounts.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: selectedAcc,
                  decoration: const InputDecoration(
                    labelText: 'Account',
                    isDense: true,
                  ),
                  items: [
                    for (final a in store.accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(a.name),
                      ),
                  ],
                  onChanged: (id) => setDialog(() => selectedAcc = id),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Mark as settled'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !context.mounted) return;
    try {
      await store.settleDebt(
        debt,
        accountId: selectedAcc,
        recordTransaction: recordTx,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          pennySnack('Settled with ${debt.personName}'),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(context, '$e', error: true);
      }
    }
  }

  Future<void> _deleteDebt(BuildContext context, DebtEntry debt) async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete this record?',
      message: 'Delete the debt record for "${debt.personName}".',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final store = context.read<FinanceStore>();
    try {
      await store.deleteDebt(debt);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          pennySnack('Record deleted'),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(context, '$e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final currency = store.currency;
    final now = DateTime.now();

    final totalOwed = store.totalOwedToMeMinor;
    final totalIOwe = store.totalIOweMinor;
    final netMinor = totalOwed - totalIOwe;

    final q = _query.trim().toLowerCase();
    final allDebts = store.debts.where((d) {
      if (q.isEmpty) return true;
      return d.personName.toLowerCase().contains(q) ||
          d.note.toLowerCase().contains(q);
    }).toList();

    final pending = allDebts.where((d) => !d.isSettled).toList()
      ..sort((a, b) {
        // Overdue first, then by date
        final aOverdue = a.isOverdue(now);
        final bOverdue = b.isOverdue(now);
        if (aOverdue != bOverdue) return aOverdue ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });

    final settled = allDebts.where((d) => d.isSettled).toList()
      ..sort((a, b) =>
          (b.settledAt ?? b.updatedAt).compareTo(a.settledAt ?? a.updatedAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debts & split bills'),
        actions: [
          IconButton(
            tooltip: 'Split a bill',
            icon: const Icon(Icons.call_split_rounded),
            onPressed: () => showSplitBillSheet(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'Pending (${store.pendingDebts.length})'),
            Tab(text: 'Settled (${store.settledDebts.length})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDebtEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add IOU'),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          child: Column(
            children: [
              // Summary Hero Card
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: PennyCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Net Balance',
                              style: context.text.titleSmall?.copyWith(
                                  color: context.penny.textMuted)),
                          Text(
                            Money.format(netMinor.abs(), currency,
                                signed: netMinor != 0),
                            style: context.text.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: netMinor > 0
                                  ? context.penny.income
                                  : (netMinor < 0
                                      ? context.penny.expense
                                      : context.penny.textMuted),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.penny.income
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.arrow_downward_rounded,
                                          size: 16,
                                          color: context.penny.income),
                                      const SizedBox(width: 4),
                                      Text('Owed to you',
                                          style: context.text.labelSmall),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    Money.format(totalOwed, currency),
                                    style: context.text.titleSmall?.copyWith(
                                      color: context.penny.income,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.penny.expense
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.arrow_upward_rounded,
                                          size: 16,
                                          color: context.penny.expense),
                                      const SizedBox(width: 4),
                                      Text('You owe',
                                          style: context.text.labelSmall),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    Money.format(totalIOwe, currency),
                                    style: context.text.titleSmall?.copyWith(
                                      color: context.penny.expense,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search by person or note…',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                  ),
                ),
              ),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _buildList(context, pending, isPending: true),
                    _buildList(context, settled, isPending: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<DebtEntry> items,
      {required bool isPending}) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: EmptyState(
            icon: isPending
                ? Icons.handshake_outlined
                : Icons.task_alt_rounded,
            title: isPending ? 'No pending debts' : 'No settled debts',
            message: isPending
                ? 'All settled up! Tap "Add IOU" or "Split a bill" above to record a new debt.'
                : 'Settled debts will appear here once marked as paid.',
          ),
        ),
      );
    }

    final currency = context.read<FinanceStore>().currency;
    final now = DateTime.now();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final d = items[index];
        final overdue = d.isOverdue(now);
        final color = _avatarColor(d.personName);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PennyCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar
                CircleAvatar(
                  radius: 20,
                  backgroundColor: color.withValues(alpha: 0.18),
                  child: Text(
                    d.personName.isNotEmpty
                        ? d.personName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Name, note, due date
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              d.personName,
                              style: context.text.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: d.isLent
                                  ? context.penny.income.withValues(alpha: 0.12)
                                  : context.penny.expense.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              d.type.shortLabel,
                              style: context.text.labelSmall?.copyWith(
                                color: d.isLent
                                    ? context.penny.income
                                    : context.penny.expense,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (d.note.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          d.note,
                          style: context.text.bodySmall?.copyWith(
                            color: context.penny.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (d.dueDate != null && !d.isSettled) ...[
                            Icon(
                              overdue
                                  ? Icons.warning_amber_rounded
                                  : Icons.calendar_today_rounded,
                              size: 13,
                              color: overdue
                                  ? context.penny.expense
                                  : context.penny.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              overdue
                                  ? 'Overdue (${DateUtilsX.dayMonth(d.dueDate!)})'
                                  : 'Due ${DateUtilsX.dayMonth(d.dueDate!)}',
                              style: context.text.labelSmall?.copyWith(
                                color: overdue
                                    ? context.penny.expense
                                    : context.penny.textMuted,
                                fontWeight: overdue ? FontWeight.bold : null,
                              ),
                            ),
                          ] else if (d.isSettled && d.settledAt != null) ...[
                            Icon(Icons.check_circle_outline_rounded,
                                size: 13, color: context.penny.income),
                            const SizedBox(width: 4),
                            Text(
                              'Settled ${DateUtilsX.dayMonth(d.settledAt!)}',
                              style: context.text.labelSmall?.copyWith(
                                color: context.penny.income,
                              ),
                            ),
                          ] else ...[
                            Text(
                              DateUtilsX.relativeDay(d.createdAt, now: now),
                              style: context.text.labelSmall?.copyWith(
                                color: context.penny.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Amount and Action
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Money.format(d.amountMinor, currency),
                      style: context.text.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: d.isLent
                            ? context.penny.income
                            : context.penny.expense,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isPending)
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 0),
                        ),
                        onPressed: () => _settleDebt(context, d),
                        child: const Text('Settle', style: TextStyle(fontSize: 12)),
                      )
                    else
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, size: 18),
                        onSelected: (v) {
                          if (v == 'edit') showDebtEditor(context, existing: d);
                          if (v == 'delete') _deleteDebt(context, d);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
