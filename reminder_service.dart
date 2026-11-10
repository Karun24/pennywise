import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/note.dart';
import '../utils/date_utils.dart';

/// Notification payloads understood by the app.
class ReminderPayload {
  ReminderPayload._();

  /// Opens the Add transaction screen.
  static const addTransaction = 'add';

  static String note(int id) => 'note:$id';

  static int? noteId(String? payload) {
    if (payload == null || !payload.startsWith('note:')) return null;
    return int.tryParse(payload.substring(5));
  }
}

/// Schedules device notifications: note reminders and the daily
/// "log your expenses" reminder.
///
/// Notifications are created entirely on the phone by the operating system;
/// nothing is sent to a server.
abstract class ReminderScheduler {
  /// [onTap] receives the payload of a tapped notification.
  Future<void> init({void Function(String payload)? onTap});

  /// Asks for notification permission. Returns false if it was refused.
  Future<bool> requestPermission();

  /// Schedules (or replaces) the reminder for [note]. Cancels it when the
  /// note has no future reminder. Returns false if it could not be set.
  Future<bool> schedule(Note note);

  Future<void> cancel(int noteId);

  /// Replaces all daily reminders with one-off notifications at [times].
  /// An empty list turns the daily reminder off.
  Future<void> scheduleDaily(List<DateTime> times);

  /// Payload of the notification that launched the app, if any.
  Future<String?> launchedPayload();
}

/// Does nothing. Used in tests and on platforms without notifications.
class NoopReminderScheduler implements ReminderScheduler {
  const NoopReminderScheduler();

  @override
  Future<void> init({void Function(String payload)? onTap}) async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> schedule(Note note) async => true;

  @override
  Future<void> cancel(int noteId) async {}

  @override
  Future<void> scheduleDaily(List<DateTime> times) async {}

  @override
  Future<String?> launchedPayload() async => null;
}

/// Real implementation backed by `flutter_local_notifications`.
class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _noteChannelId = 'pennywise_reminders';
  static const _noteChannelName = 'Note reminders';
  static const _dailyChannelId = 'pennywise_daily';
  static const _dailyChannelName = 'Daily reminder';

  /// Notification ids reserved for the daily reminder (note ids are small).
  static const _dailyBaseId = 1999999000;
  static const _dailySlots = 31;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init({void Function(String payload)? onTap}) async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_pennywise'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null) onTap?.call(payload);
        },
      );
      _ready = true;
    } catch (e) {
      debugPrint('PennyWise: notifications unavailable: $e');
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _android;
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(
                alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (e) {
      debugPrint('PennyWise: permission request failed: $e');
    }
    return false;
  }

  Future<void> _scheduleAt({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
    required String channelId,
    required String channelName,
    required String channelDescription,
  }) async {
    final exact = await _android?.canScheduleExactNotifications() ?? true;
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      // An absolute moment in time, so UTC is exact for one-off reminders.
      scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  @override
  Future<bool> schedule(Note note) async {
    final id = note.id;
    if (!_ready || id == null) return false;
    try {
      await _plugin.cancel(id: id);
      final at = note.reminderAt;
      if (at == null || !at.isAfter(DateTime.now())) return true;
      final body = note.body.trim().isEmpty
          ? 'Reminder from your notes'
          : note.body.trim();
      await _scheduleAt(
        id: id,
        at: at,
        title: note.displayTitle,
        body: body,
        payload: ReminderPayload.note(id),
        channelId: _noteChannelId,
        channelName: _noteChannelName,
        channelDescription: 'Reminders you set on your PennyWise notes',
      );
      return true;
    } catch (e) {
      debugPrint('PennyWise: could not schedule reminder: $e');
      return false;
    }
  }

  @override
  Future<void> cancel(int noteId) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: noteId);
    } catch (e) {
      debugPrint('PennyWise: could not cancel reminder: $e');
    }
  }

  @override
  Future<void> scheduleDaily(List<DateTime> times) async {
    if (!_ready) return;
    try {
      for (var i = 0; i < _dailySlots; i++) {
        await _plugin.cancel(id: _dailyBaseId + i);
      }
      final now = DateTime.now();
      var slot = 0;
      for (final at in times) {
        if (slot >= _dailySlots) break;
        if (!at.isAfter(now)) continue;
        await _scheduleAt(
          id: _dailyBaseId + slot,
          at: at,
          title: 'PennyWise',
          body: "Did you add today's expenses? Tap to add them now.",
          payload: ReminderPayload.addTransaction,
          channelId: _dailyChannelId,
          channelName: _dailyChannelName,
          channelDescription: 'A daily nudge to log your expenses',
        );
        slot++;
      }
    } catch (e) {
      debugPrint('PennyWise: could not schedule daily reminder: $e');
    }
  }

  @override
  Future<String?> launchedPayload() async {
    if (!_ready) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return details.notificationResponse?.payload;
    } catch (_) {
      return null;
    }
  }
}

/// "Today, 9:00 AM", "Tomorrow, 8:30 PM", "Fri 14 Nov, 9:00 AM".
String reminderLabel(DateTime at, DateTime now) {
  final day = DateUtilsX.dateOnly(at);
  final today = DateUtilsX.dateOnly(now);
  final time = DateUtilsX.time(at);
  if (day == today) return 'Today, $time';
  if (day == DateUtilsX.addDays(today, 1)) return 'Tomorrow, $time';
  if (day == DateUtilsX.addDays(today, -1)) return 'Yesterday, $time';
  final date = at.year == now.year
      ? '${DateUtilsX.weekdayShort(at)} ${DateUtilsX.dayMonth(at)}'
      : DateUtilsX.dayMonthYear(at);
  return '$date, $time';
}
