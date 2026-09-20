/// Issue #887: unit tests for the cycle-start consent guard
/// (`lib/domain/logging/cycle_start_confirm.dart`) — the pure
/// surprise-condition half of the remedy. The history fixtures mirror the
/// issue's on-device reproduction (profile Maya: 29 · 28 · 7 (outlier) ·
/// 23 · 28 · 29, open cycle from Sep 3 2026, light tap on day 17) plus
/// the control cases from its comments (a day-2 tap merges into the
/// running episode; Spotting never starts a cycle).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/logging/cycle_start_confirm.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

LocalDate _d(String iso) => LocalDate.fromIso(iso);

/// Maya's episode starts from the issue: consecutive cycle lengths
/// 29 · 28 · 7 (outlier, below the 15-day validity floor) · 23 · 28 · 29,
/// open cycle anchored 2026-09-03. Each start is a one-day episode — only
/// starts matter to the guard.
Set<LocalDate> _mayaStarts() => {
      _d('2026-04-12'),
      _d('2026-05-11'),
      _d('2026-06-08'),
      _d('2026-06-15'),
      _d('2026-07-08'),
      _d('2026-08-05'),
      _d('2026-09-03'),
    };

void main() {
  group('the issue\'s reproduction: light on cycle day 17', () {
    test('a surprising early start earns the confirmation', () {
      final evaluation = evaluateCycleStartWrite(
        otherBleedDates: _mayaStarts(),
        date: _d('2026-09-19'),
        today: _d('2026-09-19'),
        fromFlow: FlowLevel.none,
        toFlow: FlowLevel.light,
      );
      expect(evaluation.changesCycleStartSet, isTrue);
      expect(evaluation.startsCycleAtDate, isTrue);
      expect(evaluation.startsCycleEarly, isTrue,
          reason: 'a 16-day closed cycle is below the 21-day absolute floor');
      expect(evaluation.cycleDay, 17);
      expect(evaluation.closedCycleLengthDays, 16);
    });

    test('the guard runs against the exact engine numbers it intercepts',
        () {
      // The motivation, pinned: the same write the dialog guards flips
      // the prediction's tier Learning → High, puts a 16-day cycle into
      // the average window, and moves the estimate to Oct 15 — every
      // number here is from the issue's on-device reproduction.
      final episodes = [
        for (final start in _mayaStarts()) Episode(start, start),
      ];
      final before = computePrediction(
        episodes: episodes,
        today: _d('2026-09-19'),
      ) as ActivePrediction;
      expect(before.tier, CycleConfidence.learning);
      expect(before.averagedCycleLengths, [29, 28, 23, 28, 29]);

      final after = computePrediction(
        episodes: [...episodes, Episode(_d('2026-09-19'), _d('2026-09-19'))],
        today: _d('2026-09-19'),
      ) as ActivePrediction;
      expect(after.tier, CycleConfidence.high,
          reason: 'the window filled with the 16-day cycle the tap created');
      expect(after.averagedCycleLengths, [29, 28, 23, 28, 29, 16]);
      expect(after.estimatedNextStart, _d('2026-10-15'));
    });
  });

  group('control cases from the issue\'s comments', () {
    test('a day-2 light tap merges into the running episode — no confirm',
        () {
      final evaluation = evaluateCycleStartWrite(
        otherBleedDates: _mayaStarts(),
        date: _d('2026-09-04'),
        today: _d('2026-09-19'),
        fromFlow: FlowLevel.none,
        toFlow: FlowLevel.light,
      );
      expect(evaluation.changesCycleStartSet, isFalse,
          reason: 'one day after the last bleed day, the episode just '
              'extends — no cycle boundary moves');
      expect(evaluation.startsCycleEarly, isFalse);
      expect(evaluation.cycleDay, isNull);
    });

    test('a same-cycle-neighbor tap two days out also merges', () {
      final evaluation = evaluateCycleStartWrite(
        otherBleedDates: _mayaStarts(),
        date: _d('2026-09-05'),
        today: _d('2026-09-19'),
        fromFlow: FlowLevel.none,
        toFlow: FlowLevel.heavy,
      );
      expect(evaluation.changesCycleStartSet, isFalse,
          reason: 'a two-day gap still merges (episodes.dart: >2 splits)');
    });
  });

  group('expected starts change the set but are not surprising', () {
    test('a day-29 start on a ~27-day profile gets no dialog', () {
      final evaluation = evaluateCycleStartWrite(
        otherBleedDates: _mayaStarts(),
        date: _d('2026-10-01'), // Sep 3 + 28: right on her own mean
        today: _d('2026-10-01'),
        fromFlow: FlowLevel.none,
        toFlow: FlowLevel.medium,
      );
      expect(evaluation.changesCycleStartSet, isTrue,
          reason: 'an expected start still earns the undo snackbar');
      expect(evaluation.startsCycleAtDate, isTrue);
      expect(evaluation.startsCycleEarly, isFalse,
          reason: '28 days clears both the 21-day floor and mean − 2σ '
              '(≈22.9) of [29, 28, 23, 28, 29]');
      expect(evaluation.cycleDay, 29);
      expect(evaluation.closedCycleLengthDays, 28);
    });

    test('the first ever bleed is never surprising', () {
      final evaluation = evaluateCycleStartWrite(
        otherBleedDates: const {},
        date: _d('2026-09-19'),
        today: _d('2026-09-19'),
        fromFlow: FlowLevel.none,
        toFlow: FlowLevel.light,
      );
      expect(evaluation.changesCycleStartSet, isTrue);
      expect(evaluation.startsCycleAtDate, isTrue);
      expect(evaluation.startsCycleEarly, isFalse,
          reason: 'no open cycle is being closed');
      expect(evaluation.cycleDay, isNull);
      expect(evaluation.closedCycleLengthDays, isNull);
    });

    test('a backfill ahead of all history adds a start but closes nothing',
        () {
      final evaluation = evaluateCycleStartWrite(
        otherBleedDates: {_d('2026-09-03')},
        date: _d('2026-08-20'),
        today: _d('2026-09-19'),
        fromFlow: FlowLevel.none,
        toFlow: FlowLevel.light,
      );
      expect(evaluation.changesCycleStartSet, isTrue);
      expect(evaluation.startsCycleAtDate, isTrue);
      expect(evaluation.startsCycleEarly, isFalse);
      expect(evaluation.cycleDay, isNull);
    });
  });

  group('the profile\'s own expectation (mean − 2σ)', () {
    // 35 · 34 · 36: mean 35, σ ≈ 0.82, mean − 2σ ≈ 33.4.
    Set<LocalDate> longCycleStarts() => {
          _d('2026-05-01'),
          _d('2026-06-05'),
          _d('2026-07-09'),
          _d('2026-08-14'),
        };

    test('a 25-day close is early for a 35-day profile', () {
      final evaluation = evaluateCycleStartWrite(
        otherBleedDates: longCycleStarts(),
        date: _d('2026-09-08'), // Aug 14 + 25
        today: _d('2026-09-08'),
        fromFlow: FlowLevel.none,
        toFlow: FlowLevel.medium,
      );
      expect(evaluation.startsCycleEarly, isTrue,
          reason: '25 clears the 21-day floor but sits far below this '
              'profile\'s own mean − 2σ');
      expect(evaluation.cycleDay, 26);
    });

    test('below three usable lengths there is no σ to be surprising against',
        () {
      final evaluation = evaluateCycleStartWrite(
        otherBleedDates: {_d('2026-06-01'), _d('2026-07-06')}, // one length
        date: _d('2026-07-31'), // closes the open cycle at 25 days
        today: _d('2026-07-31'),
        fromFlow: FlowLevel.none,
        toFlow: FlowLevel.medium,
      );
      expect(evaluation.startsCycleEarly, isFalse,
          reason: '25 ≥ 21 and a single completed cycle derives no '
              'expectation (the predictor\'s own 3-cycle gate)');
    });

    test('an invalid outlier never feeds the expectation', () {
      // 40 · 12 (invalid, below 15) · 40 · 40: usable = [40, 40, 40],
      // mean 40, σ 0 → mean − 2σ = 40. A 25-day close is early; a 40-day
      // close is not.
      final starts = {
        _d('2026-04-01'),
        _d('2026-05-11'), // +40
        _d('2026-05-23'), // +12 (invalid)
        _d('2026-07-02'), // +40
        _d('2026-08-11'), // +40
      };
      expect(
        evaluateCycleStartWrite(
          otherBleedDates: starts,
          date: _d('2026-09-05'), // Aug 11 + 25
          today: _d('2026-09-05'),
          fromFlow: FlowLevel.none,
          toFlow: FlowLevel.light,
        ).startsCycleEarly,
        isTrue,
      );
      expect(
        evaluateCycleStartWrite(
          otherBleedDates: starts,
          date: _d('2026-09-20'), // Aug 11 + 40 — right on her mean
          today: _d('2026-09-20'),
          fromFlow: FlowLevel.none,
          toFlow: FlowLevel.light,
        ).startsCycleEarly,
        isFalse,
      );
    });
  });

  group('removals and non-changes', () {
    test('clearing the bleed that anchored a cycle changes the set', () {
      final evaluation = evaluateCycleStartWrite(
        otherBleedDates: _mayaStarts()..remove(_d('2026-09-03')),
        date: _d('2026-09-03'),
        today: _d('2026-09-19'),
        fromFlow: FlowLevel.heavy,
        toFlow: FlowLevel.none,
      );
      expect(evaluation.changesCycleStartSet, isTrue,
          reason: 'the cycle start disappears with the bleed');
      expect(evaluation.startsCycleAtDate, isFalse);
      expect(evaluation.startsCycleEarly, isFalse,
          reason: 'only a *start* is a consent decision; a removal gets '
              'the snackbar, never the dialog');
    });

    test('a bleed-level change between bleed levels never re-asks', () {
      final evaluation = evaluateCycleStartWrite(
        otherBleedDates: _mayaStarts(),
        date: _d('2026-09-19'),
        today: _d('2026-09-19'),
        fromFlow: FlowLevel.light,
        toFlow: FlowLevel.heavy,
      );
      expect(evaluation.changesCycleStartSet, isFalse);
    });

    test('spotting and not-bleeding selections never change anything', () {
      for (final level in [FlowLevel.none, FlowLevel.notBleeding]) {
        expect(
          evaluateCycleStartWrite(
            otherBleedDates: _mayaStarts(),
            date: _d('2026-09-19'),
            today: _d('2026-09-19'),
            fromFlow: FlowLevel.none,
            toFlow: level,
          ).changesCycleStartSet,
          isFalse,
          reason: '$level is not a bleed (Clue\'s spotting rule, #247)',
        );
      }
    });
  });

  group('edge shapes', () {
    test('a bridging edit reshuffles starts but is not an early start', () {
      // Sep 1 and Sep 4 are 3 days apart: two episodes. Logging Sep 2
      // bridges them into one — the set changes, but Sep 2 is not itself
      // a new start, so no dialog (the write still gets the snackbar).
      final evaluation = evaluateCycleStartWrite(
        otherBleedDates: {_d('2026-09-01'), _d('2026-09-04')},
        date: _d('2026-09-02'),
        today: _d('2026-09-19'),
        fromFlow: FlowLevel.none,
        toFlow: FlowLevel.light,
      );
      expect(evaluation.changesCycleStartSet, isTrue);
      expect(evaluation.startsCycleAtDate, isFalse);
      expect(evaluation.startsCycleEarly, isFalse);
    });

    test('stored bleed dates after today never participate', () {
      // LLA-071 parity: a future-dated stored row (restored export, clock
      // rollback) must neither become the closed cycle's neighbour nor
      // feed the expectation.
      final evaluation = evaluateCycleStartWrite(
        otherBleedDates: {
          ..._mayaStarts(),
          _d('2026-09-25'), // stored row after the logged day
        },
        date: _d('2026-09-19'),
        today: _d('2026-09-19'),
        fromFlow: FlowLevel.none,
        toFlow: FlowLevel.light,
      );
      expect(evaluation.startsCycleEarly, isTrue);
      expect(evaluation.closedCycleLengthDays, 16,
          reason: 'the anchor is still Sep 3 — Sep 25 is invisible here');
    });

    test('the logged day\'s own date in otherBleedDates is ignored', () {
      final evaluation = evaluateCycleStartWrite(
        otherBleedDates: {..._mayaStarts(), _d('2026-09-19')},
        date: _d('2026-09-19'),
        today: _d('2026-09-19'),
        fromFlow: FlowLevel.none,
        toFlow: FlowLevel.light,
      );
      expect(evaluation.startsCycleEarly, isTrue,
          reason: 'the caller\'s snapshot may include the day itself; the '
              'evaluation must not double-count it');
    });
  });
}
