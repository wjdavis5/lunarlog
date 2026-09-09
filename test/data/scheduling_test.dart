/// U8 planning tests (KTD7): which reminders should be pending, from live
/// predictions — upcoming window, late pre-arm, cap, generic content.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/scheduling.dart';
import 'package:lunarlog/domain/models/local_date.dart';
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
}
