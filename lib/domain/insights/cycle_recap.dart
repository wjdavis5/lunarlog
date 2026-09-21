/// The cycle-end recap (issue #852): the one retention moment in an app
/// whose every other insight is pull-based on the Analysis tab.
///
/// A recap is offered when a new period start closes the previous cycle —
/// i.e. when the completed-cycle count increments. It exists to mark that
/// moment, not to become a second analysis engine: every fact below is
/// read off something the app already computes, and a fact the engine does
/// not already produce is deliberately left out rather than re-derived
/// here.
///
/// **In-app only — deliberately no notification.** A push saying anything
/// about a cycle completing is a health disclosure on a lock screen, which
/// is exactly what issue #844 removed from the reminder action labels.
/// This file therefore never touches the notification/reminder stack; the
/// recap is a dismissible in-app card and nothing else. (Reusing
/// [CycleStatisticSnapshot]/[isMeaningfulStatisticChange] below is safe:
/// that module is the *detection* logic behind the #178 reminder, pure
/// data with no scheduler of its own.)
///
/// **No streaks, badges, or achievements, ever** (reaffirmed on #852): a
/// health app that gamifies logging punishes the weeks someone needs it
/// least. This module exposes exactly two kinds of fact — what the record
/// shows, and how trustworthy the estimate has become.
///
/// **Facts and their sources** (all already computed elsewhere):
/// * the just-completed cycle's length and number — [deriveEpisodes]
///   (`lib/domain/episodes/episodes.dart`), the same episode derivation the
///   whole app uses for cycle boundaries;
/// * this-cycle-vs-previous length and bleed-day deltas —
///   [deriveCycleComparison] (#235);
/// * the engine's displayed mean cycle length, mean period length, spread,
///   and confidence tier — [ActivePrediction], already emitted by
///   `CyclePredictionService` (#213);
/// * whether the displayed statistics shifted meaningfully since the last
///   recap — [isMeaningfulStatisticChange] (#178's own thresholds);
/// * recurring-symptom timing and cramp clustering — the
///   [CycleInsightsReport] the Analysis tab already derives
///   ([CycleInsightsCalculator], #135/#229).
///
/// **Honesty when the record is thin.** Below [ActivePrediction]'s
/// `kMinCompletedValidCycles` the engine emits `NotEnoughHistory`, and
/// [hasEstimate] is false: the recap then reports only the cycle length
/// that was actually logged and says plainly that it is still learning,
/// using the same [CycleConfidence] vocabulary as the rest of the app. It
/// never invents a comparison, a range, or encouraging copy the data has
/// not earned.
///
/// **Persistence.** The card is device-local and per-profile: the
/// [cycleRecapSettingKey] record holds the cycle-start ISO the operator has
/// already seen (so dismissing never re-shows that cycle) plus the last
/// displayed-statistics snapshot (so the *next* recap can say, honestly,
/// what changed). Neither is health data; both are the same "scheduling/
/// presentation state, never synced" posture as the #136 reminder configs.
///
/// Pure Dart (R14/R16); `test/architecture/layering_test.dart` enforces
/// that for every file under `lib/domain/`.
library;

import 'dart:convert';

import '../episodes/episodes.dart';
import '../models/day_entry.dart';
import '../models/local_date.dart';
import '../notifications/statistic_change.dart';
import '../prediction/prediction.dart'
    show ActivePrediction, CycleConfidence, CyclePrediction, NotEnoughHistory;
import 'cycle_comparison.dart';
import 'cramp_prediction.dart';
import 'symptom_trends.dart';

/// Device-local settings key for [profileId]'s recap state (issue #852),
/// parsed by [decodeCycleRecapState]. Mirrors
/// `cycle_history.dart`'s per-profile omission key: one namespaced string
/// per profile rather than a shared document, because the record is read
/// and written for exactly one profile at a time.
String cycleRecapSettingKey(String profileId) => 'cycle_recap.$profileId';

/// One recurring-symptom fact carried by a recap: the tag code
/// (`lib/domain/tags.dart`'s taxonomy, e.g. `cramps`) and the cycle days it
/// clusters on — straight from [SymptomPattern.peakCycleDays], never a
/// second pass over the entries.
class RecurringSymptom {
  const RecurringSymptom({required this.tag, required this.cycleDays});

  final String tag;
  final List<int> cycleDays;
}

/// Everything a cycle-end recap is allowed to say, each fact traceable to
/// the engine output named on its field. A `null` fact is simply "the
/// engine did not compute this for this profile" — the card omits it
/// rather than guessing.
class CycleRecap {
  const CycleRecap({
    required this.cycleNumber,
    required this.cycleStart,
    required this.previousCycleStart,
    required this.cycleLengthDays,
    required this.previousCycleLengthDays,
    required this.lengthChangeDays,
    required this.bleedDayCountDelta,
    required this.hasEstimate,
    required this.confidence,
    required this.meanCycleLengthDays,
    required this.meanPeriodLengthDays,
    required this.spreadDays,
    required this.usableCycleCount,
    required this.statisticChange,
    required this.tierChanged,
    required this.previousConfidence,
    required this.meanCycleShiftDays,
    required this.meanPeriodShiftDays,
    required this.recurringSymptoms,
    required this.crampCycleDays,
    required this.currentSnapshot,
  });

  /// 1-based ordinal of the cycle that just closed (the number of
  /// consecutive episode starts minus one).
  final int cycleNumber;

  /// The start date of the cycle that just closed — the persistence key
  /// dismissing this recap records.
  final LocalDate cycleStart;

  /// The start of the cycle before it, or null when this is the first
  /// completed cycle (nothing to compare against).
  final LocalDate? previousCycleStart;

  /// Days from [cycleStart] to the next episode start — this cycle's
  /// logged length.
  final int cycleLengthDays;

  /// The previous cycle's logged length, or null when there is none.
  final int? previousCycleLengthDays;

  /// [cycleLengthDays] minus [previousCycleLengthDays], from
  /// [CycleComparisonStats.lengthDeltaDays]; null whenever either side is
  /// open (so the first completed cycle never implies a comparison).
  final int? lengthChangeDays;

  /// This cycle's bleed-day count minus the previous cycle's, from
  /// [CycleComparisonStats.bleedDayCountDelta]; null when there is no
  /// previous cycle.
  final int? bleedDayCountDelta;

  /// Whether the engine produced an [ActivePrediction] for this profile.
  /// False means the record is still below the estimate threshold and the
  /// recap must stay in its learning state.
  final bool hasEstimate;

  /// The engine's confidence tier, or [CycleConfidence.learning] when
  /// [hasEstimate] is false (the same "no reliable estimate yet" reading
  /// `cycle_history.dart` uses for `NotEnoughHistory`).
  final CycleConfidence confidence;

  /// [ActivePrediction.meanCycleLengthDays], or null without an estimate.
  final double? meanCycleLengthDays;

  /// [ActivePrediction.meanPeriodLengthDays], or null without an estimate.
  final double? meanPeriodLengthDays;

  /// [ActivePrediction.spreadDays], or null without an estimate.
  final double? spreadDays;

  /// The engine's own usable completed-cycle tally when [hasEstimate] is
  /// false ([NotEnoughHistory.usableCycleCount]) — never a recount here.
  final int? usableCycleCount;

  /// Whether the displayed statistics moved meaningfully since the last
  /// recap, per [isMeaningfulStatisticChange]; always false without a
  /// stored previous snapshot.
  final bool statisticChange;

  /// Whether [statisticChange] included a confidence-tier transition.
  final bool tierChanged;

  /// The confidence tier recorded at the previous recap, or null when there
  /// was no stored snapshot. Carried so the card can name the direction of a
  /// transition ([confidence] vs this) without keeping detection state of
  /// its own.
  final CycleConfidence? previousConfidence;

  /// The displayed mean cycle-length shift since the last recap, or null.
  final int? meanCycleShiftDays;

  /// The displayed mean period-length shift since the last recap, or null.
  final int? meanPeriodShiftDays;

  /// Up to two recurring-symptom facts ([SymptomPattern]), already
  /// threshold-filtered by [CycleInsightsCalculator].
  final List<RecurringSymptom> recurringSymptoms;

  /// Cycle days cramps cluster on ([CrampPrediction.predictedCycleDays]),
  /// or null when the engine has no cramp forecast.
  final List<int>? crampCycleDays;

  /// The displayed-statistics snapshot at this cycle boundary, persisted on
  /// dismiss so the next recap can compute an honest change. Null without
  /// an estimate.
  final CycleStatisticSnapshot? currentSnapshot;

  /// Whether the record is still below the estimate threshold.
  bool get isLearning => !hasEstimate;
}

/// Derives the recap for the cycle that most recently closed, or null when
/// fewer than two episodes exist (no cycle has completed yet).
///
/// [entries] is the profile's live day entries; [prediction] and [report]
/// are the already-computed engine outputs the Analysis tab holds, passed in
/// rather than recomputed. [prediction] is nullable because the baseline is
/// established as soon as entries land, before the prediction stream's first
/// emission; a null prediction simply reads as "no estimate yet".
/// [previousSnapshot] is the snapshot stored by the previous recap, if any.
CycleRecap? deriveCycleRecap({
  required Iterable<DayEntry> entries,
  required CyclePrediction? prediction,
  required CycleInsightsReport report,
  required LocalDate today,
  CycleStatisticSnapshot? previousSnapshot,
}) {
  final entryList = entries.toList();
  final episodes = deriveEpisodes(bleedDatesOf(entryList));
  if (episodes.length < 2) return null;
  final sorted = [...episodes]..sort();

  final currentStart = sorted[sorted.length - 2].start;
  final newestStart = sorted.last.start;
  final previousStart =
      sorted.length >= 3 ? sorted[sorted.length - 3].start : null;

  final comparison = _comparisonFacts(
    sorted: sorted,
    entries: entryList,
    today: today,
    currentStart: currentStart,
    previousStart: previousStart,
  );
  final estimate = _estimateFacts(prediction, previousSnapshot);
  final recurring = _recurringFacts(report);
  final active = estimate.active;

  return CycleRecap(
    cycleNumber: sorted.length - 1,
    cycleStart: currentStart,
    previousCycleStart: previousStart,
    cycleLengthDays: newestStart.difference(currentStart),
    previousCycleLengthDays:
        previousStart == null ? null : currentStart.difference(previousStart),
    lengthChangeDays: comparison?.lengthChange,
    bleedDayCountDelta: comparison?.bleedDelta,
    hasEstimate: active != null,
    confidence: active?.tier ?? CycleConfidence.learning,
    meanCycleLengthDays: active?.meanCycleLengthDays,
    meanPeriodLengthDays: active?.meanPeriodLengthDays,
    spreadDays: active?.spreadDays,
    usableCycleCount: estimate.usableCycleCount,
    statisticChange: estimate.change.statisticChange,
    tierChanged: estimate.change.tierChanged,
    previousConfidence: previousSnapshot?.tier,
    meanCycleShiftDays: estimate.change.meanCycleShift,
    meanPeriodShiftDays: estimate.change.meanPeriodShift,
    recurringSymptoms: recurring.symptoms,
    crampCycleDays: recurring.crampCycleDays,
    currentSnapshot: estimate.currentSnapshot,
  );
}

/// #235's own comparison, reused rather than a second alignment pass. Null
/// when there is no previous cycle or the comparison cannot be derived.
_ComparisonFacts? _comparisonFacts({
  required List<Episode> sorted,
  required List<DayEntry> entries,
  required LocalDate today,
  required LocalDate currentStart,
  required LocalDate? previousStart,
}) {
  if (previousStart == null) return null;
  final comparison = deriveCycleComparison(
    episodes: sorted,
    entries: entries,
    today: today,
    cycleAStart: previousStart,
    cycleBStart: currentStart,
  );
  if (comparison == null) return null;
  return _ComparisonFacts(
    lengthChange: comparison.stats.lengthDeltaDays,
    bleedDelta: comparison.stats.bleedDayCountDelta,
  );
}

/// The engine's estimate side of the recap, plus the #178-detected change
/// since the last stored snapshot.
_EstimateFacts _estimateFacts(
  CyclePrediction? prediction,
  CycleStatisticSnapshot? previousSnapshot,
) {
  final active = _activeOrNull(prediction);
  final current = _snapshotOf(active);
  return _EstimateFacts(
    active: active,
    usableCycleCount:
        prediction is NotEnoughHistory ? prediction.usableCycleCount : null,
    currentSnapshot: current,
    change: _changeFacts(current, previousSnapshot),
  );
}

ActivePrediction? _activeOrNull(CyclePrediction? prediction) =>
    prediction is ActivePrediction ? prediction : null;

CycleStatisticSnapshot? _snapshotOf(ActivePrediction? active) =>
    active == null ? null : CycleStatisticSnapshot.fromPrediction(active);

/// #178's own thresholds decide what counts as a visible change.
_ChangeFacts _changeFacts(
  CycleStatisticSnapshot? current,
  CycleStatisticSnapshot? previous,
) {
  if (current == null || previous == null) return _ChangeFacts.none;
  return _ChangeFacts(
    statisticChange: isMeaningfulStatisticChange(previous, current),
    tierChanged: previous.tier != current.tier,
    meanCycleShift: current.meanCycleLengthDays - previous.meanCycleLengthDays,
    meanPeriodShift:
        current.meanPeriodLengthDays - previous.meanPeriodLengthDays,
  );
}

/// Recurring-symptom and cramp facts, straight off the already-computed
/// [CycleInsightsReport] — never a second pass over the entries.
_RecurringFacts _recurringFacts(CycleInsightsReport report) {
  final symptoms = <RecurringSymptom>[];
  for (final pattern in report.symptomPatterns) {
    if (symptoms.length >= 2) break;
    if (pattern.peakCycleDays.isEmpty) continue;
    symptoms.add(RecurringSymptom(
      tag: pattern.tag,
      cycleDays: List.unmodifiable(pattern.peakCycleDays),
    ));
  }
  final crampDays = report.crampPrediction?.predictedCycleDays;
  final hasCramps = crampDays != null && crampDays.isNotEmpty;
  return _RecurringFacts(
    symptoms: List.unmodifiable(symptoms),
    crampCycleDays: hasCramps ? List<int>.unmodifiable(crampDays) : null,
  );
}

class _ComparisonFacts {
  const _ComparisonFacts({required this.lengthChange, required this.bleedDelta});

  final int? lengthChange;
  final int? bleedDelta;
}

class _EstimateFacts {
  const _EstimateFacts({
    required this.active,
    required this.usableCycleCount,
    required this.currentSnapshot,
    required this.change,
  });

  final ActivePrediction? active;
  final int? usableCycleCount;
  final CycleStatisticSnapshot? currentSnapshot;
  final _ChangeFacts change;
}

class _ChangeFacts {
  const _ChangeFacts({
    required this.statisticChange,
    required this.tierChanged,
    required this.meanCycleShift,
    required this.meanPeriodShift,
  });

  static const _ChangeFacts none = _ChangeFacts(
    statisticChange: false,
    tierChanged: false,
    meanCycleShift: null,
    meanPeriodShift: null,
  );

  final bool statisticChange;
  final bool tierChanged;
  final int? meanCycleShift;
  final int? meanPeriodShift;
}

class _RecurringFacts {
  const _RecurringFacts({required this.symptoms, required this.crampCycleDays});

  final List<RecurringSymptom> symptoms;
  final List<int>? crampCycleDays;
}

/// The device-local recap record for one profile: the cycle-start ISO
/// already seen, plus the displayed-statistics snapshot from that moment.
class CycleRecapState {
  const CycleRecapState({
    this.recorded = false,
    this.seenCycleIso,
    this.snapshot,
  });

  /// Whether a baseline has been recorded at all. This is what lets "no
  /// completed cycle had happened when the device first looked" (a null
  /// [seenCycleIso] with `recorded` true) be told apart from "this profile
  /// has never been looked at" — so the first cycle to complete *after* the
  /// baseline is shown, while cycles that completed before it never
  /// retroactively appear.
  final bool recorded;

  /// The `yyyy-MM-dd` start of the cycle whose recap has been seen (shown
  /// and dismissed, or adopted as the baseline on first observation). Null
  /// when no cycle had completed yet at baseline time.
  final String? seenCycleIso;

  /// The displayed statistics at that moment, carried forward so the next
  /// recap can report a meaningful change. Null when the engine had no
  /// estimate at that time.
  final CycleStatisticSnapshot? snapshot;

  /// An empty record: no baseline yet.
  static const CycleRecapState empty = CycleRecapState();
}

/// Encodes [state] as the JSON string [decodeCycleRecapState] parses.
String encodeCycleRecapState(CycleRecapState state) => jsonEncode({
      'v': 1,
      if (state.recorded) 'recorded': true,
      if (state.seenCycleIso != null) 'seen': state.seenCycleIso,
      if (state.snapshot != null) 'snapshot': state.snapshot!.toJson(),
    });

/// Decodes a stored [cycleRecapSettingKey] value. A malformed payload — or
/// anything that fails its own field decode — degrades to [CycleRecapState.empty]
/// ("no baseline yet"), so a corrupt store value re-baselines silently
/// rather than fabricating a change or a dismissal.
CycleRecapState decodeCycleRecapState(String? raw) {
  if (raw == null || raw.isEmpty) return CycleRecapState.empty;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return CycleRecapState.empty;
  }
  if (decoded is! Map<String, Object?>) return CycleRecapState.empty;

  final seen = decoded['seen'];
  final snapshotJson = decoded['snapshot'];
  return CycleRecapState(
    recorded: decoded['recorded'] == true,
    seenCycleIso: seen is String && _isIsoDate(seen) ? seen : null,
    snapshot: snapshotJson is Map<String, Object?>
        ? CycleStatisticSnapshot.fromJson(snapshotJson)
        : null,
  );
}

bool _isIsoDate(String value) {
  if (value.length != 10) return false;
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
}
