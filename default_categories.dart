import '../models/category.dart';
import '../models/transaction_entry.dart';

/// Names of built-in categories. The smart categorizer maps keywords to these
/// names, so keep them in sync with `services/smart/categorizer.dart`.
class DefaultCategoryNames {
  DefaultCategoryNames._();

  static const food = 'Food & Dining';
  static const transport = 'Transportation';
  static const shopping = 'Shopping';
  static const entertainment = 'Entertainment';
  static const bills = 'Bills & Utilities';
  static const health = 'Health';
  static const education = 'Education';
  static const travel = 'Travel';
  static const groceries = 'Groceries';
  static const other = 'Other';

  static const salary = 'Salary';
  static const freelance = 'Freelance';
  static const gifts = 'Gifts';
  static const investments = 'Investments';
  static const refunds = 'Refunds';
  static const otherIncome = 'Other income';
}

List<Category> buildDefaultCategories() {
  var order = 0;
  Category e(String name, String icon, int color) => Category(
        name: name,
        iconKey: icon,
        colorValue: color,
        kind: TransactionType.expense,
        isDefault: true,
        sortOrder: order++,
      );
  Category i(String name, String icon, int color) => Category(
        name: name,
        iconKey: icon,
        colorValue: color,
        kind: TransactionType.income,
        isDefault: true,
        sortOrder: order++,
      );

  return [
    e(DefaultCategoryNames.food, 'food', 0xFFFF8A65),
    e(DefaultCategoryNames.groceries, 'groceries', 0xFF81C784),
    e(DefaultCategoryNames.transport, 'transport', 0xFF4FC3F7),
    e(DefaultCategoryNames.shopping, 'shopping', 0xFFF06292),
    e(DefaultCategoryNames.bills, 'bills', 0xFFFFD54F),
    e(DefaultCategoryNames.entertainment, 'entertainment', 0xFFBA68C8),
    e(DefaultCategoryNames.health, 'health', 0xFFEF5350),
    e(DefaultCategoryNames.education, 'education', 0xFF7986CB),
    e(DefaultCategoryNames.travel, 'travel', 0xFF4DD0E1),
    e(DefaultCategoryNames.other, 'other', 0xFF90A4AE),
    i(DefaultCategoryNames.salary, 'salary', 0xFF34D399),
    i(DefaultCategoryNames.freelance, 'freelance', 0xFF2DD4BF),
    i(DefaultCategoryNames.investments, 'investment', 0xFFA78BFA),
    i(DefaultCategoryNames.gifts, 'gift', 0xFFF472B6),
    i(DefaultCategoryNames.refunds, 'refund', 0xFF60A5FA),
    i(DefaultCategoryNames.otherIncome, 'payments', 0xFF94A3B8),
  ];
}
