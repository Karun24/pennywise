import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../services/smart/transaction_parser.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common.dart';

/// "Type it naturally" entry, powered by the local rule-based parser.
/// The parse result is always shown for confirmation before it is used.
class SmartEntryCard extends StatefulWidget {
  const SmartEntryCard({super.key, required this.onApply});

  final ValueChanged<ParsedTransaction> onApply;

  @override
  State<SmartEntryCard> createState() => _SmartEntryCardState();
}

class _SmartEntryCardState extends State<SmartEntryCard> {
  final _controller = TextEditingController();
  ParsedTransaction? _result;

  // User choices that resolve ambiguities in the preview.
  int? _chosenAmount;
  Category? _chosenCategory;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parse() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final store = context.read<FinanceStore>();
    FocusScope.of(context).unfocus();
    setState(() {
      _result = store.parser.parse(text, now: store.now);
      _chosenAmount = null;
      _chosenCategory = null;
    });
  }

  void _apply() {
    final r = _result;
    if (r == null) return;
    final category = _chosenCategory ?? r.category;
    final resolved = ParsedTransaction(
      input: r.input,
      amountMinor: _chosenAmount ?? r.amountMinor,
      type: r.type ?? category?.kind,
      category: category,
      description: r.description,
      date: r.date,
      dateDetected: r.dateDetected && !r.hasIssue(ParseField.date),
      paymentMethod: r.paymentMethod,
    );
    widget.onApply(resolved);
    setState(() {
      _result = null;
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final r = _result;
    return PennyCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 18, color: context.colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Smart entry',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Pill(
                  label: 'On-device rules',
                  icon: Icons.lock_rounded,
                  color: context.penny.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _parse(),
            decoration: InputDecoration(
              hintText: 'e.g. spent 250 on lunch yesterday via UPI',
              suffixIcon: IconButton(
                tooltip: 'Understand',
                icon: Icon(Icons.arrow_circle_right_rounded,
                    color: context.colors.primary),
                onPressed: _parse,
              ),
            ),
          ),
          if (r != null) ...[
            const SizedBox(height: 14),
            _row(context, 'Amount',
                r.amountMinor != null || _chosenAmount != null
                    ? store.format(_chosenAmount ?? r.amountMinor!)
                    : null,
                issue: r.hasIssue(ParseField.amount) && _chosenAmount == null),
            if (r.amountCandidates.isNotEmpty)
              _choices<int>(
                context,
                r.amountCandidates,
                (v) => store.format(v),
                _chosenAmount,
                (v) => setState(() => _chosenAmount = v),
              ),
            _row(context, 'Type', (r.type ?? (_chosenCategory?.kind))?.label,
                issue: r.type == null && _chosenCategory == null),
            _row(context, 'Category', (_chosenCategory ?? r.category)?.name,
                issue: (_chosenCategory ?? r.category) == null,
                hint: r.categoryReason),
            if (r.categoryAlternatives.isNotEmpty)
              _choices<Category>(
                context,
                r.categoryAlternatives,
                (c) => c.name,
                _chosenCategory,
                (c) => setState(() => _chosenCategory = c),
              ),
            _row(context, 'Description',
                r.description.isEmpty ? null : r.description),
            _row(
              context,
              'Date',
              DateUtilsX.relativeDay(r.date, now: store.now),
              issue: r.hasIssue(ParseField.date),
              hint: r.dateDetected ? null : 'none mentioned, using today',
            ),
            if (r.paymentMethod != null)
              _row(context, 'Payment', r.paymentMethod!.label),
            for (final issue in r.issues)
              if (!(issue.field == ParseField.amount && _chosenAmount != null) &&
                  !(issue.field == ParseField.category &&
                      _chosenCategory != null))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.help_outline_rounded,
                          size: 16, color: context.penny.warning),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(issue.message,
                            style: context.text.bodySmall
                                ?.copyWith(color: context.penny.warning)),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _result = null),
                  child: const Text('Discard'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(64, 44)),
                    onPressed: _apply,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Use these details',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String? value,
      {bool issue = false, String? hint}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: context.text.bodySmall),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: value ?? 'Needs your input',
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: issue || value == null
                        ? context.penny.warning
                        : context.colors.onSurface,
                  ),
                ),
                if (hint != null)
                  TextSpan(
                    text: '  ($hint)',
                    style: context.text.bodySmall,
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _choices<T>(BuildContext context, List<T> options,
      String Function(T) label, T? selected, ValueChanged<T> onPick) {
    return Padding(
      padding: const EdgeInsets.only(left: 96, top: 2, bottom: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final o in options)
            ChoiceChip(
              label: Text(label(o)),
              selected: o == selected,
              onSelected: (_) => onPick(o),
            ),
        ],
      ),
    );
  }
}
