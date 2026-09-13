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
    final validCycles = _extractValidCycles(episodes, entries);
    if (validCycles.isEmpty) {
      return CycleInsightsReport.empty;
    }

    final totalCycleCount = validCycles.length;
    final tagCycleOccurrences = <String, Map<int, Set<int>>>{};
    final tagDayCounts = <String, Map<int, int>>{};
    final flowDistribution = <int, Map<FlowLevel, int>>{};

    for (final cycle in validCycles) {
      _recordCycleEntries(
        cycle: cycle,
        tagCycleOccurrences: tagCycleOccurrences,
        tagDayCounts: tagDayCounts,
        flowDistribution: flowDistribution,
      );
    }

    final allPatterns = <SymptomPattern>[];
    for (final tag in tagCycleOccurrences.keys) {
      allPatterns.add(_buildPattern(
        tag: tag,
        cyclesWithTag: tagCycleOccurrences[tag]!,
        dayMap: tagDayCounts[tag] ?? const {},
        totalCycleCount: totalCycleCount,
      ));
    }

    allPatterns.sort((a, b) {
      if (a.meetsThreshold != b.meetsThreshold) {
        return a.meetsThreshold ? -1 : 1;
      }
      return b.totalOccurrences.compareTo(a.totalOccurrences);
    });

    final flowPattern = _buildFlowPattern(flowDistribution);
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

  static List<_CycleData> _extractValidCycles(
    List<Episode> episodes,
    List<DayEntry> entries,
  ) {
    if (episodes.length < 2) return const [];
    final sortedEpisodes = List<Episode>.from(episodes)..sort();

    final liveEntriesByDate = <LocalDate, DayEntry>{};
    for (final entry in entries) {
      if (entry.deletedAt == null) {
        liveEntriesByDate[entry.localDate] = entry;
      }
    }

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
    return validCycles;
  }

  static void _recordCycleEntries({
    required _CycleData cycle,
    required Map<String, Map<int, Set<int>>> tagCycleOccurrences,
    required Map<String, Map<int, int>> tagDayCounts,
    required Map<int, Map<FlowLevel, int>> flowDistribution,
  }) {
    for (final entry in cycle.entries) {
      final cycleDay = entry.localDate.difference(cycle.start) + 1;

      for (final rawTag in entry.tags) {
        final tag = rawTag.trim().toLowerCase();
        if (tag.isEmpty) continue;

        tagCycleOccurrences
            .putIfAbsent(tag, () => {})
            .putIfAbsent(cycle.index, () => {})
            .add(cycleDay);

        final dayMap = tagDayCounts.putIfAbsent(tag, () => {});
        dayMap[cycleDay] = (dayMap[cycleDay] ?? 0) + 1;
      }

      if (isBleed(entry.flow)) {
        final flowMap = flowDistribution.putIfAbsent(cycleDay, () => {});
        flowMap[entry.flow] = (flowMap[entry.flow] ?? 0) + 1;
      }
    }
  }

  static List<int> _calculatePeakDays(Map<int, int> dayMap) {
    if (dayMap.isEmpty) return const [];

    final sortedDays = dayMap.keys.toList()
      ..sort((a, b) => dayMap[b]!.compareTo(dayMap[a]!));

    final maxCount = dayMap[sortedDays.first]!;
    if (maxCount < 2) return const [];

    final minThreshold = (maxCount * 0.7).floor();
    final effectiveMin = minThreshold > 2 ? minThreshold : 2;

    final peakDays = <int>[];
    for (final d in sortedDays) {
      if (dayMap[d]! >= effectiveMin) {
        peakDays.add(d);
        if (peakDays.length >= 3) break;
      }
    }
    peakDays.sort();
    return peakDays;
  }

  static SymptomPattern _buildPattern({
    required String tag,
    required Map<int, Set<int>> cyclesWithTag,
    required Map<int, int> dayMap,
    required int totalCycleCount,
  }) {
    var totalOccurrences = 0;
    for (final count in dayMap.values) {
      totalOccurrences += count;
    }

    return SymptomPattern(
      tag: tag,
      totalOccurrences: totalOccurrences,
      cycleCount: cyclesWithTag.length,
      frequencyByCycleDay: dayMap,
      peakCycleDays: _calculatePeakDays(dayMap),
      trend: _calculateTrend(
        cyclesWithTag: cyclesWithTag,
        totalCycles: totalCycleCount,
      ),
      meetsThreshold: cyclesWithTag.length >= kMinObservationCycles,
    );
  }

  static FlowPattern? _buildFlowPattern(
    Map<int, Map<FlowLevel, int>> flowDistribution,
  ) {
    if (flowDistribution.isEmpty) return null;

    FlowLevel typicalPeakFlow = FlowLevel.medium;
    var maxPeakCount = 0;
    var typicalPeakDay = 1;

    for (final dayEntry in flowDistribution.entries) {
      final day = dayEntry.key;
      final levelMap = dayEntry.value;

      for (final flowLevel in [
        FlowLevel.heavy,
        FlowLevel.superHeavy,
        FlowLevel.medium,
        FlowLevel.light
      ]) {
        final count = levelMap[flowLevel] ?? 0;
        if (count > maxPeakCount) {
          maxPeakCount = count;
          typicalPeakFlow = flowLevel;
          typicalPeakDay = day;
        }
      }
    }

    return FlowPattern(
      flowByCycleDay: flowDistribution,
      typicalPeakFlow: typicalPeakFlow,
      typicalPeakDay: typicalPeakDay,
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

  static List<int>? _extractCrampDays(
    Map<int, int> dayCounts,
    int observedCrampCycles,
  ) {
    final eligibleDays = <int>[];
    for (final entry in dayCounts.entries) {
      final ratio = entry.value / observedCrampCycles;
      if (ratio >= kCrampDayThresholdRatio) {
        eligibleDays.add(entry.key);
      }
    }

    eligibleDays.sort();
    if (eligibleDays.isNotEmpty) return eligibleDays;

    final sorted = dayCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.isNotEmpty && sorted.first.value >= 3) {
      return [sorted.first.key];
    }
    return null;
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

    final eligibleDays = _extractCrampDays(
      tagDayCounts['cramps'] ?? {},
      crampCycles.length,
    );
    if (eligibleDays == null) return null;

    final predictedDates = <LocalDate>[];
    if (prediction != null) {
      for (final cd in eligibleDays) {
        predictedDates.add(prediction.estimatedNextStart.addDays(cd - 1));
      }
    }

    return CrampPrediction(
      predictedCycleDays: eligibleDays,
      predictedDates: predictedDates,
      observedCycleCount: crampCycles.length,
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
