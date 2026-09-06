import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/notifications/notification_preferences.dart';

void main() {
  group('MissedEntryThreshold', () {
    test('maps 1/2/3/off to and from the database representation', () {
      expect(MissedEntryThreshold.off.toDb(), null);
      expect(MissedEntryThreshold.oneDay.toDb(), 1);
      expect(MissedEntryThreshold.twoDays.toDb(), 2);
      expect(MissedEntryThreshold.threeDays.toDb(), 3);

      expect(MissedEntryThreshold.fromDb(null), MissedEntryThreshold.off);
      expect(MissedEntryThreshold.fromDb(1), MissedEntryThreshold.oneDay);
      expect(MissedEntryThreshold.fromDb(2), MissedEntryThreshold.twoDays);
      expect(MissedEntryThreshold.fromDb(3), MissedEntryThreshold.threeDays);
    });

    test('rejects an unknown value', () {
      expect(() => MissedEntryThreshold.fromDb(4), throwsArgumentError);
      expect(() => MissedEntryThreshold.fromDb(0), throwsArgumentError);
    });
  });

  group('QuietHours', () {
    test('a same-day window reports containment correctly', () {
      const window = QuietHours(startMinutes: 8 * 60, endMinutes: 10 * 60);
      expect(window.contains(9 * 60), isTrue);
      expect(window.contains(8 * 60), isTrue);
      expect(window.contains(10 * 60), isFalse, reason: 'end is exclusive');
      expect(window.contains(7 * 60), isFalse);
    });

    test('a window that wraps midnight reports containment correctly', () {
      const window = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60);
      expect(window.contains(23 * 60), isTrue);
      expect(window.contains(0), isTrue);
      expect(window.contains(6 * 60), isTrue);
      expect(window.contains(7 * 60), isFalse, reason: 'end is exclusive');
      expect(window.contains(12 * 60), isFalse);
    });

    test('a zero-length window is treated as empty (contains nothing)', () {
      const window = QuietHours(startMinutes: 60, endMinutes: 60);
      expect(window.isEmpty, isTrue);
      expect(window.contains(60), isFalse);
      expect(window.contains(0), isFalse);
    });

    test('a null window contains nothing', () {
      expect(QuietHours.containsIn(null, 9 * 60), isFalse);
    });
  });

  group('CaregiverAlertPreferences', () {
    const base = CaregiverAlertPreferences(
      alertOnLog: true,
      alertOnCycleStartOnly: true,
      alertOnHighSeverity: true,
      missedEntryThreshold: MissedEntryThreshold.twoDays,
      quietHours: QuietHours(startMinutes: 1320, endMinutes: 420),
      timeZone: 'America/New_York',
    );

    test('copyWith round-trips every field', () {
      expect(base.copyWith(alertOnLog: false).alertOnLog, isFalse);
      expect(
          base.copyWith(alertOnCycleStartOnly: false).alertOnCycleStartOnly,
          isFalse);
      expect(base.copyWith(alertOnHighSeverity: false).alertOnHighSeverity,
          isFalse);
      expect(
        base
            .copyWith(missedEntryThreshold: MissedEntryThreshold.off)
            .missedEntryThreshold,
        MissedEntryThreshold.off,
      );
      expect(
        base
            .copyWith(
                quietHours: const QuietHours(startMinutes: 0, endMinutes: 60))
            .quietHours,
        const QuietHours(startMinutes: 0, endMinutes: 60),
      );
      expect(base.copyWith(clearQuietHours: true).quietHours, isNull);
      expect(base.copyWith(timeZone: 'UTC').timeZone, 'UTC');
      expect(base.copyWith(clearTimeZone: true).timeZone, isNull);
    });

    test('equality distinguishes each field', () {
      expect(base, base.copyWith());
      expect(base, isNot(base.copyWith(alertOnLog: false)));
      expect(base, isNot(base.copyWith(alertOnCycleStartOnly: false)));
      expect(base, isNot(base.copyWith(alertOnHighSeverity: false)));
      expect(
        base,
        isNot(base.copyWith(missedEntryThreshold: MissedEntryThreshold.off)),
      );
      expect(base, isNot(base.copyWith(clearQuietHours: true)));
      expect(base, isNot(base.copyWith(clearTimeZone: true)));
    });

    test('the all-off default has every alert off and threshold off', () {
      expect(CaregiverAlertPreferences.off.alertOnLog, isFalse);
      expect(CaregiverAlertPreferences.off.alertOnCycleStartOnly, isFalse);
      expect(CaregiverAlertPreferences.off.alertOnHighSeverity, isFalse);
      expect(CaregiverAlertPreferences.off.missedEntryThreshold,
          MissedEntryThreshold.off);
      expect(CaregiverAlertPreferences.off.quietHours, isNull);
    });
  });
}
