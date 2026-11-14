import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../models/transaction_entry.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/category_icons.dart';
import '../../widgets/segmented.dart';

/// Creates a new category or edits [existing]. Returns the saved category.
Future<Category?> showCategoryEditor(
  BuildContext context, {
  Category? existing,
  TransactionType initialKind = TransactionType.expense,
}) {
  return showModalBottomSheet<Category>(
    context: context,
    isScrollControlled: true,
    // Providers sit above MaterialApp, so the sheet can read the store.
    builder: (_) =>
        _CategoryEditor(existing: existing, initialKind: initialKind),
  );
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({this.existing, required this.initialKind});

  final Category? existing;
  final TransactionType initialKind;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late TransactionType _kind = widget.existing?.kind ?? widget.initialKind;
  late String _icon = widget.existing?.iconKey ?? 'other';
  late int _color = widget.existing?.colorValue ?? CategoryIcons.palette.first;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = context.read<FinanceStore>();
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      Category saved;
      if (existing == null) {
        saved = await store.addCategory(Category(
          name: _name.text,
          iconKey: _icon,
          colorValue: _color,
          kind: _kind,
        ));
      } else {
        saved = existing.copyWith(
            name: _name.text.trim(), iconKey: _icon, colorValue: _color);
        await store.updateCategory(saved);
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
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editing ? 'Edit category' : 'New category',
                style: context.text.titleLarge),
            const SizedBox(height: 18),
            if (!editing) ...[
              PennySegmented<TransactionType>(
                values: const [
                  TransactionType.expense,
                  TransactionType.income,
                ],
                selected: _kind,
                labelOf: (t) => t.label,
                colorOf: (t) => t == TransactionType.expense
                    ? context.penny.expense
                    : context.penny.income,
                onChanged: (t) => setState(() => _kind = t),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _name,
              autofocus: !editing,
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              enabled: !(widget.existing?.isDefault ?? false),
              decoration: InputDecoration(
                hintText: 'Category name',
                errorText: _error,
                counterText: '',
                prefixIcon: Icon(CategoryIcons.of(_icon), color: Color(_color)),
              ),
            ),
            if (widget.existing?.isDefault ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Built-in category names stay fixed so smart '
                    'categorization keeps working.',
                    style: context.text.bodySmall),
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
                for (final entry in CategoryIcons.all.entries)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _icon = entry.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: entry.key == _icon
                            ? Color(_color).withValues(alpha: 0.2)
                            : context.penny.surfaceHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: entry.key == _icon
                              ? Color(_color)
                              : Colors.transparent,
                        ),
                      ),
                      child: Icon(entry.value,
                          size: 22,
                          color: entry.key == _icon
                              ? Color(_color)
                              : context.penny.textMuted),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(editing ? 'Save changes' : 'Create category'),
            ),
          ],
        ),
      ),
    );
  }
}
