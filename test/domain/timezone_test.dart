/// Unit tests for canonical IANA timezone resolution (finding #23 in #37, issue #46).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/util/timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUp(() {
    tzdata.initializeTimeZones();
  });

  group('resolveCurrentTimeZone', () {
    test('returns canonical IANA timezone identifier', () async {
      final initial = await resolveCurrentTimeZone();
      expect(initial, isNotEmpty);
      expect(isValidIanaTimeZone(initial), isTrue);
    });

    test('reflects location configured via tz.setLocalLocation', () async {
      final ny = tz.getLocation('America/New_York');
      tz.setLocalLocation(ny);
      expect(await resolveCurrentTimeZone(), 'America/New_York');

      final paris = tz.getLocation('Europe/Paris');
      tz.setLocalLocation(paris);
      expect(await resolveCurrentTimeZone(), 'Europe/Paris');

      final tokyo = tz.getLocation('Asia/Tokyo');
      tz.setLocalLocation(tokyo);
      expect(await resolveCurrentTimeZone(), 'Asia/Tokyo');
    });

    test('queries platform timezone provider directly even without scheduler',
        () async {
      // Acceptance criterion 2: resolveCurrentTimeZone() returns OS-reported
      // current zone even when scheduler has never run.
      final zone = await resolveCurrentTimeZone(
        platformTimeZoneProvider: () async => 'America/Chicago',
      );
      expect(zone, 'America/Chicago');
      expect(tz.local.name, 'America/Chicago');
    });

    test('falls back to tz.local.name when platform provider throws', () async {
      final tokyo = tz.getLocation('Asia/Tokyo');
      tz.setLocalLocation(tokyo);
      final zone = await resolveCurrentTimeZone(
        platformTimeZoneProvider: () async =>
            throw Exception('channel failed'),
      );
      expect(zone, 'Asia/Tokyo');
    });

    test(
        'falls back to tz.local.name when platform provider returns invalid timezone',
        () async {
      final tokyo = tz.getLocation('Asia/Tokyo');
      tz.setLocalLocation(tokyo);
      final zone = await resolveCurrentTimeZone(
        platformTimeZoneProvider: () async => 'Invalid/Zone',
      );
      expect(zone, 'Asia/Tokyo');
    });
  });

  group('resolveCurrentTimeZoneSync', () {
    test('returns tz.local.name synchronously', () {
      final paris = tz.getLocation('Europe/Paris');
      tz.setLocalLocation(paris);
      expect(resolveCurrentTimeZoneSync(), 'Europe/Paris');
    });
  });

  group('isValidIanaTimeZone', () {
    test('accepts valid canonical IANA timezone identifiers', () {
      expect(isValidIanaTimeZone('America/New_York'), isTrue);
      expect(isValidIanaTimeZone('America/Chicago'), isTrue);
      expect(isValidIanaTimeZone('Europe/London'), isTrue);
      expect(isValidIanaTimeZone('Asia/Tokyo'), isTrue);
      expect(isValidIanaTimeZone('Etc/UTC'), isTrue);
      expect(isValidIanaTimeZone('UTC'), isTrue);
    });

    test('rejects platform abbreviations and invalid names', () {
      expect(isValidIanaTimeZone('EDT'), isFalse);
      expect(isValidIanaTimeZone('CDT'), isFalse);
      expect(isValidIanaTimeZone('PDT'), isFalse);
      expect(isValidIanaTimeZone('GMT+10'), isFalse);
      expect(isValidIanaTimeZone(''), isFalse);
      expect(isValidIanaTimeZone('Not/A_Real_Timezone'), isFalse);
    });
  });

  // Issue #458: the fixed-offset designator a Health Connect import stores
  // for a record that carries only a raw zoneOffset.
  group('fixedOffsetZoneName / isFixedOffsetZoneName', () {
    test('renders zero, whole-hour, half-hour, and negative offsets', () {
      expect(fixedOffsetZoneName(Duration.zero), 'UTC');
      expect(fixedOffsetZoneName(const Duration(hours: 5)), 'UTC+05:00');
      expect(
        fixedOffsetZoneName(const Duration(hours: 5, minutes: 30)),
        'UTC+05:30',
      );
      expect(
        fixedOffsetZoneName(const Duration(hours: -4)),
        'UTC-04:00',
      );
      expect(
        fixedOffsetZoneName(const Duration(minutes: -210)),
        'UTC-03:30',
      );
    });

    test('accepts exactly the forms it renders, and rejects other strings',
        () {
      for (final value in ['UTC', 'UTC+05:30', 'UTC-04:00', 'UTC+14:00']) {
        expect(isFixedOffsetZoneName(value), isTrue, reason: value);
      }
      for (final value in [
        'UTC+5:30',
        'UTC+05:60',
        'UTC+19:00',
        'GMT+05:30',
        'America/New_York',
        '',
      ]) {
        expect(isFixedOffsetZoneName(value), isFalse, reason: value);
      }
    });
  });
}
