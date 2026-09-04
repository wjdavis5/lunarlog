/// Tests for reminder scheduling wall-clock time zone resolution (Issue #38).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/util/timezone.dart';
import 'package:lunarlog/ui/overview/notification_availability.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
  });

  // The zone-resolution tests below mutate the process-global tz.local;
  // restore UTC afterwards so file order cannot leak zones into other tests.
  tearDown(() {
    tz.setLocalLocation(tz.getLocation('UTC'));
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

  group('resolveLocalZone wiring (review #4)', () {
    test('throwing provider keeps the previous location without throwing',
        () async {
      tz.setLocalLocation(tz.getLocation('America/New_York'));
      final scheduler = FlutterLocalNotificationsScheduler(
        localTimeZoneProvider: () =>
            Future<String>.error(StateError('no channel')),
      );
      await scheduler.resolveLocalZone();
      expect(tz.local.name, 'America/New_York');
    });

    test('unknown zone falls back to UTC without throwing', () async {
      tz.setLocalLocation(tz.getLocation('America/New_York'));
      final scheduler = FlutterLocalNotificationsScheduler(
        localTimeZoneProvider: () async => 'Not/AZone',
      );
      await scheduler.resolveLocalZone();
      expect(tz.local.name, 'UTC');
    });

    test('valid zone installs the location', () async {
      tz.setLocalLocation(tz.getLocation('UTC'));
      final scheduler = FlutterLocalNotificationsScheduler(
        localTimeZoneProvider: () async => 'Asia/Tokyo',
      );
      await scheduler.resolveLocalZone();
      expect(tz.local.name, 'Asia/Tokyo');
    });
  });
}
