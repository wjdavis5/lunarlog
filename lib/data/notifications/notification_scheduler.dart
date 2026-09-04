/// Reminder scheduling seam (KTD7, R12): the coordinator plans
/// ([scheduling.dart]); an implementation owns the platform plugin.
/// Web deliberately has no reminders in v1 — a no-op scheduler (the plan's
/// posture: web is an insecure iteration surface).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:lunarlog/data/notifications/scheduling.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/ui/overview/notification_availability.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

typedef LocalTimeZoneProvider = Future<String> Function();

/// Computes the exact [tz.TZDateTime] for a morning reminder on [fireOn]
/// in the given [location] (default 9:00 AM local civil time).
tz.TZDateTime calculateReminderFireAt({
  required LocalDate fireOn,
  required tz.Location location,
  int hour = 9,
}) {
  return tz.TZDateTime(
    location,
    fireOn.year,
    fireOn.month,
    fireOn.day,
    hour,
  );
}

/// Resolves the host device's IANA time zone identifier via platform channels.
/// Falls back to 'UTC' if unavailable.
Future<String> defaultLocalTimeZoneProvider() async {
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    return info.identifier;
  } catch (_) {
    return 'UTC';
  }
}

abstract interface class ReminderScheduler {
  /// Initializes the plugin, requests permission, and reports whether
  /// notifications are actually enabled. [onLaunchFromNotification] fires
  /// for a notification tap (warm) and for a cold start launched by a tap.
  Future<NotificationAvailability> initialize({
    void Function(String profileId)? onLaunchFromNotification,
  });

  /// Reads the current OS permission without reinitializing the plugin.
  Future<NotificationAvailability> checkAvailability();

  Future<void> rescheduleAll(List<PlannedReminder> reminders);

  Future<void> cancelAll();
}

class FlutterLocalNotificationsScheduler implements ReminderScheduler {
  FlutterLocalNotificationsScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    LocalTimeZoneProvider? localTimeZoneProvider,
    this.locationProvider,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _localTimeZoneProvider =
            localTimeZoneProvider ?? defaultLocalTimeZoneProvider;

  final FlutterLocalNotificationsPlugin _plugin;
  final LocalTimeZoneProvider _localTimeZoneProvider;
  final tz.Location Function()? locationProvider;
  bool _initialized = false;

  static const String _channelId = 'lunarlog_reminders';

  @override
  Future<NotificationAvailability> initialize({
    void Function(String profileId)? onLaunchFromNotification,
  }) async {
    if (tz.timeZoneDatabase.locations.isEmpty) {
      tzdata.initializeTimeZones();
    }
    try {
      final tzName = await _localTimeZoneProvider();
      final loc = tz.getLocation(tzName);
      tz.setLocalLocation(loc);
    } catch (_) {
      // Fallback: tz.local remains UTC or previously initialized location.
    }
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

    return checkAvailability();
  }

  @override
  Future<NotificationAvailability> checkAvailability() async {
    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final macosPlugin = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();

      bool? enabled;
      if (androidPlugin != null) {
        enabled = await androidPlugin.areNotificationsEnabled();
      } else if (iosPlugin != null) {
        enabled = (await iosPlugin.checkPermissions())?.isEnabled;
      } else if (macosPlugin != null) {
        enabled = (await macosPlugin.checkPermissions())?.isEnabled;
      }
      return enabled == false
          ? NotificationAvailability.denied
          : NotificationAvailability.available;
    } catch (error) {
      // The OS remains the enforcement boundary. Preserve the historical
      // available fallback rather than aborting reminder coordination.
      debugPrint(
          'lunarlog notifications: permission probe failed (${error.runtimeType})');
      return NotificationAvailability.available;
    }
  }

  @override
  Future<void> rescheduleAll(List<PlannedReminder> reminders) async {
    if (!_initialized) return;
    await _plugin.cancelAllPendingNotifications();
    final loc = locationProvider?.call() ?? tz.local;
    for (final (index, reminder) in reminders.indexed) {
      final fireAt = calculateReminderFireAt(
        fireOn: reminder.fireOn,
        location: loc,
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
  Future<NotificationAvailability> checkAvailability() async =>
      NotificationAvailability.available;

  @override
  Future<void> rescheduleAll(List<PlannedReminder> reminders) async {}

  @override
  Future<void> cancelAll() async {}
}
