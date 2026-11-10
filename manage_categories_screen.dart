import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../models/transaction_entry.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/segmented.dart';
import 'category_editor_sheet.dart';

class ManageCategoriesScreen extends StatefulWidget {
  const ManageCategoriesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ManageCategoriesScreen()));

  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen> {
  TransactionType _kind = TransactionType.expense;

  Future<void> _delete(Category c) async {
    final store = context.read<FinanceStore>();
    final messenger = ScaffoldMessenger.of(context);
    final count = store.transactionCountFor(c.id!);
    final fallback = store.fallbackCategory(c.kind);
    final ok = await confirmAction(
      context,
      title: 'Delete "${c.name}"?',
      message: count == 0
          ? 'This category has no transactions.'
          : '$count transaction${count == 1 ? '' : 's'} will be moved to '
              '"${fallback.name}". Any budget for this category is removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await store.deleteCategory(c);
      messenger.showSnackBar(pennySnack('"${c.name}" deleted'));
    } on StoreException catch (e) {
      messenger.showSnackBar(pennySnack(e.message, error: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final list = store.categoriesOf(_kind);
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCategoryEditor(context, initialKind: _kind),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New category'),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          child: ListView(
            padding: pagePadding(context, top: 4, bottom: 96),
            children: [
              PennySegmented<TransactionType>(
                values: TransactionType.values,
                selected: _kind,
                labelOf: (t) => t == TransactionType.expense
                    ? 'Expense categories'
                    : 'Income categories',
                onChanged: (t) => setState(() => _kind = t),
              ),
              const SizedBox(height: 16),
              PennyCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final c in list)
                      ListTile(
                        onTap: () => showCategoryEditor(context, existing: c),
                        leading: CategoryAvatar(category: c, size: 40),
                        title: Text(c.name, style: context.text.titleSmall),
                        subtitle: Text(
                          '${store.transactionCountFor(c.id!)} transactions'
                          '${c.isDefault ? ' · Built-in' : ''}',
                          style: context.text.bodySmall,
                        ),
                        trailing: c.isDefault
                            ? Icon(Icons.edit_rounded,
                                size: 18, color: context.penny.textMuted)
                            : IconButton(
                                tooltip: 'Delete',
                                icon: Icon(Icons.delete_outline_rounded,
                                    color: context.penny.expense),
                                onPressed: () => _delete(c),
                              ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Built-in categories can be recoloured but not renamed or '
                'deleted, because smart categorization relies on them.',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
