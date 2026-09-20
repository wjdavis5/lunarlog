/// Tests for reminder scheduling timezone and permission handling.
///
/// **Rule (issue #949): never pin a scheduled fire date to a wall-clock
/// literal.** `rescheduleAll`'s past-due comparison is driven by the
/// injectable [ReminderNowProvider], but `flutter_local_notifications`'s
/// `zonedSchedule` rejects a `scheduledDate` already in the real past
/// independently of that seam. A literal near "today" is therefore a time
/// bomb: on 2026-09-20 a `LocalDate(2026, 9, 20)` fire date stopped being
/// "future" mid-morning and six tests in this file began failing on every
/// PR. Derive every fire date from [schedulerTestDay] (a few days ahead of
/// the real clock) instead, and pin the scheduler's own clock with [nowAt]
/// wherever a test asserts past-due behavior.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/util/timezone.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/notifications/scheduling.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../support/fake_settings_store.dart';

/// Issue #949: the base date every scheduled-reminder test fires on — a few
/// days ahead of the real wall clock, so the mock platform never rejects the
/// slot as past-due (the plugin validates against the real clock
/// independently of the injected [ReminderNowProvider]; see this file's
/// library doc). Lazy `final`, so every test in a run shares one value.
final LocalDate schedulerTestDay = LocalDate.fromDateTime(
  DateTime.now().add(const Duration(days: 3)),
);

/// A [ReminderNowProvider] pinned to [hour]:[minute] on [day], in UTC — the
/// clock seam every scheduling test below compares its fire times against.
ReminderNowProvider nowAt(LocalDate day, int hour, [int minute = 0]) =>
    (_) => tz.TZDateTime.utc(day.year, day.month, day.day, hour, minute);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    tzdata.initializeTimeZones();
  });

  group('defaultLocalTimeZoneProvider', () {
    test('falls back safely to UTC on test environment without platform channel and records breadcrumb', () async {
      final log = BreadcrumbLog();
      final tzName = await defaultLocalTimeZoneProvider(breadcrumbLog: log);
      expect(tzName, 'UTC');
      expect(isValidIanaTimeZone(tzName), isTrue);
      expect(log.snapshot(), ['timezone: MissingPluginException']);
    });

    test('a failed refresh resets a previously configured zone to UTC',
        () async {
      tz.setLocalLocation(tz.getLocation('America/Chicago'));
      final scheduler = FlutterLocalNotificationsScheduler(
        localTimeZoneProvider: () => throw StateError('unavailable'),
      );

      await scheduler.initialize();

      expect(tz.local, same(tz.UTC));
    });
  });

  group('NoopReminderScheduler', () {
    test('initialize returns available and operations complete safely', () async {
      final scheduler = NoopReminderScheduler();
      expect(await scheduler.initialize(), NotificationAvailability.available);
      await scheduler.rescheduleAll([]);
      await scheduler.cancelAll();
    });
  });

  group('Timezone resolution integration with resolveCurrentTimeZone', () {
    test('setting local location updates domain resolveCurrentTimeZone', () async {
      final paris = tz.getLocation('Europe/Paris');
      tz.setLocalLocation(paris);
      expect(await resolveCurrentTimeZone(), 'Europe/Paris');

      final chicago = tz.getLocation('America/Chicago');
      tz.setLocalLocation(chicago);
      expect(await resolveCurrentTimeZone(), 'America/Chicago');
    });
  });

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  bool? permissionEnabled;
  Object? permissionError;
  // Issue #168: the answer `requestNotificationsPermission` (Android) and
  // `requestPermissions` (Darwin) hand back — independent of
  // `permissionEnabled`, which only backs the read-only probes.
  bool? requestPermissionGranted;
  // Issue #168 (#3): when set, `requestNotificationsPermission`/
  // `requestPermissions`/`openAppNotificationSettings` throw instead of
  // answering, so tests can assert the scheduler tolerates a platform-call
  // failure rather than letting it escape.
  Object? requestPermissionError;

  setUp(() {
    calls.clear();
    permissionEnabled = null;
    permissionError = null;
    requestPermissionGranted = null;
    requestPermissionError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      if (call.method == 'checkPermissions' ||
          call.method == 'areNotificationsEnabled') {
        if (permissionError != null) throw permissionError!;
        if (call.method == 'areNotificationsEnabled') {
          return permissionEnabled;
        }
        if (permissionEnabled != null) {
          return <String, dynamic>{
            'isEnabled': permissionEnabled!,
            'isAlertEnabled': permissionEnabled!,
            'isBadgeEnabled': permissionEnabled!,
            'isSoundEnabled': permissionEnabled!,
            'isProvisionalEnabled': false,
            'isCriticalEnabled': false,
            'isProvidesAppNotificationSettingsEnabled': false,
            'isCarPlayEnabled': false,
          };
        }
        return null;
      }
      if (call.method == 'requestNotificationsPermission' ||
          call.method == 'requestPermissions') {
        if (requestPermissionError != null) throw requestPermissionError!;
        return requestPermissionGranted;
      }
      if (call.method == 'openAppNotificationSettings') {
        if (requestPermissionError != null) throw requestPermissionError!;
        return true;
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return null;
      }
      // The Android plugin's own `initialize()` declares a non-nullable
      // `Future<bool>` return, unlike every other method above.
      if (call.method == 'initialize') {
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  FlutterLocalNotificationsScheduler schedulerFor(
    TargetPlatform platform, {
    SettingsStore? settingsStore,
    LocalTimeZoneProvider? localTimeZoneProvider,
    tz.Location Function()? locationProvider,
    ReminderNowProvider? nowProvider,
    BreadcrumbLog? breadcrumbLog,
  }) {
    debugDefaultTargetPlatformOverride = platform;
    switch (platform) {
      case TargetPlatform.android:
        AndroidFlutterLocalNotificationsPlugin.registerWith();
      case TargetPlatform.iOS:
        IOSFlutterLocalNotificationsPlugin.registerWith();
      case TargetPlatform.macOS:
        MacOSFlutterLocalNotificationsPlugin.registerWith();
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        break;
    }
    return FlutterLocalNotificationsScheduler(
      settingsStore: settingsStore,
      localTimeZoneProvider: localTimeZoneProvider,
      locationProvider: locationProvider,
      nowProvider: nowProvider,
      breadcrumbLog: breadcrumbLog,
    );
  }

  group('FlutterLocalNotificationsScheduler permission probing (Issue #43)', () {
    test('reports denied when iOS permissions are disabled', () async {
      permissionEnabled = false;
      final scheduler = schedulerFor(TargetPlatform.iOS);
      final availability = await scheduler.initialize();

      expect(availability, NotificationAvailability.denied);
      expect(calls.any((c) => c.method == 'checkPermissions'), isTrue);
    });

    test('reports available when iOS permissions are enabled', () async {
      permissionEnabled = true;
      final scheduler = schedulerFor(TargetPlatform.iOS);
      final availability = await scheduler.checkAvailability();

      expect(availability, NotificationAvailability.available);
      expect(calls.any((c) => c.method == 'checkPermissions'), isTrue);
    });

    test('reports Android permission state', () async {
      permissionEnabled = false;
      final scheduler = schedulerFor(TargetPlatform.android);
      final availability = await scheduler.checkAvailability();

      expect(availability, NotificationAvailability.denied);
      expect(calls.any((c) => c.method == 'areNotificationsEnabled'), isTrue);
    });

    test('reports macOS permission state', () async {
      permissionEnabled = false;
      final scheduler = schedulerFor(TargetPlatform.macOS);
      final availability = await scheduler.checkAvailability();

      expect(availability, NotificationAvailability.denied);
      expect(calls.any((c) => c.method == 'checkPermissions'), isTrue);
    });

    test('defaults to available when no platform implementation resolves',
        () async {
      final scheduler = schedulerFor(TargetPlatform.linux);
      final availability = await scheduler.checkAvailability();

      expect(availability, NotificationAvailability.available);
      expect(calls, isEmpty);
    });

    test('defaults to available when the permission probe throws', () async {
      permissionError = PlatformException(code: 'unavailable');
      final scheduler = schedulerFor(TargetPlatform.iOS);
      final availability = await scheduler.checkAvailability();

      expect(availability, NotificationAvailability.available);
    });
  });

  group('Darwin init-time permission (issue #863)', () {
    test('initialize() never asks for the iOS permission -- the system '
        'prompt must not fire at first launch', () async {
      permissionEnabled = false;
      final scheduler = schedulerFor(TargetPlatform.iOS);

      await scheduler.initialize();

      final initCall = calls.singleWhere((c) => c.method == 'initialize');
      expect(
        (initCall.arguments as Map)['requestAlertPermission'],
        isFalse,
        reason: 'requestAlertPermission: true is exactly what spent '
            'Darwin\'s one-shot dialog over the first-launch black screen',
      );
      expect(
        calls.any((c) => c.method == 'requestPermissions'),
        isFalse,
        reason: 'the prompt belongs to the in-product "Turn on reminders" '
            'moment, not database open',
      );
    });

    test('initialize() reports the current (undetermined) Darwin state '
        'without asking', () async {
      permissionEnabled = false;
      final scheduler = schedulerFor(TargetPlatform.iOS);

      final availability = await scheduler.initialize();

      expect(availability, NotificationAvailability.denied);
      expect(calls.any((c) => c.method == 'checkPermissions'), isTrue);
      expect(calls.any((c) => c.method == 'requestPermissions'), isFalse);
    });
  });

  group('Android POST_NOTIFICATIONS request (issue #168)', () {
    test('initialize() requests the Android runtime permission before the '
        'first availability check', () async {
      requestPermissionGranted = true;
      permissionEnabled = true;
      final scheduler = schedulerFor(TargetPlatform.android);

      final availability = await scheduler.initialize();

      expect(
        calls.any((c) => c.method == 'requestNotificationsPermission'),
        isTrue,
        reason: 'API 33+ requires an explicit runtime request even though '
            'the manifest already declares POST_NOTIFICATIONS',
      );
      expect(availability, NotificationAvailability.available);
    });

    test('initialize() never requests the Android permission on iOS -- '
        'Darwin behavior is unchanged', () async {
      requestPermissionGranted = true;
      permissionEnabled = true;
      final scheduler = schedulerFor(TargetPlatform.iOS);

      await scheduler.initialize();

      expect(
        calls.any((c) => c.method == 'requestNotificationsPermission'),
        isFalse,
      );
    });

    test(
        'initialize() requests the permission regardless of push/FCM '
        'configuration -- the scheduler has no such gate at all', () async {
      // There is no AppConfig.hasPush-style parameter anywhere on
      // FlutterLocalNotificationsScheduler or its initialize(); this test
      // documents that absence rather than exercising a flag.
      requestPermissionGranted = false;
      permissionEnabled = false;
      final scheduler = schedulerFor(TargetPlatform.android);

      await scheduler.initialize();

      expect(
        calls.any((c) => c.method == 'requestNotificationsPermission'),
        isTrue,
      );
    });

    test(
        'requestPermission() re-requests after one denial, then opens '
        'settings once denied twice', () async {
      requestPermissionGranted = false;
      permissionEnabled = false;
      final scheduler = schedulerFor(TargetPlatform.android);
      await scheduler.initialize(); // first ask, denied -> attempts = 1
      calls.clear();

      await scheduler.requestPermission(); // second ask, denied -> attempts = 2
      expect(
        calls.any((c) => c.method == 'requestNotificationsPermission'),
        isTrue,
        reason: 'still eligible after only one prior denial',
      );
      expect(
        calls.any((c) => c.method == 'openAppNotificationSettings'),
        isFalse,
      );
      calls.clear();

      await scheduler.requestPermission(); // third ask: permanently denied
      expect(
        calls.any((c) => c.method == 'openAppNotificationSettings'),
        isTrue,
        reason: 'two refusals is Android\'s own permanently-denied line',
      );
      expect(
        calls.any((c) => c.method == 'requestNotificationsPermission'),
        isFalse,
        reason: 'the dialog would silently no-op; settings is the only '
            'path back to "on"',
      );
    });

    test(
        'requestPermission() reports available once granted and resets '
        'the denial count', () async {
      requestPermissionGranted = false;
      permissionEnabled = false;
      final scheduler = schedulerFor(TargetPlatform.android);
      await scheduler.initialize(); // denied -> attempts = 1

      requestPermissionGranted = true;
      permissionEnabled = true;
      final availability = await scheduler.requestPermission();
      expect(availability, NotificationAvailability.available);

      // A later denial goes through one more full request cycle rather
      // than jumping straight to settings, proving the grant reset the
      // count.
      requestPermissionGranted = false;
      permissionEnabled = false;
      calls.clear();
      await scheduler.requestPermission();
      expect(
        calls.any((c) => c.method == 'requestNotificationsPermission'),
        isTrue,
      );
      expect(
        calls.any((c) => c.method == 'openAppNotificationSettings'),
        isFalse,
      );
    });

    test('requestPermission() re-requests the Darwin permission on iOS',
        () async {
      requestPermissionGranted = true;
      permissionEnabled = true;
      final scheduler = schedulerFor(TargetPlatform.iOS);
      await scheduler.initialize();
      calls.clear();

      final availability = await scheduler.requestPermission();

      expect(calls.any((c) => c.method == 'requestPermissions'), isTrue);
      expect(availability, NotificationAvailability.available);
    });

    test(
        'requestPermission() asks at the in-product moment on the first '
        'tap, then opens Darwin notification settings once already asked '
        'and still denied', () async {
      // Issue #863: with the init-time request removed, the first tap is
      // what shows the system prompt. Darwin's dialog is one-shot, so a
      // later still-denied tap must route to settings instead of silently
      // re-asking into a no-op.
      final store = FakeSettingsStore();
      permissionEnabled = false;
      final scheduler = schedulerFor(TargetPlatform.iOS, settingsStore: store);
      await scheduler.initialize();
      calls.clear();

      await scheduler.requestPermission();

      expect(
        calls.any((c) => c.method == 'requestPermissions'),
        isTrue,
        reason: 'the in-product "Turn on reminders" tap is the prompt',
      );
      expect(
        calls.any((c) => c.method == 'openAppNotificationSettings'),
        isFalse,
        reason: 'a never-asked permission must not jump straight to '
            'Settings',
      );
      expect(
        await store.get(SettingsKeys.darwinNotificationPermissionRequested),
        'true',
        reason: 'the ask is persisted so a later launch knows the dialog '
            'is spent',
      );
      calls.clear();

      await scheduler.requestPermission();

      expect(
        calls.any((c) => c.method == 'openAppNotificationSettings'),
        isTrue,
        reason: 'Darwin only ever shows its permission dialog once per '
            'install; requesting again once already denied would silently '
            'no-op forever',
      );
      expect(
        calls.any((c) => c.method == 'requestPermissions'),
        isFalse,
      );
    });
  });

  group('Persisted Android denial count (issue #168)', () {
    test('initialize() persists the post-request count to the settings '
        'store', () async {
      final store = FakeSettingsStore();
      requestPermissionGranted = false;
      permissionEnabled = false;
      final scheduler =
          schedulerFor(TargetPlatform.android, settingsStore: store);

      await scheduler.initialize();

      expect(
        await store.get(SettingsKeys.androidNotificationDeniedAttempts),
        '1',
      );
    });

    test(
        'a fresh scheduler instance over the same settings store remembers '
        'two prior denials across a restart, so the very next action opens '
        'settings instead of silently re-asking', () async {
      final store = FakeSettingsStore();
      requestPermissionGranted = false;
      permissionEnabled = false;

      final beforeRestart =
          schedulerFor(TargetPlatform.android, settingsStore: store);
      await beforeRestart.initialize(); // denied -> persisted count = 1
      await beforeRestart.requestPermission(); // denied -> persisted count = 2
      expect(
        await store.get(SettingsKeys.androidNotificationDeniedAttempts),
        '2',
      );

      // Simulates a process restart: a brand-new scheduler instance with
      // no in-memory history, but the same underlying (device-local)
      // settings store -- and the same automatic `initialize()` call
      // app.dart's coordinator always makes on startup, before any tap
      // can happen.
      final afterRestart =
          schedulerFor(TargetPlatform.android, settingsStore: store);
      await afterRestart.initialize();
      calls.clear();

      await afterRestart.requestPermission();

      expect(
        calls.any((c) => c.method == 'openAppNotificationSettings'),
        isTrue,
        reason: 'the persisted count already reflected two prior refusals '
            'before this fresh instance ever ran, so this tap goes '
            'straight to settings',
      );
      expect(
        calls.any((c) => c.method == 'requestNotificationsPermission'),
        isFalse,
        reason: 'the pre-fix bug: an in-memory-only count would restart at '
            'zero here and this tap would re-ask into silence instead',
      );
    });

    test(
        'a null result from the Android request is treated as unknown, not '
        'a denial -- the persisted count is unchanged', () async {
      final store = FakeSettingsStore(
          {SettingsKeys.androidNotificationDeniedAttempts: '1'});
      requestPermissionGranted = null;
      permissionEnabled = false;
      final scheduler =
          schedulerFor(TargetPlatform.android, settingsStore: store);

      await scheduler.initialize();

      expect(
        await store.get(SettingsKeys.androidNotificationDeniedAttempts),
        '1',
        reason: 'an unresolved (null) request result must not ratchet the '
            'count toward openSettings',
      );
    });
  });

  group('Platform-call failures are tolerated (issue #168 #3)', () {
    test('initialize() tolerates a throwing Android permission request',
        () async {
      requestPermissionError = PlatformException(code: 'in_progress');
      permissionEnabled = true;
      final scheduler = schedulerFor(TargetPlatform.android);

      final availability = await scheduler.initialize();

      expect(availability, NotificationAvailability.available);
    });

    test('requestPermission() tolerates a throwing Android permission '
        'request, still reporting through checkAvailability()', () async {
      requestPermissionGranted = false;
      permissionEnabled = false;
      final scheduler = schedulerFor(TargetPlatform.android);
      await scheduler.initialize(); // denied -> attempts = 1

      requestPermissionError = PlatformException(code: 'in_progress');
      final availability = await scheduler.requestPermission();

      expect(availability, NotificationAvailability.denied);
    });

    test('requestPermission() tolerates a throwing Darwin requestPermissions '
        'call', () async {
      // Not (yet) denied, so `requestPermission()` takes the re-request
      // branch (not the settings-opening one) and hits the throw there.
      permissionEnabled = true;
      final scheduler = schedulerFor(TargetPlatform.iOS);
      await scheduler.initialize();

      requestPermissionError = PlatformException(code: 'in_progress');
      final availability = await scheduler.requestPermission();

      expect(availability, NotificationAvailability.available);
    });

    test('requestPermission() tolerates a throwing Darwin '
        'openAppNotificationSettings call', () async {
      // Issue #863: the settings branch is reached only once a prior ask
      // has been recorded -- seed that state so this exercises the
      // openAppNotificationSettings throw, not the requestPermissions one.
      final store = FakeSettingsStore({
        SettingsKeys.darwinNotificationPermissionRequested: 'true',
      });
      permissionEnabled = false;
      final scheduler = schedulerFor(TargetPlatform.iOS, settingsStore: store);
      await scheduler.initialize();

      requestPermissionError = PlatformException(code: 'boom');
      final availability = await scheduler.requestPermission();

      expect(availability, NotificationAvailability.denied);
    });
  });

  group('Reminder action delivery (Issue #623, LLA-028)', () {
    test(
        'Darwin reminder actions carry the foreground option so a tap '
        'launches the app instead of requiring an unregistered background '
        'handler', () async {
      final scheduler = schedulerFor(TargetPlatform.iOS);

      await scheduler.initialize();

      final initCall = calls.singleWhere((c) => c.method == 'initialize');
      final categories =
          (initCall.arguments as Map)['notificationCategories'] as List;
      final category = categories.single as Map;
      expect(category['identifier'], kReminderCategoryId);
      final actions = category['actions'] as List;
      expect(actions, hasLength(3));
      for (final action in actions) {
        final options = (action as Map)['options'] as List;
        expect(
          options,
          contains(DarwinNotificationActionOption.foreground.value),
          reason: '${action['identifier']} must open the app in the '
              'foreground -- there is no background callback registered '
              'to handle it otherwise',
        );
      }
    });

    test(
        'Android reminder actions request the foreground UI instead of '
        'the unconfigured background-delivery default', () async {
      final scheduler = schedulerFor(TargetPlatform.android);
      await scheduler.initialize();
      calls.clear();

      await scheduler.rescheduleAll([
        PlannedReminder(
          profileId: 'profile-1',
          fireOn: schedulerTestDay,
          kind: ReminderKind.upcoming,
        ),
      ]);

      final scheduleCall = calls.singleWhere((c) => c.method == 'zonedSchedule');
      final platformSpecifics =
          (scheduleCall.arguments as Map)['platformSpecifics'] as Map;
      final actions = platformSpecifics['actions'] as List;
      expect(actions, hasLength(3));
      for (final action in actions) {
        expect(
          (action as Map)['showsUserInterface'],
          isTrue,
          reason: 'the default (false) selects a background delivery path '
              'that needs onDidReceiveBackgroundNotificationResponse, '
              'which is never registered',
        );
      }
    });

    test(
        'a reminder kind with no actions (Issue #178) schedules with no '
        'action list on Android', () async {
      final scheduler = schedulerFor(TargetPlatform.android);
      await scheduler.initialize();
      calls.clear();

      await scheduler.rescheduleAll([
        PlannedReminder(
          profileId: 'profile-1',
          fireOn: schedulerTestDay,
          kind: ReminderKind.log,
        ),
      ]);

      final scheduleCall = calls.singleWhere((c) => c.method == 'zonedSchedule');
      final platformSpecifics =
          (scheduleCall.arguments as Map)['platformSpecifics'] as Map;
      expect(platformSpecifics['actions'], isNull);
    });
  });

  group('Custom notification text (Issue #184)', () {
    test(
        'the built notification carries the resolved custom '
        'title and body verbatim', () async {
      final scheduler = schedulerFor(TargetPlatform.android);
      await scheduler.initialize();
      calls.clear();

      await scheduler.rescheduleAll([
        PlannedReminder(
          profileId: 'profile-1',
          fireOn: schedulerTestDay,
          kind: ReminderKind.upcoming,
          title: 'Tea time',
          body: 'Bring the blue bottle.',
        ),
      ]);

      final scheduleCall = calls.singleWhere((c) => c.method == 'zonedSchedule');
      final args = scheduleCall.arguments as Map;
      expect(args['title'], 'Tea time',
          reason: 'the custom title reaches the OS exactly as configured');
      expect(args['body'], 'Bring the blue bottle.');
      expect(args['title'], isNot(contains('profile-1')));
      expect(args['body'], isNot(contains('2026')));
    });

    test('a reminder with no custom text still carries the generic copy',
        () async {
      final scheduler = schedulerFor(TargetPlatform.android);
      await scheduler.initialize();
      calls.clear();

      await scheduler.rescheduleAll([
        PlannedReminder(
          profileId: 'profile-1',
          fireOn: schedulerTestDay,
          kind: ReminderKind.log,
        ),
      ]);

      final scheduleCall = calls.singleWhere((c) => c.method == 'zonedSchedule');
      final args = scheduleCall.arguments as Map;
      expect(args['title'], kReminderTitle);
      expect(args['body'], kReminderBody);
    });
  });

  group('past-due skip and per-reminder isolation (issue #171)', () {
    PlannedReminder lateOn(
      LocalDate date,
      int minuteOfDay, {
      String profile = 'profile-1',
    }) =>
        PlannedReminder(
          profileId: profile,
          fireOn: date,
          kind: ReminderKind.late,
          timeOfDayMinutes: minuteOfDay,
        );

    Set<Object?> zonedScheduleIds() => calls
        .where((c) => c.method == 'zonedSchedule')
        .map((c) => (c.arguments as Map)['id'])
        .toSet();

    test(
        'a replan after the fire hour skips the past-dated slot and still '
        'arms every later reminder', () async {
      final log = BreadcrumbLog();
      final day = schedulerTestDay;
      final scheduler = schedulerFor(
        TargetPlatform.android,
        localTimeZoneProvider: () async => 'UTC',
        locationProvider: () => tz.getLocation('UTC'),
        // 12:00 UTC — after the day's 09:00 slot, before its 15:00 one.
        nowProvider: nowAt(day, 12),
        breadcrumbLog: log,
      );
      await scheduler.initialize();
      calls.clear();

      final past = lateOn(day, 9 * 60);
      final thisAfternoon = lateOn(day, 15 * 60);
      final tomorrow = lateOn(day.addDays(1), 9 * 60);

      await scheduler.rescheduleAll([past, thisAfternoon, tomorrow]);

      final ids = zonedScheduleIds();
      expect(ids, isNot(contains(past.id)),
          reason: 'a past-dated trigger is never delivered and must never be '
              'handed to zonedSchedule');
      expect(ids, contains(thisAfternoon.id),
          reason: 'a later slot on the same day still arms');
      expect(ids, contains(tomorrow.id),
          reason: 'the next occurrence of the recurring window still arms');
      expect(log.snapshot(), contains('reminders: skipped past-due slot'));
    });

    test('a replan before the fire hour skips nothing', () async {
      final log = BreadcrumbLog();
      final day = schedulerTestDay;
      final scheduler = schedulerFor(
        TargetPlatform.android,
        localTimeZoneProvider: () async => 'UTC',
        locationProvider: () => tz.getLocation('UTC'),
        // 08:00 UTC — before the day's 09:00 slot.
        nowProvider: nowAt(day, 8),
        breadcrumbLog: log,
      );
      await scheduler.initialize();
      calls.clear();

      final today = lateOn(day, 9 * 60);
      final tomorrow = lateOn(day.addDays(1), 9 * 60);

      await scheduler.rescheduleAll([today, tomorrow]);

      expect(zonedScheduleIds(), {today.id, tomorrow.id});
      expect(log.snapshot(), isEmpty);
    });

    test(
        'a throwing zonedSchedule for one reminder leaves every other '
        'reminder scheduled and is recorded through the seam', () async {
      final log = BreadcrumbLog();
      final day = schedulerTestDay;
      final scheduler = schedulerFor(
        TargetPlatform.android,
        localTimeZoneProvider: () async => 'UTC',
        locationProvider: () => tz.getLocation('UTC'),
        // 00:00 UTC — every one of the day's slots is still ahead.
        nowProvider: nowAt(day, 0),
        breadcrumbLog: log,
      );
      await scheduler.initialize();
      calls.clear();

      final first = lateOn(day, 9 * 60, profile: 'p1');
      final failing = lateOn(day, 10 * 60, profile: 'p2');
      final third = lateOn(day, 11 * 60, profile: 'p3');

      // Replace the default handler with one that rejects exactly the middle
      // reminder's call — the OS notification cap / invalid-date failure
      // class that used to abort the whole batch.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call);
        if (call.method == 'zonedSchedule' &&
            (call.arguments as Map)['id'] == failing.id) {
          throw PlatformException(code: 'schedule_failed');
        }
        return null;
      });

      await scheduler.rescheduleAll([first, failing, third]);

      final ids = zonedScheduleIds();
      expect(ids, contains(first.id),
          reason: 'the call before the failure is unaffected');
      expect(ids, contains(third.id),
          reason: 'one failure must never abort the remaining reminders');
      expect(log.snapshot(), contains('reminders: PlatformException'),
          reason: 'the failure is reported through the breadcrumb seam, not '
              'swallowed');
    });
  });
}
