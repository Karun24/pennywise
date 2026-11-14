import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/account.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/category_icons.dart';
import '../../utils/money.dart';
import '../../widgets/segmented.dart';

/// Creates a new account/wallet or edits [existing]. Returns the saved account.
Future<Account?> showAccountEditor(
  BuildContext context, {
  Account? existing,
}) {
  return showModalBottomSheet<Account>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AccountEditor(existing: existing),
  );
}

class _AccountEditor extends StatefulWidget {
  const _AccountEditor({this.existing});

  final Account? existing;

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _balance = TextEditingController(
      text: widget.existing != null
          ? Money.toEditable(widget.existing!.initialBalanceMinor)
          : '0');
  late AccountType _type = widget.existing?.type ?? AccountType.regular;
  late String _icon = widget.existing?.iconKey ?? _type.defaultIcon;
  late int _color = widget.existing?.colorValue ?? CategoryIcons.palette[1];
  late bool _isDefault = widget.existing?.isDefault ?? false;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _onTypeChanged(AccountType t) {
    setState(() {
      if (_icon == _type.defaultIcon) {
        _icon = t.defaultIcon;
      }
      _type = t;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter an account name.');
      return;
    }
    final minor = Money.parseToMinor(_balance.text) ?? 0;
    final store = context.read<FinanceStore>();
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });

    final now = DateTime.now();
    try {
      final existing = widget.existing;
      Account saved;
      if (existing == null) {
        saved = await store.addAccount(Account(
          name: name,
          type: _type,
          iconKey: _icon,
          colorValue: _color,
          initialBalanceMinor: minor,
          isDefault: _isDefault,
          sortOrder: store.accounts.length,
          createdAt: now,
          updatedAt: now,
        ));
      } else {
        saved = existing.copyWith(
          name: name,
          type: _type,
          iconKey: _icon,
          colorValue: _color,
          initialBalanceMinor: minor,
          isDefault: _isDefault,
          updatedAt: now,
        );
        await store.updateAccount(saved);
      }
      navigator.pop(saved);
    } on StoreException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final editing = widget.existing != null;
    final store = context.watch<FinanceStore>();
    final currency = store.currency;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editing ? 'Edit account' : 'New account / wallet',
                style: context.text.titleLarge),
            const SizedBox(height: 18),
            PennySegmented<AccountType>(
              values: AccountType.values,
              selected: _type,
              labelOf: (t) => t.label,
              onChanged: _onTypeChanged,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: !editing,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Account name',
                hintText: 'e.g. HDFC Bank, Cash Wallet',
                errorText: _error,
                counterText: '',
                prefixIcon: Icon(CategoryIcons.of(_icon), color: Color(_color)),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _balance,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(14),
              ],
              decoration: InputDecoration(
                labelText: 'Starting / Initial balance',
                prefixText: '${currency.symbol} ',
                hintText: '0',
                helperText: 'Initial balance before any recorded transactions',
              ),
            ),
            const SizedBox(height: 18),
            Text('Colour', style: context.text.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in CategoryIcons.palette)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == _color
                              ? context.colors.onSurface
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Icon', style: context.text.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final iconKey in const [
                  'bank',
                  'wallet',
                  'creditCard',
                  'savings',
                  'payments',
                  'investment',
                  'salary',
                  'home',
                  'shopping',
                  'travel',
                  'other',
                ])
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _icon = iconKey),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: iconKey == _icon
                            ? Color(_color).withValues(alpha: 0.2)
                            : context.penny.surfaceHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: iconKey == _icon
                              ? Color(_color)
                              : Colors.transparent,
                        ),
                      ),
                      child: Icon(
                        CategoryIcons.of(iconKey),
                        size: 22,
                        color: iconKey == _icon
                            ? Color(_color)
                            : context.penny.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Default account'),
              subtitle: const Text('Used by default when adding expenses and income'),
              value: _isDefault,
              onChanged: (v) => setState(() => _isDefault = v),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(editing ? 'Save changes' : 'Create account'),
            ),
          ],
        ),
      ),
    );
  }
}
