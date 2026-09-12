/// Unit tests for the pure `lunarlog/health` channel codec (Issue #173):
/// the guard-args and day-args encoders, and the result-string decoder —
/// the wire protocol's single definition, so these tests ARE the protocol
/// contract the Swift (AppDelegate.swift) and Kotlin
/// (HealthConnectAdapter.kt) halves mirror.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_channel_codec.dart';
import 'package:lunarlog/domain/health/day_boundary.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';

Profile _profile({
  String id = 'p1',
  bool isMinor = false,
  int? birthYear = 1990,
  DateTime? transferredAt,
}) =>
    Profile(
      id: id,
      displayName: 'Test',
      isMinor: isMinor,
      birthYear: birthYear,
      transferredAt: transferredAt,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('encodeGuardArgs', () {
    test('carries every #153 guard input', () {
      final transferredAt = DateTime.utc(2026, 1, 15, 9, 30);
      final args = encodeGuardArgs(
        HealthGuardFacts(
          profile: _profile(transferredAt: transferredAt),
          signedInUserId: 'u1',
          ownerUserId: 'u1',
        ),
        minorBindingAllowed: false,
      );
      expect(args, {
        'profileId': 'p1',
        'signedInUserId': 'u1',
        'ownerUserId': 'u1',
        'isMinor': false,
        'birthYear': 1990,
        'transferredAtMs': transferredAt.millisecondsSinceEpoch,
        'minorBindingAllowed': false,
      });
    });

    test('null session/ownership/birth/transfer cross as nulls', () {
      final args = encodeGuardArgs(
        HealthGuardFacts(
          profile: _profile(birthYear: null),
          signedInUserId: null,
          ownerUserId: null,
        ),
        minorBindingAllowed: true,
      );
      expect(args['signedInUserId'], isNull);
      expect(args['ownerUserId'], isNull);
      expect(args['birthYear'], isNull);
      expect(args['transferredAtMs'], isNull);
      expect(args['isMinor'], isFalse);
      expect(args['minorBindingAllowed'], isTrue);
    });
  });

  group('encodeDayArgs', () {
    test('whole envelope for a fixed date and zone', () {
      // 2026-08-30 in America/New_York (EDT, UTC-4):
      // midnight start = 04:00Z; inclusive end = next 04:00Z - 1s;
      // exclusive end = next 04:00Z; offsets -4h at both ends (no DST
      // transition that day).
      final args = encodeDayArgs(LocalDate(2026, 8, 30), 'America/New_York');
      final startMs =
          DateTime.utc(2026, 8, 30, 4).millisecondsSinceEpoch;
      expect(args['startMs'], startMs);
      expect(args['instantMs'], startMs); // same instant, HC point form
      expect(args['endMs'], startMs + 24 * 3600 * 1000 - 1000);
      expect(args['endExclusiveMs'], startMs + 24 * 3600 * 1000);
      expect(args['zoneOffsetMs'], -4 * 3600 * 1000);
      expect(args['endZoneOffsetMs'], -4 * 3600 * 1000);
    });

    test('a fall-back day: the exclusive end carries a different offset '
        'than midnight (#180 contract note)', () {
      // 2026-11-01 America/New_York: DST ends at 02:00 EDT. Midnight of
      // Nov 1 is EDT (-4h); midnight of Nov 2 (the exclusive end) is EST
      // (-5h) — endZoneOffset must differ from zoneOffset, and the day is
      // 25 hours long.
      final date = LocalDate(2026, 11, 1);
      final args = encodeDayArgs(date, 'America/New_York');
      expect(args['zoneOffsetMs'], -4 * 3600 * 1000);
      expect(args['endZoneOffsetMs'], -5 * 3600 * 1000);
      expect(
        (args['endExclusiveMs'] as int) - (args['startMs'] as int),
        25 * 3600 * 1000,
      );
      expect(
        (args['endMs'] as int) - (args['startMs'] as int),
        25 * 3600 * 1000 - 1000,
      );
    });

    test('agrees with day_boundary.dart\'s own functions', () {
      final date = LocalDate(2026, 3, 8); // US spring-forward
      final args = encodeDayArgs(date, 'America/New_York');
      final interval = localDayInterval(date, 'America/New_York');
      expect(args['startMs'], interval.start.millisecondsSinceEpoch);
      expect(args['endMs'], interval.end.millisecondsSinceEpoch);
      expect(
        args['endExclusiveMs'],
        localDayEndExclusive(date, 'America/New_York').millisecondsSinceEpoch,
      );
      expect(args['zoneOffsetMs'], zoneOffsetFor(date, 'America/New_York').inMilliseconds);
      expect(
        args['endZoneOffsetMs'],
        endZoneOffsetFor(date, 'America/New_York').inMilliseconds,
      );
    });

    test('throws TimeZoneResolutionException for an unknown zone', () {
      expect(
        () => encodeDayArgs(LocalDate(2026, 1, 1), 'Not/AZone'),
        throwsA(isA<TimeZoneResolutionException>()),
      );
    });
  });

  group('encodePeriodDayArgs (Issue #202 MenstruationPeriodRecord)', () {
    test('a multi-day episode spans start midnight to the exclusive end '
        'midnight, each with its own zone offset', () {
      // 2026-08-30..2026-09-01 in America/New_York (EDT, UTC-4 throughout —
      // no DST transition inside): start = 08-30 04:00Z; end = exclusive
      // 09-02 04:00Z; both offsets -4h.
      final args = encodePeriodDayArgs(
        LocalDate(2026, 8, 30),
        LocalDate(2026, 9, 1),
        'America/New_York',
      );
      expect(args['startMs'], DateTime.utc(2026, 8, 30, 4).millisecondsSinceEpoch);
      expect(args['startZoneOffsetMs'], -4 * 3600 * 1000);
      expect(args['endMs'], DateTime.utc(2026, 9, 2, 4).millisecondsSinceEpoch);
      expect(args['endZoneOffsetMs'], -4 * 3600 * 1000);
    });

    test('an end day across a fall-back DST transition carries a different '
        'endZoneOffset than the start (#180 contract note)', () {
      // 2026-11-01 America/New_York: DST ends 02:00 EDT. The episode's end
      // exclusive is midnight of Nov 2 (EST, -5h) while its start is
      // midnight of Nov 1 (EDT, -4h) — endZoneOffset must differ.
      final args = encodePeriodDayArgs(
        LocalDate(2026, 11, 1),
        LocalDate(2026, 11, 1),
        'America/New_York',
      );
      expect(args['startZoneOffsetMs'], -4 * 3600 * 1000);
      expect(args['endZoneOffsetMs'], -5 * 3600 * 1000);
    });

    test('agrees with day_boundary.dart\'s own functions', () {
      final start = LocalDate(2026, 8, 30);
      final end = LocalDate(2026, 9, 1);
      final args = encodePeriodDayArgs(start, end, 'America/New_York');
      expect(args['startMs'], localDayInstant(start, 'America/New_York').millisecondsSinceEpoch);
      expect(args['startZoneOffsetMs'], zoneOffsetFor(start, 'America/New_York').inMilliseconds);
      expect(args['endMs'], localDayEndExclusive(end, 'America/New_York').millisecondsSinceEpoch);
      expect(args['endZoneOffsetMs'], endZoneOffsetFor(end, 'America/New_York').inMilliseconds);
    });

    test('throws TimeZoneResolutionException for an unknown zone', () {
      expect(
        () => encodePeriodDayArgs(
          LocalDate(2026, 1, 1),
          LocalDate(2026, 1, 2),
          'Not/AZone',
        ),
        throwsA(isA<TimeZoneResolutionException>()),
      );
    });
  });

  group('decodeHealthResult', () {
    test('"allowed" decodes to the allowed variant', () {
      expect(
        decodeHealthResult('allowed'),
        isA<HealthPlatformAllowed>(),
      );
    });

    test('platform outcomes decode to their variants', () {
      expect(
        decodeHealthResult('unavailable'),
        isA<HealthPlatformUnavailable>(),
      );
      expect(
        decodeHealthResult('permissionDenied'),
        isA<HealthPlatformPermissionDenied>(),
      );
    });

    test('every HealthSyncCheck deny name round-trips to refused(check)',
        () {
      for (final check in HealthSyncCheck.values) {
        if (check == HealthSyncCheck.allowed) continue;
        final decoded = decodeHealthResult(check.name);
        expect(decoded, isA<HealthPlatformRefused>());
        expect((decoded as HealthPlatformRefused).check, check);
      }
    });

    test('an unknown string is a failed result, never a silent fallback',
        () {
      final decoded = decodeHealthResult('writeFailed');
      expect(decoded, isA<HealthPlatformFailed>());
      expect(
        (decoded as HealthPlatformFailed).message,
        contains('unknown channel result'),
      );
    });

    test('a non-string result is a failed result', () {
      final decoded = decodeHealthResult(7);
      expect(decoded, isA<HealthPlatformFailed>());
    });
  });

  group('HealthFlowValue wire vocabulary', () {
    test('every value round-trips through its wire string', () {
      for (final value in HealthFlowValue.values) {
        expect(HealthFlowValue.fromWire(value.toWire()), value);
      }
    });

    test('anything else parses to null (a protocol error, not a fallback)',
        () {
      expect(HealthFlowValue.fromWire('spotting'), isNull);
      expect(HealthFlowValue.fromWire('none'), isNull);
      expect(HealthFlowValue.fromWire(null), isNull);
    });
  });
}
