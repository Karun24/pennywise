import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/account.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/category_icons.dart';
import '../../utils/money.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import 'account_editor_sheet.dart';

class ManageAccountsScreen extends StatelessWidget {
  const ManageAccountsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ManageAccountsScreen()));

  Future<void> _delete(BuildContext context, Account a) async {
    final store = context.read<FinanceStore>();
    final messenger = ScaffoldMessenger.of(context);
    final fallback = store.defaultAccount;

    if (a.isDefault) {
      showSnack(context, 'Cannot delete the default account. Set another account as default first.',
          error: true);
      return;
    }

    final ok = await confirmAction(
      context,
      title: 'Delete "${a.name}"?',
      message: 'Transactions associated with this account will be moved to '
          '"${fallback.name}".',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;

    try {
      await store.deleteAccount(a);
      messenger.showSnackBar(pennySnack('"${a.name}" deleted'));
    } on StoreException catch (e) {
      messenger.showSnackBar(pennySnack(e.message, error: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final currency = store.currency;
    final accounts = store.accounts;

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts & Wallets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAccountEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New account'),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          child: ListView(
            padding: pagePadding(context, top: 4, bottom: 96),
            children: [
              PennyCard(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: context.penny.accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.account_balance_rounded,
                          color: context.penny.accent),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total across all accounts',
                              style: context.text.bodySmall),
                          const SizedBox(height: 2),
                          Text(
                            Money.format(store.totalBalanceMinor, currency),
                            style: context.text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontFeatures: tabularFigures,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PennyCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final a in accounts) ...[
                      ListTile(
                        onTap: () => showAccountEditor(context, existing: a),
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: a.color.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            CategoryIcons.of(a.iconKey),
                            color: a.color,
                            size: 22,
                          ),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                a.name,
                                style: context.text.titleSmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (a.isDefault) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: context.penny.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'DEFAULT',
                                  style: context.text.labelSmall?.copyWith(
                                    color: context.penny.accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          a.type.label,
                          style: context.text.bodySmall,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              Money.format(store.accountBalance(a.id!), currency),
                              style: context.text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (!a.isDefault && accounts.length > 1)
                              IconButton(
                                tooltip: 'Delete',
                                icon: Icon(Icons.delete_outline_rounded,
                                    color: context.penny.expense),
                                onPressed: () => _delete(context, a),
                              )
                            else
                              const SizedBox(width: 24),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'PennyWise tracks independent balances for each bank account, cash wallet, '
                'or credit card. You can transfer money between them without affecting '
                'your expense or income analytics.',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
