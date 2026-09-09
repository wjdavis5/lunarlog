/// Unit tests for the per-type reminder configuration (Issue #136):
/// preset-derived defaults, JSON round-trips with tolerant decoding, and
/// the quiet-hours boundary shift.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/notifications/notification_preferences.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/reminder_presets.dart';

void main() {
  group('defaults', () {
    test('standard defaults reproduce the pre-#136 plan exactly', () {
      const config = ReminderConfig.standard;
      expect(config.upcoming.enabled, isTrue,
          reason: 'upcoming was always on');
      expect(config.upcoming.leadDays, kUpcomingDefaultLeadDays);
      expect(config.upcoming.leadDays, 2,
          reason: 'the old kUpcomingReminderOffsetDays');
      expect(config.upcoming.timeOfDayMinutes, 9 * 60,
          reason: 'the old hardcoded 9 AM');
      expect(config.late.enabled, isTrue, reason: 'late was always on');
      expect(config.late.timeOfDayMinutes, 9 * 60);
      expect(config.late.leadDays, isNull,
          reason: 'late has no estimate anchor');
      expect(config.pms.enabled, isFalse, reason: 'PMS-watch ships off');
      expect(config.log.enabled, isFalse, reason: 'the log nudge ships off');
      expect(config.quietHours, isNull);
    });

    test('fromMode follows the care-mode preset for the always-on types',
        () {
      final standard = ReminderConfig.fromMode(ProfileMode.standard);
      expect(standard.upcoming.enabled, isTrue);
      expect(standard.late.enabled, isTrue);

      final teen = ReminderConfig.fromMode(ProfileMode.teen);
      expect(teen.upcoming.enabled, isTrue);
      expect(teen.late.enabled, isFalse,
          reason: 'the teen preset silences the late window');

      final caregiver = ReminderConfig.fromMode(ProfileMode.caregiver);
      expect(caregiver.upcoming.enabled, isFalse);
      expect(caregiver.late.enabled, isFalse);

      final irregular = ReminderConfig.fromMode(ProfileMode.irregular);
      expect(irregular.upcoming.enabled, isTrue);
      expect(irregular.late.enabled, isFalse);

      // PMS-watch and the log nudge are never preset-defaulted on: they
      // are new opt-ins, not part of any pre-#136 behavior.
      for (final mode in ProfileMode.values) {
        final config = ReminderConfig.fromMode(mode);
        expect(config.pms.enabled, isFalse, reason: '$mode');
        expect(config.log.enabled, isFalse, reason: '$mode');
      }
    });

    test('fromPreset matches reminderPresetFor exhaustively', () {
      for (final mode in ProfileMode.values) {
        final preset = reminderPresetFor(mode);
        final config = ReminderConfig.fromPreset(preset);
        expect(config.upcoming.enabled, preset.upcoming, reason: '$mode');
        expect(config.late.enabled, preset.late, reason: '$mode');
      }
    });
  });

  group('JSON round-trip', () {
    test('encode then decode preserves every field', () {
      const config = ReminderConfig(
        upcoming: ReminderTypeConfig(
            enabled: true, leadDays: 3, timeOfDayMinutes: 8 * 60),
        pms: ReminderTypeConfig(
            enabled: true, leadDays: 5, timeOfDayMinutes: 19 * 60 + 45),
        late: ReminderTypeConfig(enabled: false, timeOfDayMinutes: 10 * 60),
        log: ReminderTypeConfig(enabled: true, timeOfDayMinutes: 20 * 60),
        quietHours: QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60),
      );
      final decoded =
          decodeReminderConfigs(encodeReminderConfigs({'p1': config}));
      expect(decoded['p1'], config);
    });

    test('a profile-less or empty value decodes to nothing', () {
      expect(decodeReminderConfigs(null), isEmpty);
      expect(decodeReminderConfigs(''), isEmpty);
      expect(decodeReminderConfigs('not json'), isEmpty);
      expect(decodeReminderConfigs('{"v":1}'), isEmpty);
      expect(decodeReminderConfigs('{"v":1,"profiles":{"p1":"junk"}}'),
          isEmpty,
          reason: 'a non-map profile section is dropped, never thrown on');
    });

    test('malformed fields degrade to the stock defaults field-by-field',
        () {
      final decoded = decodeReminderConfigs('''
{
  "v": 1,
  "profiles": {
    "p1": {
      "upcoming": {"enabled": "yes", "leadDays": 99, "timeOfDay": -5},
      "late": {},
      "pms": "junk",
      "log": {"enabled": true, "timeOfDay": 2000}
    }
  }
}
''');
      final config = decoded['p1']!;
      // Out-of-range lead clamps to the bound.
      expect(config.upcoming.leadDays, kMaxLeadDays);
      // Out-of-range time clamps, not throws.
      expect(config.log.timeOfDayMinutes, kMaxTimeOfDayMinutes);
      // A bad enabled flag falls back to the type default (on).
      expect(config.upcoming.enabled, isTrue);
      // An empty section is all defaults.
      expect(config.late, ReminderTypeConfig.late);
      // A non-map section is all defaults.
      expect(config.pms, ReminderTypeConfig.pms);
    });

    test('lead-day and time-of-day bounds are clamped, in both directions',
        () {
      final decoded = decodeReminderConfigs('''
{
  "v": 1,
  "profiles": {"p1": {"upcoming": {"leadDays": -3, "timeOfDay": 1500}}}
}
''');
      final upcoming = decoded['p1']!.upcoming;
      expect(upcoming.leadDays, kMinLeadDays);
      expect(upcoming.timeOfDayMinutes, kMaxTimeOfDayMinutes);
    });
  });

  group('late-snooze JSON', () {
    test('encode then decode preserves profile ids and dates', () {
      final encoded = encodeLateSnoozes({
        'p1': LocalDate(2026, 9, 3),
        'p2': LocalDate(2026, 12, 31),
      });
      expect(decodeLateSnoozes(encoded), {
        'p1': LocalDate(2026, 9, 3),
        'p2': LocalDate(2026, 12, 31),
      });
    });

    test('malformed values degrade to "not snoozed"', () {
      expect(decodeLateSnoozes(null), isEmpty);
      expect(decodeLateSnoozes('junk'), isEmpty);
      expect(decodeLateSnoozes('{"v":1}'), isEmpty);
      expect(decodeLateSnoozes('{"snoozes":{"p1":"2026-9-3"}}'), isEmpty,
          reason: 'a non-padded date is not an ISO civil date');
      expect(decodeLateSnoozes('{"snoozes":{"p1":"soon"}}'), isEmpty);
    });
  });

  group('shiftQuietHours', () {
    final day = LocalDate(2026, 9, 3);

    test('a fire outside the window is untouched', () {
      const window =
          QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60);
      expect(shiftQuietHours(day, 9 * 60, window),
          (date: day, minuteOfDay: 9 * 60));
      expect(shiftQuietHours(day, 12 * 60, null),
          (date: day, minuteOfDay: 12 * 60));
    });

    test('a fire inside a same-day window shifts to its end', () {
      const window =
          QuietHours(startMinutes: 13 * 60, endMinutes: 15 * 60);
      final shifted = shiftQuietHours(day, 14 * 60, window);
      expect(shifted.date, day);
      expect(shifted.minuteOfDay, 15 * 60);
    });

    test('an evening fire in a wrapping window shifts to the next morning',
        () {
      const window =
          QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60);
      final shifted = shiftQuietHours(day, 23 * 60, window);
      expect(shifted.date, day.addDays(1));
      expect(shifted.minuteOfDay, 7 * 60);
    });

    test('a post-midnight fire in a wrapping window shifts to the same '
        'morning boundary', () {
      const window =
          QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60);
      final shifted = shiftQuietHours(day, 6 * 60 + 30, window);
      expect(shifted.date, day);
      expect(shifted.minuteOfDay, 7 * 60);
    });

    test('a fire exactly at the boundary is outside (end-exclusive)', () {
      const window =
          QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60);
      expect(shiftQuietHours(day, 7 * 60, window),
          (date: day, minuteOfDay: 7 * 60));
    });
  });

  group('ReminderTypeConfig / ReminderConfig plumbing', () {
    test('typeConfig and withTypeConfig round-trip every kind', () {
      const config = ReminderConfig.standard;
      for (final kind in ReminderKind.values) {
        expect(config.typeConfig(kind), isA<ReminderTypeConfig>());
      }
      final updated = config.withTypeConfig(
        ReminderKind.log,
        config.typeConfig(ReminderKind.log).copyWith(enabled: true),
      );
      expect(updated.log.enabled, isTrue);
      expect(updated.upcoming, config.upcoming,
          reason: 'the other types are untouched');
    });

    test('equality is field-wise', () {
      expect(ReminderConfig.standard, ReminderConfig.standard);
      expect(
        ReminderConfig.standard.copyWith(
            log: ReminderTypeConfig(
                enabled: true, timeOfDayMinutes: 9 * 60)),
        isNot(ReminderConfig.standard),
      );
      expect(
        ReminderConfig.standard.copyWith(
          quietHours: const QuietHours(startMinutes: 1, endMinutes: 2),
        ),
        isNot(ReminderConfig.standard),
      );
    });
  });
}
