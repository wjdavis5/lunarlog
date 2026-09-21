/// Issue #852: the cycle-end recap's pure derivation and its device-local
/// persistence codecs — the facts are read off the engine ([ActivePrediction]
/// / `NotEnoughHistory`, `deriveCycleComparison`, the #178 statistic-change
/// thresholds, the #135/#229 report), and the store round-trips a baseline
/// plus a displayed-statistics snapshot.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/insights/cycle_insights_calculator.dart';
import 'package:lunarlog/domain/insights/cycle_recap.dart';
import 'package:lunarlog/domain/insights/symptom_trends.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/statistic_change.dart';
import 'package:lunarlog/domain/prediction/prediction.dart'
    show
        ActivePrediction,
        CycleConfidence,
        NotEnoughHistory,
        computePrediction;

Episode _episode(LocalDate start) => Episode(start, start.addDays(3));

List<Episode> _episodesFor(List<LocalDate> starts) =>
    [for (final start in starts) _episode(start)];

DayEntry _entry(LocalDate date, {List<String> tags = const []}) => DayEntry(
      id: 'e-${date.iso}',
      profileId: 'p1',
      localDate: date,
      tz: 'UTC',
      flow: FlowLevel.medium,
      tags: tags,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Seven 30-day episodes ending Aug 5, 2026 — six completed cycles, all 30
/// days long, so the engine's mean is exactly 30 and its spread 0.
final List<LocalDate> _steadyStarts = [
  LocalDate(2026, 2, 6),
  LocalDate(2026, 3, 8),
  LocalDate(2026, 4, 7),
  LocalDate(2026, 5, 7),
  LocalDate(2026, 6, 6),
  LocalDate(2026, 7, 6),
  LocalDate(2026, 8, 5),
];

final LocalDate _today = LocalDate(2026, 8, 30);

void main() {
  group('deriveCycleRecap', () {
    test('null with fewer than two episodes — no cycle has completed', () {
      for (final starts in <List<LocalDate>>[
        const [],
        [LocalDate(2026, 7, 1)],
      ]) {
        expect(
          deriveCycleRecap(
            entries: const [],
            prediction: null,
            report: CycleInsightsReport.empty,
            today: _today,
          ),
          isNull,
          reason: 'starts=$starts has no completed cycle',
        );
      }
    });

    test('a single completed cycle reads as still learning, with no invented '
        'estimate facts', () {
      final starts = [LocalDate(2026, 7, 1), LocalDate(2026, 7, 29)];
      final entries = [
        for (final start in starts)
          for (var i = 0; i < 4; i++) _entry(start.addDays(i)),
      ];
      final episodes = _episodesFor(starts);
      final prediction = computePrediction(
        episodes: episodes,
        today: LocalDate(2026, 8, 20),
      );
      final report = CycleInsightsCalculator.compute(
        entries: entries,
        episodes: episodes,
        prediction: null,
      );

      final recap = deriveCycleRecap(
        entries: entries,
        prediction: prediction,
        report: report,
        today: LocalDate(2026, 8, 20),
      );

      expect(recap, isNotNull);
      expect(recap!.cycleNumber, 1);
      expect(recap.cycleLengthDays, 28);
      expect(recap.hasEstimate, isFalse);
      expect(recap.isLearning, isTrue);
      expect(recap.confidence, CycleConfidence.learning);
      expect(recap.meanCycleLengthDays, isNull);
      expect(recap.spreadDays, isNull);
      expect(recap.lengthChangeDays, isNull);
      expect(recap.previousCycleStart, isNull);
      expect(recap.usableCycleCount,
          (prediction as NotEnoughHistory).usableCycleCount);
      expect(recap.currentSnapshot, isNull);
    });

    test('enough history reproduces exactly what the engine computed', () {
      final entries = [
        for (final start in _steadyStarts)
          for (var i = 0; i < 4; i++) _entry(start.addDays(i)),
      ];
      final episodes = _episodesFor(_steadyStarts);
      final prediction = computePrediction(episodes: episodes, today: _today);
      expect(prediction, isA<ActivePrediction>());
      final active = prediction as ActivePrediction;
      final report = CycleInsightsCalculator.compute(
        entries: entries,
        episodes: episodes,
        prediction: active,
      );

      final recap = deriveCycleRecap(
        entries: entries,
        prediction: prediction,
        report: report,
        today: _today,
      );

      expect(recap, isNotNull);
      expect(recap!.cycleNumber, 6);
      expect(recap.cycleStart, LocalDate(2026, 7, 6));
      expect(recap.previousCycleStart, LocalDate(2026, 6, 6));
      expect(recap.cycleLengthDays, 30);
      expect(recap.previousCycleLengthDays, 30);
      expect(recap.lengthChangeDays, 0);
      expect(recap.bleedDayCountDelta, 0);
      expect(recap.hasEstimate, isTrue);
      // Every fact below is the engine's own field, not a re-derivation.
      expect(recap.meanCycleLengthDays, active.meanCycleLengthDays);
      expect(recap.meanPeriodLengthDays, active.meanPeriodLengthDays);
      expect(recap.spreadDays, active.spreadDays);
      expect(recap.confidence, active.tier);
      expect(recap.meanCycleLengthDays, 30.0);
      expect(recap.spreadDays, 0.0);
      expect(recap.confidence, CycleConfidence.high);
      expect(recap.statisticChange, isFalse);
      expect(recap.recurringSymptoms, isEmpty);
      expect(recap.currentSnapshot, isNotNull);
    });

    test('a meaningful displayed-statistic shift is reported from the #178 '
        'thresholds, including a tier transition', () {
      final entries = [
        for (final start in _steadyStarts)
          for (var i = 0; i < 4; i++) _entry(start.addDays(i)),
      ];
      final episodes = _episodesFor(_steadyStarts);
      final active =
          computePrediction(episodes: episodes, today: _today)
              as ActivePrediction;
      final report = CycleInsightsCalculator.compute(
        entries: entries,
        episodes: episodes,
        prediction: active,
      );

      // Previous recap saw a 26-day mean at the learning tier; the current
      // engine reads 30 days at high — a 4-day shift AND a tier transition.
      const previous = CycleStatisticSnapshot(
        meanCycleLengthDays: 26,
        meanPeriodLengthDays: 4,
        tier: CycleConfidence.learning,
      );
      final recap = deriveCycleRecap(
        entries: entries,
        prediction: active,
        report: report,
        today: _today,
        previousSnapshot: previous,
      );

      expect(recap!.statisticChange, isTrue);
      expect(recap.tierChanged, isTrue);
      expect(recap.previousConfidence, CycleConfidence.learning);
      expect(recap.confidence, CycleConfidence.high);
      expect(recap.meanCycleShiftDays, 4);
      expect(recap.meanPeriodShiftDays, 0);
    });

    test('a same-tier mean shift is a statistic change without a tier '
        'transition, and an unchanged snapshot is no change at all', () {
      final entries = [
        for (final start in _steadyStarts)
          for (var i = 0; i < 4; i++) _entry(start.addDays(i)),
      ];
      final episodes = _episodesFor(_steadyStarts);
      final active =
          computePrediction(episodes: episodes, today: _today)
              as ActivePrediction;
      final report = CycleInsightsCalculator.compute(
        entries: entries,
        episodes: episodes,
        prediction: active,
      );

      const shifted = CycleStatisticSnapshot(
        meanCycleLengthDays: 28,
        meanPeriodLengthDays: 4,
        tier: CycleConfidence.high,
      );
      final shiftedRecap = deriveCycleRecap(
        entries: entries,
        prediction: active,
        report: report,
        today: _today,
        previousSnapshot: shifted,
      );
      expect(shiftedRecap!.statisticChange, isTrue);
      expect(shiftedRecap.tierChanged, isFalse);
      expect(shiftedRecap.meanCycleShiftDays, 2);

      final same = deriveCycleRecap(
        entries: entries,
        prediction: active,
        report: report,
        today: _today,
        previousSnapshot: shiftedRecap.currentSnapshot,
      );
      expect(same!.statisticChange, isFalse);
    });

    test('recurring-symptom and cramp facts come from the already-computed '
        'report', () {
      // Four cycles with cramps on days 1-2, which trips both the symptom
      // threshold (#135) and the cramp forecast (#229).
      final starts = [
        LocalDate(2026, 1, 1),
        LocalDate(2026, 1, 29),
        LocalDate(2026, 2, 26),
        LocalDate(2026, 3, 26),
        LocalDate(2026, 4, 23),
      ];
      final entries = [
        for (final start in starts) ...[
          _entry(start, tags: const ['cramps']),
          _entry(start.addDays(1), tags: const ['cramps']),
        ],
      ];
      final episodes = _episodesFor(starts);
      final prediction = computePrediction(
        episodes: episodes,
        today: LocalDate(2026, 5, 10),
      );
      final report = CycleInsightsCalculator.compute(
        entries: entries,
        episodes: episodes,
        prediction: prediction is ActivePrediction ? prediction : null,
      );

      final recap = deriveCycleRecap(
        entries: entries,
        prediction: prediction,
        report: report,
        today: LocalDate(2026, 5, 10),
      );

      expect(recap!.recurringSymptoms, isNotEmpty);
      expect(recap.recurringSymptoms.first.tag, 'cramps');
      expect(recap.recurringSymptoms.first.cycleDays, [1, 2]);
      expect(report.crampPrediction, isNotNull);
      expect(recap.crampCycleDays, report.crampPrediction!.predictedCycleDays);
    });
  });

  group('CycleRecapState codecs', () {
    test('round-trips a baseline and snapshot', () {
      const state = CycleRecapState(
        recorded: true,
        seenCycleIso: '2026-06-06',
        snapshot: CycleStatisticSnapshot(
          meanCycleLengthDays: 30,
          meanPeriodLengthDays: 4,
          tier: CycleConfidence.high,
        ),
      );
      final decoded = decodeCycleRecapState(encodeCycleRecapState(state));
      expect(decoded.recorded, isTrue);
      expect(decoded.seenCycleIso, '2026-06-06');
      expect(decoded.snapshot, state.snapshot);
    });

    test('a recorded baseline with no cycle yet round-trips as such', () {
      const state = CycleRecapState(recorded: true);
      final decoded = decodeCycleRecapState(encodeCycleRecapState(state));
      expect(decoded.recorded, isTrue);
      expect(decoded.seenCycleIso, isNull);
      expect(decoded.snapshot, isNull);
    });

    test('unset/empty/malformed values degrade to no baseline', () {
      for (final raw in <String?>[null, '', 'not json', '[]', '"x"']) {
        final decoded = decodeCycleRecapState(raw);
        expect(decoded.recorded, isFalse);
        expect(decoded.seenCycleIso, isNull);
        expect(decoded.snapshot, isNull);
      }
    });

    test('a malformed date drops just the date; a malformed snapshot drops '
        'just the snapshot', () {
      final decoded = decodeCycleRecapState(
        '{"v":1,"recorded":true,"seen":"nope","snapshot":{"cycleDays":30,'
        '"periodDays":4,"tier":"high"}}',
      );
      expect(decoded.recorded, isTrue);
      expect(decoded.seenCycleIso, isNull);
      expect(decoded.snapshot, isNotNull);

      final noSnapshot = decodeCycleRecapState(
        '{"v":1,"recorded":true,"seen":"2026-06-06","snapshot":7}',
      );
      expect(noSnapshot.seenCycleIso, '2026-06-06');
      expect(noSnapshot.snapshot, isNull);
    });
  });
}
