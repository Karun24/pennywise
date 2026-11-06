import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/note.dart';
import '../utils/date_utils.dart';

/// Schedules device notifications for note reminders.
///
/// Notifications are created entirely on the phone by the operating system;
/// nothing is sent to a server.
abstract class ReminderScheduler {
  Future<void> init({void Function(int noteId)? onOpenNote});

  /// Asks for notification permission. Returns false if it was refused.
  Future<bool> requestPermission();

  /// Schedules (or replaces) the reminder for [note]. Cancels it when the
  /// note has no future reminder. Returns false if it could not be set.
  Future<bool> schedule(Note note);

  Future<void> cancel(int noteId);

  /// Note id from the notification that launched the app, if any.
  Future<int?> launchedFromNote();
}

/// Does nothing. Used in tests and on platforms without notifications.
class NoopReminderScheduler implements ReminderScheduler {
  const NoopReminderScheduler();

  @override
  Future<void> init({void Function(int noteId)? onOpenNote}) async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> schedule(Note note) async => true;

  @override
  Future<void> cancel(int noteId) async {}

  @override
  Future<int?> launchedFromNote() async => null;
}

/// Real implementation backed by `flutter_local_notifications`.
class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'pennywise_reminders';
  static const _channelName = 'Reminders';

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  static int? _noteIdFrom(String? payload) {
    if (payload == null || !payload.startsWith('note:')) return null;
    return int.tryParse(payload.substring(5));
  }

  @override
  Future<void> init({void Function(int noteId)? onOpenNote}) async {
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
          final id = _noteIdFrom(response.payload);
          if (id != null) onOpenNote?.call(id);
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

  @override
  Future<bool> schedule(Note note) async {
    final id = note.id;
    if (!_ready || id == null) return false;
    try {
      await _plugin.cancel(id: id);
      final at = note.reminderAt;
      if (at == null || !at.isAfter(DateTime.now())) return true;

      final exact = await _android?.canScheduleExactNotifications() ?? true;
      final body = note.body.trim().isEmpty
          ? 'Reminder from your notes'
          : note.body.trim();
      await _plugin.zonedSchedule(
        id: id,
        title: note.displayTitle,
        body: body,
        // An absolute moment in time, so UTC is exact for one-off reminders.
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Reminders you set on your PennyWise notes',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'note:$id',
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
  Future<int?> launchedFromNote() async {
    if (!_ready) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return _noteIdFrom(details.notificationResponse?.payload);
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
