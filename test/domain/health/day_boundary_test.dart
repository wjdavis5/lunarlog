/// Dedicated regression matrix for the day-boundary/time-zone contract
/// (Issue #180) — DST transitions, cross-zone travel, and midnight-boundary
/// instants in extreme-offset zones. This project has shipped two prior
/// timezone bugs (#38, #46), which is why this file exists as dedicated
/// coverage rather than incidental coverage from other health-sync tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/day_boundary.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
  });

  group('localDayInterval — DST spring-forward', () {
    test('America/New_York 2026-03-08 (02:00 -> 03:00 local): a 23-hour day',
        () {
      final result =
          localDayInterval(LocalDate(2026, 3, 8), 'America/New_York');
      // Local midnight, still EST (-05:00): pre-transition.
      expect(result.start, DateTime.utc(2026, 3, 8, 5, 0, 0));
      // Next local midnight is already EDT (-04:00): post-transition,
      // minus one second (this project's whole-day convention).
      expect(result.end, DateTime.utc(2026, 3, 9, 3, 59, 59));
      expect(result.start.isUtc, isTrue);
      expect(result.end.isUtc, isTrue);
    });

    test('Europe/London 2026-03-29 (01:00 UTC transition): a 23-hour day',
        () {
      final result = localDayInterval(LocalDate(2026, 3, 29), 'Europe/London');
      // Local midnight, still GMT (+00:00): pre-transition.
      expect(result.start, DateTime.utc(2026, 3, 29, 0, 0, 0));
      // Next local midnight is already BST (+01:00): post-transition,
      // minus one second.
      expect(result.end, DateTime.utc(2026, 3, 29, 22, 59, 59));
    });
  });

  group('localDayInterval — DST fall-back', () {
    test('America/New_York 2026-11-01 (02:00 -> 01:00 local): a 25-hour day',
        () {
      final result =
          localDayInterval(LocalDate(2026, 11, 1), 'America/New_York');
      // Local midnight, still EDT (-04:00): pre-transition.
      expect(result.start, DateTime.utc(2026, 11, 1, 4, 0, 0));
      // Next local midnight is already EST (-05:00): post-transition,
      // minus one second.
      expect(result.end, DateTime.utc(2026, 11, 2, 4, 59, 59));
    });

    test('Europe/London 2026-10-25 (02:00 -> 01:00 local): a 25-hour day',
        () {
      final result =
          localDayInterval(LocalDate(2026, 10, 25), 'Europe/London');
      // Local midnight, still BST (+01:00): pre-transition.
      expect(result.start, DateTime.utc(2026, 10, 24, 23, 0, 0));
      // Next local midnight is already GMT (+00:00): post-transition,
      // minus one second.
      expect(result.end, DateTime.utc(2026, 10, 25, 23, 59, 59));
    });
  });

  group('localDayInstant', () {
    test('is local midnight of the given date as a UTC instant', () {
      expect(
        localDayInstant(LocalDate(2026, 3, 8), 'America/New_York'),
        DateTime.utc(2026, 3, 8, 5, 0, 0),
      );
      expect(
        localDayInstant(LocalDate(2026, 11, 1), 'America/New_York'),
        DateTime.utc(2026, 11, 1, 4, 0, 0),
      );
    });

    test('result is always a UTC DateTime', () {
      expect(
        localDayInstant(LocalDate(2026, 6, 1), 'Asia/Tokyo').isUtc,
        isTrue,
      );
    });
  });

  group('localDateForSample — DST transitions', () {
    test(
        'America/New_York: an instant the day after spring-forward resolves '
        'correctly, not one day early', () {
      // 2026-03-09T04:30:00Z is 2026-03-09 00:30 EDT (-04:00, the jump
      // already happened the day before) -- a bug that kept using EST
      // (-05:00) would compute 2026-03-08 23:30, landing one day early.
      final result = localDateForSample(
        DateTime.utc(2026, 3, 9, 4, 30),
        tzName: 'America/New_York',
      );
      expect(result, LocalDate(2026, 3, 9));
    });

    test(
        'America/New_York: an instant the day after fall-back resolves '
        'correctly, not one day late', () {
      // 2026-11-02T04:30:00Z is 2026-11-01 23:30 EST (-05:00, the rollback
      // already happened the day before) -- a bug that kept using EDT
      // (-04:00) would compute 2026-11-02 00:30, landing one day late.
      final result = localDateForSample(
        DateTime.utc(2026, 11, 2, 4, 30),
        tzName: 'America/New_York',
      );
      expect(result, LocalDate(2026, 11, 1));
    });
  });

  group('cross-zone travel: the entry\'s own tz is used, never the device zone', () {
    tearDown(() => tz.setLocalLocation(tz.UTC));

    test('localDayInterval ignores tz.local entirely', () {
      final date = LocalDate(2026, 6, 15);

      tz.setLocalLocation(tz.getLocation('America/Los_Angeles'));
      final resultWithLaDevice = localDayInterval(date, 'Asia/Tokyo');

      tz.setLocalLocation(tz.getLocation('Pacific/Auckland'));
      final resultWithAucklandDevice = localDayInterval(date, 'Asia/Tokyo');

      tz.setLocalLocation(tz.UTC);
      final resultWithUtcDevice = localDayInterval(date, 'Asia/Tokyo');

      // Asia/Tokyo carries no DST -- identical regardless of what tz.local
      // was set to at call time.
      expect(resultWithLaDevice, resultWithAucklandDevice);
      expect(resultWithLaDevice, resultWithUtcDevice);
      expect(resultWithLaDevice.start, DateTime.utc(2026, 6, 14, 15, 0, 0));
    });

    test('localDateForSample ignores tz.local entirely', () {
      final instant = DateTime.utc(2026, 6, 15, 0, 30);

      tz.setLocalLocation(tz.getLocation('America/Los_Angeles'));
      final resultWithLaDevice =
          localDateForSample(instant, tzName: 'Pacific/Auckland');

      tz.setLocalLocation(tz.getLocation('Europe/London'));
      final resultWithLondonDevice =
          localDateForSample(instant, tzName: 'Pacific/Auckland');

      // A device in America/Los_Angeles (this same instant is still
      // 2026-06-14 there) must not leak into the Pacific/Auckland answer.
      expect(resultWithLaDevice, LocalDate(2026, 6, 15));
      expect(resultWithLaDevice, resultWithLondonDevice);
    });
  });

  group('midnight-boundary instants in extreme-offset zones', () {
    test('Pacific/Auckland (+12:00/+13:00): a late-UTC-day instant is '
        'already the next local calendar day', () {
      final result = localDateForSample(
        DateTime.utc(2026, 6, 14, 23, 30),
        tzName: 'Pacific/Auckland',
      );
      // NZST +12:00 in June (no DST mid-year): 23:30 + 12:00 = 11:30 the
      // following day.
      expect(result, LocalDate(2026, 6, 15));
    });

    test('Pacific/Kiritimati (+14:00, no DST): a UTC instant lands a full '
        'day ahead', () {
      final result = localDateForSample(
        DateTime.utc(2026, 6, 14, 23, 0),
        tzName: 'Pacific/Kiritimati',
      );
      // +14:00: 23:00 + 14:00 = 13:00 the following day.
      expect(result, LocalDate(2026, 6, 15));
    });

    test('Pacific/Pago_Pago (-11:00, no DST): a UTC instant lands a full '
        'day behind', () {
      final result = localDateForSample(
        DateTime.utc(2026, 6, 15, 0, 30),
        tzName: 'Pacific/Pago_Pago',
      );
      // -11:00: 00:30 - 11:00 = 13:30 the PREVIOUS day.
      expect(result, LocalDate(2026, 6, 14));
    });

    test('localDayInterval also resolves correctly at +14:00', () {
      final result =
          localDayInterval(LocalDate(2026, 6, 15), 'Pacific/Kiritimati');
      expect(result.start, DateTime.utc(2026, 6, 14, 10, 0, 0));
      expect(result.end, DateTime.utc(2026, 6, 15, 9, 59, 59));
    });
  });

  group('localDateForSample — offset variant (Health Connect)', () {
    test('uses the supplied Duration offset, not any zone lookup', () {
      final result = localDateForSample(
        DateTime.utc(2026, 6, 15, 0, 30),
        offset: const Duration(hours: -11),
      );
      expect(result, LocalDate(2026, 6, 14));
    });

    test('throws ArgumentError when neither tzName nor offset is supplied',
        () {
      expect(
        () => localDateForSample(DateTime.utc(2026, 1, 1)),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when both tzName and offset are supplied', () {
      expect(
        () => localDateForSample(
          DateTime.utc(2026, 1, 1),
          tzName: 'UTC',
          offset: Duration.zero,
        ),
        throwsArgumentError,
      );
    });
  });

  group('zoneOffsetFor', () {
    test('is DST-aware across the America/New_York spring-forward boundary',
        () {
      expect(
        zoneOffsetFor(LocalDate(2026, 3, 8), 'America/New_York'),
        const Duration(hours: -5),
      );
      expect(
        zoneOffsetFor(LocalDate(2026, 3, 9), 'America/New_York'),
        const Duration(hours: -4),
      );
    });

    test('is DST-aware across the America/New_York fall-back boundary', () {
      expect(
        zoneOffsetFor(LocalDate(2026, 11, 1), 'America/New_York'),
        const Duration(hours: -4),
      );
      expect(
        zoneOffsetFor(LocalDate(2026, 11, 2), 'America/New_York'),
        const Duration(hours: -5),
      );
    });

    test('matches a fixed extreme-offset zone with no DST', () {
      expect(
        zoneOffsetFor(LocalDate(2026, 6, 15), 'Pacific/Kiritimati'),
        const Duration(hours: 14),
      );
      expect(
        zoneOffsetFor(LocalDate(2026, 6, 15), 'Pacific/Pago_Pago'),
        const Duration(hours: -11),
      );
    });
  });

  group('midnight-boundary instants: DST-gap and DST-ambiguous local '
      'midnights (review addition, Issue #180)', () {
    test(
        'America/Havana 2026-03-08: local midnight falls inside the '
        'spring-forward gap (00:00 jumps straight to 01:00) -- resolves to '
        'the pre-transition (-05:00) offset', () {
      final result = localDayInstant(LocalDate(2026, 3, 8), 'America/Havana');
      expect(result, DateTime.utc(2026, 3, 8, 5, 0, 0));
    });

    test(
        'America/Santiago 2026-09-06: Southern-hemisphere DST start -- '
        'local midnight falls inside that gap, resolving to the '
        'pre-transition (-04:00) offset', () {
      final result =
          localDayInstant(LocalDate(2026, 9, 6), 'America/Santiago');
      expect(result, DateTime.utc(2026, 9, 6, 4, 0, 0));
    });

    test(
        'America/Havana 2026-11-01: fall-back day -- local midnight is '
        'AMBIGUOUS (00:00 occurs twice, once under -04:00 DST and again '
        'under -05:00 standard time an hour later); resolves to the '
        'earlier (-04:00, DST) instant', () {
      final result =
          localDayInstant(LocalDate(2026, 11, 1), 'America/Havana');
      expect(result, DateTime.utc(2026, 11, 1, 4, 0, 0));
    });
  });

  group('round-trip property: localDateForSample(localDayInstant(d, z)) == d',
      () {
    // A zone/date matrix covering: no-DST fixed offsets (both signs and an
    // extreme +14:00), Northern- and Southern-hemisphere DST, and the two
    // gap/ambiguous-midnight zones exercised above -- every date this file's
    // other groups already touch, so a regression in either function's
    // rounding would be caught by more than one group.
    const zones = [
      'UTC',
      'America/New_York',
      'Europe/London',
      'Asia/Tokyo',
      'Pacific/Auckland',
      'Pacific/Kiritimati',
      'Pacific/Pago_Pago',
      'America/Havana',
      'America/Santiago',
    ];
    final dates = [
      LocalDate(2026, 1, 1),
      LocalDate(2026, 3, 8),
      LocalDate(2026, 6, 15),
      LocalDate(2026, 9, 6),
      LocalDate(2026, 11, 1),
      LocalDate(2026, 12, 31),
    ];

    for (final zone in zones) {
      for (final date in dates) {
        test('$zone @ $date', () {
          final instant = localDayInstant(date, zone);
          final roundTripped =
              localDateForSample(instant, tzName: zone);
          expect(roundTripped, date);
        });
      }
    }
  });

  group('invalid zone', () {
    test('localDayInterval throws TimeZoneResolutionException(unknownZone)',
        () {
      expect(
        () => localDayInterval(LocalDate(2026, 1, 1), 'Mars/Olympus'),
        throwsA(isA<TimeZoneResolutionException>().having(
          (e) => e.reason,
          'reason',
          TimeZoneResolutionReason.unknownZone,
        )),
      );
    });

    test('localDayInstant throws TimeZoneResolutionException(unknownZone)',
        () {
      expect(
        () => localDayInstant(LocalDate(2026, 1, 1), 'Mars/Olympus'),
        throwsA(isA<TimeZoneResolutionException>().having(
          (e) => e.reason,
          'reason',
          TimeZoneResolutionReason.unknownZone,
        )),
      );
    });

    test(
        'localDateForSample throws TimeZoneResolutionException(unknownZone)',
        () {
      expect(
        () => localDateForSample(DateTime.utc(2026, 1, 1),
            tzName: 'Mars/Olympus'),
        throwsA(isA<TimeZoneResolutionException>().having(
          (e) => e.reason,
          'reason',
          TimeZoneResolutionReason.unknownZone,
        )),
      );
    });

    test('zoneOffsetFor throws TimeZoneResolutionException(unknownZone)', () {
      expect(
        () => zoneOffsetFor(LocalDate(2026, 1, 1), 'Mars/Olympus'),
        throwsA(isA<TimeZoneResolutionException>().having(
          (e) => e.reason,
          'reason',
          TimeZoneResolutionReason.unknownZone,
        )),
      );
    });

    test('exception carries the offending tzName and a readable message', () {
      try {
        localDayInstant(LocalDate(2026, 1, 1), 'Mars/Olympus');
        fail('expected TimeZoneResolutionException');
      } on TimeZoneResolutionException catch (e) {
        expect(e.tzName, 'Mars/Olympus');
        expect(e.toString(), contains('Mars/Olympus'));
        expect(e.toString(), contains('unknown time zone'));
      }
    });
  });
}
