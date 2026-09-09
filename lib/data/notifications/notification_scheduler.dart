/// Reminder scheduling seam (KTD7, R12): the coordinator plans
/// ([scheduling.dart]); an implementation owns the platform plugin.
/// Web deliberately has no reminders in v1 — a no-op scheduler (the plan's
/// posture: web is an insecure iteration surface).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:lunarlog/data/notifications/reminder_payload.dart';
import 'package:lunarlog/data/notifications/scheduling.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/notifications/notification_permission_action.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

typedef LocalTimeZoneProvider = Future<String> Function();

/// The Darwin notification category the reminder actions (Issue #136) are
/// registered under. Every period-anchored reminder carries this category
/// identifier so iOS offers its action buttons; the actions themselves are
/// registered once in [FlutterLocalNotificationsScheduler.initialize].
const String kReminderCategoryId = 'lunarlog_reminder';

/// Which reminder kinds carry the Started / Spotting / Not yet action
/// buttons (Issue #136, widened by Issue #178): the period-anchored kinds
/// do — their "period may be starting" semantics is what the buttons
/// assert. The daily log nudge, the fertile-window-soon kind, and the
/// statistic-change kind carry none: their reminders make no period-start
/// claim, so "Started" would log a period the notification never suggested
/// (and "Not yet" would pre-snooze a late window it says nothing about).
bool reminderHasActions(ReminderKind kind) => switch (kind) {
      ReminderKind.upcoming ||
      ReminderKind.periodStartingSoon ||
      ReminderKind.pms ||
      ReminderKind.late =>
        true,
      ReminderKind.fertileWindowSoon ||
      ReminderKind.cycleStatisticChange ||
      ReminderKind.log =>
        false,
    };

/// Computes the exact [tz.TZDateTime] for a reminder on [fireOn] at
/// [minuteOfDay] (minutes since local midnight; default 09:00 — the
/// pre-#136 hardcoded hour) in the given [location].
tz.TZDateTime calculateReminderFireAt({
  required LocalDate fireOn,
  required tz.Location location,
  int minuteOfDay = kDefaultReminderTimeMinutes,
}) {
  return tz.TZDateTime(
    location,
    fireOn.year,
    fireOn.month,
    fireOn.day,
    minuteOfDay ~/ 60,
    minuteOfDay % 60,
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
  /// for a notification tap (warm) and for a cold start launched by a tap,
  /// decoded into a [ReminderLaunch] — whose [ReminderLaunch.actionId]
  /// distinguishes an action-button tap (Issue #136) from a plain tap.
  Future<NotificationAvailability> initialize({
    void Function(ReminderLaunch launch)? onLaunchFromNotification,
  });

  /// Reads the current OS permission without reinitializing the plugin.
  Future<NotificationAvailability> checkAvailability();

  /// Issue #168: re-requests the OS permission from an explicit user
  /// action (the overview hint's "Turn on reminders" tap) — independent of
  /// [initialize], and not gated on push/FCM being configured. Once the OS
  /// has stopped showing the request dialog at all — Android: two
  /// refusals (see [nextNotificationPermissionAction]); Darwin: one, since
  /// its own dialog is one-shot-per-install — this opens the platform's
  /// notification-settings screen instead of re-prompting silently. Always
  /// ends by reporting the resulting availability, the same as
  /// [initialize] and [checkAvailability].
  Future<NotificationAvailability> requestPermission();

  Future<void> rescheduleAll(List<PlannedReminder> reminders);

  Future<void> cancelAll();
}

class FlutterLocalNotificationsScheduler implements ReminderScheduler {
  FlutterLocalNotificationsScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    LocalTimeZoneProvider? localTimeZoneProvider,
    this.locationProvider,
    this.settingsStore,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _localTimeZoneProvider =
            localTimeZoneProvider ?? defaultLocalTimeZoneProvider;

  final FlutterLocalNotificationsPlugin _plugin;
  final LocalTimeZoneProvider _localTimeZoneProvider;
  final tz.Location Function()? locationProvider;
  bool _initialized = false;

  /// Issue #168: the device-local store the Android denial count is
  /// persisted in. Not available at construction time in production —
  /// `main.dart` builds this scheduler before the database (and so the
  /// settings store) exists — so it is mutable rather than `final`;
  /// `_LunarLogAppState.initState` attaches it as soon as the store is
  /// built. `null` (a widget test with no scheduler wiring, or before that
  /// attachment happens) falls back to the in-memory-only behavior this
  /// counter used to always have.
  SettingsStore? settingsStore;

  // Issue #168: how many OS asks (the automatic one in [initialize], plus
  // every [requestPermission] tap) have come back refused on Android.
  // Mirrors (and is kept in sync with) the persisted copy in
  // [settingsStore] under [SettingsKeys.androidNotificationDeniedAttempts]
  // — reading here avoids an `await` on every [nextNotificationPermissionAction]
  // decision. Feeds that function so a permanently-denied permission opens
  // settings instead of re-prompting into silence.
  int _androidDeniedAttempts = 0;

  static const String _channelId = 'lunarlog_reminders';

  /// Loads the persisted count ([SettingsKeys.androidNotificationDeniedAttempts])
  /// so a fresh process (after a restart) picks up where the last one left
  /// off instead of re-starting at zero. Falls back to the in-memory value
  /// when no store is attached (e.g. a test that constructs this scheduler
  /// directly) or the stored value is missing/unparsable.
  Future<int> _loadAndroidDeniedAttempts() async {
    final store = settingsStore;
    if (store == null) return _androidDeniedAttempts;
    final raw = await store.get(SettingsKeys.androidNotificationDeniedAttempts);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<void> _persistAndroidDeniedAttempts(int value) async {
    final store = settingsStore;
    if (store == null) return;
    await store.set(
      SettingsKeys.androidNotificationDeniedAttempts,
      '$value',
    );
  }

  @override
  Future<NotificationAvailability> initialize({
    void Function(ReminderLaunch launch)? onLaunchFromNotification,
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
    // Issue #136: the action buttons the reminders offer. Registered once
    // here so a notification carrying the category identifier presents
    // them (Darwin); Android carries the same actions per-notification in
    // [rescheduleAll]. Generic words only — no health detail (KTD7).
    // (DarwinNotificationAction.plain is a factory, not const.)
    final darwinActions = [
      DarwinNotificationAction.plain(
          kReminderActionStarted, kReminderActionStartedLabel),
      DarwinNotificationAction.plain(
          kReminderActionSpotting, kReminderActionSpottingLabel),
      DarwinNotificationAction.plain(
          kReminderActionNotYet, kReminderActionNotYetLabel),
    ];
    final reminderCategory = DarwinNotificationCategory(
      kReminderCategoryId,
      actions: darwinActions,
    );
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    final darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [reminderCategory],
    );
    await _plugin.initialize(
      settings: InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ),
      onDidReceiveNotificationResponse: (response) {
        final launch = decodeReminderLaunch(
          response.payload,
          actionId: response.actionId,
        );
        if (launch != null) {
          onLaunchFromNotification?.call(launch);
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
    // configured, unlike the request in firebase_push_token_source.dart:105
    // -- see [requestPermission]'s Darwin branch note on why that matters).
    if (androidPlugin != null) {
      try {
        final previous = await _loadAndroidDeniedAttempts();
        final granted = await androidPlugin.requestNotificationsPermission();
        // #5: a `null` result means the OS never actually resolved this
        // request -- most likely `FirebaseMessaging.requestPermission()`
        // (firebase_push_token_source.dart:105, on `hasPush` builds) raced
        // this call and the platform reported
        // `PERMISSION_REQUEST_IN_PROGRESS` for one of them. That is
        // "unknown", not a refusal: don't ratchet the count toward
        // `openSettings` on an answer the OS never actually gave.
        _androidDeniedAttempts = switch (granted) {
          true => 0,
          false => previous + 1,
          null => previous,
        };
        await _persistAndroidDeniedAttempts(_androidDeniedAttempts);
      } catch (error) {
        // #3: never let a platform-call failure escape `initialize()` --
        // it is `unawaited` from `_startReminders`, so a throw here would
        // leave `_started` false and the "Turn on reminders" hint's
        // callback permanently unusable. `checkAvailability()` below is
        // still the source of truth for what gets reported.
        debugPrint('lunarlog notifications: requestNotificationsPermission '
            'failed (${error.runtimeType})');
      }
    }
    _initialized = true;

    // Cold start from a notification tap carries its payload (and, for an
    // action-button launch, its action id — Issue #136) here.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final response = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        response != null &&
        response.payload != null &&
        response.payload!.isNotEmpty) {
      final launch = decodeReminderLaunch(
        response.payload,
        actionId: response.actionId,
      );
      if (launch != null) {
        onLaunchFromNotification?.call(launch);
      }
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
      // #1: read the persisted count fresh rather than trusting whatever
      // is already in memory — covers a caller that reaches this before
      // (or without ever calling) [initialize] on this instance, not just
      // the ordinary startup-then-tap sequence.
      _androidDeniedAttempts = await _loadAndroidDeniedAttempts();
      final action =
          nextNotificationPermissionAction(_androidDeniedAttempts);
      try {
        if (action == NotificationPermissionAction.openSettings) {
          await androidPlugin.openAppNotificationSettings();
        } else {
          final previous = _androidDeniedAttempts;
          final granted =
              await androidPlugin.requestNotificationsPermission();
          // #5: `null` is "unknown", not a refusal -- see the matching
          // note in [initialize].
          _androidDeniedAttempts = switch (granted) {
            true => 0,
            false => previous + 1,
            null => previous,
          };
          await _persistAndroidDeniedAttempts(_androidDeniedAttempts);
        }
      } catch (error) {
        // #3: tolerate a platform-call failure the same way [initialize]
        // does -- report through [checkAvailability] below rather than
        // throwing back into the (also unawaited-in-practice) caller.
        debugPrint('lunarlog notifications: Android permission re-request '
            'failed (${error.runtimeType})');
      }
      return checkAvailability();
    }
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final macosPlugin = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    try {
      // #4: both `IOSFlutterLocalNotificationsPlugin` and
      // `MacOSFlutterLocalNotificationsPlugin` DO carry their own
      // `openAppNotificationSettings()` (pinned 22.3.0's
      // platform_flutter_local_notifications.dart:812 / :1020) -- an
      // earlier version of this comment claimed otherwise. Darwin's own
      // permission dialog is one-shot-per-install: [initialize]'s
      // `DarwinInitializationSettings(requestAlertPermission: true, ...)`
      // already spends it, so a `requestPermissions()` re-request here
      // would silently no-op forever once the OS has already recorded a
      // decision, leaving the "Turn on reminders" tap dead exactly like
      // the pre-fix Android button. Checking the *current* availability
      // first and routing a denied result to settings avoids that without
      // inventing a parallel denial counter: the overview hint that drives
      // this call is itself gated on "not available" already.
      final current = await checkAvailability();
      if (current == NotificationAvailability.denied) {
        await iosPlugin?.openAppNotificationSettings();
        await macosPlugin?.openAppNotificationSettings();
      } else {
        await iosPlugin?.requestPermissions(
            alert: true, badge: false, sound: false);
        await macosPlugin?.requestPermissions(
            alert: true, badge: false, sound: false);
      }
    } catch (error) {
      // #3: same tolerance as the Android branch above.
      debugPrint('lunarlog notifications: Darwin permission re-request '
          'failed (${error.runtimeType})');
    }
    return checkAvailability();
  }

  @override
  Future<void> rescheduleAll(List<PlannedReminder> reminders) async {
    if (!_initialized) return;
    await _plugin.cancelAllPendingNotifications();
    final loc = locationProvider?.call() ?? tz.local;
    for (final reminder in reminders) {
      final fireAt = calculateReminderFireAt(
        fireOn: reminder.fireOn,
        location: loc,
        minuteOfDay: reminder.timeOfDayMinutes,
      );
      // Issue #136: the period reminders (upcoming, period-starting-soon,
      // PMS-watch, late) offer the Started / Spotting / Not yet action
      // buttons; the daily log nudge offers none (a generic nudge opens
      // the app, nothing more), and so do Issue #178's fertile-window-soon
      // and statistic-change kinds (see [reminderHasActions]). The action
      // ids ride [kReminderActionIds]; on Darwin they reach the
      // notification via the category registered in [initialize].
      final hasActions = reminderHasActions(reminder.kind);
      await _plugin.zonedSchedule(
        id: reminder.id,
        title: kReminderTitle,
        body: kReminderBody,
        scheduledDate: fireAt,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Reminders',
            channelDescription: 'Period reminders from Lunarlog',
            // Lock-screen privacy: content hidden on the lock screen; the
            // generic body is the second line of defense. iOS preview
            // visibility is a user OS setting — generic content is the only
            // app-controlled iOS control (KTD7).
            visibility: NotificationVisibility.secret,
            actions: hasActions
                ? const [
                    AndroidNotificationAction(
                        kReminderActionStarted, kReminderActionStartedLabel),
                    AndroidNotificationAction(kReminderActionSpotting,
                        kReminderActionSpottingLabel),
                    AndroidNotificationAction(kReminderActionNotYet,
                        kReminderActionNotYetLabel),
                  ]
                : null,
          ),
          // Previously no Darwin details were passed at all; passing only
          // the category identifier (every presentation field left null)
          // keeps iOS/macOS presentation exactly as it was while attaching
          // the action buttons (Issue #136).
          iOS: hasActions
              ? const DarwinNotificationDetails(
                  categoryIdentifier: kReminderCategoryId)
              : null,
          macOS: hasActions
              ? const DarwinNotificationDetails(
                  categoryIdentifier: kReminderCategoryId)
              : null,
        ),
        // Inexact on purpose: no SCHEDULE_EXACT_ALARM permission needed
        // (Android 12+), and minute-level drift is fine for ±2-day windows.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: encodeReminderPayload(
          profileId: reminder.profileId,
          kind: reminder.kind,
        ),
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
    void Function(ReminderLaunch launch)? onLaunchFromNotification,
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
