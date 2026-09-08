/// Cycle prediction (KTD5, settled). Pure functions over episode starts —
/// never persisted, never triggered by writes: the service in
/// `prediction_service.dart` computes these as a map over repository
/// streams.
///
/// All date math is on civil dates ([LocalDate]); the caller supplies
/// `today` in the profile's local zone. Output vocabulary is date-based
/// only (period / cycle day / days until next period) — no
/// fertility-phase wording anywhere (R13).
///
/// Issue #132 adds the omission seam: a device-local set of cycle *start*
/// dates the operator has excluded from the averages ("omit from average"
/// in the history list, "skip this cycle" in the late resolver). Omitted
/// cycles stay in history; their lengths simply never feed a mean.
library;

import '../episodes/episodes.dart';
import '../models/day_entry.dart';
import '../models/local_date.dart';

/// A cycle length outside [kMinCycleDays, kMaxCycleDays] is excluded from
/// the average but kept in history.
const int kMinCycleDays = 15;
const int kMaxCycleDays = 60;

/// Estimates require at least this many completed *valid* cycles; with
/// fewer, the result is [NotEnoughHistory] (never partial numbers).
const int kMinCompletedValidCycles = 3;

/// The average uses at most this many of the most recent valid cycles.
const int kMaxAveragedCycles = 3;

/// An open cycle longer than this pauses prediction ("awaiting next
/// period") instead of extrapolating.
const int kMaxOpenCycleDays = 60;

/// Late means today is more than this many days past the estimate.
const int kLateGraceDays = 2;

/// "Skip this cycle" in the late resolver (issue #132/R6) appends the open
/// cycle's start to the omission list. While that skip is in effect the
/// estimate advances one full averaged cycle — the skipped cycle is
/// expected to run an average length, so the next period is estimated one
/// cycle later than usual. When the next period is eventually logged, the
/// skipped cycle's real length is excluded from the average like any other
/// omitted cycle, so an atypically long cycle never poisons the mean.
const int kSkipAdvanceCycles = 1;

/// The result of computing a prediction for one profile.
sealed class CyclePrediction {
  const CyclePrediction();
}

/// Too little valid history to estimate anything. Carries only counts of
/// recorded history — no means, no partial dates.
class NotEnoughHistory extends CyclePrediction {
  const NotEnoughHistory({
    required this.episodeCount,
    required this.completedCycleCount,
    required this.validCycleCount,
  });

  final int episodeCount;
  final int completedCycleCount;
  final int validCycleCount;

  String get statusLabel => 'not enough history yet';

  @override
  String toString() => 'NotEnoughHistory(episodes: $episodeCount, '
      'completedCycles: $completedCycleCount, validCycles: $validCycleCount, '
      'status: $statusLabel)';
}

/// The open cycle has run past [kMaxOpenCycleDays]: prediction is paused
/// until the next period is recorded. No extrapolation is attempted.
class PausedAwaitingNextPeriod extends CyclePrediction {
  const PausedAwaitingNextPeriod({
    required this.today,
    required this.lastEpisodeStart,
  });

  final LocalDate today;
  final LocalDate lastEpisodeStart;

  int get daysSinceLastEpisodeStart => today.difference(lastEpisodeStart);

  String get statusLabel => 'awaiting next period';

  @override
  String toString() => 'PausedAwaitingNextPeriod('
      'lastEpisodeStart: ${lastEpisodeStart.iso}, '
      'daysSinceLastEpisodeStart: $daysSinceLastEpisodeStart, '
      'status: $statusLabel)';
}

/// A live estimate: last episode start + mean of the most recent
/// [kMaxAveragedCycles] usable cycle lengths (valid per the 15–60 window
/// and not omitted; rounded to a whole day). A skipped open cycle advances
/// the estimate by [kSkipAdvanceCycles] extra averaged cycles.
class ActivePrediction extends CyclePrediction {
  const ActivePrediction({
    required this.today,
    required this.lastEpisodeStart,
    required this.estimatedNextStart,
    required this.averagedCycleLengths,
    required this.meanCycleLengthDays,
    required this.cycleDay,
    required this.duringEpisode,
    required this.completedCycleCount,
    required this.validCycleCount,
  });

  final LocalDate today;
  final LocalDate lastEpisodeStart;

  /// Estimated start date of the next episode.
  final LocalDate estimatedNextStart;

  /// The valid cycle lengths the average was computed from (most recent
  /// [kMaxAveragedCycles], chronological order). Valid and not omitted.
  final List<int> averagedCycleLengths;

  /// Exact mean of [averagedCycleLengths] (the estimate rounds it).
  final double meanCycleLengthDays;

  /// 1-based day of the current cycle (today − last episode start + 1).
  final int cycleDay;

  /// Whether today falls inside a derived episode (phase "period").
  final bool duringEpisode;

  /// All completed cycles (valid and invalid alike) — history context.
  final int completedCycleCount;

  /// Completed cycles within the valid length window — history context.
  final int validCycleCount;

  /// Whole civil days from today to [estimatedNextStart] (negative when
  /// past).
  int get daysUntilNextStart => estimatedNextStart.difference(today);

  /// True when today is more than [kLateGraceDays] days past the estimate
  /// and no new episode has started (a started episode would have shifted
  /// [lastEpisodeStart] and recomputed everything).
  bool get isLate => daysUntilNextStart < -kLateGraceDays;

  /// Date-based phase wording only (R13): "period" during an episode,
  /// otherwise the cycle day.
  String get phaseLabel => duringEpisode ? 'period' : 'cycle day $cycleDay';

  String get untilNextPeriodLabel {
    final days = daysUntilNextStart;
    if (days < 0) return 'period is late';
    return '≈$days day${days == 1 ? '' : 's'} until next period';
  }

  @override
  String toString() => 'ActivePrediction('
      'lastEpisodeStart: ${lastEpisodeStart.iso}, '
      'estimatedNextStart: ${estimatedNextStart.iso}, '
      'meanCycleLengthDays: $meanCycleLengthDays, '
      'cycleDay: $cycleDay, phase: $phaseLabel, '
      'untilNextPeriod: $untilNextPeriodLabel)';
}

/// Computes the prediction for one profile from its derived episodes, the
/// current civil date, and (issue #132) the device-local set of omitted
/// cycle starts.
///
/// Ordering of the gates:
/// 1. No episodes, or fewer than [kMinCompletedValidCycles] completed
///    *usable* cycles (valid per the 15–60 window and not omitted) →
///    [NotEnoughHistory].
/// 2. Open cycle (today − last episode start) beyond [kMaxOpenCycleDays]
///    → [PausedAwaitingNextPeriod] (no extrapolation — a skip does not
///    lift this pause; the resolver's "log it" is the way through, R6).
/// 3. Otherwise → [ActivePrediction]; late is reported within it rather
///    than being a separate state. When the open cycle's start is in
///    [omittedCycleStarts] (a skip), the estimate advances
///    [kSkipAdvanceCycles] averaged cycles beyond the last episode start.
CyclePrediction computePrediction({
  required List<Episode> episodes,
  required LocalDate today,
  Set<LocalDate> omittedCycleStarts = const {},
}) {
  final sorted = [...episodes]..sort();
  if (sorted.isEmpty) {
    return const NotEnoughHistory(
        episodeCount: 0, completedCycleCount: 0, validCycleCount: 0);
  }

  final starts = [for (final episode in sorted) episode.start];
  final lengths = <int>[
    for (var i = 1; i < starts.length; i++)
      starts[i].difference(starts[i - 1]),
  ];
  final validLengths =
      lengths.where(_withinValidWindow).toList(growable: false);
  // Issue #132: a length belongs to the cycle that *starts* it, so the
  // omission check applies to the earlier start of each pair.
  final usableLengths = <int>[
    for (var i = 0; i < lengths.length; i++)
      if (_withinValidWindow(lengths[i]) &&
          !omittedCycleStarts.contains(starts[i]))
        lengths[i],
  ];

  if (usableLengths.length < kMinCompletedValidCycles) {
    return NotEnoughHistory(
      episodeCount: sorted.length,
      completedCycleCount: lengths.length,
      validCycleCount: validLengths.length,
    );
  }

  final lastStart = starts.last;
  final openDays = today.difference(lastStart);
  if (openDays > kMaxOpenCycleDays) {
    return PausedAwaitingNextPeriod(today: today, lastEpisodeStart: lastStart);
  }

  final averaged = usableLengths.length <= kMaxAveragedCycles
      ? usableLengths
      : usableLengths.sublist(usableLengths.length - kMaxAveragedCycles);
  var total = 0;
  for (final length in averaged) {
    total += length;
  }
  final mean = total / averaged.length;
  final meanDays = mean.round();
  // A skipped open cycle ("skip this cycle", R6) advances the estimate
  // one averaged cycle: the skipped cycle is expected to run a mean length.
  final skipAdvanceDays = omittedCycleStarts.contains(lastStart)
      ? meanDays * kSkipAdvanceCycles
      : 0;

  return ActivePrediction(
    today: today,
    lastEpisodeStart: lastStart,
    estimatedNextStart: lastStart.addDays(meanDays + skipAdvanceDays),
    averagedCycleLengths: List.unmodifiable(averaged),
    meanCycleLengthDays: mean,
    cycleDay: today.difference(lastStart) + 1,
    duringEpisode: sorted.any((episode) => episode.contains(today)),
    completedCycleCount: lengths.length,
    validCycleCount: validLengths.length,
  );
}

bool _withinValidWindow(int length) =>
    length >= kMinCycleDays && length <= kMaxCycleDays;

/// Convenience: derives episodes from raw entries first, then predicts.
CyclePrediction computePredictionFromEntries({
  required Iterable<DayEntry> entries,
  required LocalDate today,
  Set<LocalDate> omittedCycleStarts = const {},
}) =>
    computePrediction(
      episodes: deriveEpisodes(bleedDatesOf(entries)),
      today: today,
      omittedCycleStarts: omittedCycleStarts,
    );
