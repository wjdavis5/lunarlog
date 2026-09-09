/// Tests for Issue #220's PMS phase derivation (`lib/domain/prediction
/// /pms.dart`): interval derivation from the first-class day-entry marker,
/// the 6-cycle (`kAverageWindowCycles`) onset/length averages, the hard
/// 3-logged-interval minimum below which nothing is predicted, the clamp
/// that keeps an interval's counted length inside its onset, the tier
/// carried through from the period estimate, and the band anchoring.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/pms.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

LocalDate _d(int y, int m, int day) => LocalDate(y, m, day);

DayEntry _entry(String profileId, LocalDate date,
        {bool pms = false, FlowLevel flow = FlowLevel.none}) =>
    DayEntry(
      id: '',
      profileId: profileId,
      localDate: date,
      tz: 'America/Chicago',
      flow: flow,
      pms: pms,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Episode _episode(LocalDate start, int lengthDays) =>
    Episode(start, start.addDays(lengthDays - 1));

void main() {
  group('pmsDatesOf', () {
    test('collects live marked days and skips tombstones and unmarked days',
        () {
      final entries = [
        _entry('p', _d(2026, 8, 1), pms: true),
        _entry('p', _d(2026, 8, 2)),
        _entry('p', _d(2026, 8, 3), pms: true,
            flow: FlowLevel.medium),
        DayEntry(
          id: '',
          profileId: 'p',
          localDate: _d(2026, 8, 4),
          tz: 'America/Chicago',
          flow: FlowLevel.none,
          pms: true,
          updatedAt: DateTime.utc(2026, 1, 1),
          deletedAt: DateTime.utc(2026, 1, 2),
        ),
      ];
      expect(
        pmsDatesOf(entries),
        {_d(2026, 8, 1), _d(2026, 8, 3)},
      );
    });
  });

  group('derivePmsIntervals', () {
    test('merges consecutive days, splits at any gap, ignores order', () {
      final intervals = derivePmsIntervals([
        _d(2026, 8, 5),
        _d(2026, 8, 3),
        _d(2026, 8, 4), // 3–5 consecutive
        _d(2026, 8, 8), // a one-day gap (8/7 missing) splits — no bleed-style merge
        _d(2026, 8, 8), // duplicate ignored
      ]);
      expect(intervals, [
        PmsInterval(_d(2026, 8, 3), _d(2026, 8, 5)),
        PmsInterval(_d(2026, 8, 8), _d(2026, 8, 8)),
      ]);
      expect(intervals.first.lengthDays, 3);
    });

    test('empty input yields no intervals', () {
      expect(derivePmsIntervals(const []), isEmpty);
    });
  });

  group('usablePmsIntervals', () {
    test('attributes each interval to the next episode start and clamps '
        'length to onset', () {
      // Periods: Aug 1–4, Sep 1–4. The Aug 28–Sep 1 interval starts 4 days
      // before Sep 1; its 5-day length clamps to that 4-day onset so the
      // counted span can never overlap the period itself.
      final episodes = [
        _episode(_d(2026, 8, 1), 4),
        _episode(_d(2026, 9, 1), 4),
      ];
      final usable = usablePmsIntervals(
        episodes: episodes,
        intervalList: [PmsInterval(_d(2026, 8, 28), _d(2026, 9, 1))],
      );
      expect(usable, hasLength(1));
      expect(usable.single.followingPeriodStart, _d(2026, 9, 1));
      expect(usable.single.onsetDays, 4);
      expect(usable.single.lengthDays, 4, reason: 'clamped from 5');
    });

    test('skips intervals with no following period (open cycle) and '
        'intervals starting on/after the following period start', () {
      final episodes = [_episode(_d(2026, 8, 1), 4)];
      final usable = usablePmsIntervals(
        episodes: episodes,
        intervalList: [
          PmsInterval(_d(2026, 9, 10), _d(2026, 9, 11)), // no following episode
          PmsInterval(_d(2026, 8, 1), _d(2026, 8, 2)), // starts on the period
        ],
      );
      expect(usable, isEmpty);
    });
  });

  group('computePmsEstimate', () {
    // Three cycles: Aug, Sep, Oct period starts on the 1st (30-day steps).
    // PMS runs the 3 days before each period starts, plus 2 more days
    // earlier in the month to keep the intervals strictly premenstrual.
    List<Episode> episodesOf(List<LocalDate> starts) =>
        [for (final start in starts) _episode(start, 4)];

    Set<LocalDate> pmsOf(List<LocalDate> periodStarts, {int onset = 3}) => {
          for (final start in periodStarts)
            for (var i = 1; i <= onset; i++) start.addDays(-i),
        };

    test('averages onset and length over the logged intervals and anchors '
        'the band before the next predicted start', () {
      final starts = [_d(2026, 8, 1), _d(2026, 8, 31), _d(2026, 9, 30)];
      final estimate = computePmsEstimate(
        episodes: episodesOf(starts),
        pmsDates: pmsOf(starts),
        nextPredictedStart: _d(2026, 10, 30),
        tier: CycleConfidence.high,
      );
      expect(estimate, isNotNull);
      expect(estimate!.usableIntervalCount, 3);
      expect(estimate.meanOnsetDaysBeforeNextPeriod, 3);
      expect(estimate.meanLengthDays, 3);
      expect(estimate.predictedStart, _d(2026, 10, 27));
      expect(estimate.predictedEnd, _d(2026, 10, 29));
      expect(estimate.predictedEnd.isBefore(_d(2026, 10, 30)), isTrue,
          reason: 'the band never overlaps the predicted period itself');
    });

    test('the hard minimum: fewer than 3 usable intervals predicts nothing',
        () {
      final starts = [_d(2026, 8, 1), _d(2026, 8, 31), _d(2026, 9, 30)];
      final estimate = computePmsEstimate(
        episodes: episodesOf(starts),
        pmsDates: pmsOf(starts.take(2).toList()),
        nextPredictedStart: _d(2026, 10, 30),
        tier: CycleConfidence.learning,
      );
      expect(estimate, isNull,
          reason: 'below kMinPmsIntervalsForPrediction: no band, no averages');
    });

    test('averages use only the most recent kAverageWindowCycles intervals',
        () {
      // Eight monthly period starts (Mar 1 … Oct 1), each preceded by a
      // 2-day PMS interval (onset 2), plus one stale 4-day interval 14
      // days before the oldest period. Nine usable intervals; the average
      // window holds only the six most recent, so the stale onset-14
      // interval must not move the means.
      final monthly = [
        _d(2026, 3, 1),
        _d(2026, 4, 1),
        _d(2026, 5, 1),
        _d(2026, 6, 1),
        _d(2026, 7, 1),
        _d(2026, 8, 1),
        _d(2026, 9, 1),
        _d(2026, 10, 1),
      ];
      final dates = <LocalDate>{
        for (final start in monthly)
          for (var i = 1; i <= 2; i++) start.addDays(-i),
        _d(2026, 2, 15),
        _d(2026, 2, 16),
        _d(2026, 2, 17),
        _d(2026, 2, 18),
      };
      final estimate = computePmsEstimate(
        episodes: episodesOf(monthly),
        pmsDates: dates,
        nextPredictedStart: _d(2026, 10, 31),
        tier: CycleConfidence.learning,
      );
      expect(estimate!.usableIntervalCount, kAverageWindowCycles);
      expect(estimate.meanOnsetDaysBeforeNextPeriod, 2,
          reason: 'the stale 14-day interval sits outside the 6-window');
    });

    test('carries the period estimate tier through verbatim (no second '
        'confidence vocabulary)', () {
      final starts = [_d(2026, 8, 1), _d(2026, 8, 31), _d(2026, 9, 30)];
      for (final tier in CycleConfidence.values) {
        final estimate = computePmsEstimate(
          episodes: episodesOf(starts),
          pmsDates: pmsOf(starts),
          nextPredictedStart: _d(2026, 10, 30),
          tier: tier,
        );
        expect(estimate!.tier, tier);
      }
    });
  });

  group('computePredictionFromEntries integration', () {
    test('an ActivePrediction carries the PMS estimate from the entries',
        () {
      final entries = <DayEntry>[
        // Three 30-day cycles (Aug 1, Aug 31, Sep 30), 4 bleed days each.
        for (final start in [_d(2026, 8, 1), _d(2026, 8, 31), _d(2026, 9, 30)])
          for (var i = 0; i < 4; i++) _entry('p', start.addDays(i), flow: FlowLevel.medium),
        // A fourth cycle closing Oct 30 so the estimate is complete and
        // three PMS intervals each have a following period.
        for (var i = 0; i < 4; i++)
          _entry('p', _d(2026, 10, 30).addDays(i), flow: FlowLevel.medium),
        // PMS: the 3 days before each of the Aug 31 / Sep 30 / Oct 30
        // periods (the Aug 1 period has no predecessor, so only three
        // intervals are usable — exactly the minimum).
        for (final start in [_d(2026, 8, 31), _d(2026, 9, 30), _d(2026, 10, 30)])
          for (var i = 1; i <= 3; i++)
            _entry('p', start.addDays(-i), pms: true),
      ];
      final prediction = computePredictionFromEntries(
        entries: entries,
        today: _d(2026, 11, 5),
      ) as ActivePrediction;
      expect(prediction.pms, isNotNull);
      expect(prediction.pms!.usableIntervalCount, 3);
      expect(prediction.pms!.tier, prediction.tier);
      expect(prediction.pms!.predictedStart,
          prediction.estimatedNextStart.addDays(-3));
    });

    test('below the minimum the prediction carries no PMS estimate at all',
        () {
      final entries = <DayEntry>[
        for (final start in [_d(2026, 8, 1), _d(2026, 8, 31), _d(2026, 9, 30), _d(2026, 10, 30)])
          for (var i = 0; i < 4; i++) _entry('p', start.addDays(i), flow: FlowLevel.medium),
        // Only two logged PMS intervals.
        for (final start in [_d(2026, 9, 30), _d(2026, 10, 30)])
          for (var i = 1; i <= 3; i++) _entry('p', start.addDays(-i), pms: true),
      ];
      final prediction = computePredictionFromEntries(
        entries: entries,
        today: _d(2026, 11, 5),
      ) as ActivePrediction;
      expect(prediction.pms, isNull);
    });

    test('NotEnoughHistory never carries a PMS estimate even with plenty of '
        'PMS days logged', () {
      final entries = <DayEntry>[
        // Lots of PMS days, but no bleed history at all — nothing to
        // anchor a band before.
        for (var i = 1; i <= 10; i++) _entry('p', _d(2026, 8, i), pms: true),
      ];
      final prediction = computePredictionFromEntries(
        entries: entries,
        today: _d(2026, 8, 15),
      );
      expect(prediction, isA<NotEnoughHistory>());
    });
  });
}
