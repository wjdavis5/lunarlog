/// PMS as a predicted phase (Issue #220): pure derivations over the logged
/// first-class PMS marker (`domain.DayEntry.pms`) and the bleed episodes —
/// never persisted, never triggered by writes, the same posture as
/// `prediction.dart`/`fertile_window.dart`.
///
/// What Clue does (A2-9, the issue's own source) and what this file
/// implements:
/// * a PMS *interval* is a maximal run of consecutive logged PMS days
///   (strictly consecutive — unlike bleed episodes, no one-day-gap
///   merging: a one-day hole in the middle of a logged PMS run is a real
///   "not PMS that day" signal the operator typed, and inventing a fill
///   rule for it would fabricate health content);
/// * each interval is attributed to the period that *followed* it — the
///   first episode starting after the interval — giving that cycle's
///   `onset` (days before the following period start where the interval
///   began) and `length` (days, clamped to the onset so an interval whose
///   log runs into the period itself contributes only its premenstrual
///   portion and a predicted band can never overlap the predicted bleed
///   band);
/// * both averages run over the most recent [kAverageWindowCycles] usable
///   intervals — the exact window `prediction.dart` uses for cycle
///   length, period length, and spread; no second window exists;
/// * nothing is predicted below [kMinPmsIntervalsForPrediction] usable
///   intervals (mirroring `kMinCompletedValidCycles`): fewer than three
///   produces `null` — no band, no averages presented as confident;
/// * the estimate carries the *period estimate's own* [CycleConfidence]
///   tier (`ActivePrediction.tier`) rather than inventing a second
///   confidence vocabulary for PMS (the issue's explicit constraint), and
///   can only exist when a period estimate exists at all — the band is
///   positioned before the next *predicted* period start
///   (`ActivePrediction.estimatedNextStart`), so a profile with PMS logs
///   but [NotEnoughHistory] gets no band either.
///
/// Disclaimers are the renderer's job (`kEstimateDisclaimer`); this module
/// only ever hands back the honest numbers (or null).
library;

import '../episodes/episodes.dart';
import '../models/day_entry.dart';
import '../models/local_date.dart';
import 'prediction.dart' show CycleConfidence, kAverageWindowCycles;

/// PROVISIONAL (Issue #220): the hard minimum of logged PMS intervals
/// below which nothing is predicted — no band, no averages. Mirrors
/// `prediction.dart`'s `kMinCompletedValidCycles` (3), the issue's own
/// "mirroring" note. A named calibration constant pending the same
/// real-history calibration as #213's thresholds.
const int kMinPmsIntervalsForPrediction = 3;

/// One maximal run of consecutive logged PMS days; [start] and [end] are
/// inclusive. Derived by [derivePmsIntervals].
class PmsInterval implements Comparable<PmsInterval> {
  PmsInterval(this.start, this.end) {
    if (end.isBefore(start)) {
      throw ArgumentError.value(end, 'end', 'must not precede start');
    }
  }

  final LocalDate start;
  final LocalDate end;

  int get lengthDays => end.difference(start) + 1;

  @override
  int compareTo(PmsInterval other) => start.compareTo(other.start);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PmsInterval && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() =>
      'PmsInterval(${start.iso}..${end.iso}, $lengthDays days)';
}

/// The set of live PMS-marker dates among [entries] (the deletedAt check
/// is defensive for full-fidelity inputs; repository reads are already
/// live-only).
Set<LocalDate> pmsDatesOf(Iterable<DayEntry> entries) => {
      for (final entry in entries)
        if (entry.deletedAt == null && entry.pms) entry.localDate,
    };

/// Derives maximal runs of *strictly consecutive* PMS dates from
/// [pmsDates] (input order irrelevant, duplicates ignored) — see the
/// module doc for why there is no one-day-gap merge here.
List<PmsInterval> derivePmsIntervals(Iterable<LocalDate> pmsDates) {
  final dates = pmsDates.toSet().toList()..sort();
  final intervals = <PmsInterval>[];
  LocalDate? runStart;
  LocalDate? runEnd;
  for (final date in dates) {
    if (runEnd == null || date.difference(runEnd) > 1) {
      if (runEnd != null) {
        intervals.add(PmsInterval(runStart!, runEnd));
      }
      runStart = date;
    }
    runEnd = date;
  }
  if (runEnd != null) {
    intervals.add(PmsInterval(runStart!, runEnd));
  }
  return intervals;
}

/// One usable observation: a PMS interval and the episode start of the
/// period that followed it. [onsetDays] is how many days before that
/// period the interval *began*; [lengthDays] is the interval's own length
/// clamped to [onsetDays] (see the module doc).
class UsablePmsInterval {
  const UsablePmsInterval({
    required this.interval,
    required this.followingPeriodStart,
    required this.onsetDays,
    required this.lengthDays,
  });

  final PmsInterval interval;
  final LocalDate followingPeriodStart;
  final int onsetDays;
  final int lengthDays;
}

/// Attributes each PMS [interval] to the first episode starting strictly
/// after the interval *begins*, keeping the usable ones. An interval is
/// unusable — skipped, never averaged — when no episode follows it (the
/// cycle it belongs to is still open; onset is unknowable), or when it
/// starts on/after the following period start (nothing premenstrual about
/// it; `onsetDays` would be zero or negative). [episodes] must be sorted.
List<UsablePmsInterval> usablePmsIntervals({
  required List<Episode> episodes,
  required List<PmsInterval> intervalList,
}) {
  final usable = <UsablePmsInterval>[];
  for (final interval in intervalList) {
    Episode? following;
    for (final episode in episodes) {
      if (episode.start.isAfter(interval.start)) {
        following = episode;
        break;
      }
    }
    final start = following?.start;
    if (start == null) continue;
    final onset = start.difference(interval.start);
    if (onset < 1) continue;
    usable.add(UsablePmsInterval(
      interval: interval,
      followingPeriodStart: start,
      onsetDays: onset,
      lengthDays: interval.lengthDays > onset ? onset : interval.lengthDays,
    ));
  }
  return usable;
}

/// The predicted PMS phase (Issue #220): averages over the logged
/// intervals plus the concrete band they predict before the next
/// estimated period start. Produced only by [computePmsEstimate] — never
/// for a profile below [kMinPmsIntervalsForPrediction] usable intervals,
/// never without a live period estimate to anchor on.
class PmsEstimate {
  const PmsEstimate({
    required this.meanOnsetDaysBeforeNextPeriod,
    required this.meanLengthDays,
    required this.usableIntervalCount,
    required this.tier,
    required this.predictedStart,
    required this.predictedEnd,
  });

  /// Mean onset over the averaging window: how many days before the
  /// following period start a logged PMS interval began.
  final double meanOnsetDaysBeforeNextPeriod;

  /// Mean (clamped) PMS interval length over the averaging window.
  final double meanLengthDays;

  /// How many usable intervals fed the averages (never below
  /// [kMinPmsIntervalsForPrediction]).
  final int usableIntervalCount;

  /// The period estimate's own tier (`ActivePrediction.tier`) — the same
  /// confidence vocabulary, never a second PMS-specific one (the issue's
  /// constraint). The band renders gated on exactly this tier.
  final CycleConfidence tier;

  /// First predicted PMS day: the next estimated period start minus the
  /// (rounded) mean onset.
  final LocalDate predictedStart;

  /// Last predicted PMS day, inclusive: [predictedStart] plus the
  /// (rounded) mean length minus one — always before the predicted period
  /// start itself, because every averaged length was clamped to its onset.
  final LocalDate predictedEnd;

  @override
  String toString() =>
      'PmsEstimate(onset: ${meanOnsetDaysBeforeNextPeriod.toStringAsFixed(1)}, '
      'length: ${meanLengthDays.toStringAsFixed(1)}, '
      'intervals: $usableIntervalCount, tier: ${tier.name}, '
      'band: ${predictedStart.iso}..${predictedEnd.iso})';
}

/// Computes the PMS estimate for one profile, or `null` when the hard
/// minimum is not met (fewer than [kMinPmsIntervalsForPrediction] usable
/// intervals) — the caller renders nothing at all in that case, never a
/// noisy partial band.
///
/// [episodes] are the profile's derived bleed episodes (any order; sorted
/// internally, matching `computePrediction`'s own first step);
/// [pmsDates] the live logged PMS-marker dates; [nextPredictedStart] the
/// live period estimate (`ActivePrediction.estimatedNextStart`) the band
/// anchors before; [tier] that estimate's own tier, carried through
/// verbatim.
PmsEstimate? computePmsEstimate({
  required List<Episode> episodes,
  required Set<LocalDate> pmsDates,
  required LocalDate nextPredictedStart,
  required CycleConfidence tier,
}) {
  final sorted = [...episodes]..sort();
  final usable = usablePmsIntervals(
    episodes: sorted,
    intervalList: derivePmsIntervals(pmsDates),
  );
  // Most recent first, by the period the interval preceded — the same
  // "recency before averaging" posture `prediction.dart` applies to cycle
  // lengths — then cut to the 6-cycle average window.
  usable.sort((a, b) =>
      b.followingPeriodStart.compareTo(a.followingPeriodStart));
  final window =
      usable.length <= kAverageWindowCycles ? usable : usable.sublist(0, kAverageWindowCycles);
  if (window.length < kMinPmsIntervalsForPrediction) return null;

  var onsetTotal = 0;
  var lengthTotal = 0;
  for (final interval in window) {
    onsetTotal += interval.onsetDays;
    lengthTotal += interval.lengthDays;
  }
  final meanOnset = onsetTotal / window.length;
  final meanLength = lengthTotal / window.length;
  final predictedStart = nextPredictedStart.addDays(-meanOnset.round());
  return PmsEstimate(
    meanOnsetDaysBeforeNextPeriod: meanOnset,
    meanLengthDays: meanLength,
    usableIntervalCount: window.length,
    tier: tier,
    predictedStart: predictedStart,
    predictedEnd: predictedStart.addDays(meanLength.round() - 1),
  );
}
