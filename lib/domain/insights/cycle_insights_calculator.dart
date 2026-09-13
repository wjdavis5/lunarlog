/// Pure computation of cycle statistics, symptom trends, and cramp predictions
/// (Issues #135 and #229).
///
/// Runs purely in-memory over existing [DayEntry] and [Episode] streams.
/// Performs no database writes and makes no causal health inferences.
library;

import '../episodes/episodes.dart';
import '../models/day_entry.dart';
import '../models/flow_level.dart';
import '../models/local_date.dart';
import '../prediction/prediction.dart';
import 'cramp_prediction.dart';
import 'symptom_trends.dart';

class CycleInsightsCalculator {
  const CycleInsightsCalculator._();

  /// Computes a [CycleInsightsReport] from [entries], [episodes], and [prediction].
  static CycleInsightsReport compute({
    required List<DayEntry> entries,
    required List<Episode> episodes,
    ActivePrediction? prediction,
  }) {
    if (episodes.length < 2) {
      return CycleInsightsReport.empty;
    }

    // Sort episodes chronologically.
    final sortedEpisodes = List<Episode>.from(episodes)..sort();

    // Map non-tombstoned entries by localDate for O(1) lookup.
    final liveEntriesByDate = <LocalDate, DayEntry>{};
    for (final entry in entries) {
      if (entry.deletedAt == null) {
        liveEntriesByDate[entry.localDate] = entry;
      }
    }

    // Extract completed valid cycles (15–60 days).
    final validCycles = <_CycleData>[];
    for (var i = 0; i < sortedEpisodes.length - 1; i++) {
      final cycleStart = sortedEpisodes[i].start;
      final nextStart = sortedEpisodes[i + 1].start;
      final cycleLength = nextStart.difference(cycleStart);

      if (cycleLength >= 15 && cycleLength <= 60) {
        final cycleEntries = <DayEntry>[];
        var curr = cycleStart;
        while (curr.isBefore(nextStart)) {
          final e = liveEntriesByDate[curr];
          if (e != null) {
            cycleEntries.add(e);
          }
          curr = curr.addDays(1);
        }

        validCycles.add(_CycleData(
          index: i,
          start: cycleStart,
          end: nextStart.addDays(-1),
          lengthDays: cycleLength,
          entries: cycleEntries,
        ));
      }
    }

    if (validCycles.isEmpty) {
      return CycleInsightsReport.empty;
    }

    final totalCycleCount = validCycles.length;

    // 1. Tag occurrences & cycle-day distributions
    // tag -> (cycleIndex -> Set<cycleDay>)
    final tagCycleOccurrences = <String, Map<int, Set<int>>>{};
    final tagDayCounts = <String, Map<int, int>>{};

    // Flow distribution: cycleDay -> (FlowLevel -> count)
    final flowDistribution = <int, Map<FlowLevel, int>>{};

    for (var cIdx = 0; cIdx < validCycles.length; cIdx++) {
      final cycle = validCycles[cIdx];
      for (final entry in cycle.entries) {
        final cycleDay = entry.localDate.difference(cycle.start) + 1;

        // Collect tags
        for (final rawTag in entry.tags) {
          final tag = rawTag.trim().toLowerCase();
          if (tag.isEmpty) continue;

          tagCycleOccurrences
              .putIfAbsent(tag, () => {})
              .putIfAbsent(cIdx, () => {})
              .add(cycleDay);

          final dayMap = tagDayCounts.putIfAbsent(tag, () => {});
          dayMap[cycleDay] = (dayMap[cycleDay] ?? 0) + 1;
        }

        // Collect flow
        if (isBleed(entry.flow)) {
          final flowMap = flowDistribution.putIfAbsent(cycleDay, () => {});
          flowMap[entry.flow] = (flowMap[entry.flow] ?? 0) + 1;
        }
      }
    }

    // 2. Build SymptomPattern models
    final allPatterns = <SymptomPattern>[];

    for (final tag in tagCycleOccurrences.keys) {
      final cyclesWithTag = tagCycleOccurrences[tag]!;
      final cycleCount = cyclesWithTag.length;
      final dayMap = tagDayCounts[tag] ?? {};

      var totalOccurrences = 0;
      for (final count in dayMap.values) {
        totalOccurrences += count;
      }

      // Identify peak cycle days (days with count >= 2 and within top frequency)
      final sortedDays = dayMap.keys.toList()
        ..sort((a, b) => (dayMap[b] ?? 0).compareTo(dayMap[a] ?? 0));

      final peakDays = <int>[];
      if (sortedDays.isNotEmpty) {
        final maxCount = dayMap[sortedDays.first] ?? 0;
        if (maxCount >= 2) {
          for (final d in sortedDays) {
            final count = dayMap[d] ?? 0;
            // Include days within 70% of peak count, up to 3 days
            if (count >= 2 && count >= (maxCount * 0.7).floor()) {
              peakDays.add(d);
              if (peakDays.length >= 3) break;
            }
          }
        }
      }
      peakDays.sort();

      // Trend analysis: compare recent cycles vs prior cycles
      final trend = _calculateTrend(
        cyclesWithTag: cyclesWithTag,
        totalCycles: totalCycleCount,
      );

      allPatterns.add(SymptomPattern(
        tag: tag,
        totalOccurrences: totalOccurrences,
        cycleCount: cycleCount,
        frequencyByCycleDay: dayMap,
        peakCycleDays: peakDays,
        trend: trend,
        meetsThreshold: cycleCount >= kMinObservationCycles,
      ));
    }

    // Sort patterns: threshold-meeting first, then by total occurrences descending
    allPatterns.sort((a, b) {
      if (a.meetsThreshold != b.meetsThreshold) {
        return a.meetsThreshold ? -1 : 1;
      }
      return b.totalOccurrences.compareTo(a.totalOccurrences);
    });

    // 3. Build FlowPattern model
    FlowPattern? flowPattern;
    if (flowDistribution.isNotEmpty) {
      FlowLevel typicalPeakFlow = FlowLevel.medium;
      var maxPeakCount = 0;
      var typicalPeakDay = 1;

      for (final dayEntry in flowDistribution.entries) {
        final day = dayEntry.key;
        final levelMap = dayEntry.value;

        for (final flowLevel in [FlowLevel.heavy, FlowLevel.superHeavy, FlowLevel.medium, FlowLevel.light]) {
          final count = levelMap[flowLevel] ?? 0;
          if (count > maxPeakCount) {
            maxPeakCount = count;
            typicalPeakFlow = flowLevel;
            typicalPeakDay = day;
          }
        }
      }

      flowPattern = FlowPattern(
        flowByCycleDay: flowDistribution,
        typicalPeakFlow: typicalPeakFlow,
        typicalPeakDay: typicalPeakDay,
      );
    }

    // 4. Predict Cramps (Issue #229)
    final crampPrediction = _predictCramps(
      tagCycleOccurrences: tagCycleOccurrences,
      tagDayCounts: tagDayCounts,
      totalCycleCount: totalCycleCount,
      prediction: prediction,
    );

    return CycleInsightsReport(
      symptomPatterns: allPatterns.where((p) => p.meetsThreshold).toList(),
      flowPattern: flowPattern,
      crampPrediction: crampPrediction,
      analyzedCycleCount: totalCycleCount,
      hasEnoughData: totalCycleCount >= kMinObservationCycles,
    );
  }

  /// Evaluates trend direction comparing recent half vs prior half of cycles.
  static TrendDirection _calculateTrend({
    required Map<int, Set<int>> cyclesWithTag,
    required int totalCycles,
  }) {
    if (totalCycles < 4) {
      return TrendDirection.insufficientData;
    }

    final midpoint = totalCycles ~/ 2;
    var priorCount = 0;
    var recentCount = 0;

    for (final cIdx in cyclesWithTag.keys) {
      if (cIdx < midpoint) {
        priorCount++;
      } else {
        recentCount++;
      }
    }

    final priorRatio = priorCount / midpoint;
    final recentRatio = recentCount / (totalCycles - midpoint);

    final diff = recentRatio - priorRatio;
    if (diff > 0.25) return TrendDirection.increasing;
    if (diff < -0.25) return TrendDirection.decreasing;
    return TrendDirection.stable;
  }

  /// Predicts upcoming cramp days based on historical clustering.
  static CrampPrediction? _predictCramps({
    required Map<String, Map<int, Set<int>>> tagCycleOccurrences,
    required Map<String, Map<int, int>> tagDayCounts,
    required int totalCycleCount,
    required ActivePrediction? prediction,
  }) {
    final crampCycles = tagCycleOccurrences['cramps'];
    if (crampCycles == null || crampCycles.length < kMinCrampCycles) {
      return null;
    }

    final dayCounts = tagDayCounts['cramps'] ?? {};
    final observedCrampCycles = crampCycles.length;

    // Find cycle days where cramps appeared in >= 40% of cycles with cramps
    final eligibleDays = <int>[];
    for (final entry in dayCounts.entries) {
      final day = entry.key;
      final occurrences = entry.value;

      final ratio = occurrences / observedCrampCycles;
      if (ratio >= kCrampDayThresholdRatio) {
        eligibleDays.add(day);
      }
    }

    eligibleDays.sort();
    if (eligibleDays.isEmpty) {
      // Fall back to the single highest day if it has >= 3 occurrences
      final sorted = dayCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (sorted.isNotEmpty && sorted.first.value >= 3) {
        eligibleDays.add(sorted.first.key);
      } else {
        return null;
      }
    }

    // Translate to predicted calendar dates
    final predictedDates = <LocalDate>[];
    if (prediction != null) {
      for (final cd in eligibleDays) {
        predictedDates.add(prediction.estimatedNextStart.addDays(cd - 1));
      }
    }

    return CrampPrediction(
      predictedCycleDays: eligibleDays,
      predictedDates: predictedDates,
      observedCycleCount: observedCrampCycles,
      totalCyclesAnalyzed: totalCycleCount,
      disclaimer: CrampPrediction.kStandardDisclaimer,
    );
  }
}

class _CycleData {
  const _CycleData({
    required this.index,
    required this.start,
    required this.end,
    required this.lengthDays,
    required this.entries,
  });

  final int index;
  final LocalDate start;
  final LocalDate end;
  final int lengthDays;
  final List<DayEntry> entries;
}
