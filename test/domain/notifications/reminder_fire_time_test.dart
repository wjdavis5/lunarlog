/// Unit tests for the reminder fire-time computation (issue #215):
/// a planned reminder's exact [tz.TZDateTime], pinned to local civil time
/// across zones. Moved verbatim out of
/// `test/data/notification_scheduler_test.dart` when the function moved to
/// `lib/domain/notifications/reminder_fire_time.dart`, so the tests count
/// toward the coverage floor instead of landing in an excluded file.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/reminder_fire_time.dart';
import 'package:lunarlog/domain/notifications/scheduling.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
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
      final fireSydney = calculateReminderFireAt(
        fireOn: date,
        location: sydney,
      );
      expect(fireSydney.hour, 9);
      // Sydney is AEST (UTC+10) in August -> 09:00 AEST == 23:00 UTC previous day
      expect(fireSydney.toUtc(), DateTime.utc(2026, 8, 29, 23, 0));
    });

    test('supports custom reminder times (minutes since local midnight)', () {
      final utc = tz.getLocation('UTC');
      final fire = calculateReminderFireAt(
        fireOn: date,
        location: utc,
        minuteOfDay: 8 * 60,
      );
      expect(fire.hour, 8);
      expect(fire.toUtc(), DateTime.utc(2026, 8, 30, 8, 0));

      final afternoon = calculateReminderFireAt(
        fireOn: date,
        location: utc,
        minuteOfDay: 20 * 60 + 30,
      );
      expect(afternoon.hour, 20);
      expect(afternoon.minute, 30);
    });
  });

  group('resolveReminderFireTimes (issue #171)', () {
    final date = LocalDate(2026, 8, 30);

    PlannedReminder reminderAt(int minuteOfDay, {LocalDate? fireOn}) =>
        PlannedReminder(
          profileId: 'p1',
          fireOn: fireOn ?? date,
          kind: ReminderKind.late,
          timeOfDayMinutes: minuteOfDay,
        );

    test('marks a slot before now as past and a slot after now as armable',
        () {
      final utc = tz.getLocation('UTC');
      final resolved = resolveReminderFireTimes(
        reminders: [reminderAt(9 * 60), reminderAt(15 * 60)],
        location: utc,
        now: tz.TZDateTime.utc(2026, 8, 30, 12),
      );

      expect(resolved, hasLength(2));
      expect(resolved[0].isPast, isTrue,
          reason: '09:00 today is already behind a 12:00 replan');
      expect(resolved[0].fireAt.toUtc(), DateTime.utc(2026, 8, 30, 9));
      expect(resolved[1].isPast, isFalse,
          reason: '15:00 today is still ahead of a 12:00 replan');
      expect(resolved[1].fireAt.toUtc(), DateTime.utc(2026, 8, 30, 15));
    });

    test('a slot exactly at now is already due, not armable', () {
      final utc = tz.getLocation('UTC');
      final resolved = resolveReminderFireTimes(
        reminders: [reminderAt(12 * 60)],
        location: utc,
        now: tz.TZDateTime.utc(2026, 8, 30, 12),
      );

      expect(resolved.single.isPast, isTrue,
          reason: 'a notification requested for this very instant is already '
              'due and is not delivered');
    });

    test('a future date is never past, whatever its time-of-day', () {
      final utc = tz.getLocation('UTC');
      final resolved = resolveReminderFireTimes(
        reminders: [reminderAt(0, fireOn: date.addDays(1))],
        location: utc,
        now: tz.TZDateTime.utc(2026, 8, 30, 23, 59),
      );

      expect(resolved.single.isPast, isFalse);
    });

    test('preserves input order and resolves each reminder independently',
        () {
      final utc = tz.getLocation('UTC');
      final first = reminderAt(9 * 60);
      final second = reminderAt(9 * 60, fireOn: date.addDays(1));
      final resolved = resolveReminderFireTimes(
        reminders: [first, second],
        location: utc,
        now: tz.TZDateTime.utc(2026, 8, 30, 12),
      );

      expect(resolved.map((r) => r.reminder), [first, second]);
      expect(resolved.map((r) => r.isPast), [true, false]);
    });

    test('resolves in the given location, not UTC', () {
      final tokyo = tz.getLocation('Asia/Tokyo');
      final resolved = resolveReminderFireTimes(
        reminders: [reminderAt(9 * 60)],
        location: tokyo,
        // 09:00 JST is 00:00 UTC; at 01:00 UTC (10:00 JST) it is past.
        now: tz.TZDateTime.utc(2026, 8, 30, 1),
      );

      expect(resolved.single.fireAt.hour, 9);
      expect(resolved.single.fireAt.location, tokyo);
      expect(resolved.single.isPast, isTrue);
    });

    test('toString names the kind and marks a past slot', () {
      final utc = tz.getLocation('UTC');
      final resolved = resolveReminderFireTimes(
        reminders: [reminderAt(9 * 60)],
        location: utc,
        now: tz.TZDateTime.utc(2026, 8, 30, 12),
      ).single;

      expect(resolved.toString(), contains('late'));
      expect(resolved.toString(), contains('past'));
    });
  });
}
