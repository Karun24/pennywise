import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/transaction_entry.dart';
import '../theme/theme_ext.dart';
import 'common.dart';

/// One row in a transaction list.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.entry,
    required this.category,
    required this.amountText,
    this.accountName,
    this.toAccountName,
    this.onTap,
    this.showDate = false,
    this.dateText,
  });

  final TransactionEntry entry;
  final Category? category;
  final String amountText;
  final String? accountName;
  final String? toAccountName;
  final VoidCallback? onTap;
  final bool showDate;
  final String? dateText;

  @override
  Widget build(BuildContext context) {
    final isTransfer = entry.isTransfer;
    final title = isTransfer
        ? (entry.note.isNotEmpty ? entry.note : 'Transfer')
        : (entry.note.isNotEmpty
            ? entry.note
            : (category?.name ?? 'Transaction'));

    final accountDesc = isTransfer
        ? (accountName != null && toAccountName != null
            ? '$accountName → $toAccountName'
            : (accountName ?? 'Transfer'))
        : accountName;

    final tagText =
        entry.tags.isNotEmpty ? '#${entry.tags.join(' #')}' : null;

    final subtitle = [
      if (!isTransfer && entry.note.isNotEmpty)
        category?.name ?? 'Uncategorised',
      if (accountDesc != null) accountDesc,
      if (showDate && dateText != null) dateText!,
      if (entry.isRecurring) 'Recurring',
      if (tagText != null) tagText,
      if (!isTransfer) entry.paymentMethod.label,
    ].join(' · ');

    final Color amountColor = isTransfer
        ? context.penny.accent
        : (entry.isIncome ? context.penny.income : context.colors.onSurface);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            if (isTransfer)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.penny.accent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.swap_horiz_rounded,
                  color: context.penny.accent,
                  size: 24,
                ),
              )
            else
              CategoryAvatar(category: category),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall,
                        ),
                      ),
                      if (entry.hasReceipt) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.receipt_long_rounded,
                          size: 14,
                          color: context.penny.subtleText,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              isTransfer
                  ? amountText
                  : (entry.isIncome ? '+$amountText' : '-$amountText'),
              style: context.text.titleSmall?.copyWith(
                color: amountColor,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
