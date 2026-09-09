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
///
/// Issue #221 (A2-11/A2-12) replaces two dead ends with a "never go
/// silent" posture: (1) [ActivePrediction.daysLate] reports how late a
/// period is as a count, not a blanket string, and once that count passes
/// [kLateGraceDays] `estimatedNextStart` itself rolls forward in whole
/// mean-cycle-length steps (see `_rollLateEstimate`) rather than freezing —
/// [ActivePrediction.originalEstimatedNextStart] keeps the un-rolled date
/// so the day count can keep growing regardless; (2) the old
/// `PausedAwaitingNextPeriod` dead end past [kMaxOpenCycleDays] is gone —
/// that case now stays an [ActivePrediction] (forced to
/// [CycleConfidence.irregular], flagged [ActivePrediction.unusuallyLongCycle])
/// with the same rolled estimate, so reminder planning (which only ever
/// sees [ActivePrediction]s) keeps a nudge alive instead of going quiet.
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

/// An open cycle longer than this is "unusually long" (issue #221/A2-12):
/// [ActivePrediction.unusuallyLongCycle] flags it and [ActivePrediction.tier]
/// is forced to [CycleConfidence.irregular]. Before issue #221 this
/// threshold instead returned the dead-end `PausedAwaitingNextPeriod`
/// state — no date, no reminders; predictions never go silent now, they
/// just get less confident.
const int kMaxOpenCycleDays = 60;

/// Fallback bleed length used only when the period-length window carries
/// no episodes at all (see `computePrediction`'s use, below) — unreachable
/// with an [ActivePrediction] today, kept so that case reads as an honest,
/// named fallback rather than an unexplained `1`. Mirrors `forecast.dart`'s
/// own `kDefaultPredictedPeriodDays`.
const int kDefaultPeriodLengthDays = 4;

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
/// proposal for "confidence compounds the further out you look". The base
/// is floored at one day: an exactly-zero spread (a perfectly steady
/// history) would otherwise stay zero forever (`0 * sqrt(i) == 0`),
/// leaving every forecast cycle at the same tier however far out it goes —
/// the floor guarantees the widening actually widens, and can eventually
/// cross into a lower tier, without changing [ActivePrediction.spreadDays]
/// itself (that display value stays the exact, unfloored population
/// standard deviation).
double _forecastSpreadFor(double baseSpreadDays, int cycleIndex) =>
    (baseSpreadDays < 1.0 ? 1.0 : baseSpreadDays) * sqrt(cycleIndex);

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
///
/// `learning` reads as: 3–5 usable cycles (the [kAverageWindowCycles]
/// window is not yet full) and not otherwise `irregular`. Below three, this
/// function still reads `learning` for the same reason (defensiveness) even
/// though [computePrediction] never actually reaches it with fewer than
/// three — that gate returns [NotEnoughHistory] first. At exactly six (the
/// window full) and not irregular, this reads `high`.
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
  if (validCycleCountInWindow < kAverageWindowCycles) {
    return CycleConfidence.learning;
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

/// A live estimate: last episode start + mean of the most recent usable
/// (valid per the 15–60 window, not omitted, recency-bounded) cycle
/// lengths, rounded to a whole day. A skipped open cycle advances the
/// estimate by [kSkipAdvanceCycles] extra averaged cycles.
class ActivePrediction extends CyclePrediction {
  const ActivePrediction({
    required this.today,
    required this.lastEpisodeStart,
    required this.estimatedNextStart,
    required this.originalEstimatedNextStart,
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
    this.unusuallyLongCycle = false,
  });

  final LocalDate today;
  final LocalDate lastEpisodeStart;

  /// Estimated start date of the next episode — the "live" date calendar
  /// and reminder consumers should track (issue #221/A2-11). Equal to
  /// [originalEstimatedNextStart] until [daysLate] first goes non-null;
  /// from then on it is rolled forward in whole mean-cycle-length steps
  /// (`_rollLateEstimate`) until it sits within [kLateGraceDays] of today,
  /// so consumers are never handed a date arbitrarily far in the past.
  /// Equal to `forecast.first.start`.
  final LocalDate estimatedNextStart;

  /// The un-rolled next-cycle estimate: last episode start + mean cycle
  /// length (+ the skip advance, issue #132/R6) — what [estimatedNextStart]
  /// used to be, before issue #221's forward-roll could ever move it.
  /// [daysLate] is always measured against this, never against the
  /// possibly-rolled [estimatedNextStart]: otherwise the day count would
  /// reset every time the estimate rolls forward instead of growing for as
  /// long as the cycle stays open.
  final LocalDate originalEstimatedNextStart;

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
  /// [meanCycleLengthDays], sourced from [Episode.lengthDays]. The
  /// underlying episode window is offset by one cycle from the cycle-length
  /// window: N cycles are bounded by N+1 episode starts, so recency is
  /// applied over [kRecencyWindowCycles] + 1 episodes before this average
  /// takes its own most-recent [kAverageWindowCycles] slice (see
  /// `_meanPeriodLength`'s `recentEpisodesOffset`).
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

  /// True once the open cycle (today − [lastEpisodeStart]) exceeds
  /// [kMaxOpenCycleDays] (issue #221/A2-12). Before this issue this
  /// threshold returned the dead-end `PausedAwaitingNextPeriod` state
  /// instead — no date, no reminders. Now it stays an [ActivePrediction]
  /// (forced to [CycleConfidence.irregular], per #213) with
  /// [estimatedNextStart] rolled forward the same way any other late
  /// estimate is; this flag is the seam the UI uses to show the "this
  /// cycle is unusually long" prompt (exclude this cycle / turn off
  /// predictions) alongside it.
  final bool unusuallyLongCycle;

  /// Whole civil days from today to [estimatedNextStart] (negative when
  /// past). Once late, [estimatedNextStart] is the rolled date, so this
  /// answers "how far to the live estimate", not "how late" — use
  /// [daysLate] for that.
  int get daysUntilNextStart => estimatedNextStart.difference(today);

  /// Whole civil days [today] is past [originalEstimatedNextStart] — the
  /// raw, un-rolled "N days late" count (issue #221/A2-11). Non-null once
  /// that count exceeds [kLateGraceDays]. Independent of the roll: the
  /// count keeps growing for as long as no new episode is logged, even
  /// once the rolled [estimatedNextStart] has itself caught back up to (or
  /// past) today.
  int? get daysLate {
    final daysPast = today.difference(originalEstimatedNextStart);
    return daysPast > kLateGraceDays ? daysPast : null;
  }

  /// True once [daysLate] is non-null — kept as its own boolean for
  /// callers that only need the gate, not the count (a started episode
  /// would have shifted [lastEpisodeStart] and recomputed everything, so
  /// this can never be stuck true past a new log).
  bool get isLate => daysLate != null;

  /// Whole civil days since [lastEpisodeStart] (today's cycle day minus
  /// one) — named to mirror the pre-#221 `PausedAwaitingNextPeriod` field
  /// of the same name that [unusuallyLongCycle] replaces.
  int get daysSinceLastEpisodeStart => cycleDay - 1;

  /// Date-based phase wording only (R13): "period" during an episode,
  /// otherwise the cycle day.
  String get phaseLabel => duringEpisode ? 'period' : 'cycle day $cycleDay';

  /// Issue #221/A2-11: names the day count once past due, rather than a
  /// blanket "period is late" string. Measured against
  /// [originalEstimatedNextStart] (so it grows from day one, ahead of
  /// [kLateGraceDays] gating the late-resolver banner elsewhere) rather
  /// than the possibly-rolled [estimatedNextStart].
  String get untilNextPeriodLabel {
    final daysPastDue = today.difference(originalEstimatedNextStart);
    if (daysPastDue > 0) {
      return '$daysPastDue day${daysPastDue == 1 ? '' : 's'} late';
    }
    final days = daysUntilNextStart;
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
/// 2. Otherwise → [ActivePrediction]; late is reported within it rather
///    than being a separate state. When the open cycle's start is in
///    [omittedCycleStarts] (a skip), the estimate advances
///    [kSkipAdvanceCycles] averaged cycles beyond the last episode start.
///    Once the open cycle (today − last episode start) passes
///    [kMaxOpenCycleDays] (issue #221/A2-12), [ActivePrediction
///    .unusuallyLongCycle] is set and [ActivePrediction.tier] is forced to
///    [CycleConfidence.irregular] — a skip does not lift this flag; "log
///    it" (R6) is still the only way an open cycle actually closes.
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
  final windows = _recentValidCycles(starts, omittedCycleStarts);

  if (windows.usableLengths.length < kMinCompletedValidCycles) {
    return NotEnoughHistory(
      episodeCount: sorted.length,
      completedCycleCount: windows.lengths.length,
      validCycleCount: windows.validLengths.length,
    );
  }

  final lastStart = starts.last;
  final openDays = today.difference(lastStart);
  final unusuallyLongCycle = openDays > kMaxOpenCycleDays;

  final estimate = _cycleLengthEstimate(
    usableLengths: windows.usableLengths,
    lastStart: lastStart,
    omittedCycleStarts: omittedCycleStarts,
  );
  final rolledStart = _rollLateEstimate(
    original: estimate.firstEstimateStart,
    today: today,
    stepDays: estimate.meanDays,
  );
  final spreadAndTier = _spreadAndTier(
    usableLengths: windows.usableLengths,
    recentLengths: windows.recentLengths,
  );
  // #221 follow-up (review fix): derive the forced tier once and pass it
  // into _buildForecast too — otherwise the forecast built its per-cycle
  // tiers by stepping down from the un-forced spreadAndTier.tier, while
  // ActivePrediction.tier (forecast.first's tier, by the invariant above)
  // was separately forced to irregular for unusuallyLongCycle. Two
  // derivations of the same "first cycle" tier could disagree; there must
  // be exactly one (#299 invariant).
  final tier =
      unusuallyLongCycle ? CycleConfidence.irregular : spreadAndTier.tier;
  final periodLength = _meanPeriodLength(
    sorted: sorted,
    omittedCycleStarts: omittedCycleStarts,
    meanCycleDays: estimate.meanDays,
  );
  final forecast = _buildForecast(
    firstStart: rolledStart,
    meanCycleDays: estimate.meanDays,
    periodLengthDays: periodLength.periodLengthDays,
    baseTier: tier,
    baseSpreadDays: spreadAndTier.spreadDays,
  );

  return ActivePrediction(
    today: today,
    lastEpisodeStart: lastStart,
    estimatedNextStart: forecast.first.start,
    originalEstimatedNextStart: estimate.firstEstimateStart,
    averagedCycleLengths: List.unmodifiable(windows.usableLengths),
    meanCycleLengthDays: estimate.mean,
    cycleDay: today.difference(lastStart) + 1,
    duringEpisode: sorted.any((episode) => episode.contains(today)),
    completedCycleCount: windows.lengths.length,
    validCycleCount: windows.validLengths.length,
    meanPeriodLengthDays: periodLength.meanPeriodLengthDays,
    spreadDays: spreadAndTier.spreadDays,
    tier: tier,
    forecast: forecast,
    unusuallyLongCycle: unusuallyLongCycle,
  );
}

/// Rolls [original] forward in whole [stepDays] increments until [today] is
/// no more than [kLateGraceDays] days past it (issue #221/A2-11): once a
/// cycle is late, `estimatedNextStart` keeps stepping forward by a full
/// mean cycle length at a time rather than freezing at [original], so
/// calendar and reminder consumers always see a live, near-term date
/// instead of one arbitrarily far in the past. [original] itself is kept
/// separately (`originalEstimatedNextStart`) so `daysLate` can go on
/// counting the true distance the whole time this rolls. A non-positive
/// [stepDays] (an unreachable, defensive-only mean of zero) returns
/// [original] unrolled rather than looping forever.
LocalDate _rollLateEstimate({
  required LocalDate original,
  required LocalDate today,
  required int stepDays,
}) {
  if (stepDays <= 0) return original;
  var estimate = original;
  while (today.difference(estimate) > kLateGraceDays) {
    estimate = estimate.addDays(stepDays);
  }
  return estimate;
}

/// Holds the three windows [computePrediction] derives from the raw
/// chronological cycle-length list before it estimates anything (issue
/// #213 split — CRAP gate): [lengths] is every completed cycle (valid or
/// not, for the history-count stats), [validLengths] is [lengths] filtered
/// to the 15–60 window (also stats-only), and [usableLengths] is the
/// recency-bounded, validity-and-omission-filtered list the estimate
/// itself is built from.
class _CycleWindows {
  const _CycleWindows({
    required this.lengths,
    required this.validLengths,
    required this.recentLengths,
    required this.usableLengths,
  });

  final List<int> lengths;
  final List<int> validLengths;
  final List<int> recentLengths;
  final List<int> usableLengths;
}

/// Derives [_CycleWindows] from the chronological episode [starts] (A2-13):
/// pairwise cycle lengths, then the recency bound applied *before* validity
/// filtering, then validity-and-omission filtering within that recency
/// window. See the module doc and [kRecencyWindowCycles] for why this
/// ordering matters.
_CycleWindows _recentValidCycles(
  List<LocalDate> starts,
  Set<LocalDate> omittedCycleStarts,
) {
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

  return _CycleWindows(
    lengths: lengths,
    validLengths: validLengths,
    recentLengths: recentLengths,
    usableLengths: usableLengths,
  );
}

/// The mean cycle length (over [_CycleWindows.usableLengths]) and the
/// estimated start of the next cycle, including the "skip this cycle"
/// advance (issue #213 split).
class _CycleLengthEstimate {
  const _CycleLengthEstimate({
    required this.mean,
    required this.meanDays,
    required this.firstEstimateStart,
  });

  final double mean;
  final int meanDays;
  final LocalDate firstEstimateStart;
}

_CycleLengthEstimate _cycleLengthEstimate({
  required List<int> usableLengths,
  required LocalDate lastStart,
  required Set<LocalDate> omittedCycleStarts,
}) {
  // Issue #213 cheap fix: this used to re-truncate to kPredictionWindowCycles
  // here, but that branch was dead — usableLengths is already bounded to at
  // most kRecencyWindowCycles entries by the recency window above, and
  // kRecencyWindowCycles == kPredictionWindowCycles, so usableLengths can
  // never be longer than kPredictionWindowCycles by the time it gets here.
  // kPredictionWindowCycles still names the forecast's own cycle count
  // (_buildForecast, below) — only the redundant second truncation is gone.
  var total = 0;
  for (final length in usableLengths) {
    total += length;
  }
  final mean = total / usableLengths.length;
  final meanDays = mean.round();
  // A skipped open cycle ("skip this cycle", R6) advances the estimate
  // one averaged cycle: the skipped cycle is expected to run a mean length.
  final skipAdvanceDays = omittedCycleStarts.contains(lastStart)
      ? meanDays * kSkipAdvanceCycles
      : 0;
  final firstEstimateStart = lastStart.addDays(meanDays + skipAdvanceDays);
  return _CycleLengthEstimate(
    mean: mean,
    meanDays: meanDays,
    firstEstimateStart: firstEstimateStart,
  );
}

/// The 6-cycle spread metric and derived confidence tier (issue #213,
/// item 2/3 — split out of `computePrediction` for the CRAP gate).
class _SpreadAndTier {
  const _SpreadAndTier({
    required this.spreadDays,
    required this.tier,
  });

  final double spreadDays;
  final CycleConfidence tier;
}

_SpreadAndTier _spreadAndTier({
  required List<int> usableLengths,
  required List<int> recentLengths,
}) {
  // Issue #213, item 2/3: the 6-cycle average window feeds the spread
  // metric, the confidence tier, and the period-length average — distinct
  // from the (up to 12-cycle) window that feeds the estimate itself.
  final averageWindow = usableLengths.length <= kAverageWindowCycles
      ? usableLengths
      : usableLengths.sublist(usableLengths.length - kAverageWindowCycles);
  final spreadDays = _populationStdDev(averageWindow);
  // Deliberately NOT omission-aware: an omitted-but-otherwise-valid cycle
  // still counts toward recentValidCount (and so toward validRatio) even
  // though it never feeds averageWindow/spreadDays above. validRatio reads
  // the raw regularity of what was actually recorded (a data-quality
  // signal); omission is the operator's editorial choice about which
  // otherwise-normal cycles feed the averages, not a claim that the cycle
  // was irregular. Counting an omission as invalid here would let omitting
  // a handful of ordinary cycles manufacture an `irregular` tier on its
  // own, which is not what omission means.
  final recentValidCount = recentLengths.where(_withinValidWindow).length;
  final validRatio =
      recentLengths.isEmpty ? 1.0 : recentValidCount / recentLengths.length;
  final tier = confidenceTierFor(
    validCycleCountInWindow: averageWindow.length,
    spreadDays: spreadDays,
    validRatio: validRatio,
  );
  return _SpreadAndTier(
    spreadDays: spreadDays,
    tier: tier,
  );
}

/// The 6-episode period-length average and the (clamped) length fed to the
/// forecast (issue #213, item 3 — split out of `computePrediction` for the
/// CRAP gate).
class _MeanPeriodLength {
  const _MeanPeriodLength({
    required this.meanPeriodLengthDays,
    required this.periodLengthDays,
  });

  final double meanPeriodLengthDays;
  final int periodLengthDays;
}

_MeanPeriodLength _meanPeriodLength({
  required List<Episode> sorted,
  required Set<LocalDate> omittedCycleStarts,
  required int meanCycleDays,
}) {
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

  // Issue #213 cheap fix: periodWindow is empty only when every episode in
  // the recency window is omitted — unreachable today with an
  // ActivePrediction (an omission never removes an episode from history,
  // only from the averages), but a silent `.clamp(1, ...)` on a fake 0.0
  // mean would read as "the app estimated a 1-day period" rather than "no
  // data" if that ever changed. kDefaultPeriodLengthDays names the
  // fallback honestly instead (mirrors forecast.dart's own
  // kDefaultPredictedPeriodDays).
  final maxPeriodLengthDays = meanCycleDays <= 0 ? 1 : meanCycleDays;
  final periodLengthDays = periodWindow.isEmpty
      ? kDefaultPeriodLengthDays.clamp(1, maxPeriodLengthDays)
      : meanPeriodLengthDays.round().clamp(1, maxPeriodLengthDays);
  return _MeanPeriodLength(
    meanPeriodLengthDays: meanPeriodLengthDays,
    periodLengthDays: periodLengthDays,
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
