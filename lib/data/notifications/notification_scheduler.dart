/// Reminder scheduling seam (KTD7, R12): the coordinator plans
/// ([scheduling.dart]); an implementation owns the platform plugin.
/// Web deliberately has no reminders in v1 — a no-op scheduler (the plan's
/// posture: web is an insecure iteration surface).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:lunarlog/data/notifications/notification_permission_gate.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/notifications/notification_permission_action.dart';
import 'package:lunarlog/domain/notifications/reminder_fire_time.dart';
import 'package:lunarlog/domain/notifications/reminder_payload.dart';
import 'package:lunarlog/domain/notifications/reminder_scheduler.dart';
import 'package:lunarlog/domain/notifications/scheduling.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

typedef LocalTimeZoneProvider = Future<String> Function();

/// The Darwin notification category the reminder actions (Issue #136) are
/// registered under. Every period-anchored reminder carries this category
/// identifier so iOS offers its action buttons; the actions themselves are
/// registered once in [FlutterLocalNotificationsScheduler.initialize].
const String kReminderCategoryId = 'lunarlog_reminder';

/// The Android notification channel every reminder-shaped notification is
/// posted on (Issue #174: promoted from the scheduler's private constant so
/// the FCM manifest meta-data and the push presenter in
/// `push_presentation.dart` can pin FCM-delivered caregiver alerts onto the
/// exact same channel locally scheduled reminders use, and
/// `test/release/fcm_presentation_manifest_test.dart` can assert the
/// manifest copy matches).
const String kReminderChannelId = 'lunarlog_reminders';

/// The "Reminders" channel itself, shared by [FlutterLocalNotificationsScheduler.initialize]
/// and the FCM background handler (issue #174) so a channel created from
/// either path is identical.
const AndroidNotificationChannel kReminderNotificationChannel =
    AndroidNotificationChannel(
  kReminderChannelId,
  'Reminders',
  description: 'Period reminders from lunarlog',
);

/// The Android notification details every reminder-shaped notification is
/// posted with — locally scheduled (Issue #136/#178/#183) and FCM-delivered
/// caregiver alerts (Issue #174) alike, so the two are visually identical:
/// same channel, same lock-screen privacy (`secret`), and — when [actions]
/// is passed — the same Started / Spotting / Not yet buttons.
AndroidNotificationDetails reminderNotificationDetails({
  List<AndroidNotificationAction>? actions,
}) =>
    AndroidNotificationDetails(
      kReminderChannelId,
      'Reminders',
      channelDescription: 'Period reminders from lunarlog',
      // Lock-screen privacy: content hidden on the lock screen; the
      // generic body is the second line of defense. iOS preview
      // visibility is a user OS setting — generic content is the only
      // app-controlled iOS control (KTD7).
      visibility: NotificationVisibility.secret,
      actions: actions,
    );

/// Which reminder kinds carry the Started / Spotting / Not yet action
/// buttons (Issue #136, widened by Issue #178): the period-anchored kinds
/// do — their "period may be starting" semantics is what the buttons
/// assert. The daily log nudge, the fertile-window-soon kind, the
/// statistic-change kind, and Issue #183's birth-control adherence kinds
/// carry none: their reminders make no period-start claim, so "Started"
/// would log a period the notification never suggested (and "Not yet"
/// would pre-snooze a late window it says nothing about).
bool reminderHasActions(ReminderKind kind) => switch (kind) {
      ReminderKind.upcoming ||
      ReminderKind.periodStartingSoon ||
      ReminderKind.pms ||
      ReminderKind.late =>
        true,
      ReminderKind.fertileWindowSoon ||
      ReminderKind.cycleStatisticChange ||
      ReminderKind.log ||
      ReminderKind.birthControlPill ||
      ReminderKind.birthControlPatch ||
      ReminderKind.birthControlRing ||
      ReminderKind.birthControlShot =>
        false,
    };

// Issue #215: calculateReminderFireAt (the fire-time computation this file
// used to own) moved to lib/domain/notifications/reminder_fire_time.dart —
// same signature, same behavior — so its unit tests count toward the
// coverage floor instead of living in this gate-excluded file.

/// Resolves the host device's IANA time zone identifier via platform channels.
/// Falls back to 'UTC' if unavailable.
Future<String> defaultLocalTimeZoneProvider({
  BreadcrumbLog? breadcrumbLog,
}) async {
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    return info.identifier;
  } catch (error) {
    (breadcrumbLog ?? defaultBreadcrumbLog)
        .record('timezone', error.runtimeType.toString());
    return 'UTC';
  }
}

class FlutterLocalNotificationsScheduler implements ReminderScheduler {
  FlutterLocalNotificationsScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    LocalTimeZoneProvider? localTimeZoneProvider,
    this.locationProvider,
    this.settingsStore,
    NotificationPermissionGate? permissionGate,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _localTimeZoneProvider =
            localTimeZoneProvider ?? defaultLocalTimeZoneProvider,
        _permissionGate = permissionGate ?? defaultNotificationPermissionGate;

  final FlutterLocalNotificationsPlugin _plugin;
  final LocalTimeZoneProvider _localTimeZoneProvider;
  final tz.Location Function()? locationProvider;
  bool _initialized = false;

  /// Issue #287: serializes every OS permission-request call below against
  /// [FirebasePushTokenSource]'s own `FirebaseMessaging.instance
  /// .requestPermission()` — both fire at database open with no ordering
  /// relationship between the two widgets that start them. See
  /// `notification_permission_gate.dart`'s library doc for the full
  /// decision record.
  final NotificationPermissionGate _permissionGate;

  /// Issue #168: the device-local store the Android denial count is
  /// persisted in. Constructor-injected (R9): the composition factory builds
  /// the scheduler only after the database — and so the settings store —
  /// exists, so this is never mutated after construction. `null` (a widget
  /// test with no scheduler wiring) falls back to the in-memory-only
  /// behavior this counter used to always have.
  final SettingsStore? settingsStore;

  // Issue #168: how many OS asks (the automatic one in [initialize], plus
  // every [requestPermission] tap) have come back refused on Android.
  // Mirrors (and is kept in sync with) the persisted copy in
  // [settingsStore] under [SettingsKeys.androidNotificationDeniedAttempts]
  // — reading here avoids an `await` on every [nextNotificationPermissionAction]
  // decision. Feeds that function so a permanently-denied permission opens
  // settings instead of re-prompting into silence.
  int _androidDeniedAttempts = 0;

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
    // LLA-028 (issue #623): every action opts into `.foreground`. None of
    // these buttons carries a background handler
    // (`onDidReceiveBackgroundNotificationResponse` is never registered,
    // deliberately -- a period-start/spotting write belongs on the
    // gate-aware executor `reminder_action_executor.dart` reaches, which
    // needs a running, unlocked app, not a background isolate), so without
    // this option a tap on a background/terminated app's action silently
    // did nothing on iOS: a plain action never launches the app.
    const darwinForeground = {DarwinNotificationActionOption.foreground};
    final darwinActions = [
      DarwinNotificationAction.plain(
          kReminderActionStarted, kReminderActionStartedLabel,
          options: darwinForeground),
      DarwinNotificationAction.plain(
          kReminderActionSpotting, kReminderActionSpottingLabel,
          options: darwinForeground),
      DarwinNotificationAction.plain(
          kReminderActionNotYet, kReminderActionNotYetLabel,
          options: darwinForeground),
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
    // Issue #287: on Darwin, `requestAlertPermission: true` above means
    // this call itself is when the OS permission prompt fires -- guarded
    // the same way the explicit Android request below is, so it never runs
    // concurrently with FirebasePushTokenSource's own
    // `FirebaseMessaging.instance.requestPermission()`.
    await _permissionGate.guard(() => _plugin.initialize(
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
    ));
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      kReminderNotificationChannel,
    );
    // Issue #168: API 33+ (Android 13) treats POST_NOTIFICATIONS as a
    // runtime permission that stays denied until requested, no matter what
    // the manifest declares -- mirrors the Darwin `requestAlertPermission`
    // request above, and runs unconditionally (not gated on push/FCM being
    // configured, unlike the request in firebase_push_token_source.dart --
    // see [requestPermission]'s Darwin branch note on why that matters).
    if (androidPlugin != null) {
      try {
        final previous = await _loadAndroidDeniedAttempts();
        // Issue #287: guarded so this never runs concurrently with
        // FirebasePushTokenSource's own `requestPermission()` -- previously
        // the two could race, and Android drops a second
        // `requestPermissions()` call while one is already pending.
        final granted = await _permissionGate
            .guard(() => androidPlugin.requestNotificationsPermission());
        // #5: a `null` result means the OS never actually resolved this
        // request -- kept as defense in depth now that [_permissionGate]
        // closes the race that used to cause it (a concurrent
        // `FirebaseMessaging.requestPermission()` reporting
        // `PERMISSION_REQUEST_IN_PROGRESS`): still "unknown", not a
        // refusal, whatever else might produce a `null` here. Don't
        // ratchet the count toward `openSettings` on an answer the OS
        // never actually gave.
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
      // Issue #215: the enabled→availability mapping itself is the pure
      // domain function notificationAvailabilityFromPlatformProbe()
      // (lib/domain/notifications/notification_availability.dart),
      // directly unit-tested and counted toward the coverage floor; only
      // the platform probes above remain plugin-bound.
      return notificationAvailabilityFromPlatformProbe(enabled);
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
          // Issue #287: same gate as [initialize]'s own Android request --
          // this is user-triggered (the "Turn on reminders" tap) rather
          // than a startup race, but routing it through the same gate
          // costs nothing and keeps every real request serialized, not
          // just the ones known to race today.
          final granted = await _permissionGate
              .guard(() => androidPlugin.requestNotificationsPermission());
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
        // Issue #287: same gate as every other permission request in this
        // class -- see [initialize]'s Android branch note.
        await _permissionGate.guard(() async {
          await iosPlugin?.requestPermissions(
              alert: true, badge: false, sound: false);
          await macosPlugin?.requestPermissions(
              alert: true, badge: false, sound: false);
        });
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
        // Issue #184: the reminder's own resolved text — custom per-type
        // copy when the profile configured it, else the generic defaults.
        // The text is baked in here at schedule time (local notifications
        // have no Dart callback at fire time) and stays current through
        // #136's replan-on-every-change machinery, which cancels and
        // re-arms the whole plan the moment stored text changes.
        title: reminder.title,
        body: reminder.body,
        scheduledDate: fireAt,
        // Issue #136/#178/#183: the shared reminder presentation (channel,
        // lock-screen privacy) plus this reminder's action buttons, when it
        // carries any — see [reminderNotificationDetails].
        // LLA-028 (issue #623) on the actions: `showsUserInterface: true`
        // on every one — the default (`false`) selects Android's
        // background-delivery path, which requires
        // `onDidReceiveBackgroundNotificationResponse` (a top-level
        // entry-point function running in a separate isolate, no Activity
        // context) to be registered; it never is, since the gate-aware
        // executor these actions must route through
        // (`reminder_action_executor.dart`) needs a running, unlocked app.
        // Without this flag every tap was silently dropped whenever the app
        // was not already in the foreground.
        notificationDetails: NotificationDetails(
          android: reminderNotificationDetails(
            actions: hasActions
                ? const [
                    AndroidNotificationAction(
                        kReminderActionStarted, kReminderActionStartedLabel,
                        showsUserInterface: true),
                    AndroidNotificationAction(kReminderActionSpotting,
                        kReminderActionSpottingLabel,
                        showsUserInterface: true),
                    AndroidNotificationAction(kReminderActionNotYet,
                        kReminderActionNotYetLabel,
                        showsUserInterface: true),
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
