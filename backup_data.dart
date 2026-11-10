import 'category.dart';
import 'note.dart';
import 'recurring_rule.dart';
import 'transaction_entry.dart';

/// A complete snapshot of the user's data, used for backup/restore.
class BackupData {
  const BackupData({
    required this.categories,
    required this.transactions,
    required this.budgets,
    required this.settings,
    this.notes = const [],
    this.recurring = const [],
    this.exportedAt,
  });

  final List<Category> categories;
  final List<TransactionEntry> transactions;
  final List<CategoryBudget> budgets;
  final Map<String, String> settings;
  final List<Note> notes;
  final List<RecurringRule> recurring;
  final DateTime? exportedAt;
}
