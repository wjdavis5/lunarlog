/// Per-reminder custom notification text (Issue #184): the resolver's
/// fallback and verbatim behavior, and — the issue's hard constraint —
/// the discretion invariant that no code path ever concatenates a profile
/// name or a date into notification text, default or custom.
///
/// The invariant is pinned two ways:
///
/// * structurally, `resolveReminderText` accepts *only* a
///   [ReminderTypeConfig] — there is no profile, name, or date parameter
///   anywhere on the one resolver every reminder's presentation text
///   flows through;
/// * behaviorally, the DISCRETION PIN tests below feed a name-bearing
///   profile id and a dated plan through [planReminders] and assert the
///   built text equals the configured strings verbatim — nothing added,
///   nothing interpolated.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/scheduling.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

ActivePrediction _prediction({
  required LocalDate today,
  required LocalDate estimatedNextStart,
}) {
  final lastStart = estimatedNextStart.addDays(-28);
  return ActivePrediction(
    today: today,
    lastEpisodeStart: lastStart,
    estimatedNextStart: estimatedNextStart,
    originalEstimatedNextStart: estimatedNextStart,
    averagedCycleLengths: const [28],
    meanCycleLengthDays: 28,
    cycleDay: today.difference(lastStart) + 1,
    duringEpisode: false,
    completedCycleCount: 4,
    validCycleCount: 4,
    forecast: const [],
    pms: null,
    basis: PredictionBasis.statistical,
  );
}

void main() {
  group('resolveReminderText fallback (AC: no type is left without valid text)', () {
    test('unset custom title and body resolve to the generic defaults', () {
      final text = resolveReminderText(ReminderTypeConfig.upcoming);
      expect(text.title, kReminderTitle);
      expect(text.body, kReminderBody);
    });

    test('a blank custom value resolves to the generic default', () {
      final text = resolveReminderText(
        ReminderTypeConfig.upcoming.copyWith(
          customTitle: '   ',
          customBody: ' \n\t ',
          clearCustomTitle: false,
          clearCustomBody: false,
        ),
      );
      expect(text.title, kReminderTitle);
      expect(text.body, kReminderBody);
    });

    test('custom title and body resolve verbatim — trimmed, never edited', () {
      final text = resolveReminderText(
        ReminderTypeConfig.upcoming.copyWith(
          customTitle: '  Tea time  ',
          customBody: 'Bring the blue bottle.',
        ),
      );
      expect(text.title, 'Tea time');
      expect(text.body, 'Bring the blue bottle.');
    });

    test('title and body resolve independently (custom title, default body)', () {
      final text = resolveReminderText(
        ReminderTypeConfig.upcoming.copyWith(customTitle: 'Check in'),
      );
      expect(text.title, 'Check in');
      expect(text.body, kReminderBody);
    });

    test('ReminderText is a value type (equality covers both halves)', () {
      const a = ReminderText(title: 'T', body: 'B');
      expect(a, const ReminderText(title: 'T', body: 'B'));
      expect(a, isNot(const ReminderText(title: 'T2', body: 'B')));
      expect(a, isNot(const ReminderText(title: 'T', body: 'B2')));
      expect(a, isNot('T B'));
      expect(a.hashCode, const ReminderText(title: 'T', body: 'B').hashCode);
    });
  });

  group('DISCRETION PIN: built notification text never carries a profile '
      'name or a date (Issue #184 hard constraint)', () {
    final today = LocalDate(2026, 8, 30);

    // A plan whose inputs all but beg to leak: the profile id is a name,
    // the estimate is a dated moment.
    List<PlannedReminder> planFor(ReminderConfig config) => planReminders(
          today: today,
          predictions: {
            'Alice (14)': _prediction(
              today: today,
              estimatedNextStart: today.addDays(10),
            ),
          },
          configs: {'Alice (14)': config},
        );

    test('default text: every planned reminder carries the generic strings '
        'verbatim — no profile name, no date digits', () {
      final plan = planFor(ReminderConfig.standard);

      expect(plan, isNotEmpty);
      for (final reminder in plan) {
        expect(reminder.title, kReminderTitle,
            reason: '${reminder.kind} title must be the generic default');
        expect(reminder.body, kReminderBody,
            reason: '${reminder.kind} body must be the generic default');
        expect(reminder.title.contains('Alice'), isFalse);
        expect(reminder.body.contains('Alice'), isFalse);
        expect(RegExp(r'\d').hasMatch(reminder.title + reminder.body),
            isFalse,
            reason: 'a date (or any digit) leaked into ${reminder.kind}');
      }
    });

    test('custom text: every planned reminder carries exactly the '
        'configured strings — the profile name and the fire dates the '
        'planner knew never reach the built text', () {
      const customTitle = 'A little heads-up';
      const customBody = 'Nothing to see here.';
      final plan = planFor(
        ReminderConfig.standard.copyWith(
          upcoming: ReminderTypeConfig.upcoming
              .copyWith(customTitle: customTitle, customBody: customBody),
          late: ReminderTypeConfig.late.copyWith(
              customTitle: customTitle, customBody: customBody),
        ),
      );

      expect(plan, isNotEmpty);
      for (final reminder in plan) {
        expect(reminder.title, customTitle,
            reason: '${reminder.kind} title must equal the configured '
                'string verbatim — nothing concatenated');
        expect(reminder.body, customBody,
            reason: '${reminder.kind} body must equal the configured '
                'string verbatim — nothing concatenated');
      }
    });

    test('per-type independence in the plan: a customized type carries its '
        'own text while every other type keeps the generic defaults', () {
      final plan = planFor(
        ReminderConfig.standard.copyWith(
          upcoming: ReminderTypeConfig.upcoming.copyWith(
              customTitle: 'Due-soon title', customBody: 'Due-soon body'),
          // The log nudge is prediction-independent, so the same plan
          // carries a second (never-customized) type alongside upcoming.
          log: const ReminderTypeConfig(
              enabled: true, timeOfDayMinutes: 9 * 60),
        ),
      );

      final kinds = plan.map((r) => r.kind).toSet();
      expect(kinds, contains(ReminderKind.upcoming),
          reason: 'fixture must plan both a customized and a default type');
      expect(kinds, contains(ReminderKind.log));
      for (final reminder in plan) {
        if (reminder.kind == ReminderKind.upcoming) {
          expect(reminder.title, 'Due-soon title');
          expect(reminder.body, 'Due-soon body');
        } else {
          expect(reminder.title, kReminderTitle,
              reason: '${reminder.kind} was never customized');
          expect(reminder.body, kReminderBody);
        }
      }
    });

    test('per-profile separation: two profiles on one device plan '
        'independent text for the same kind', () {
      final estimate = today.addDays(10);
      final plan = planReminders(
        today: today,
        predictions: {
          'alice': _prediction(today: today, estimatedNextStart: estimate),
          'bea': _prediction(today: today, estimatedNextStart: estimate),
        },
        configs: {
          'alice': ReminderConfig.standard.copyWith(
            upcoming: ReminderTypeConfig.upcoming.copyWith(
                customTitle: 'Alice-only title',
                customBody: 'Alice-only body'),
          ),
          // Bea has no stored config: her reminder keeps the defaults.
        },
      );

      final alice =
          plan.singleWhere((r) => r.profileId == 'alice' && r.kind == ReminderKind.upcoming);
      final bea =
          plan.singleWhere((r) => r.profileId == 'bea' && r.kind == ReminderKind.upcoming);
      expect(alice.title, 'Alice-only title');
      expect(alice.body, 'Alice-only body');
      expect(bea.title, kReminderTitle,
          reason: 'Bea never configured custom text');
      expect(bea.body, kReminderBody);
    });

    test('the generic defaults themselves contain no name-shaped or '
        'date-shaped content', () {
      expect(RegExp(r'\d').hasMatch(kReminderTitle + kReminderBody), isFalse);
      expect(kReminderTitle, isNot(contains('Lunarlog (')));
    });
  });
}
