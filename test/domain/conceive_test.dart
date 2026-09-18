/// Issue #204 (Conceive mode): the pure DOT-equivalent conception
/// estimator — the cited per-day probability curve, the ovulation
/// back-calculation, the current-window walk, and the mode's category
/// ordering — plus the safety regression the issue demands: logging an
/// ovulation test or a discharge/BBT reading never moves the curve.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/conceive.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/fertile_window.dart'
    show kDefaultLutealPhaseDays;
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/tags.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

final DateTime _stamp = DateTime.utc(2026, 1, 1);

/// One bleed day (flow-carrying) — the only kind of row the estimator is
/// allowed to read.
DayEntry _bleed(LocalDate date, {List<String> tags = const []}) => DayEntry(
      id: 'bleed-${date.iso}',
      profileId: 'p',
      localDate: date,
      tz: 'UTC',
      flow: FlowLevel.medium,
      tags: tags,
      updatedAt: _stamp,
    );

/// One non-bleed logging row (an ovulation test, discharge, a BBT note) —
/// present in history, deliberately carrying a non-bleeding flow so it can
/// never be mistaken for a cycle start.
DayEntry _signal(
  LocalDate date, {
  List<String> tags = const [],
  String? note,
}) =>
    DayEntry(
      id: 'signal-${date.iso}',
      profileId: 'p',
      localDate: date,
      tz: 'UTC',
      flow: FlowLevel.notBleeding,
      tags: tags,
      note: note,
      updatedAt: _stamp,
    );

/// Five steady 28-day bleed starts (four completed cycles — above
/// [kMinCompletedValidCycles]), the last open cycle starting 2026-04-23.
final List<LocalDate> _starts = [
  d(2026, 1, 1),
  d(2026, 1, 29),
  d(2026, 2, 26),
  d(2026, 3, 26),
  d(2026, 4, 23),
];

/// A today just after the open cycle's start: the forecast's first window
/// (2026-05-02 … 2026-05-08) is still current.
final LocalDate _today = d(2026, 5, 5);

void expectSameEstimate(ConceptionEstimate? a, ConceptionEstimate? b) {
  expect(a.toString(), b.toString());
}

void main() {
  group('kConceptionProbabilityByDayOffset (the cited curve)', () {
    test('peaks on the estimated ovulation day and covers ovulation -5 … +1',
        () {
      expect(kConceptionProbabilityByDayOffset.keys.toList(),
          [-5, -4, -3, -2, -1, 0, 1]);
      expect(kConceptionProbabilityByDayOffset[0], 0.33);
      expect(
        kConceptionProbabilityByDayOffset.values
            .reduce((a, b) => a > b ? a : b),
        0.33,
        reason: 'the study peaks at ovulation, not before or after',
      );
    });

    test('the window bounds are the same lead/trail span as #143', () {
      expect(kConceptionProbabilityByDayOffset.keys.first, -5);
      expect(kConceptionProbabilityByDayOffset.keys.last, 1);
    });
  });

  group('conceptionEstimateFor', () {
    test('back-calculates ovulation from the next period start minus the '
        'assumed luteal phase, and lands each cited day on its civil date',
        () {
      final estimate = conceptionEstimateFor(
        nextPeriodStart: d(2026, 5, 21),
        tier: CycleConfidence.high,
      );
      expect(estimate.estimatedOvulation,
          d(2026, 5, 21).addDays(-kDefaultLutealPhaseDays));
      expect(estimate.estimatedOvulation, d(2026, 5, 7));
      expect(estimate.fertileWindowStart, d(2026, 5, 2));
      expect(estimate.fertileWindowEnd, d(2026, 5, 8));
      expect(estimate.peakDay, estimate.estimatedOvulation);
      expect(estimate.peakProbability, 0.33);
      expect(estimate.tier, CycleConfidence.high);
      expect(estimate.days, hasLength(7));
      expect(estimate.days.first.date, estimate.fertileWindowStart);
      expect(estimate.days.last.date, estimate.fertileWindowEnd);
      for (final day in estimate.days) {
        expect(day.probability,
            kConceptionProbabilityByDayOffset[
                day.date.difference(estimate.estimatedOvulation)]);
      }
    });

    test('carries the caller\'s tier through unchanged (never a second '
        'confidence vocabulary, the #213/#143 rule)', () {
      final estimate = conceptionEstimateFor(
        nextPeriodStart: d(2026, 5, 21),
        tier: CycleConfidence.irregular,
      );
      expect(estimate.tier, CycleConfidence.irregular);
    });
  });

  group('currentConceptionEstimate', () {
    test('returns the first forecast window that has not passed', () {
      final prediction = computePredictionFromEntries(
        entries: [for (final start in _starts) _bleed(start)],
        today: _today,
      ) as ActivePrediction;
      final estimate = currentConceptionEstimate(prediction);
      expect(estimate, isNotNull);
      expect(estimate!.fertileWindowEnd.isBefore(_today), isFalse,
          reason: 'the returned window must still be current');
    });

    test('null for a null prediction and for a regimen-schedule basis', () {
      expect(currentConceptionEstimate(null), isNull);
      final pack = ActivePrediction(
        today: _today,
        lastEpisodeStart: d(2026, 4, 23),
        estimatedNextStart: d(2026, 5, 21),
        originalEstimatedNextStart: d(2026, 5, 21),
        averagedCycleLengths: const [28, 28, 28],
        meanCycleLengthDays: 28,
        cycleDay: 13,
        duringEpisode: false,
        completedCycleCount: 4,
        validCycleCount: 4,
        basis: PredictionBasis.regimenSchedule,
      );
      expect(currentConceptionEstimate(pack), isNull);
      expect(conceiveEstimateFromHistory(entries: const [], today: _today),
          isNull);
    });
  });

  group('conceiveEstimateFromHistory', () {
    test('computes a curve from period start dates alone', () {
      final estimate = conceiveEstimateFromHistory(
        entries: [for (final start in _starts) _bleed(start)],
        today: _today,
      );
      expect(estimate, isNotNull);
      expect(estimate!.estimatedOvulation, d(2026, 5, 7));
      expect(estimate.fertileWindowStart, d(2026, 5, 2));
      expect(estimate.fertileWindowEnd, d(2026, 5, 8));
    });

    test('a different bleed history produces a different curve', () {
      final a = conceiveEstimateFromHistory(
        entries: [for (final start in _starts) _bleed(start)],
        today: _today,
      );
      final b = conceiveEstimateFromHistory(
        entries: [
          for (final start in [
            d(2026, 1, 1),
            d(2026, 1, 31),
            d(2026, 3, 2),
            d(2026, 4, 1),
          ])
            _bleed(start),
        ],
        today: _today,
      );
      expect(a.toString(), isNot(b.toString()));
    });
  });

  group('logging a test or discharge/BBT signal never moves the curve '
      '(Issue #204 safety regression)', () {
    final plain = [for (final start in _starts) _bleed(start)];

    test('a positive ovulation test logged mid-cycle changes nothing', () {
      final tested = [
        ...plain,
        _signal(d(2026, 5, 6),
            tags: const ['ovulation_positive', 'ovulation_peak']),
        _signal(d(2026, 5, 3), tags: const ['ovulation_negative']),
      ];
      expectSameEstimate(
        conceiveEstimateFromHistory(entries: plain, today: _today),
        conceiveEstimateFromHistory(entries: tested, today: _today),
      );
    });

    test('discharge categories change nothing', () {
      final tested = [
        ...plain,
        _signal(d(2026, 5, 4),
            tags: const ['discharge_egg_white', 'discharge_creamy']),
      ];
      expectSameEstimate(
        conceiveEstimateFromHistory(entries: plain, today: _today),
        conceiveEstimateFromHistory(entries: tested, today: _today),
      );
    });

    test('a BBT reading is not an input at all — the estimator takes '
        'entries only, and entries carry no BBT', () {
      // BBT lives in `observations`; neither `conceiveEstimateFromHistory`
      // nor the prediction stack it delegates to accepts observations. The
      // only history this seam can see is the flow-carrying day entries, so
      // a logged BBT reading cannot reach it. A non-bleeding entry whose
      // note mentions a temperature stands in for "the row exists" here.
      final withBbtNote = [
        ...plain,
        _signal(d(2026, 5, 4), note: 'bbt 36.7 C'),
      ];
      expectSameEstimate(
        conceiveEstimateFromHistory(entries: plain, today: _today),
        conceiveEstimateFromHistory(entries: withBbtNote, today: _today),
      );
    });

    test('the underlying predictor ignores the same tags, so the result is '
        'structural, not a coincidence of this one call site', () {
      final base = computePredictionFromEntries(
          entries: plain, today: _today) as ActivePrediction;
      final tagged = computePredictionFromEntries(
        entries: [
          ...plain,
          _signal(d(2026, 5, 6),
              tags: const ['ovulation_positive', 'ovulation_peak']),
        ],
        today: _today,
      ) as ActivePrediction;
      expect(tagged.estimatedNextStart, base.estimatedNextStart);
      expect(tagged.meanCycleLengthDays, base.meanCycleLengthDays);
    });
  });

  group('ConceptionDayLikelihood value semantics', () {
    test('equality and hashCode follow date + probability, never identity',
        () {
      final a = ConceptionDayLikelihood(date: d(2026, 5, 7), probability: 0.3);
      final same =
          ConceptionDayLikelihood(date: d(2026, 5, 7), probability: 0.3);
      final otherDay =
          ConceptionDayLikelihood(date: d(2026, 5, 8), probability: 0.3);
      final otherProbability =
          ConceptionDayLikelihood(date: d(2026, 5, 7), probability: 0.2);
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a == otherDay, isFalse);
      expect(a == otherProbability, isFalse);
      expect(a == Object(), isFalse);
      expect(a.toString(), contains(d(2026, 5, 7).iso));
      expect(a.toString(), contains('0.3'));
    });
  });

  group('conceiveCategoryOrder (AC5)', () {
    test('surfaces Tests then Discharge first, in that order', () {
      expect(kConceivePriorityCategories,
          [TagCategory.tests, TagCategory.discharge]);
      final ordered = conceiveCategoryOrder(TagCategory.values);
      expect(ordered.take(2).toList(),
          [TagCategory.tests, TagCategory.discharge]);
    });

    test('is a permutation — every category kept, nothing added', () {
      final ordered = conceiveCategoryOrder(TagCategory.values);
      expect(ordered, hasLength(TagCategory.values.length));
      expect(ordered.toSet(), TagCategory.values.toSet());
    });

    test('keeps the relative order of every non-priority category', () {
      final standard = TagCategory.values;
      final ordered = conceiveCategoryOrder(standard);
      final rest = ordered
          .where((c) => !kConceivePriorityCategories.contains(c))
          .toList();
      final expectedRest = standard
          .where((c) => !kConceivePriorityCategories.contains(c))
          .toList();
      expect(rest, expectedRest);
    });

    test('is idempotent and tolerant of a list that already lacks both', () {
      final once = conceiveCategoryOrder(TagCategory.values);
      expect(conceiveCategoryOrder(once), once);
      expect(conceiveCategoryOrder(const [TagCategory.pain]),
          const [TagCategory.pain]);
    });
  });
}
