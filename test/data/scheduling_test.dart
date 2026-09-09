/// U8 planning tests (KTD7): which reminders should be pending, from live
/// predictions — upcoming window, late pre-arm, cap, generic content.
/// Issue #136 adds the per-type configuration: enable toggles, lead days,
/// per-type time-of-day, quiet hours, same-day coalescing, the eviction
/// order under the cap, stable ids, and the "Not yet" late snooze.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/scheduling.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/notification_preferences.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/reminder_presets.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

ActivePrediction _prediction({
  required LocalDate today,
  required LocalDate estimatedNextStart,
}) {
  final lastStart = estimatedNextStart.addDays(-28);
  final cycleDay = today.difference(lastStart) + 1;
  return ActivePrediction(
    today: today,
    lastEpisodeStart: lastStart,
    estimatedNextStart: estimatedNextStart,
    originalEstimatedNextStart: estimatedNextStart,
    averagedCycleLengths: const [28],
    meanCycleLengthDays: 28,
    cycleDay: cycleDay,
    duringEpisode: false,
    completedCycleCount: 4,
    validCycleCount: 4,
  );
}

void main() {
  final today = LocalDate(2026, 8, 30);

  test('upcoming reminder scheduled at estimate minus 2, when future', () {
    final estimate = today.addDays(10);
    final plan = planReminders(
      today: today,
      predictions: {'p1': _prediction(today: today, estimatedNextStart: estimate)},
    );
    expect(plan, hasLength(1));
    expect(plan.single.kind, ReminderKind.upcoming);
    expect(plan.single.fireOn, today.addDays(8));
  });

  test('no upcoming reminder when the window already passed', () {
    // Estimate is tomorrow: the -2 day moment is in the past.
    final estimate = today.addDays(1);
    final plan = planReminders(
      today: today,
      predictions: {'p1': _prediction(today: today, estimatedNextStart: estimate)},
    );
    expect(plan, isEmpty);
  });

  test('late profile gets a pre-armed daily window (iOS has no same-day callback)', () {
    // Estimate 5 days ago ⇒ daysUntilNextStart = -5 < -2 ⇒ late.
    final estimate = today.addDays(-5);
    final plan = planReminders(
      today: today,
      predictions: {'p1': _prediction(today: today, estimatedNextStart: estimate)},
    );
    expect(plan, hasLength(kLatePreArmDays));
    expect(plan.every((r) => r.kind == ReminderKind.late), isTrue);
    expect(plan.first.fireOn, today);
    expect(plan.last.fireOn, today.addDays(kLatePreArmDays - 1));
  });

  test('not-late-but-past-grace produces nothing extra', () {
    // Estimate 2 days ago: within grace ⇒ not late, window passed.
    final estimate = today.addDays(-2);
    final plan = planReminders(
      today: today,
      predictions: {'p1': _prediction(today: today, estimatedNextStart: estimate)},
    );
    expect(plan, isEmpty);
  });

  test('generic content: title/body carry no names, dates, or digits', () {
    expect(kReminderTitle, 'A reminder from Lunarlog');
    expect(RegExp(r'\d').hasMatch(kReminderTitle + kReminderBody), isFalse);
  });

  test('plan is capped under the iOS 64-notification limit', () {
    // 30 late profiles would want 210 slots; only 60 may pend.
    final predictions = <String, ActivePrediction>{
      for (var i = 0; i < 30; i++)
        'p$i': _prediction(
          today: today,
          estimatedNextStart: today.addDays(-10),
        ),
    };
    final plan = planReminders(today: today, predictions: predictions);
    expect(plan.length, lessThanOrEqualTo(kMaxPendingReminders));
    expect(plan.length, kMaxPendingReminders);
  });

  test('PlannedReminder equality and hashCode are field-wise', () {
    final a = PlannedReminder(
      profileId: 'p1',
      fireOn: today,
      kind: ReminderKind.upcoming,
    );
    final same = PlannedReminder(
      profileId: 'p1',
      fireOn: today,
      kind: ReminderKind.upcoming,
    );
    expect(a, same);
    expect(a.hashCode, same.hashCode);
    expect(a, isNot(PlannedReminder(profileId: 'p2', fireOn: today, kind: ReminderKind.upcoming)));
    expect(a, isNot(PlannedReminder(profileId: 'p1', fireOn: today.addDays(1), kind: ReminderKind.upcoming)));
    expect(a, isNot(PlannedReminder(profileId: 'p1', fireOn: today, kind: ReminderKind.late)));
    expect(
      a,
      isNot(PlannedReminder(
        profileId: 'p1',
        fireOn: today,
        kind: ReminderKind.upcoming,
        timeOfDayMinutes: 10 * 60,
      )),
      reason: 'the fire time-of-day is part of identity (Issue #136)');
    // ignore: unrelated_type_equality_checks
    expect(a == 'not a PlannedReminder', isFalse);
  });

  test('sorted by fire date', () {
    final plan = planReminders(
      today: today,
      predictions: {
        'late': _prediction(today: today, estimatedNextStart: today.addDays(-6)),
        'soon': _prediction(today: today, estimatedNextStart: today.addDays(20)),
      },
    );
    final dates = plan.map((r) => r.fireOn).toList();
    final sorted = [...dates]..sort();
    expect(dates, sorted);
  });

  test('AC5 (issue #221): an unusually-long-cycle profile with a rolled '
      'estimate still gets reminders planned -- the old paused dead end '
      'never went silent, and neither does this', () {
    // A 79-day open cycle (past kMaxOpenCycleDays): the raw estimate is 49
    // days overdue, rolled forward to 6 days out for display -- exactly
    // the shape computePrediction produces once a cycle runs unusually
    // long (prediction_test.dart's own "open cycle beyond 60 days" case).
    final lastEpisodeStart = today.addDays(-78);
    final originalEstimate = today.addDays(-49);
    final rolledEstimate = today.addDays(6);
    final prediction = ActivePrediction(
      today: today,
      lastEpisodeStart: lastEpisodeStart,
      estimatedNextStart: rolledEstimate,
      originalEstimatedNextStart: originalEstimate,
      averagedCycleLengths: const [29, 29, 29],
      meanCycleLengthDays: 29,
      cycleDay: today.difference(lastEpisodeStart) + 1,
      duringEpisode: false,
      completedCycleCount: 4,
      validCycleCount: 4,
      tier: CycleConfidence.irregular,
      unusuallyLongCycle: true,
    );

    final plan = planReminders(
      today: today,
      predictions: {'p1': prediction},
    );

    expect(plan, isNotEmpty,
        reason: 'an unusually-long-cycle prediction must still plan '
            'reminders, not go silent the way the old paused state did');
    expect(plan.every((r) => r.fireOn.difference(today) >= 0), isTrue,
        reason: 'no planned reminder is dated in the past');
  });

  group('care-mode presets (Issue #131, R12)', () {
    // A profile whose estimate is 10 days out (upcoming) for one profile
    // and 6 days past (late) is covered by separate cases below.
    test('a profile with no preset entry plans exactly as before '
        '(ReminderPreset.all fallback)', () {
      final estimate = today.addDays(10);
      final plan = planReminders(
        today: today,
        predictions: {
          'p1': _prediction(today: today, estimatedNextStart: estimate),
        },
        presets: {},
      );
      expect(plan, hasLength(1));
      expect(plan.single.kind, ReminderKind.upcoming);
    });

    test('irregular/teen presets drop the late window but keep upcoming', () {
      final upcoming = _prediction(today: today, estimatedNextStart: today.addDays(10));
      final late = _prediction(today: today, estimatedNextStart: today.addDays(-6));
      for (final preset in [
        const ReminderPreset(upcoming: true, late: false),
      ]) {
        final plan = planReminders(
          today: today,
          predictions: {
            'up': upcoming,
            'late': late,
          },
          presets: {'up': preset, 'late': preset},
        );
        expect(plan, hasLength(1), reason: 'only the upcoming reminder');
        expect(plan.single.kind, ReminderKind.upcoming);
      }
    });

    test('caregiver preset plans nothing (a guardian is not nagged)', () {
      final plan = planReminders(
        today: today,
        predictions: {
          'p1': _prediction(today: today, estimatedNextStart: today.addDays(10)),
          'p2': _prediction(today: today, estimatedNextStart: today.addDays(-6)),
        },
        presets: {
          'p1': ReminderPreset.none,
          'p2': ReminderPreset.none,
        },
      );
      expect(plan, isEmpty);
    });

    test('presets are per profile: standard keeps everything beside a '
        'silenced caregiver profile', () {
      final plan = planReminders(
        today: today,
        predictions: {
          'std': _prediction(today: today, estimatedNextStart: today.addDays(-6)),
          'cg': _prediction(today: today, estimatedNextStart: today.addDays(-6)),
        },
        presets: {
          'std': ReminderPreset.all,
          'cg': ReminderPreset.none,
        },
      );
      expect(plan, hasLength(kLatePreArmDays));
      expect(plan.every((r) => r.profileId == 'std'), isTrue);
    });
  });

  group('per-type configuration (Issue #136, R10/R11)', () {
    test('each type can be turned off independently while others stay on',
        () {
      final latePrediction =
          _prediction(today: today, estimatedNextStart: today.addDays(-6));
      final upcomingOnly = ReminderConfig.standard.copyWith(
        late: ReminderTypeConfig(enabled: false, timeOfDayMinutes: 9 * 60),
      );
      final plan = planReminders(
        today: today,
        predictions: {'p1': latePrediction},
        configs: {'p1': upcomingOnly},
      );
      expect(plan, everyElement(isA<PlannedReminder>()));
      expect(plan.any((r) => r.kind == ReminderKind.late), isFalse,
          reason: 'the late window is off');
      expect(plan.any((r) => r.kind == ReminderKind.upcoming), isFalse,
          reason: 'the -2 moment is in the past for this estimate anyway');
      expect(plan, isEmpty);

      // Flipping only the late switch back on restores just the late
      // window; the log nudge and PMS-watch stay off.
      final lateOnly = ReminderConfig.standard.copyWith(
        upcoming:
            ReminderTypeConfig(enabled: false, leadDays: 2, timeOfDayMinutes: 9 * 60),
      );
      final plan2 = planReminders(
        today: today,
        predictions: {'p1': latePrediction},
        configs: {'p1': lateOnly},
      );
      expect(plan2.map((r) => r.kind), everyElement(ReminderKind.late));
    });

    test('a stored config overrides the preset (teen profile turns late '
        'on)', () {
      final latePrediction =
          _prediction(today: today, estimatedNextStart: today.addDays(-6));
      final plan = planReminders(
        today: today,
        predictions: {'p1': latePrediction},
        presets: {
          'p1': const ReminderPreset(upcoming: true, late: false),
        },
        configs: {'p1': ReminderConfig.standard},
      );
      expect(plan.map((r) => r.kind), everyElement(ReminderKind.late),
          reason: 'the explicit config wins over the mode default');
    });

    test('configured lead days move the upcoming fire date', () {
      final estimate = today.addDays(10);
      final plan = planReminders(
        today: today,
        predictions: {'p1': _prediction(today: today, estimatedNextStart: estimate)},
        configs: {
          'p1': ReminderConfig.standard.copyWith(
            upcoming: ReminderTypeConfig(
                enabled: true, leadDays: 5, timeOfDayMinutes: 9 * 60),
          ),
        },
      );
      expect(plan.single.kind, ReminderKind.upcoming);
      expect(plan.single.fireOn, today.addDays(5),
          reason: 'estimate - 5, not the default - 2');
    });

    test('PMS-watch plans at its own lead days when enabled', () {
      final estimate = today.addDays(10);
      final plan = planReminders(
        today: today,
        predictions: {'p1': _prediction(today: today, estimatedNextStart: estimate)},
        configs: {
          'p1': ReminderConfig.standard.copyWith(
            pms: ReminderTypeConfig(
                enabled: true, leadDays: 6, timeOfDayMinutes: 19 * 60),
          ),
        },
      );
      final pms = plan.where((r) => r.kind == ReminderKind.pms).single;
      expect(pms.fireOn, today.addDays(4));
      expect(pms.timeOfDayMinutes, 19 * 60);
      // The default upcoming (lead 2) plans beside it, not coalesced
      // (different days).
      expect(
        plan.where((r) => r.kind == ReminderKind.upcoming).single.fireOn,
        today.addDays(8),
      );
    });

    test('the daily log nudge plans a bounded forward window, '
        'prediction-independent', () {
      final plan = planReminders(
        today: today,
        predictions: {},
        configs: {
          // No prediction at all — the nudge is most valuable exactly when
          // history is thin — but the config carries the profile id.
          'p1': ReminderConfig.standard.copyWith(
            log: ReminderTypeConfig(enabled: true, timeOfDayMinutes: 20 * 60),
          ),
        },
      );
      expect(plan, hasLength(kLogNudgePreArmDays));
      expect(plan.map((r) => r.kind), everyElement(ReminderKind.log));
      expect(plan.first.fireOn, today);
      expect(plan.last.fireOn, today.addDays(kLogNudgePreArmDays - 1));
      expect(plan.every((r) => r.timeOfDayMinutes == 20 * 60), isTrue);
    });

    test('per-type time-of-day is honored (not the hardcoded 9 AM)', () {
      final estimate = today.addDays(10);
      final plan = planReminders(
        today: today,
        predictions: {'p1': _prediction(today: today, estimatedNextStart: estimate)},
        configs: {
          'p1': ReminderConfig.standard.copyWith(
            upcoming: ReminderTypeConfig(
                enabled: true, leadDays: 2, timeOfDayMinutes: 15 * 60 + 30),
          ),
        },
      );
      expect(plan.single.timeOfDayMinutes, 15 * 60 + 30);
    });

    test('quiet hours shift a fire to the window end instead of dropping '
        'it (R10)', () {
      final estimate = today.addDays(3);
      // Upcoming would fire today+1 at 05:00 — inside a 22:00-07:00
      // wrapping window — so it moves to today+1 at 07:00.
      final plan = planReminders(
        today: today,
        predictions: {'p1': _prediction(today: today, estimatedNextStart: estimate)},
        configs: {
          'p1': ReminderConfig.standard.copyWith(
            upcoming: ReminderTypeConfig(
                enabled: true, leadDays: 2, timeOfDayMinutes: 5 * 60),
            quietHours:
                const QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60),
          ),
        },
      );
      expect(plan.single.fireOn, today.addDays(1));
      expect(plan.single.timeOfDayMinutes, 7 * 60,
          reason: 'shifted to the boundary, never dropped');
    });

    test('same-day duplicates coalesce to the higher-priority kind', () {
      final estimate = today.addDays(4);
      // Upcoming (lead 2) and PMS-watch (lead 2, configured) would both
      // fire today+2: upcoming wins the day (late > upcoming > pms > log).
      final plan = planReminders(
        today: today,
        predictions: {'p1': _prediction(today: today, estimatedNextStart: estimate)},
        configs: {
          'p1': ReminderConfig.standard.copyWith(
            pms: ReminderTypeConfig(
                enabled: true, leadDays: 2, timeOfDayMinutes: 11 * 60),
          ),
        },
      );
      final thatDay = plan.where((r) => r.fireOn == today.addDays(2)).toList();
      expect(thatDay, hasLength(1));
      expect(thatDay.single.kind, ReminderKind.upcoming);
    });

    test('the late window outranks a same-day log nudge', () {
      final plan = planReminders(
        today: today,
        predictions: {
          'p1': _prediction(today: today, estimatedNextStart: today.addDays(-6)),
        },
        configs: {
          'p1': ReminderConfig.standard.copyWith(
            log: ReminderTypeConfig(enabled: true, timeOfDayMinutes: 9 * 60),
          ),
        },
      );
      // Both the late window and the nudge want today at 09:00; the late
      // reminder wins every coalesced day.
      expect(plan, hasLength(kLatePreArmDays));
      expect(plan.map((r) => r.kind), everyElement(ReminderKind.late));
    });

    test('the cap evicts in documented order: late over upcoming over '
        'PMS-watch over log-nudge', () {
      // Two late profiles fill 14 slots and fifty upcoming ones want 50
      // more (64 together) — the cap keeps only late + upcoming, evicting
      // every lower-priority kind before either of them.
      final predictions = <String, ActivePrediction>{
        for (var i = 0; i < 2; i++)
          'late$i': _prediction(
              today: today, estimatedNextStart: today.addDays(-10)),
        for (var i = 0; i < 50; i++)
          'up$i': _prediction(
              today: today, estimatedNextStart: today.addDays(10 + i)),
      };
      final configs = <String, ReminderConfig>{
        for (var i = 0; i < 20; i++)
          'log$i': ReminderConfig.standard.copyWith(
            log: ReminderTypeConfig(
                enabled: true, timeOfDayMinutes: 21 * 60),
          ),
      };
      final plan = planReminders(
        today: today,
        predictions: predictions,
        configs: configs,
      );
      expect(plan.length, kMaxPendingReminders);
      final kinds = plan.map((r) => r.kind).toSet();
      expect(kinds, {ReminderKind.late, ReminderKind.upcoming},
          reason: 'the cap fills with late + upcoming; PMS-watch (none '
              'armed here) and the log nudges are evicted first');
      expect(plan.any((r) => r.kind == ReminderKind.log), isFalse);
    });

    test('notification ids are stable across identical replans and differ '
        'per (profile, kind, date, time)', () {
      final estimate = today.addDays(10);
      final prediction =
          _prediction(today: today, estimatedNextStart: estimate);
      final first = planReminders(
        today: today,
        predictions: {'p1': prediction},
      );
      final second = planReminders(
        today: today,
        predictions: {'p1': prediction},
      );
      expect(first.map((r) => r.id), second.map((r) => r.id),
          reason: 'the same plan re-derives the same ids');

      final otherProfile = planReminders(
        today: today,
        predictions: {'p2': prediction},
      );
      expect(otherProfile.single.id, isNot(first.single.id));

      final otherTime = planReminders(
        today: today,
        predictions: {'p1': prediction},
        configs: {
          'p1': ReminderConfig.standard.copyWith(
            upcoming: ReminderTypeConfig(
                enabled: true, leadDays: 2, timeOfDayMinutes: 10 * 60),
          ),
        },
      );
      expect(otherTime.single.id, isNot(first.single.id));
    });

    test('a "Not yet" snooze suppresses the late window through its end '
        'date', () {
      final latePrediction =
          _prediction(today: today, estimatedNextStart: today.addDays(-6));
      // Snoozed today (set yesterday, running through today): still quiet.
      var plan = planReminders(
        today: today,
        predictions: {'p1': latePrediction},
        configs: {'p1': ReminderConfig.standard},
        lateSnoozes: {'p1': today},
      );
      expect(plan.where((r) => r.kind == ReminderKind.late), isEmpty);

      // Snooze ended yesterday: the window pre-arms again.
      plan = planReminders(
        today: today,
        predictions: {'p1': latePrediction},
        configs: {'p1': ReminderConfig.standard},
        lateSnoozes: {'p1': today.addDays(-1)},
      );
      expect(plan.map((r) => r.kind), everyElement(ReminderKind.late));

      // A three-day snooze set today suppresses today through today+3 and
      // resumes on today+4.
      const snoozeDays = kNotYetSnoozeDays;
      final snoozeEnd = today.addDays(snoozeDays);
      plan = planReminders(
        today: today,
        predictions: {'p1': latePrediction},
        configs: {'p1': ReminderConfig.standard},
        lateSnoozes: {'p1': snoozeEnd},
      );
      expect(plan.where((r) => r.kind == ReminderKind.late), isEmpty,
          reason: 'suppressed through the snooze end');
      final resumed = planReminders(
        today: snoozeEnd.addDays(1),
        predictions: {
          'p1': _prediction(
              today: snoozeEnd.addDays(1),
              estimatedNextStart: today.addDays(-6)),
        },
        configs: {'p1': ReminderConfig.standard},
        lateSnoozes: {'p1': snoozeEnd},
      );
      expect(resumed.map((r) => r.kind), everyElement(ReminderKind.late),
          reason: 'the window re-arms the day after the snooze ends');
    });

    test('estimate shifts re-derive the fire date on the next replan '
        '(transition-driven, not pre-computed)', () {
      final estimate = today.addDays(10);
      final planBefore = planReminders(
        today: today,
        predictions: {'p1': _prediction(today: today, estimatedNextStart: estimate)},
      );
      expect(planBefore.single.fireOn, today.addDays(8));

      // The estimate moves by three days; the next replan (which the
      // coordinator runs on every prediction emission) re-derives from
      // the live estimate.
      final planAfter = planReminders(
        today: today,
        predictions: {
          'p1': _prediction(
              today: today, estimatedNextStart: estimate.addDays(3)),
        },
      );
      expect(planAfter.single.fireOn, today.addDays(11));
    });

    test('becoming late arms the window that did not exist before', () {
      final onTime =
          _prediction(today: today, estimatedNextStart: today.addDays(10));
      expect(
        planReminders(today: today, predictions: {'p1': onTime}),
        hasLength(1),
        reason: 'only the upcoming reminder while on time',
      );
      final nowLate = _prediction(
        today: today,
        estimatedNextStart: onTime.estimatedNextStart.addDays(-16),
      );
      final plan = planReminders(today: today, predictions: {'p1': nowLate});
      expect(plan.map((r) => r.kind), everyElement(ReminderKind.late),
          reason: 'the late transition pre-arms the daily window');
    });
  });
}
