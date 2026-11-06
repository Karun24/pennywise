import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme_ext.dart';
import '../utils/money.dart';

/// Asks the user to confirm a destructive or important action.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: ctx.penny.expense,
                  minimumSize: const Size(88, 44),
                )
              : FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Consistent floating snack bar. Build it with this and show it through a
/// captured [ScaffoldMessengerState] when crossing async gaps.
SnackBar pennySnack(String message,
    {SnackBarAction? action, bool error = false}) {
  return SnackBar(
    content: Row(
      children: [
        Icon(
          error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
          color: error ? const Color(0xFFFF9AAE) : const Color(0xFF6EE7B7),
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ],
    ),
    action: action,
    duration: Duration(seconds: action == null ? 3 : 5),
  );
}

void showSnack(BuildContext context, String message,
    {SnackBarAction? action, bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(pennySnack(message, action: action, error: error));
}

/// Result of [showAmountSheet].
class AmountSheetResult {
  const AmountSheetResult.value(this.amountMinor) : removed = false;
  const AmountSheetResult.removed()
      : amountMinor = null,
        removed = true;

  final int? amountMinor;
  final bool removed;
}

/// Bottom sheet for entering an amount (budgets, starting balance).
Future<AmountSheetResult?> showAmountSheet(
  BuildContext context, {
  required String title,
  required CurrencyInfo currency,
  String? subtitle,
  int? initialMinor,
  bool allowZero = false,
  String? removeLabel,
}) {
  return showModalBottomSheet<AmountSheetResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _AmountSheet(
      title: title,
      subtitle: subtitle,
      currency: currency,
      initialMinor: initialMinor,
      allowZero: allowZero,
      removeLabel: removeLabel,
    ),
  );
}

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({
    required this.title,
    required this.currency,
    this.subtitle,
    this.initialMinor,
    required this.allowZero,
    this.removeLabel,
  });

  final String title;
  final String? subtitle;
  final CurrencyInfo currency;
  final int? initialMinor;
  final bool allowZero;
  final String? removeLabel;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialMinor == null ? '' : Money.toEditable(widget.initialMinor!),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (widget.allowZero && (text.isEmpty || text == '0')) {
      Navigator.of(context).pop(const AmountSheetResult.value(0));
      return;
    }
    final minor = Money.parseToMinor(text);
    if (minor == null) {
      setState(() => _error = 'Enter a valid amount greater than zero.');
      return;
    }
    Navigator.of(context).pop(AmountSheetResult.value(minor));
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: context.text.titleLarge),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(widget.subtitle!, style: context.text.bodySmall),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: context.text.headlineSmall
                ?.copyWith(fontFeatures: tabularFigures),
            decoration: InputDecoration(
              prefixText: '${widget.currency.symbol} ',
              hintText: '0',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (widget.removeLabel != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context)
                        .pop(const AmountSheetResult.removed()),
                    child: Text(widget.removeLabel!),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _submit,
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
