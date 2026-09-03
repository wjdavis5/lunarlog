/// Reminder scheduling seam (KTD7, R12): the coordinator plans
/// ([scheduling.dart]); an implementation owns the platform plugin.
/// Web deliberately has no reminders in v1 — a no-op scheduler (the plan's
/// posture: web is an insecure iteration surface).
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lunarlog/data/notifications/scheduling.dart';
import 'package:lunarlog/ui/overview/notification_availability.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

abstract interface class ReminderScheduler {
  /// Initializes the plugin, requests permission, and reports whether
  /// notifications are actually enabled. [onLaunchFromNotification] fires
  /// for a notification tap (warm) and for a cold start launched by a tap.
  Future<NotificationAvailability> initialize({
    void Function(String profileId)? onLaunchFromNotification,
  });

  Future<void> rescheduleAll(List<PlannedReminder> reminders);

  Future<void> cancelAll();
}

class FlutterLocalNotificationsScheduler implements ReminderScheduler {
  FlutterLocalNotificationsScheduler({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static const String _channelId = 'lunarlog_reminders';

  @override
  Future<NotificationAvailability> initialize({
    void Function(String profileId)? onLaunchFromNotification,
  }) async {
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          onLaunchFromNotification?.call(payload);
        }
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            'Reminders',
            description: 'Period reminders from Lunarlog',
          ),
        );
    _initialized = true;

    // Cold start from a notification tap carries its payload here.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final payload = launchDetails?.notificationResponse?.payload;
    if (launchDetails?.didNotificationLaunchApp == true &&
        payload != null &&
        payload.isNotEmpty) {
      onLaunchFromNotification?.call(payload);
    }

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final macosPlugin = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();

    bool enabled = true;
    if (androidPlugin != null) {
      enabled = await androidPlugin.areNotificationsEnabled() ?? true;
    } else if (iosPlugin != null) {
      final options = await iosPlugin.checkPermissions();
      if (options != null) {
        enabled = options.isEnabled;
      }
    } else if (macosPlugin != null) {
      final options = await macosPlugin.checkPermissions();
      if (options != null) {
        enabled = options.isEnabled;
      }
    }

    return enabled
        ? NotificationAvailability.available
        : NotificationAvailability.denied;
  }

  @override
  Future<void> rescheduleAll(List<PlannedReminder> reminders) async {
    if (!_initialized) return;
    await _plugin.cancelAllPendingNotifications();
    for (final (index, reminder) in reminders.indexed) {
      final fireAt = tz.TZDateTime.local(
        reminder.fireOn.year,
        reminder.fireOn.month,
        reminder.fireOn.day,
        9, // Morning reminder, local civil time.
      );
      await _plugin.zonedSchedule(
        id: index,
        title: kReminderTitle,
        body: kReminderBody,
        scheduledDate: fireAt,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Reminders',
            channelDescription: 'Period reminders from Lunarlog',
            // Lock-screen privacy: content hidden on the lock screen; the
            // generic body is the second line of defense. iOS preview
            // visibility is a user OS setting — generic content is the only
            // app-controlled iOS control (KTD7).
            visibility: NotificationVisibility.secret,
          ),
        ),
        // Inexact on purpose: no SCHEDULE_EXACT_ALARM permission needed
        // (Android 12+), and minute-level drift is fine for ±2-day windows.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: reminder.profileId,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAllPendingNotifications();
  }
}

/// Web scheduler: no reminders in v1 (KTD9 — web is the insecure iteration
/// surface; scheduling paths are skipped entirely).
class NoopReminderScheduler implements ReminderScheduler {
  @override
  Future<NotificationAvailability> initialize({
    void Function(String profileId)? onLaunchFromNotification,
  }) async => NotificationAvailability.available;

  @override
  Future<void> rescheduleAll(List<PlannedReminder> reminders) async {}

  @override
  Future<void> cancelAll() async {}
}
