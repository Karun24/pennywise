import 'dart:ui' show Color;

import 'transaction_entry.dart';

/// A spending or income category.
class Category {
  const Category({
    this.id,
    required this.name,
    required this.iconKey,
    required this.colorValue,
    required this.kind,
    this.isDefault = false,
    this.sortOrder = 0,
  });

  final int? id;
  final String name;

  /// Key into [CategoryIcons]; stored as text so icons stay tree-shakeable.
  final String iconKey;
  final int colorValue;
  final TransactionType kind;
  final bool isDefault;
  final int sortOrder;

  Color get color => Color(colorValue);

  Category copyWith({
    int? id,
    String? name,
    String? iconKey,
    int? colorValue,
    TransactionType? kind,
    bool? isDefault,
    int? sortOrder,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      colorValue: colorValue ?? this.colorValue,
      kind: kind ?? this.kind,
      isDefault: isDefault ?? this.isDefault,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'icon_key': iconKey,
        'color': colorValue,
        'kind': kind.name,
        'is_default': isDefault ? 1 : 0,
        'sort_order': sortOrder,
      };

  factory Category.fromMap(Map<String, Object?> map) => Category(
        id: (map['id'] as num?)?.toInt(),
        name: (map['name'] as String?) ?? 'Unnamed',
        iconKey: (map['icon_key'] as String?) ?? 'other',
        colorValue: (map['color'] as num?)?.toInt() ?? 0xFF8B8FA8,
        kind: TransactionType.fromName(map['kind'] as String?),
        isDefault: ((map['is_default'] as num?)?.toInt() ?? 0) == 1,
        sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      );
}

/// A recurring monthly limit for one expense category.
class CategoryBudget {
  const CategoryBudget({required this.categoryId, required this.amountMinor});

  final int categoryId;
  final int amountMinor;

  Map<String, Object?> toMap() =>
      {'category_id': categoryId, 'amount_minor': amountMinor};

  factory CategoryBudget.fromMap(Map<String, Object?> map) => CategoryBudget(
        categoryId: (map['category_id'] as num).toInt(),
        amountMinor: (map['amount_minor'] as num).toInt(),
      );
}
