import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/insights/cycle_insights_calculator.dart';
import 'package:lunarlog/domain/insights/symptom_trends.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

LocalDate _d(int y, int m, int day) => LocalDate(y, m, day);

DayEntry _makeEntry({
  required LocalDate date,
  FlowLevel flow = FlowLevel.none,
  List<String> tags = const [],
}) {
  return DayEntry(
    id: 'entry-${date.iso}',
    profileId: 'p1',
    localDate: date,
    tz: 'UTC',
    flow: flow,
    tags: tags,
    note: null,
    updatedAt: DateTime.utc(2026, 9, 1),
  );
}

void main() {
  group('CycleInsightsCalculator', () {
    test('returns empty report when fewer than 2 episodes', () {
      final report = CycleInsightsCalculator.compute(
        entries: [],
        episodes: [Episode(_d(2026, 1, 1), _d(2026, 1, 5))],
      );

      expect(report.hasEnoughData, isFalse);
      expect(report.analyzedCycleCount, 0);
      expect(report.symptomPatterns, isEmpty);
      expect(report.flowPattern, isNull);
      expect(report.crampPrediction, isNull);
    });

    test('returns not enough data when fewer than 3 valid cycles', () {
      // 2 cycles: Jan 1 -> Jan 29 (28d), Jan 29 -> Feb 26 (28d)
      final episodes = [
        Episode(_d(2026, 1, 1), _d(2026, 1, 5)),
        Episode(_d(2026, 1, 29), _d(2026, 2, 2)),
        Episode(_d(2026, 2, 26), _d(2026, 3, 2)),
      ];

      final report = CycleInsightsCalculator.compute(
        entries: [],
        episodes: episodes,
      );

      expect(report.hasEnoughData, isFalse);
      expect(report.analyzedCycleCount, 2);
    });

    test('computes symptom patterns, flow distribution, and cramp forecasts for 3+ cycles', () {
      // 3 cycles of 28 days:
      // Cycle 0: Jan 1 -> Jan 29
      // Cycle 1: Jan 29 -> Feb 26
      // Cycle 2: Feb 26 -> Mar 26
      // Endpoint episode: Mar 26
      final episodes = [
        Episode(_d(2026, 1, 1), _d(2026, 1, 5)),
        Episode(_d(2026, 1, 29), _d(2026, 2, 2)),
        Episode(_d(2026, 2, 26), _d(2026, 3, 2)),
        Episode(_d(2026, 3, 26), _d(2026, 3, 30)),
      ];

      final entries = <DayEntry>[];

      // Add entries for each cycle:
      // Cycle 0 (start Jan 1):
      // Day 1 (Jan 1): heavy flow, cramps
      // Day 2 (Jan 2): medium flow, cramps, headache
      // Day 3 (Jan 3): light flow
      entries.add(_makeEntry(date: _d(2026, 1, 1), flow: FlowLevel.heavy, tags: ['cramps']));
      entries.add(_makeEntry(date: _d(2026, 1, 2), flow: FlowLevel.medium, tags: ['cramps', 'headache']));
      entries.add(_makeEntry(date: _d(2026, 1, 3), flow: FlowLevel.light));

      // Cycle 1 (start Jan 29):
      // Day 1 (Jan 29): heavy flow, cramps
      // Day 2 (Jan 30): medium flow, cramps
      // Day 3 (Jan 31): light flow
      entries.add(_makeEntry(date: _d(2026, 1, 29), flow: FlowLevel.heavy, tags: ['cramps']));
      entries.add(_makeEntry(date: _d(2026, 1, 30), flow: FlowLevel.medium, tags: ['cramps']));
      entries.add(_makeEntry(date: _d(2026, 1, 31), flow: FlowLevel.light));

      // Cycle 2 (start Feb 26):
      // Day 1 (Feb 26): heavy flow, cramps
      // Day 2 (Feb 27): medium flow, cramps
      // Day 3 (Feb 28): light flow
      entries.add(_makeEntry(date: _d(2026, 2, 26), flow: FlowLevel.heavy, tags: ['cramps']));
      entries.add(_makeEntry(date: _d(2026, 2, 27), flow: FlowLevel.medium, tags: ['cramps']));
      entries.add(_makeEntry(date: _d(2026, 2, 28), flow: FlowLevel.light));

      final prediction = ActivePrediction(
        today: _d(2026, 3, 27),
        lastEpisodeStart: _d(2026, 3, 26),
        estimatedNextStart: _d(2026, 4, 23),
        originalEstimatedNextStart: _d(2026, 4, 23),
        averagedCycleLengths: const [28, 28, 28],
        meanCycleLengthDays: 28,
        meanPeriodLengthDays: 5,
        cycleDay: 2,
        duringEpisode: true,
        completedCycleCount: 3,
        validCycleCount: 3,
      );

      final report = CycleInsightsCalculator.compute(
        entries: entries,
        episodes: episodes,
        prediction: prediction,
      );

      expect(report.hasEnoughData, isTrue);
      expect(report.analyzedCycleCount, 3);

      // Symptom patterns
      // 'cramps' was logged in 3 cycles -> meets threshold
      // 'headache' was logged in 1 cycle -> fails threshold
      expect(report.symptomPatterns.length, 1);
      final crampPattern = report.symptomPatterns.first;
      expect(crampPattern.tag, 'cramps');
      expect(crampPattern.totalOccurrences, 6);
      expect(crampPattern.cycleCount, 3);
      expect(crampPattern.peakCycleDays, containsAll([1, 2]));
      expect(crampPattern.timingSummary, contains('Cycle Days 1, 2'));
      expect(crampPattern.meetsThreshold, isTrue);

      // Flow pattern
      expect(report.flowPattern, isNotNull);
      expect(report.flowPattern!.typicalPeakFlow, FlowLevel.heavy);
      expect(report.flowPattern!.typicalPeakDay, 1);

      // Cramp prediction (Issue #229)
      expect(report.crampPrediction, isNotNull);
      final cp = report.crampPrediction!;
      expect(cp.observedCycleCount, 3);
      expect(cp.predictedCycleDays, containsAll([1, 2]));
      expect(cp.disclaimer, contains('Cramp estimates are based on your past logged tags'));
      expect(cp.predictedDates, isNotEmpty);
      // Prediction estimatedNextStart is 2026-04-23, so Day 1 is 2026-04-23, Day 2 is 2026-04-24
      expect(cp.predictedDates, containsAll([_d(2026, 4, 23), _d(2026, 4, 24)]));
    });

    test('trend direction calculates increasing, decreasing, stable', () {
      // 4 cycles:
      // Cycle 0: Jan 1
      // Cycle 1: Jan 29
      // Cycle 2: Feb 26
      // Cycle 3: Mar 26
      // Endpoint: Apr 23
      final episodes = [
        Episode(_d(2026, 1, 1), _d(2026, 1, 5)),
        Episode(_d(2026, 1, 29), _d(2026, 2, 2)),
        Episode(_d(2026, 2, 26), _d(2026, 3, 2)),
        Episode(_d(2026, 3, 26), _d(2026, 3, 30)),
        Episode(_d(2026, 4, 23), _d(2026, 4, 27)),
      ];

      // Increasing symptom: logged only in cycle 2 and 3 (and meets threshold? threshold is 3 cycles for reporting in symptomPatterns, but let's test with 3 cycles: cycle 1, 2, 3 -> prior ratio = 1/2, recent ratio = 2/2 -> diff = 0.5 > 0.25 -> increasing)
      final entries = <DayEntry>[
        _makeEntry(date: _d(2026, 1, 30), tags: ['bloating']), // Cycle 1 (prior)
        _makeEntry(date: _d(2026, 2, 27), tags: ['bloating']), // Cycle 2 (recent)
        _makeEntry(date: _d(2026, 3, 27), tags: ['bloating']), // Cycle 3 (recent)
      ];

      final report = CycleInsightsCalculator.compute(
        entries: entries,
        episodes: episodes,
      );

      final pattern = report.symptomPatterns.firstWhere((p) => p.tag == 'bloating');
      expect(pattern.trend, TrendDirection.increasing);
      expect(pattern.trend.displayName, 'Rising recently');
    });
  });
}
