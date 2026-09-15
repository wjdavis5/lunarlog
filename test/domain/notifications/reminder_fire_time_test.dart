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
}
