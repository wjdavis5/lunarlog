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
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/notifications/notification_permission_action.dart';
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

  /// Issue #168: re-requests the OS permission from an explicit user
  /// action (the overview hint's "Turn on reminders" tap) — independent of
  /// [initialize], and not gated on push/FCM being configured. Once the OS
  /// has stopped showing the request dialog at all (Android: two
  /// refusals; see [nextNotificationPermissionAction]), this opens the
  /// platform's notification-settings screen instead of re-prompting
  /// silently. Always ends by reporting the resulting availability, the
  /// same as [initialize] and [checkAvailability].
  Future<NotificationAvailability> requestPermission();

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

  // Issue #168: how many OS asks (the automatic one in [initialize], plus
  // every [requestPermission] tap) have come back refused on Android.
  // Feeds [nextNotificationPermissionAction] so a permanently-denied
  // permission opens settings instead of re-prompting into silence. Not
  // persisted across app restarts -- a fresh process re-learns it from the
  // first denied result, which costs at most one extra "Turn on reminders"
  // tap after a restart that lands between the two refusals.
  int _androidDeniedAttempts = 0;

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
      // Never retain a stale location after the device zone changes and a
      // subsequent lookup fails.
      tz.setLocalLocation(tz.UTC);
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
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Reminders',
        description: 'Period reminders from Lunarlog',
      ),
    );
    // Issue #168: API 33+ (Android 13) treats POST_NOTIFICATIONS as a
    // runtime permission that stays denied until requested, no matter what
    // the manifest declares -- mirrors the Darwin `requestAlertPermission`
    // request above, and runs unconditionally (not gated on push/FCM being
    // configured, unlike the request in firebase_push_token_source.dart).
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      _androidDeniedAttempts = granted == true ? 0 : 1;
    }
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
  Future<NotificationAvailability> requestPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final action =
          nextNotificationPermissionAction(_androidDeniedAttempts);
      if (action == NotificationPermissionAction.openSettings) {
        await androidPlugin.openAppNotificationSettings();
      } else {
        final granted = await androidPlugin.requestNotificationsPermission();
        _androidDeniedAttempts =
            granted == true ? 0 : _androidDeniedAttempts + 1;
      }
      return checkAvailability();
    }
    // Darwin has no in-package "open settings" path, and the OS itself
    // enforces the one-shot-then-cached-answer rule on a re-request the
    // same way Android does -- so re-asking is always the safe action.
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final macosPlugin = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(
        alert: true, badge: false, sound: false);
    await macosPlugin?.requestPermissions(
        alert: true, badge: false, sound: false);
    return checkAvailability();
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
  Future<NotificationAvailability> requestPermission() async =>
      NotificationAvailability.available;

  @override
  Future<void> rescheduleAll(List<PlannedReminder> reminders) async {}

  @override
  Future<void> cancelAll() async {}
}
