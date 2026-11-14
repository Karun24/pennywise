import 'dart:ui' show Color;

/// Type of financial account.
enum AccountType {
  regular('Bank account', 'bank'),
  cash('Cash', 'wallet'),
  creditCard('Credit card', 'creditCard'),
  savings('Savings', 'savings'),
  other('Other', 'other');

  const AccountType(this.label, this.defaultIcon);
  final String label;
  final String defaultIcon;

  static AccountType fromName(String? name) => AccountType.values
      .firstWhere((t) => t.name == name, orElse: () => AccountType.regular);
}

/// A wallet or account where money is kept (e.g. Bank, Cash, Credit Card).
class Account {
  const Account({
    this.id,
    required this.name,
    this.type = AccountType.regular,
    required this.iconKey,
    required this.colorValue,
    this.initialBalanceMinor = 0,
    this.isDefault = false,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final AccountType type;
  final String iconKey;
  final int colorValue;

  Color get color => Color(colorValue);

  /// Starting balance when the user begins tracking this account.
  final int initialBalanceMinor;

  /// True for the primary account used for transactions by default.
  final bool isDefault;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCreditCard => type == AccountType.creditCard;

  Account copyWith({
    int? id,
    String? name,
    AccountType? type,
    String? iconKey,
    int? colorValue,
    int? initialBalanceMinor,
    bool? isDefault,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      iconKey: iconKey ?? this.iconKey,
      colorValue: colorValue ?? this.colorValue,
      initialBalanceMinor: initialBalanceMinor ?? this.initialBalanceMinor,
      isDefault: isDefault ?? this.isDefault,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'type': type.name,
        'icon_key': iconKey,
        'color': colorValue,
        'initial_balance_minor': initialBalanceMinor,
        'is_default': isDefault ? 1 : 0,
        'sort_order': sortOrder,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Account.fromMap(Map<String, Object?> map) {
    return Account(
      id: (map['id'] as num?)?.toInt(),
      name: (map['name'] as String?) ?? 'Account',
      type: AccountType.fromName(map['type'] as String?),
      iconKey: (map['icon_key'] as String?) ?? 'bank',
      colorValue: (map['color'] as num?)?.toInt() ?? 0xFF4FC3F7,
      initialBalanceMinor:
          (map['initial_balance_minor'] as num?)?.toInt() ?? 0,
      isDefault: ((map['is_default'] as num?)?.toInt() ?? 0) == 1,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as num?)?.toInt() ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['updated_at'] as num?)?.toInt() ?? 0),
    );
  }

  List<String> validate() {
    final errors = <String>[];
    if (name.trim().isEmpty) errors.add('Account name cannot be empty.');
    if (name.length > 50) errors.add('Account name is too long.');
    return errors;
  }
}
