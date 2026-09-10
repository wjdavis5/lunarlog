/// U8 planning tests (KTD7): which reminders should be pending, from live
/// predictions — upcoming window, late pre-arm, cap, generic content.
/// Issue #136 adds the per-type configuration: enable toggles, lead days,
/// per-type time-of-day, quiet hours, same-day coalescing, the eviction
/// order under the cap, stable ids, and the "Not yet" late snooze.
/// Issue #183 adds the birth-control adherence kinds: per-method cadence
/// anchored on the profile's recorded method and its effective dates.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/notifications/birth_control_reminder_kind.dart';
import 'package:lunarlog/domain/notifications/scheduling.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/notification_preferences.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/reminder_presets.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

ActivePrediction _prediction({
  required LocalDate today,
  required LocalDate estimatedNextStart,
  List<PredictedCycle> forecast = const [],
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
    forecast: forecast,
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

  group('issue #178 kinds (period-starting-soon, fertile-window-soon, '
      'cycle-statistic-change)', () {
    // The fertile-window arithmetic the assertions below rely on: the
    // window for a forecast cycle starting at S is S−19..S−13 (#143's
    // fertileWindowFor), so the default 2-day lead fires at S−21.
    List<PredictedCycle> forecastFrom(LocalDate firstStart, {int count = 12}) =>
        [
          for (var i = 1; i <= count; i++)
            PredictedCycle(
              cycleIndex: i,
              start: firstStart.addDays(28 * (i - 1)),
              estimatedPeriodLengthDays: 4,
              tier: CycleConfidence.high,
              spreadDays: 2,
            ),
        ];

    test('all three kinds ship off: the default plan is unchanged', () {
      const config = ReminderConfig.standard;
      expect(config.periodStartingSoon.enabled, isFalse);
      expect(config.fertileWindowSoon.enabled, isFalse);
      expect(config.cycleStatisticChange.enabled, isFalse);
      final plan = planReminders(
        today: today,
        predictions: {
          'p1': _prediction(today: today, estimatedNextStart: today.addDays(10)),
        },
        configs: {'p1': config},
        statisticChangeSignals: {'p1': today},
      );
      expect(plan.map((r) => r.kind), everyElement(ReminderKind.upcoming),
          reason: 'an enabled-by-default signal date still plans nothing '
              'while every #178 kind is off');
    });

    test('AC1: periodStartingSoon is independent of periodDue and fires at '
        'its own longer lead', () {
      final estimate = today.addDays(10);
      final plan = planReminders(
        today: today,
        predictions: {
          'p1': _prediction(today: today, estimatedNextStart: estimate),
        },
        configs: {
          'p1': ReminderConfig.standard.copyWith(
            periodStartingSoon: ReminderTypeConfig(
                enabled: true, leadDays: 4, timeOfDayMinutes: 8 * 60),
          ),
        },
      );
      final soon = plan.where((r) => r.kind == ReminderKind.periodStartingSoon).single;
      expect(soon.fireOn, today.addDays(6),
          reason: 'estimate − 4, not the due reminder\'s − 2');
      expect(soon.timeOfDayMinutes, 8 * 60);
      expect(plan.where((r) => r.kind == ReminderKind.upcoming).single.fireOn,
          today.addDays(8),
          reason: 'the due reminder plans unchanged beside it');
    });

    test('periodStartingSoon fires nothing once its moment has passed', () {
      final plan = planReminders(
        today: today,
        predictions: {
          'p1': _prediction(today: today, estimatedNextStart: today.addDays(2)),
        },
        configs: {
          'p1': ReminderConfig.standard.copyWith(
            periodStartingSoon: ReminderTypeConfig(
                enabled: true, leadDays: 4, timeOfDayMinutes: 9 * 60),
          ),
        },
      );
      expect(plan, isEmpty);
    });

    test('AC2: fertileWindowSoon arms against the next still-ahead window', () {
      // Cycle 1's window start (18 − 19) is already past, so the reminder
      // arms on cycle 2's window instead: start 46 days out → fire at 46 −
      // 21 = 25 days out.
      final plan = planReminders(
        today: today,
        predictions: {
          'p1': _prediction(
            today: today,
            estimatedNextStart: today.addDays(18),
            forecast: forecastFrom(today.addDays(18)),
          ),
        },
        configs: {
          'p1': ReminderConfig.standard.copyWith(
            fertileWindowSoon: ReminderTypeConfig(
                enabled: true, leadDays: 2, timeOfDayMinutes: 10 * 60),
          ),
        },
      );
      final fertile =
          plan.where((r) => r.kind == ReminderKind.fertileWindowSoon).toList();
      expect(fertile, hasLength(1));
      expect(fertile.single.fireOn, today.addDays(25));
      expect(fertile.single.timeOfDayMinutes, 10 * 60);
    });

    test('fertileWindowSoon arms the first cycle when its window is ahead',
        () {
      final plan = planReminders(
        today: today,
        predictions: {
          'p1': _prediction(
            today: today,
            estimatedNextStart: today.addDays(25),
            forecast: forecastFrom(today.addDays(25)),
          ),
        },
        configs: {
          'p1': ReminderConfig.standard.copyWith(
            fertileWindowSoon: ReminderTypeConfig(
                enabled: true, leadDays: 2, timeOfDayMinutes: 9 * 60),
          ),
        },
      );
      expect(
        plan.where((r) => r.kind == ReminderKind.fertileWindowSoon).single,
        isNotNull,
      );
      expect(
        plan.where((r) => r.kind == ReminderKind.fertileWindowSoon).single.fireOn,
        today.addDays(4),
        reason: 'window start 25 − 19 = +6, minus the 2-day lead',
      );
    });

    test('AC2: fertileWindowSoon cannot fire without a computed window', () {
      // No forecast ⇒ no window ⇒ nothing, never a mis-fire against
      // absent data. (The default due reminder still plans.)
      final plan = planReminders(
        today: today,
        predictions: {
          'p1': _prediction(today: today, estimatedNextStart: today.addDays(25)),
        },
        configs: {
          'p1': ReminderConfig.standard.copyWith(
            fertileWindowSoon: ReminderTypeConfig(
                enabled: true, leadDays: 2, timeOfDayMinutes: 9 * 60),
          ),
        },
      );
      expect(
        plan.where((r) => r.kind == ReminderKind.fertileWindowSoon),
        isEmpty,
      );
    });

    test('AC3: the statistic-change reminder fires on the signal date only',
        () {
      ReminderConfig configWith({int minuteOfDay = 12 * 60}) =>
          ReminderConfig.standard.copyWith(
            cycleStatisticChange: ReminderTypeConfig(
                enabled: true, timeOfDayMinutes: minuteOfDay),
          );
      final plan = planReminders(
        today: today,
        predictions: {},
        configs: {'p1': configWith()},
        statisticChangeSignals: {'p1': today},
      );
      expect(plan, hasLength(1));
      expect(plan.single.kind, ReminderKind.cycleStatisticChange);
      expect(plan.single.fireOn, today);
      expect(plan.single.timeOfDayMinutes, 12 * 60);

      // A stale (yesterday's) signal plans nothing.
      expect(
        planReminders(
          today: today,
          predictions: {},
          configs: {'p1': configWith()},
          statisticChangeSignals: {'p1': today.addDays(-1)},
        ),
        isEmpty,
      );
      // Without a signal at all: nothing.
      expect(
        planReminders(
          today: today,
          predictions: {},
          configs: {'p1': configWith()},
        ),
        isEmpty,
      );
    });

    test('a same-day late window outranks the statistic-change nudge '
        '(coalescing)', () {
      final plan = planReminders(
        today: today,
        predictions: {
          'p1': _prediction(
              today: today, estimatedNextStart: today.addDays(-6)),
        },
        configs: {
          'p1': ReminderConfig.standard.copyWith(
            cycleStatisticChange: ReminderTypeConfig(
                enabled: true, timeOfDayMinutes: 9 * 60),
          ),
        },
        statisticChangeSignals: {'p1': today},
      );
      expect(plan.map((r) => r.kind), everyElement(ReminderKind.late),
          reason: 'the late window wins the coalesced day; the stat nudge '
              'does not double up');
    });

    test('the cap still evicts in priority order with the new kinds', () {
      // One late profile (7 daily slots) and sixty period-starting-soon
      // profiles (1 slot each) want 67; one statistic-change nudge wants a
      // 68th. The 60-slot cap keeps late + soon and evicts the
      // statistic-change nudge (priority 5) before either.
      final predictions = <String, ActivePrediction>{
        'late': _prediction(
            today: today, estimatedNextStart: today.addDays(-10)),
        for (var i = 0; i < 60; i++)
          'soon$i': _prediction(
              today: today, estimatedNextStart: today.addDays(30 + i)),
      };
      final configs = <String, ReminderConfig>{
        for (var i = 0; i < 60; i++)
          'soon$i': ReminderConfig.standard.copyWith(
            upcoming:
                ReminderTypeConfig(enabled: false, timeOfDayMinutes: 9 * 60),
            periodStartingSoon: ReminderTypeConfig(
                enabled: true, leadDays: 4, timeOfDayMinutes: 9 * 60),
          ),
        'stat': ReminderConfig.standard.copyWith(
          cycleStatisticChange:
              ReminderTypeConfig(enabled: true, timeOfDayMinutes: 9 * 60),
        ),
      };
      final plan = planReminders(
        today: today,
        predictions: predictions,
        configs: configs,
        statisticChangeSignals: {'stat': today},
      );
      expect(plan.length, kMaxPendingReminders);
      expect(plan.any((r) => r.kind == ReminderKind.cycleStatisticChange),
          isFalse,
          reason: 'statistic-change outranks only the log nudge, so the cap '
              'evicts it before the period-anchored kinds');
      final lateCount = plan.where((r) => r.kind == ReminderKind.late).length;
      final soonCount =
          plan.where((r) => r.kind == ReminderKind.periodStartingSoon).length;
      expect(lateCount, kLatePreArmDays);
      expect(lateCount + soonCount, kMaxPendingReminders);
    });
  });

  group('birth-control adherence reminders (Issue #183)', () {
    /// Every adherence kind on — each test below enables what its scenario
    /// needs so a stray plan proves the gate that let it through.
    ReminderConfig bcConfig() => ReminderConfig.standard.copyWith(
          birthControlPill:
              const ReminderTypeConfig(enabled: true, timeOfDayMinutes: 9 * 60),
          birthControlPatch:
              const ReminderTypeConfig(enabled: true, timeOfDayMinutes: 9 * 60),
          birthControlRing:
              const ReminderTypeConfig(enabled: true, timeOfDayMinutes: 9 * 60),
          birthControlShot:
              const ReminderTypeConfig(enabled: true, timeOfDayMinutes: 9 * 60),
        );

    test('kind/cadence mapping covers exactly the four self-administered '
        'cadences', () {
      expect(birthControlReminderKindFor(BirthControlMethod.pill),
          ReminderKind.birthControlPill);
      expect(birthControlReminderKindFor(BirthControlMethod.patch),
          ReminderKind.birthControlPatch);
      expect(birthControlReminderKindFor(BirthControlMethod.ring),
          ReminderKind.birthControlRing);
      expect(birthControlReminderKindFor(BirthControlMethod.shot),
          ReminderKind.birthControlShot);
      // No user-administered schedule: no kind, no cadence.
      for (final method in [
        BirthControlMethod.none,
        BirthControlMethod.implant,
        BirthControlMethod.hormonalIud,
        BirthControlMethod.copperIud,
        BirthControlMethod.condom,
        BirthControlMethod.other,
        BirthControlMethod.unknown,
      ]) {
        expect(birthControlReminderKindFor(method), isNull,
            reason: '${method.name} must never grow an adherence reminder');
        expect(birthControlCadenceDays(method), isNull);
      }
      expect(birthControlCadenceDays(BirthControlMethod.pill), 1);
      expect(birthControlCadenceDays(BirthControlMethod.patch), 7);
      expect(birthControlCadenceDays(BirthControlMethod.ring), 28);
      expect(birthControlCadenceDays(BirthControlMethod.shot), 84);
    });

    test('the four kinds ship off: a default config plans nothing', () {
      final plan = planReminders(
        today: today,
        predictions: {},
        birthControlModes: {
          'p1': (method: 'pill', startedOn: null, stoppedOn: null),
        },
      );
      expect(plan, isEmpty, reason: 'opt-in kinds, like every #178 kind');
    });

    test('daily pill reminder arms a bounded daily window, no anchor '
        'needed', () {
      final plan = planReminders(
        today: today,
        predictions: {},
        configs: {'p1': bcConfig()},
        birthControlModes: {
          'p1': (method: 'pill', startedOn: '2025-01-01', stoppedOn: null),
        },
      );
      expect(plan, hasLength(kBirthControlPillPreArmDays));
      expect(plan.every((r) => r.kind == ReminderKind.birthControlPill),
          isTrue);
      expect(plan.first.fireOn, today);
      expect(plan.last.fireOn, today.addDays(kBirthControlPillPreArmDays - 1));
      expect(plan.map((r) => r.timeOfDayMinutes), everyElement(9 * 60));
    });

    test('weekly patch reminder anchors on the recorded start date', () {
      // Started exactly one week ago: the first due change is today (n=1).
      final plan = planReminders(
        today: today,
        predictions: {},
        configs: {'p1': bcConfig()},
        birthControlModes: {
          'p1': (
            method: 'patch',
            startedOn: today.addDays(-7).iso,
            stoppedOn: null,
          ),
        },
      );
      expect(plan, hasLength(kBirthControlPreArmOccurrences));
      expect(
          plan.map((r) => r.fireOn).toList(),
          [today, today.addDays(7), today.addDays(14)]);
    });

    test('monthly ring and 12-weekly injection cadences count from the '
        'start date', () {
      // Started today: the first change is one cadence out (n=1), never
      // the start day itself.
      final ring = planReminders(
        today: today,
        predictions: {},
        configs: {'p1': bcConfig()},
        birthControlModes: {
          'p1': (method: 'ring', startedOn: today.iso, stoppedOn: null),
        },
      );
      expect(ring.map((r) => r.fireOn).toList(),
          [today.addDays(28), today.addDays(56), today.addDays(84)]);
      final shot = planReminders(
        today: today,
        predictions: {},
        configs: {'p1': bcConfig()},
        birthControlModes: {
          'p1': (method: 'shot', startedOn: today.iso, stoppedOn: null),
        },
      );
      expect(shot.map((r) => r.fireOn).toList(),
          [today.addDays(84), today.addDays(168), today.addDays(252)]);
    });

    test('past due dates are not re-fired retroactively; the next three '
        'forward dates are armed', () {
      // Started 30 days ago, weekly patch: n=1..4 are past; n=5 is
      // startedOn+35 = today+5.
      final plan = planReminders(
        today: today,
        predictions: {},
        configs: {'p1': bcConfig()},
        birthControlModes: {
          'p1': (
            method: 'patch',
            startedOn: today.addDays(-30).iso,
            stoppedOn: null,
          ),
        },
      );
      expect(plan.map((r) => r.fireOn).toList(),
          [today.addDays(5), today.addDays(12), today.addDays(19)]);
    });

    test('an anchor-based kind without a recorded start date plans '
        'nothing', () {
      final plan = planReminders(
        today: today,
        predictions: {},
        configs: {'p1': bcConfig()},
        birthControlModes: {
          'p1': (method: 'patch', startedOn: null, stoppedOn: null),
        },
      );
      expect(plan, isEmpty,
          reason: 'no knowable due date; never invent an anchor');
    });

    test('implant and IUD never plan a reminder, even with every kind '
        'enabled', () {
      for (final method in ['implant', 'hormonal_iud', 'copper_iud']) {
        final plan = planReminders(
          today: today,
          predictions: {},
          configs: {'p1': bcConfig()},
          birthControlModes: {
            'p1': (
              method: method,
              startedOn: today.addDays(-10).iso,
              stoppedOn: null,
            ),
          },
        );
        expect(plan, isEmpty,
            reason: '$method is not user-administered on a schedule');
      }
    });

    test('a method recorded as none/unknown plans nothing', () {
      for (final stored in ['none', 'condom', 'other', 'something_new']) {
        final plan = planReminders(
          today: today,
          predictions: {},
          configs: {'p1': bcConfig()},
          birthControlModes: {
            'p1': (method: stored, startedOn: today.iso, stoppedOn: null),
          },
        );
        expect(plan, isEmpty, reason: '$stored has no adherence cadence');
      }
    });

    test('a method whose stop date has passed plans nothing', () {
      final plan = planReminders(
        today: today,
        predictions: {},
        configs: {'p1': bcConfig()},
        birthControlModes: {
          'p1': (
            method: 'pill',
            startedOn: today.addDays(-30).iso,
            stoppedOn: today.iso,
          ),
        },
      );
      expect(plan, isEmpty, reason: 'stopped today means not in effect');
    });

    test('changing the recorded method re-routes the reminder: nothing '
        'stale survives a replan', () {
      final onPill = planReminders(
        today: today,
        predictions: {},
        configs: {'p1': bcConfig()},
        birthControlModes: {
          'p1': (method: 'pill', startedOn: null, stoppedOn: null),
        },
      );
      expect(onPill.map((r) => r.kind),
          everyElement(ReminderKind.birthControlPill));
      final onPatch = planReminders(
        today: today,
        predictions: {},
        configs: {'p1': bcConfig()},
        birthControlModes: {
          'p1': (method: 'patch', startedOn: today.iso, stoppedOn: null),
        },
      );
      expect(onPatch.map((r) => r.kind),
          everyElement(ReminderKind.birthControlPatch),
          reason: 'the pill kind vanished with the method; the patch kind '
              'appeared without a config edit');
    });

    test('birth-control kinds are prediction-independent', () {
      final plan = planReminders(
        today: today,
        predictions: {},
        configs: {'p1': bcConfig()},
        birthControlModes: {
          'p1': (method: 'pill', startedOn: null, stoppedOn: null),
        },
      );
      expect(plan, isNotEmpty,
          reason: 'an adherence reminder is exactly what a profile with '
              'thin history still needs');
    });

    test('quiet hours shift a birth-control fire like any other', () {
      final config = ReminderConfig.standard.copyWith(
        birthControlPatch:
            const ReminderTypeConfig(enabled: true, timeOfDayMinutes: 9 * 60),
        quietHours:
            const QuietHours(startMinutes: 8 * 60, endMinutes: 12 * 60),
      );
      final plan = planReminders(
        today: today,
        predictions: {},
        configs: {'p1': config},
        birthControlModes: {
          'p1': (method: 'patch', startedOn: today.iso, stoppedOn: null),
        },
      );
      expect(
          plan.map((r) => r.fireOn).toList(),
          [today.addDays(7), today.addDays(14), today.addDays(21)],
          reason: 'all three occurrences keep their dates');
      expect(plan.map((r) => r.timeOfDayMinutes), everyElement(12 * 60),
          reason: '09:00 sits inside 08:00-12:00, so every fire shifts to '
              'the boundary');
    });

    test('on a shared fire date the adherence reminder outranks the log '
        'nudge', () {
      final plan = planReminders(
        today: today,
        predictions: {},
        configs: {
          'p1': bcConfig().copyWith(
            log:
                const ReminderTypeConfig(enabled: true, timeOfDayMinutes: 9 * 60),
          ),
        },
        birthControlModes: {
          'p1': (method: 'pill', startedOn: null, stoppedOn: null),
        },
      );
      final todayPlan =
          plan.where((r) => r.fireOn == today).toList(growable: false);
      expect(todayPlan, hasLength(1),
          reason: 'same-day duplicates coalesce per profile');
      expect(todayPlan.single.kind, ReminderKind.birthControlPill);
    });

    test('a malformed start date degrades to no anchor, never a crash', () {
      final plan = planReminders(
        today: today,
        predictions: {},
        configs: {'p1': bcConfig()},
        birthControlModes: {
          'p1': (method: 'patch', startedOn: 'not-a-date', stoppedOn: null),
        },
      );
      expect(plan, isEmpty);
    });
  });
}
