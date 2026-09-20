/// Issue #887: the cycle-start consent guard for the day sheet's flow row.
///
/// A single `light`/`medium`/`heavy`/`superHeavy` tap on a day inside the
/// open cycle silently starts a new cycle (a bleed day 3+ days after the
/// last bleed day is a new episode start, `episodes.dart`), closes the
/// running one into the averages, and can flip the confidence tier *up*
/// by filling the average window — with no confirmation and no undo. This
/// module is the pure decision half of the remedy: it answers, for one
/// prospective flow write on one date, whether that write changes the
/// derived set of episode starts (cycle starts) and whether the new cycle
/// it would start looks *early* — the surprise condition that earns the
/// confirmation dialog.
///
/// Design principle (the same one issue #130 applied to same-date merges,
/// and what keeps this out of the engine): disclosure and consent, never
/// a different model. The episode-derivation and prediction semantics in
/// `lib/domain/episodes/` and `lib/domain/prediction/` are untouched;
/// this file only *reads* their expectations:
///
/// * "early" against any profile: the closed cycle would be shorter than
///   [kEarlyCycleStartAbsoluteDays] (21) days — no cycle in the engine's
///   valid window is expected anywhere near this short;
/// * "early" against the profile's own history: the closed cycle would be
///   shorter than mean − [kEarlyCycleStartSigmas]·σ of the recent usable
///   cycle lengths, derived with the same window discipline the predictor
///   uses (recency bound applied before validity filtering, spread over
///   the [kAverageWindowCycles] window). A mostly-35-day profile closing
///   a 25-day cycle is far outside her own history even though 25 clears
///   the absolute floor.
///
/// Deliberately NOT omission-aware: this is an advisory disclosure guard,
/// not an average, so the device-local "omit from average" list
/// (issue #132) does not participate — a cycle the operator omitted from
/// the averages still says something about what length would be
/// surprising for that profile.
///
/// LLA-071 parity: bleed dates strictly after [today] never participate
/// (a future-dated stored row cannot anchor the expectation or the "open
/// cycle" being closed), mirroring `computePrediction`'s as-of-`today`
/// episode filtering exactly. Rows *between* the logged date and today —
/// ordinary history when backfilling a day — do participate: the engine
/// sees them, so the guard does too.
library;

import 'dart:math' show sqrt;

import '../episodes/episodes.dart';
import '../models/flow_level.dart';
import '../models/local_date.dart';
import '../prediction/prediction.dart'
    show
        kAverageWindowCycles,
        kMaxCycleDays,
        kMinCompletedValidCycles,
        kMinCycleDays,
        kRecencyWindowCycles;

/// Closing a cycle shorter than this many days is surprising for *any*
/// profile (issue #887's "below 21 days") — the absolute floor of the
/// surprise condition, independent of history.
const int kEarlyCycleStartAbsoluteDays = 21;

/// Closed cycles shorter than the profile's own recent mean minus this
/// many standard deviations are surprising *for that profile* (issue
/// #887's "mean − 2σ") — the statistical half of the surprise condition.
/// Only consulted once the history carries at least
/// [kMinCompletedValidCycles] usable lengths (the predictor's own gate);
/// below that there is no meaningful σ to be surprising against.
const double kEarlyCycleStartSigmas = 2.0;

/// The evaluation of one prospective flow write on one date (issue #887).
/// See [evaluateCycleStartWrite] for how each field is derived.
class CycleStartWriteEvaluation {
  const CycleStartWriteEvaluation({
    required this.changesCycleStartSet,
    required this.startsCycleAtDate,
    required this.startsCycleEarly,
    this.cycleDay,
    this.closedCycleLengthDays,
  });

  /// Whether the write changes the derived set of episode starts at all —
  /// adding one (a new cycle start), removing one (clearing a bleed that
  /// anchored a cycle), or reshuffling them (a bridging edit). This is the
  /// issue's snackbar condition: any day-sheet write that changes the
  /// cycle-start set gets the Undo affordance, surprising or not.
  final bool changesCycleStartSet;

  /// Whether the write makes the logged date *itself* a new episode
  /// start — a bleed 3+ days after the last bleed day (or before the
  /// first one). The common append case; a bridging edit that only
  /// reshuffles earlier starts leaves this false.
  final bool startsCycleAtDate;

  /// Whether [startsCycleAtDate] holds *and* the new cycle would close an
  /// open cycle early — below [kEarlyCycleStartAbsoluteDays] or below the
  /// profile's own mean − [kEarlyCycleStartSigmas]·σ. This is the issue's
  /// confirmation condition: the dialog asks before the write happens.
  final bool startsCycleEarly;

  /// 1-based day in the cycle this write would close (`closedCycleLengthDays
  /// + 1`) — "cycle day 17" for the dialog copy. Null unless a previous
  /// episode start precedes the logged date.
  final int? cycleDay;

  /// Length in days of the cycle this write would close (logged date −
  /// previous episode start). Null unless a previous episode start
  /// precedes the logged date.
  final int? closedCycleLengthDays;

  @override
  String toString() => 'CycleStartWriteEvaluation('
      'changesCycleStartSet: $changesCycleStartSet, '
      'startsCycleAtDate: $startsCycleAtDate, '
      'startsCycleEarly: $startsCycleEarly, '
      'cycleDay: $cycleDay, closedCycleLengthDays: $closedCycleLengthDays)';
}

/// Evaluates the prospective write `fromFlow` → `toFlow` on [date], as of
/// [today] (the device-local civil date, used only for the LLA-071
/// future-row filter — see the library doc).
///
/// [otherBleedDates] is the profile's set of bleed dates *excluding* the
/// day being logged (the day sheet's own current flow for [date] arrives
/// as [fromFlow] instead — persisted flow when evaluating a completed
/// write, the in-memory selection when guarding a chip tap, so a bleed
/// level change *between* bleed levels never re-asks). Both flows are the
/// *effective* flow ([`resolveEffectiveFlow`]'s output or the raw chip
/// selection — identical for bleed-ness, since spotting only ever raises
/// `none` to `notBleeding`); non-bleed transitions never change anything.
CycleStartWriteEvaluation evaluateCycleStartWrite({
  required Set<LocalDate> otherBleedDates,
  required LocalDate date,
  required LocalDate today,
  required FlowLevel fromFlow,
  required FlowLevel toFlow,
}) {
  final fromBleeds = isBleed(fromFlow);
  final toBleeds = isBleed(toFlow);
  if (fromBleeds == toBleeds) return _noChange;
  // LLA-071 parity (see the library doc): stored rows after today are not
  // this day's history to reason about.
  final others = {
    for (final other in otherBleedDates)
      if (!other.isAfter(today) && other != date) other,
  };
  final startsBefore = _episodeStarts(fromBleeds ? {...others, date} : others);
  final startsAfter = _episodeStarts(toBleeds ? {...others, date} : others);
  if (_sameStarts(startsBefore, startsAfter)) return _noChange;
  if (!toBleeds || !startsAfter.contains(date) || startsBefore.contains(date)) {
    // A removal, or a bridging edit that only reshuffles earlier starts:
    // the set changed (the undo snackbar's condition) but the logged day
    // is not itself a new start, so there is no consent decision to ask.
    return _setChangedOnly;
  }
  return _earlyStartEvaluation(others, date, startsBefore);
}

const CycleStartWriteEvaluation _noChange = CycleStartWriteEvaluation(
  changesCycleStartSet: false,
  startsCycleAtDate: false,
  startsCycleEarly: false,
);

const CycleStartWriteEvaluation _setChangedOnly = CycleStartWriteEvaluation(
  changesCycleStartSet: true,
  startsCycleAtDate: false,
  startsCycleEarly: false,
);

/// The episode-start set of a bleed-date set (issue #887 — split out of
/// [evaluateCycleStartWrite] for the CRAP gate, same as the predictor's
/// own window helpers).
Set<LocalDate> _episodeStarts(Set<LocalDate> bleeds) => {
      for (final episode in deriveEpisodes(bleeds)) episode.start,
    };

bool _sameStarts(Set<LocalDate> a, Set<LocalDate> b) =>
    a.length == b.length && a.containsAll(b);

/// The anchored half of the evaluation: [date] is a new episode start, so
/// the question is whether the cycle it closes (anchored on the latest
/// episode start before [date], if any) looks early.
CycleStartWriteEvaluation _earlyStartEvaluation(
  Set<LocalDate> others,
  LocalDate date,
  Set<LocalDate> startsBefore,
) {
  final anchor = _latestStartBefore(startsBefore, date);
  if (anchor == null) {
    // The profile's first ever bleed, or a backfill ahead of all
    // history: nothing is closed and nothing is surprising — the write
    // still changed the cycle-start set, so it still earns the undo
    // snackbar, just not the dialog.
    return const CycleStartWriteEvaluation(
      changesCycleStartSet: true,
      startsCycleAtDate: true,
      startsCycleEarly: false,
    );
  }
  final closedLength = date.difference(anchor);
  return CycleStartWriteEvaluation(
    changesCycleStartSet: true,
    startsCycleAtDate: true,
    startsCycleEarly: closedLength < kEarlyCycleStartAbsoluteDays ||
        _belowRecentExpectation(others, closedLength),
    cycleDay: closedLength + 1,
    closedCycleLengthDays: closedLength,
  );
}

/// The latest episode start strictly before [date], or null when [date]
/// precedes every episode.
LocalDate? _latestStartBefore(Set<LocalDate> starts, LocalDate date) {
  LocalDate? latest;
  for (final start in starts) {
    if (start.isBefore(date) &&
        (latest == null || start.isAfter(latest))) {
      latest = start;
    }
  }
  return latest;
}

/// Whether [closedLength] is shorter than mean − [kEarlyCycleStartSigmas]·σ
/// of the recent usable cycle lengths in [otherBleedDates], derived with
/// the predictor's own window discipline: pairwise lengths over the
/// sorted episode starts, the [kRecencyWindowCycles] recency bound
/// applied *before* validity filtering (A2-13's ordering), then the
/// [kAverageWindowCycles] most recent valid lengths as the window both
/// the mean and the σ are taken over (the same window
/// `prediction.dart`'s spread metric uses). No usable expectation (fewer
/// than [kMinCompletedValidCycles] lengths) reads as "not surprising":
/// with two logged cycles there is no σ worth consulting, and the
/// absolute floor above still guards the pathological cases.
bool _belowRecentExpectation(Set<LocalDate> otherBleedDates, int closedLength) {
  final starts = [
    for (final episode in deriveEpisodes(otherBleedDates)) episode.start,
  ];
  final lengths = <int>[
    for (var i = 1; i < starts.length; i++)
      starts[i].difference(starts[i - 1]),
  ];
  final recentOffset =
      lengths.length > kRecencyWindowCycles ? lengths.length - kRecencyWindowCycles : 0;
  final usable = <int>[
    for (var i = recentOffset; i < lengths.length; i++)
      if (lengths[i] >= kMinCycleDays && lengths[i] <= kMaxCycleDays) lengths[i],
  ];
  if (usable.length < kMinCompletedValidCycles) return false;
  final window = usable.length <= kAverageWindowCycles
      ? usable
      : usable.sublist(usable.length - kAverageWindowCycles);
  var total = 0;
  for (final length in window) {
    total += length;
  }
  final mean = total / window.length;
  return closedLength < mean - kEarlyCycleStartSigmas * _populationStdDev(window);
}

double _populationStdDev(List<int> values) {
  var total = 0;
  for (final value in values) {
    total += value;
  }
  final mean = total / values.length;
  var sumSquaredDiff = 0.0;
  for (final value in values) {
    final diff = value - mean;
    sumSquaredDiff += diff * diff;
  }
  return sqrt(sumSquaredDiff / values.length);
}
