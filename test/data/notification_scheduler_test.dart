/// Tests for reminder scheduling timezone and permission handling.
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
    return FlutterLocalNotificationsScheduler(settingsStore: settingsStore);
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
        'requestPermission() opens Darwin notification settings once '
        'already denied, instead of re-requesting into silence', () async {
      // #4: `checkPermissions` reports the current (already-denied) state
      // before this call ever tries to ask again.
      permissionEnabled = false;
      final scheduler = schedulerFor(TargetPlatform.iOS);
      await scheduler.initialize();
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
      permissionEnabled = false;
      final scheduler = schedulerFor(TargetPlatform.iOS);
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
          fireOn: LocalDate(2026, 9, 20),
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
          fireOn: LocalDate(2026, 9, 20),
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
          fireOn: LocalDate(2026, 9, 20),
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
          fireOn: LocalDate(2026, 9, 20),
          kind: ReminderKind.log,
        ),
      ]);

      final scheduleCall = calls.singleWhere((c) => c.method == 'zonedSchedule');
      final args = scheduleCall.arguments as Map;
      expect(args['title'], kReminderTitle);
      expect(args['body'], kReminderBody);
    });
  });
}
