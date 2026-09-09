/// Tests for reminder scheduling timezone and permission handling.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/util/timezone.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    tzdata.initializeTimeZones();
  });

  group('calculateReminderFireAt', () {
    final date = LocalDate(2026, 8, 30);

    test('pins 9:00 AM local civil time across various time zones', () {
      final ny = tz.getLocation('America/New_York');
      final fireNy = calculateReminderFireAt(fireOn: date, location: ny);
      expect(fireNy.year, 2026);
      expect(fireNy.month, 8);
      expect(fireNy.day, 30);
      expect(fireNy.hour, 9);
      expect(fireNy.minute, 0);
      // New York is EDT (UTC-4) in August -> 09:00 EDT == 13:00 UTC
      expect(fireNy.toUtc(), DateTime.utc(2026, 8, 30, 13, 0));

      final la = tz.getLocation('America/Los_Angeles');
      final fireLa = calculateReminderFireAt(fireOn: date, location: la);
      expect(fireLa.hour, 9);
      // Los Angeles is PDT (UTC-7) in August -> 09:00 PDT == 16:00 UTC
      expect(fireLa.toUtc(), DateTime.utc(2026, 8, 30, 16, 0));

      final tokyo = tz.getLocation('Asia/Tokyo');
      final fireTokyo = calculateReminderFireAt(fireOn: date, location: tokyo);
      expect(fireTokyo.hour, 9);
      // Tokyo is JST (UTC+9) year-round -> 09:00 JST == 00:00 UTC
      expect(fireTokyo.toUtc(), DateTime.utc(2026, 8, 30, 0, 0));

      final sydney = tz.getLocation('Australia/Sydney');
      final fireSydney = calculateReminderFireAt(fireOn: date, location: sydney);
      expect(fireSydney.hour, 9);
      // Sydney is AEST (UTC+10) in August -> 09:00 AEST == 23:00 UTC previous day
      expect(fireSydney.toUtc(), DateTime.utc(2026, 8, 29, 23, 0));
    });

    test('supports custom reminder hours', () {
      final utc = tz.getLocation('UTC');
      final fire = calculateReminderFireAt(fireOn: date, location: utc, hour: 8);
      expect(fire.hour, 8);
      expect(fire.toUtc(), DateTime.utc(2026, 8, 30, 8, 0));
    });
  });

  group('defaultLocalTimeZoneProvider', () {
    test('falls back safely to UTC on test environment without platform channel', () async {
      final tzName = await defaultLocalTimeZoneProvider();
      expect(tzName, isNotEmpty);
      expect(isValidIanaTimeZone(tzName), isTrue);
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
    test('setting local location updates domain resolveCurrentTimeZone', () {
      final paris = tz.getLocation('Europe/Paris');
      tz.setLocalLocation(paris);
      expect(resolveCurrentTimeZone(), 'Europe/Paris');

      final chicago = tz.getLocation('America/Chicago');
      tz.setLocalLocation(chicago);
      expect(resolveCurrentTimeZone(), 'America/Chicago');
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

  setUp(() {
    calls.clear();
    permissionEnabled = null;
    permissionError = null;
    requestPermissionGranted = null;
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
        return requestPermissionGranted;
      }
      if (call.method == 'openAppNotificationSettings') {
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

  FlutterLocalNotificationsScheduler schedulerFor(TargetPlatform platform) {
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
    return FlutterLocalNotificationsScheduler();
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
  });
}
