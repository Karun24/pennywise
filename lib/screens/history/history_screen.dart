import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/transaction_entry.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/transaction_tile.dart';
import '../add_transaction/add_transaction_screen.dart';

enum _TypeFilter { all, expense, income, transfer }

enum _PeriodFilter {
  all('All time'),
  thisMonth('This month'),
  lastMonth('Last month'),
  last30('Last 30 days'),
  thisYear('This year'),
  custom('Custom range');

  const _PeriodFilter(this.label);
  final String label;
}

/// Full transaction list with search, filters, edit and delete.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    this.initialAccountId,
    this.initialTag,
  });

  final int? initialAccountId;
  final String? initialTag;

  static Future<void> open(
    BuildContext context, {
    int? initialAccountId,
    String? initialTag,
  }) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(
          initialAccountId: initialAccountId,
          initialTag: initialTag,
        ),
      ));

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _search = TextEditingController();
  String _query = '';
  _TypeFilter _type = _TypeFilter.all;
  _PeriodFilter _period = _PeriodFilter.all;
  DateTimeRange? _custom;
  final Set<int> _categories = {};
  late int? _accountId = widget.initialAccountId;
  late String? _tag = widget.initialTag;

  /// Rows swiped away but not yet removed by the store. Filtering them out
  /// synchronously keeps Dismissible happy.
  final Set<int> _hidden = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateRange? _range(DateTime now) {
    switch (_period) {
      case _PeriodFilter.all:
        return null;
      case _PeriodFilter.thisMonth:
        return DateRange.month(now);
      case _PeriodFilter.lastMonth:
        return DateRange.month(DateUtilsX.addMonths(now, -1));
      case _PeriodFilter.last30:
        return DateRange.lastDays(30, now);
      case _PeriodFilter.thisYear:
        return DateRange.year(now);
      case _PeriodFilter.custom:
        final c = _custom;
        if (c == null) return null;
        return DateRange(DateUtilsX.dateOnly(c.start),
            DateUtilsX.addDays(DateUtilsX.dateOnly(c.end), 1));
    }
  }

  List<TransactionEntry> _filter(FinanceStore store) {
    final range = _range(store.now);
    final q = _query.trim().toLowerCase();
    return store.transactions.where((t) {
      if (_hidden.contains(t.id)) return false;
      if (_type == _TypeFilter.expense && !t.isExpense) return false;
      if (_type == _TypeFilter.income && !t.isIncome) return false;
      if (_type == _TypeFilter.transfer && !t.isTransfer) return false;
      if (_accountId != null &&
          t.accountId != _accountId &&
          t.toAccountId != _accountId) {
        return false;
      }
      if (_tag != null && !t.tags.contains(_tag)) {
        return false;
      }
      if (range != null && !range.contains(t.date)) return false;
      if (_categories.isNotEmpty && !_categories.contains(t.categoryId)) {
        return false;
      }
      if (q.isNotEmpty) {
        final cat = store.categoryById(t.categoryId)?.name.toLowerCase() ?? '';
        final amount = (t.amountMinor / 100).toStringAsFixed(2);
        final tagMatch = t.tags.any((tag) => tag.toLowerCase().contains(q));
        final acct = store.accountById(t.accountId)?.name.toLowerCase() ?? '';
        final toAcct =
            store.accountById(t.toAccountId)?.name.toLowerCase() ?? '';
        if (!t.note.toLowerCase().contains(q) &&
            !cat.contains(q) &&
            !t.paymentMethod.label.toLowerCase().contains(q) &&
            !amount.startsWith(q) &&
            !tagMatch &&
            !acct.contains(q) &&
            !toAcct.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Future<void> _pickAccount(FinanceStore store) async {
    final picked = await showModalBottomSheet<int?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All accounts'),
              trailing: _accountId == null
                  ? Icon(Icons.check_rounded, color: ctx.colors.primary)
                  : null,
              onTap: () => Navigator.of(ctx).pop(-1),
            ),
            for (final a in store.accounts)
              ListTile(
                title: Text(a.name),
                subtitle: Text(a.type.label),
                trailing: _accountId == a.id
                    ? Icon(Icons.check_rounded, color: ctx.colors.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(a.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _accountId = picked == -1 ? null : picked);
  }

  Future<void> _pickTag(FinanceStore store) async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All tags'),
              trailing: _tag == null
                  ? Icon(Icons.check_rounded, color: ctx.colors.primary)
                  : null,
              onTap: () => Navigator.of(ctx).pop(''),
            ),
            for (final t in store.allTags)
              ListTile(
                title: Text('#$t'),
                trailing: _tag == t
                    ? Icon(Icons.check_rounded, color: ctx.colors.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(t),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _tag = picked.isEmpty ? null : picked);
  }

  Future<void> _pickPeriod() async {
    final picked = await showModalBottomSheet<_PeriodFilter>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in _PeriodFilter.values)
              ListTile(
                title: Text(p.label),
                trailing: p == _period
                    ? Icon(Icons.check_rounded, color: ctx.colors.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(p),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == _PeriodFilter.custom) {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 1, 12, 31),
        initialDateRange: _custom,
      );
      if (range == null || !mounted) return;
      setState(() {
        _custom = range;
        _period = picked;
      });
    } else {
      setState(() => _period = picked);
    }
  }

  Future<void> _pickCategories(FinanceStore store) async {
    final selected = Set<int>.of(_categories);
    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          builder: (ctx, controller) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                        child: Text('Categories', style: ctx.text.titleLarge)),
                    TextButton(
                      onPressed: () => setSheet(selected.clear),
                      child: const Text('Clear'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(72, 40)),
                      onPressed: () => Navigator.of(ctx).pop(selected),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: [
                    for (final c in store.categories)
                      CheckboxListTile(
                        value: selected.contains(c.id),
                        onChanged: (v) => setSheet(() {
                          if (v == true) {
                            selected.add(c.id!);
                          } else {
                            selected.remove(c.id);
                          }
                        }),
                        secondary: CategoryAvatar(category: c, size: 36),
                        title: Text(c.name),
                        subtitle: Text(c.kind.label),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _categories
        ..clear()
        ..addAll(result);
    });
  }

  Future<bool> _confirmDelete(TransactionEntry t) => confirmAction(
        context,
        title: 'Delete transaction?',
        message: 'This removes it from your history and all totals.',
        confirmLabel: 'Delete',
        destructive: true,
      );

  Future<void> _delete(FinanceStore store, TransactionEntry t) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _hidden.add(t.id!));
    try {
      await store.deleteTransaction(t);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(pennySnack(
          'Transaction deleted',
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.restoreTransaction(t),
          ),
        ));
    } on StoreException catch (e) {
      messenger.showSnackBar(pennySnack(e.message, error: true));
    } finally {
      if (mounted) setState(() => _hidden.remove(t.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final items = _filter(store);
    var spent = 0, earned = 0;
    for (final t in items) {
      if (t.isIncome) {
        earned += t.amountMinor;
      } else {
        spent += t.amountMinor;
      }
    }

    // Group by day, newest first (store keeps transactions sorted).
    final groups = <DateTime, List<TransactionEntry>>{};
    for (final t in items) {
      groups.putIfAbsent(DateUtilsX.dateOnly(t.date), () => []).add(t);
    }

    final periodLabel = _period == _PeriodFilter.custom && _custom != null
        ? '${DateUtilsX.dayMonth(_custom!.start)} – ${DateUtilsX.dayMonth(_custom!.end)}'
        : _period.label;

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: SafeArea(
        child: ResponsiveCenter(
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: pagePadding(context, top: 4, bottom: 8),
                sliver: SliverList.list(
                  children: [
                    TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Search description, category, amount',
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
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final f in _TypeFilter.values) ...[
                            ChoiceChip(
                              label: Text(switch (f) {
                                _TypeFilter.all => 'All',
                                _TypeFilter.expense => 'Expenses',
                                _TypeFilter.income => 'Income',
                                _TypeFilter.transfer => 'Transfers',
                              }),
                              selected: _type == f,
                              onSelected: (_) => setState(() => _type = f),
                            ),
                            const SizedBox(width: 8),
                          ],
                          ActionChip(
                            avatar: const Icon(Icons.account_balance_wallet_rounded,
                                size: 18),
                            label: Text(_accountId == null
                                ? 'All accounts'
                                : (store.accountById(_accountId)?.name ??
                                    'Account')),
                            onPressed: () => _pickAccount(store),
                          ),
                          const SizedBox(width: 8),
                          if (store.allTags.isNotEmpty || _tag != null) ...[
                            ActionChip(
                              avatar: const Icon(Icons.tag_rounded, size: 18),
                              label: Text(_tag == null ? 'Tags' : '#$_tag'),
                              onPressed: () => _pickTag(store),
                            ),
                            const SizedBox(width: 8),
                          ],
                          ActionChip(
                            avatar: const Icon(Icons.date_range_rounded,
                                size: 18),
                            label: Text(periodLabel),
                            onPressed: _pickPeriod,
                          ),
                          const SizedBox(width: 8),
                          ActionChip(
                            avatar: const Icon(Icons.filter_list_rounded,
                                size: 18),
                            label: Text(_categories.isEmpty
                                ? 'Categories'
                                : '${_categories.length} categories'),
                            onPressed: () => _pickCategories(store),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${items.length} transaction${items.length == 1 ? '' : 's'}'
                      ' · Spent ${store.format(spent)}'
                      ' · Earned ${store.format(earned)}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: store.hasTransactions
                        ? 'No matching transactions'
                        : 'No transactions yet',
                    message: store.hasTransactions
                        ? 'Try a different search or filter.'
                        : 'Tap + to add your first one.',
                  ),
                )
              else
                SliverPadding(
                  padding: pagePadding(context, top: 0, bottom: 32),
                  sliver: SliverList.list(
                    children: [
                      for (final entry in groups.entries) ...[
                        _DayHeader(
                          day: entry.key,
                          now: store.now,
                          spentText: store.format(entry.value
                              .where((t) => t.isExpense)
                              .fold<int>(0, (a, t) => a + t.amountMinor)),
                        ),
                        for (final t in entry.value)
                          Dismissible(
                            key: ValueKey('tx-${t.id}'),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) => _confirmDelete(t),
                            onDismissed: (_) => _delete(store, t),
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: context.penny.expense
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(Icons.delete_outline_rounded,
                                  color: context.penny.expense),
                            ),
                            child: TransactionTile(
                              entry: t,
                              category: store.categoryById(t.categoryId),
                              accountName: store.accountById(t.accountId)?.name,
                              toAccountName:
                                  store.accountById(t.toAccountId)?.name,
                              amountText: store.format(t.amountMinor),
                              onTap: () => AddTransactionScreen.open(context,
                                  existing: t),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(
      {required this.day, required this.now, required this.spentText});

  final DateTime day;
  final DateTime now;
  final String spentText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4, left: 4, right: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(DateUtilsX.relativeDay(day, now: now),
                style: context.text.labelLarge
                    ?.copyWith(color: context.penny.textMuted)),
          ),
          Text('Spent $spentText',
              style: context.text.labelMedium
                  ?.copyWith(color: context.penny.textMuted)),
        ],
      ),
    );
  }
}
