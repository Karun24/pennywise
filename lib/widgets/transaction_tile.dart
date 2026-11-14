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
    this.onTap,
    this.showDate = false,
    this.dateText,
  });

  final TransactionEntry entry;
  final Category? category;
  final String amountText;
  final VoidCallback? onTap;
  final bool showDate;
  final String? dateText;

  @override
  Widget build(BuildContext context) {
    final title = entry.note.isNotEmpty
        ? entry.note
        : (category?.name ?? 'Transaction');
    final subtitle = [
      if (entry.note.isNotEmpty) category?.name ?? 'Uncategorised',
      if (showDate && dateText != null) dateText!,
      if (entry.isRecurring) 'Recurring',
      entry.paymentMethod.label,
    ].join(' · ');
    final amountColor =
        entry.isIncome ? context.penny.income : context.colors.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            CategoryAvatar(category: category),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall,
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
              entry.isIncome ? '+$amountText' : '-$amountText',
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
