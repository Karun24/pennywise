import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/database/default_categories.dart';
import 'package:pennywise/models/app_settings.dart';
import 'package:pennywise/models/note.dart';
import 'package:pennywise/models/recurring_rule.dart';
import 'package:pennywise/models/transaction_entry.dart';
import 'package:pennywise/repositories/in_memory_finance_repository.dart';
import 'package:pennywise/services/backup_service.dart';
import 'package:pennywise/services/recurring_service.dart';
import 'package:pennywise/services/reminder_service.dart';
import 'package:pennywise/state/finance_store.dart';

class _Reminders implements ReminderScheduler {
  final daily = <List<DateTime>>[];

  @override
  Future<void> init({void Function(String payload)? onTap}) async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<bool> schedule(Note note) async => true;
  @override
  Future<void> cancel(int noteId) async {}
  @override
  Future<void> scheduleDaily(List<DateTime> times) async => daily.add(times);
  @override
  Future<String?> launchedPayload() async => null;
}

void main() {
  group('RecurringRule.advance', () {
    test('monthly keeps the anchor day across short months', () {
      var d = DateTime(2026, 1, 31);
      d = RecurringRule.advance(d, RepeatFrequency.monthly, 31);
      expect(d, DateTime(2026, 2, 28));
      d = RecurringRule.advance(d, RepeatFrequency.monthly, 31);
      expect(d, DateTime(2026, 3, 31));
      d = RecurringRule.advance(d, RepeatFrequency.monthly, 31);
      expect(d, DateTime(2026, 4, 30));
    });

    test('daily, weekly and yearly', () {
      expect(RecurringRule.advance(DateTime(2026, 12, 31),
          RepeatFrequency.daily, 31), DateTime(2027, 1, 1));
      expect(RecurringRule.advance(DateTime(2026, 11, 6),
          RepeatFrequency.weekly, 6), DateTime(2026, 11, 13));
      expect(RecurringRule.advance(DateTime(2028, 2, 29),
          RepeatFrequency.yearly, 29), DateTime(2029, 2, 28));
    });
  });

  group('FinanceStore recurring', () {
    late DateTime now;
    late FinanceStore store;

    setUp(() async {
      now = DateTime(2026, 11, 10, 12);
      store = FinanceStore(InMemoryFinanceRepository(), clock: () => now);
      await store.load();
    });

    TransactionEntry rent(DateTime date) {
      final cat = store.categories
          .firstWhere((c) => c.name == DefaultCategoryNames.bills);
      return TransactionEntry(
        type: TransactionType.expense,
        amountMinor: 1500000,
        categoryId: cat.id!,
        note: 'Rent',
        date: date,
        paymentMethod: PaymentMethod.netBanking,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('starting today adds the first one and schedules the next', () async {
      final rule =
          await store.addRecurring(rent(now), RepeatFrequency.monthly);
      expect(store.transactions, hasLength(1));
      expect(store.transactions.single.recurringId, rule.id);
      expect(rule.nextDue, DateTime(2026, 12, 10));
    });

    test('a start date in the past back-fills every missed month', () async {
      await store.addRecurring(
          rent(DateTime(2026, 8, 1)), RepeatFrequency.monthly);
      // Aug, Sep, Oct, Nov
      expect(store.transactions, hasLength(4));
      expect(store.recurring.single.nextDue, DateTime(2026, 12, 1));
    });

    test('a future start date adds nothing yet, then catches up later',
        () async {
      await store.addRecurring(
          rent(DateTime(2026, 11, 15)), RepeatFrequency.monthly);
      expect(store.transactions, isEmpty);

      now = DateTime(2026, 12, 16, 8);
      final added = await store.runRecurring();
      expect(added, 2); // 15 Nov and 15 Dec
      expect(store.takeNotice(), contains('2 recurring'));
      expect(store.takeNotice(), isNull);
    });

    test('paused rules add nothing; deleting keeps history', () async {
      final rule =
          await store.addRecurring(rent(now), RepeatFrequency.weekly);
      await store.updateRecurring(rule.copyWith(active: false));
      now = DateTime(2026, 12, 31, 12);
      expect(await store.runRecurring(), 0);

      await store.deleteRecurring(store.recurring.single);
      expect(store.recurring, isEmpty);
      expect(store.transactions, hasLength(1));
      expect(store.transactions.single.recurringId, isNull);
    });

    test('recurring rules survive backup and restore', () async {
      await store.addRecurring(rent(now), RepeatFrequency.monthly);
      final data = BackupService.decode(BackupService.encode(store.snapshot()));
      expect(data.recurring, hasLength(1));

      final other =
          FinanceStore(InMemoryFinanceRepository(), clock: () => now);
      await other.load();
      await other.restore(data);
      expect(other.recurring.single.note, 'Rent');
      expect(other.transactions, hasLength(1));
    });
  });

  group('daily reminder', () {
    test('skips today when something was logged or the time passed', () {
      final at9pm = RecurringService.dailyReminderTimes(
          now: DateTime(2026, 11, 10, 12),
          minutesOfDay: 21 * 60,
          loggedToday: false,
          days: 3);
      expect(at9pm.first, DateTime(2026, 11, 10, 21));
      expect(at9pm, hasLength(3));

      final logged = RecurringService.dailyReminderTimes(
          now: DateTime(2026, 11, 10, 12),
          minutesOfDay: 21 * 60,
          loggedToday: true,
          days: 3);
      expect(logged.first, DateTime(2026, 11, 11, 21));

      final afterTime = RecurringService.dailyReminderTimes(
          now: DateTime(2026, 11, 10, 22),
          minutesOfDay: 21 * 60,
          loggedToday: false,
          days: 3);
      expect(afterTime.first, DateTime(2026, 11, 11, 21));
    });

    test('store reschedules after a transaction is added', () async {
      final reminders = _Reminders();
      final now = DateTime(2026, 11, 10, 12);
      final store = FinanceStore(InMemoryFinanceRepository(),
          clock: () => now, reminders: reminders);
      await store.load();
      await store.updateSettings(store.settings.copyWith(dailyReminder: true));
      expect(reminders.daily.last.first, DateTime(2026, 11, 10, 21));

      final cat = store.categories.first;
      await store.addTransaction(TransactionEntry(
        type: TransactionType.expense,
        amountMinor: 10000,
        categoryId: cat.id!,
        note: 'Lunch',
        date: now,
        paymentMethod: PaymentMethod.upi,
        createdAt: now,
        updatedAt: now,
      ));
      // Already logged today, so the first reminder is tomorrow.
      expect(reminders.daily.last.first, DateTime(2026, 11, 11, 21));

      await store.updateSettings(store.settings.copyWith(dailyReminder: false));
      expect(reminders.daily.last, isEmpty);
    });

    test('settings round-trip', () {
      const s = AppSettings(
          dailyReminder: true, dailyReminderMinutes: 20 * 60 + 30, appLock: true);
      final back = AppSettings.fromKeyValues(s.toKeyValues());
      expect(back.dailyReminder, isTrue);
      expect(back.dailyReminderMinutes, 20 * 60 + 30);
      expect(back.appLock, isTrue);
    });
  });
}
