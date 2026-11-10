import '../models/recurring_rule.dart';
import '../models/transaction_entry.dart';
import '../utils/date_utils.dart';

/// Transactions to add and rules to move forward after a catch-up run.
class RecurringRun {
  const RecurringRun({required this.created, required this.updated});

  final List<TransactionEntry> created;
  final List<RecurringRule> updated;

  bool get isEmpty => created.isEmpty;
}

/// Pure logic that turns recurring rules into real transactions.
///
/// Runs when the app opens (and when it returns to the foreground), adding
/// every occurrence that has become due since last time - so nothing is
/// missed even if the app was not opened for a while.
class RecurringService {
  RecurringService._();

  /// Safety cap per rule and run (e.g. a daily rule after a long break).
  static const maxPerRule = 400;

  static RecurringRun due(List<RecurringRule> rules, DateTime now) {
    final today = DateUtilsX.dateOnly(now);
    final created = <TransactionEntry>[];
    final updated = <RecurringRule>[];
    for (final rule in rules) {
      if (!rule.active || rule.id == null) continue;
      var next = rule.nextDue;
      var count = 0;
      while (!next.isAfter(today) && count < maxPerRule) {
        // 9 AM keeps auto-added items in a sensible place within the day.
        final at = DateTime(next.year, next.month, next.day, 9);
        created.add(TransactionEntry(
          type: rule.type,
          amountMinor: rule.amountMinor,
          categoryId: rule.categoryId,
          note: rule.note,
          date: at,
          paymentMethod: rule.paymentMethod,
          createdAt: now,
          updatedAt: now,
          recurringId: rule.id,
        ));
        next = RecurringRule.advance(next, rule.frequency, rule.anchorDay);
        count++;
      }
      if (count > 0) updated.add(rule.copyWith(nextDue: next));
    }
    return RecurringRun(created: created, updated: updated);
  }

  /// Local times for the daily "log your expenses" reminder over the next
  /// [days] days. Today is skipped if something was already logged or the
  /// time has passed.
  static List<DateTime> dailyReminderTimes({
    required DateTime now,
    required int minutesOfDay,
    required bool loggedToday,
    int days = 14,
  }) {
    final today = DateUtilsX.dateOnly(now);
    final h = minutesOfDay ~/ 60, m = minutesOfDay % 60;
    final out = <DateTime>[];
    for (var i = 0; i < days; i++) {
      final d = DateUtilsX.addDays(today, i);
      final at = DateTime(d.year, d.month, d.day, h, m);
      if (i == 0 && (loggedToday || !at.isAfter(now))) continue;
      out.add(at);
    }
    return out;
  }
}
