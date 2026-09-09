/// Cycle prediction (KTD5, settled). Pure functions over episode starts —
/// never persisted, never triggered by writes: the service in
/// `prediction_service.dart` computes these as a map over repository
/// streams.
///
/// All date math is on civil dates ([LocalDate]); the caller supplies
/// `today` in the profile's local zone. Output vocabulary is date-based
/// only today (period / cycle day / days until next period); fertile-window
/// and ovulation estimation is planned for this module (#143) and does not
/// exist yet.
///
/// Issue #132 adds the omission seam: a device-local set of cycle *start*
/// dates the operator has excluded from the averages ("omit from average"
/// in the history list, "skip this cycle" in the late resolver). Omitted
/// cycles stay in history; their lengths simply never feed a mean.
///
/// Issue #213 rebuilds the window/confidence/forecast machinery this file
/// owns so #132's history/confidence framing and #133's forward calendar
/// consume one engine rather than each deriving their own: three named
/// windows (recency/prediction/average, below), a spread metric and
/// [CycleConfidence] tier on [ActivePrediction], a period-length average,
/// and an N-cycle [ActivePrediction.forecast] with per-cycle degrading
/// confidence. `estimatedNextStart` stays as `forecast.first.start` for
/// existing call sites.
library;

import 'dart:math' show sqrt;

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

/// Recency bound (A2-13): only the most recent [kRecencyWindowCycles]
/// *completed* cycles — valid or not — are ever considered as prediction
/// input. This is applied to the raw chronological cycle list *before*
/// validity filtering, so a profile with old valid data and a long recent
/// gap of invalid/short cycles cannot present a stale, full-confidence
/// estimate built from data outside this window — the concrete fix for
/// A2-13. Never filter for validity across full unbounded history and then
/// window the result; that ordering is the bug this issue replaces.
const int kRecencyWindowCycles = 12;

/// Of the cycles inside [kRecencyWindowCycles], up to this many of the
/// most recent *valid* (and not omitted) ones feed [estimatedNextStart]
/// and [ActivePrediction.forecast]. Replaces the old `kMaxAveragedCycles`
/// for prediction purposes (was 3; Clue-matched to 12, synthesis.md #6).
const int kPredictionWindowCycles = 12;

/// Of the cycles inside [kRecencyWindowCycles], up to this many of the
/// most recent *valid* (and not omitted) ones feed the displayed averages:
/// [ActivePrediction.meanPeriodLengthDays], [ActivePrediction.spreadDays],
/// and [ActivePrediction.tier]. Replaces the old `kMaxAveragedCycles` for
/// display purposes (was 3; Clue-matched to 6, synthesis.md #6).
const int kAverageWindowCycles = 6;

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

/// PROVISIONAL (issue #213): the confidence tier thresholds below are named
/// constants pending calibration against real user histories (A2's own
/// assumptions section: Clue does not publish a numeric threshold). A
/// spread over this many days reads `irregular`.
const double kIrregularSpreadThresholdDays = 7.0;

/// PROVISIONAL (see above): a valid-cycle ratio (within
/// [kRecencyWindowCycles]) below this reads `irregular`.
const double kIrregularValidRatioThreshold = 0.5;

/// PROVISIONAL (issue #213, A2-16): each forecast cycle further out widens
/// the reported spread geometrically by `sqrt(cycleIndex)` — Clue does not
/// publish its own degradation formula, so this is this issue's own
/// proposal for "confidence compounds the further out you look".
double _forecastSpreadFor(double baseSpreadDays, int cycleIndex) =>
    baseSpreadDays * sqrt(cycleIndex);

/// R5/#132's confidence framing, reused everywhere the app talks about how
/// much to trust an estimate (the history list, the forward calendar, this
/// file's own [ActivePrediction.tier]) — issue #213 moved the single
/// canonical definition here so no second vocabulary exists; `cycle_history
/// .dart` re-exports this type for its existing importers. `learning` is
/// also the honest label for thin history where no estimate exists yet.
enum CycleConfidence {
  high,
  learning,
  irregular;

  String get label => switch (this) {
        high => 'High confidence',
        learning => 'Learning',
        irregular => 'Irregular',
      };

  /// Plain-language summary; deliberately free of numbers so it can sit
  /// under thin-data states without leaking partial estimates.
  String get summary => switch (this) {
        high =>
          'Recent cycles are steady — estimates are at their most '
              'reliable.',
        learning =>
          'Still learning — estimates improve after a few more '
              'cycles.',
        irregular => 'Cycles vary a lot — treat estimates as rough guides.',
      };
}

/// Maps a 6-cycle spread and a 12-cycle valid ratio to a [CycleConfidence]
/// tier (issue #213, provisional thresholds above). [validCycleCountInWindow]
/// is the count feeding [spreadDays] (the [kAverageWindowCycles] window);
/// in practice it never falls below [kMinCompletedValidCycles] once
/// [computePrediction] has already gated on that count, but the check is
/// kept for defensiveness and to document the rule on its own.
CycleConfidence confidenceTierFor({
  required int validCycleCountInWindow,
  required double spreadDays,
  required double validRatio,
}) {
  if (validCycleCountInWindow < kMinCompletedValidCycles) {
    return CycleConfidence.learning;
  }
  if (spreadDays > kIrregularSpreadThresholdDays ||
      validRatio < kIrregularValidRatioThreshold) {
    return CycleConfidence.irregular;
  }
  return CycleConfidence.high;
}

/// Steps a tier down exactly one level (`high` → `learning` → `irregular`);
/// `irregular` floors and never degrades further.
CycleConfidence _stepTierDown(CycleConfidence tier) => switch (tier) {
      CycleConfidence.high => CycleConfidence.learning,
      CycleConfidence.learning => CycleConfidence.irregular,
      CycleConfidence.irregular => CycleConfidence.irregular,
    };

/// One forecasted future cycle (issue #213, item 4): [cycleIndex] is
/// 1-based (1 = the next cycle, the same one [estimatedNextStart] names).
/// Confidence degrades further out — [spreadDays] widens geometrically and
/// [tier] steps down one level once that widened spread crosses
/// [kIrregularSpreadThresholdDays] (never below `irregular`). Cycle-day
/// numerals (per #133) are only meaningful on `cycleIndex == 1`.
class PredictedCycle {
  const PredictedCycle({
    required this.cycleIndex,
    required this.start,
    required this.estimatedPeriodLengthDays,
    required this.tier,
    required this.spreadDays,
  });

  /// 1-based: 1 is the next cycle, 2 the one after, and so on.
  final int cycleIndex;

  /// Estimated start date of this cycle.
  final LocalDate start;

  /// Estimated bleed length for this cycle (rounded
  /// [ActivePrediction.meanPeriodLengthDays]).
  final int estimatedPeriodLengthDays;

  /// This cycle's confidence tier — degrades with [cycleIndex].
  final CycleConfidence tier;

  /// This cycle's widened spread, in days either side of [start].
  final double spreadDays;

  @override
  String toString() => 'PredictedCycle(#$cycleIndex ${start.iso}, '
      'periodLength: $estimatedPeriodLengthDays, tier: ${tier.name}, '
      'spread: ${spreadDays.toStringAsFixed(1)})';
}

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

/// A live estimate: last episode start + mean of the most recent usable
/// (valid per the 15–60 window, not omitted, recency-bounded) cycle
/// lengths, rounded to a whole day. A skipped open cycle advances the
/// estimate by [kSkipAdvanceCycles] extra averaged cycles.
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
    this.meanPeriodLengthDays = 0,
    this.spreadDays = 0,
    this.tier = CycleConfidence.learning,
    this.forecast = const [],
  });

  final LocalDate today;
  final LocalDate lastEpisodeStart;

  /// Estimated start date of the next episode. Kept for existing call
  /// sites; equal to `forecast.first.start`.
  final LocalDate estimatedNextStart;

  /// The valid, usable cycle lengths the estimate was computed from (up to
  /// [kPredictionWindowCycles] most recent, within [kRecencyWindowCycles],
  /// chronological order).
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

  /// Mean bleed (episode) length over the [kAverageWindowCycles] window
  /// (issue #213, item 3) — same aggregation shape as
  /// [meanCycleLengthDays], sourced from [Episode.lengthDays].
  final double meanPeriodLengthDays;

  /// Population standard deviation of the cycle lengths inside the
  /// [kAverageWindowCycles] window (issue #213, item 2) — the spread
  /// metric behind [tier] and the range rendering below.
  final double spreadDays;

  /// Confidence tier (issue #213), from [spreadDays] and the valid ratio
  /// over [kRecencyWindowCycles]. Render the estimate as a range rather
  /// than one exact date whenever this is not [CycleConfidence.high].
  final CycleConfidence tier;

  /// Up to [kPredictionWindowCycles] forecasted future cycles, each with
  /// degrading confidence the further out it is (issue #213, item 4).
  /// `forecast.first.start == estimatedNextStart`.
  final List<PredictedCycle> forecast;

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

  /// The estimate rendered as a range rather than one exact date
  /// (`estimatedNextStart ± spreadDays.round()`) — the display #213
  /// prescribes whenever [tier] is not [CycleConfidence.high].
  LocalDate get estimatedRangeStart =>
      estimatedNextStart.addDays(-spreadDays.round());

  LocalDate get estimatedRangeEnd =>
      estimatedNextStart.addDays(spreadDays.round());

  @override
  String toString() => 'ActivePrediction('
      'lastEpisodeStart: ${lastEpisodeStart.iso}, '
      'estimatedNextStart: ${estimatedNextStart.iso}, '
      'meanCycleLengthDays: $meanCycleLengthDays, '
      'meanPeriodLengthDays: $meanPeriodLengthDays, '
      'spreadDays: ${spreadDays.toStringAsFixed(1)}, tier: ${tier.name}, '
      'cycleDay: $cycleDay, phase: $phaseLabel, '
      'untilNextPeriod: $untilNextPeriodLabel)';
}

/// Computes the prediction for one profile from its derived episodes, the
/// current civil date, and (issue #132) the device-local set of omitted
/// cycle starts.
///
/// Ordering of the gates:
/// 1. No episodes, or fewer than [kMinCompletedValidCycles] completed
///    *usable* cycles (valid per the 15–60 window and not omitted, within
///    [kRecencyWindowCycles] of the raw chronological list — issue #213) →
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

  // Issue #213 (A2-13 fix): the recency bound applies to the raw
  // chronological list *first*, before validity filtering — otherwise a
  // handful of old valid cycles behind a long recent gap of invalid ones
  // would still feed a full-confidence estimate. `recentLengths[i]`
  // belongs to the cycle starting `starts[recentOffset + i]`.
  final recentOffset =
      lengths.length > kRecencyWindowCycles
          ? lengths.length - kRecencyWindowCycles
          : 0;
  final recentLengths = lengths.sublist(recentOffset);

  // Issue #132: a length belongs to the cycle that *starts* it, so the
  // omission check applies to the earlier start of each pair.
  final usableLengths = <int>[
    for (var i = 0; i < recentLengths.length; i++)
      if (_withinValidWindow(recentLengths[i]) &&
          !omittedCycleStarts.contains(starts[recentOffset + i]))
        recentLengths[i],
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

  final averaged = usableLengths.length <= kPredictionWindowCycles
      ? usableLengths
      : usableLengths.sublist(usableLengths.length - kPredictionWindowCycles);
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
  final firstEstimateStart = lastStart.addDays(meanDays + skipAdvanceDays);

  // Issue #213, item 2/3: the 6-cycle average window feeds the spread
  // metric, the confidence tier, and the period-length average — distinct
  // from the (up to 12-cycle) window that feeds the estimate itself.
  final averageWindow = usableLengths.length <= kAverageWindowCycles
      ? usableLengths
      : usableLengths.sublist(usableLengths.length - kAverageWindowCycles);
  final spreadDays = _populationStdDev(averageWindow);
  final recentValidCount = recentLengths.where(_withinValidWindow).length;
  final validRatio =
      recentLengths.isEmpty ? 1.0 : recentValidCount / recentLengths.length;
  final tier = confidenceTierFor(
    validCycleCountInWindow: averageWindow.length,
    spreadDays: spreadDays,
    validRatio: validRatio,
  );

  final recentEpisodesOffset =
      sorted.length > kRecencyWindowCycles + 1
          ? sorted.length - (kRecencyWindowCycles + 1)
          : 0;
  final recentPeriodLengths = <int>[
    for (var i = recentEpisodesOffset; i < sorted.length; i++)
      if (!omittedCycleStarts.contains(sorted[i].start)) sorted[i].lengthDays,
  ];
  final periodWindow = recentPeriodLengths.length <= kAverageWindowCycles
      ? recentPeriodLengths
      : recentPeriodLengths.sublist(
          recentPeriodLengths.length - kAverageWindowCycles);
  final meanPeriodLengthDays =
      periodWindow.isEmpty ? 0.0 : _meanOf(periodWindow);

  final forecast = _buildForecast(
    firstStart: firstEstimateStart,
    meanCycleDays: meanDays,
    periodLengthDays: meanPeriodLengthDays.round().clamp(1, meanDays <= 0 ? 1 : meanDays),
    baseTier: tier,
    baseSpreadDays: spreadDays,
  );

  return ActivePrediction(
    today: today,
    lastEpisodeStart: lastStart,
    estimatedNextStart: forecast.first.start,
    averagedCycleLengths: List.unmodifiable(averaged),
    meanCycleLengthDays: mean,
    cycleDay: today.difference(lastStart) + 1,
    duringEpisode: sorted.any((episode) => episode.contains(today)),
    completedCycleCount: lengths.length,
    validCycleCount: validLengths.length,
    meanPeriodLengthDays: meanPeriodLengthDays,
    spreadDays: spreadDays,
    tier: tier,
    forecast: forecast,
  );
}

/// Chains [kPredictionWindowCycles] future cycles off [firstStart] by the
/// (rounded) mean cycle length, degrading confidence further out (issue
/// #213, item 4).
List<PredictedCycle> _buildForecast({
  required LocalDate firstStart,
  required int meanCycleDays,
  required int periodLengthDays,
  required CycleConfidence baseTier,
  required double baseSpreadDays,
}) {
  final cycles = <PredictedCycle>[];
  var start = firstStart;
  for (var i = 1; i <= kPredictionWindowCycles; i++) {
    final spread = _forecastSpreadFor(baseSpreadDays, i);
    final tier = spread > kIrregularSpreadThresholdDays
        ? _stepTierDown(baseTier)
        : baseTier;
    cycles.add(PredictedCycle(
      cycleIndex: i,
      start: start,
      estimatedPeriodLengthDays: periodLengthDays,
      tier: tier,
      spreadDays: spread,
    ));
    start = start.addDays(meanCycleDays);
  }
  return List.unmodifiable(cycles);
}

double _populationStdDev(List<int> values) {
  if (values.isEmpty) return 0;
  final mean = _meanOf(values);
  var sumSquaredDiff = 0.0;
  for (final value in values) {
    final diff = value - mean;
    sumSquaredDiff += diff * diff;
  }
  return sqrt(sumSquaredDiff / values.length);
}

double _meanOf(List<int> values) =>
    values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

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
