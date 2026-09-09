/// Forward forecast derivation (issue #133, roadmap R1/R2/KTD7): the pure
/// functions behind the twelve-month calendar's predicted bleed bands,
/// first-cycle numerals, and fixed-offset badges.
///
/// INTERIM SEAM (issue #213): #213 owns rebuilding the prediction engine to
/// emit a `forecast: List<PredictedCycle>` directly. Until it lands, this
/// module derives the forward cycles minimally by chaining the mean cycle
/// length off [ActivePrediction.estimatedNextStart] — a single-purpose
/// derivation isolated here so #213 replaces [deriveForecast] alone and the
/// calendar keeps consuming [ForecastCycle]s either way. Never persisted,
/// never triggered by writes: pure recompute per stream emission, matching
/// `prediction.dart`'s posture.
///
/// Everything emits days strictly after "today" only (past stays factual —
/// a logged day always renders as logged, KTD3).
///
/// Issue #143: each [ForecastCycle] also carries its own
/// [FertileWindowEstimate] — [fertile_window.dart]'s calendar-method
/// back-calculation applied to that *cycle's* predicted start rather than
/// only the live [ActivePrediction.estimatedNextStart], so a fertile window
/// renders on the calendar ahead of every forecasted cycle, not only the
/// next one, at that cycle's own (already-degrading) tier. [ForecastDayCell
/// .fertileWindow] marks the per-date lookup the same way
/// `predictedBleed`/`pmsBadge`/`crampsBadge` already do.
library;

import '../models/local_date.dart';
import 'cycle_history.dart';
import 'fertile_window.dart';
import 'pms.dart' show PmsEstimate;
import 'prediction.dart' show ActivePrediction;

/// The forward calendar navigates this many months past the current one
/// (R1). Forecast cycles are derived far enough to cover the end of that
/// month, so every navigable month carries bands even for short cycles.
const int kForecastHorizonMonths = 12;

/// Defensive bound on the derived cycle count so a degenerate (zero-day)
/// mean could never loop unbounded. Unreachable in practice: the shortest
/// valid cycle is 15 days and the horizon spans at most ~13 months, so at
/// most ~32 cycles are ever needed.
const int kForecastMaxCycles = 32;

/// PROVISIONAL (pending #213's calibration): each cycle further out widens
/// the reported spread by this many days — uncertainty compounds the
/// further out you look.
const int kForecastSpreadGrowthPerCycle = 1;

/// PROVISIONAL: bleed length used when the history view carries no mean
/// episode length (unreachable with an [ActivePrediction], defensive
/// only).
const int kDefaultPredictedPeriodDays = 4;

/// PMS badges (Issue #220) are data-driven, not fixed-offset: they cover
/// the [PmsEstimate] band (`prediction.dart`'s 6-cycle onset/length
/// averages, anchored before the next estimated period start) and only
/// exist once at least `kMinPmsIntervalsForPrediction` PMS intervals have
/// been logged — below that the calendar shows no PMS band at all rather
/// than a noisy one. Before this issue they were a fixed
/// `estimate − 7 … − 1` lead window with no logged history behind it;
/// that constant (`kPmsLeadDays`) is gone.
///
/// Cramps badges cover estimate − [kCrampsLeadDays] … estimate +
/// [kCrampsTrailDays] (roadmap KTD7), only while an estimate is active.
const int kCrampsLeadDays = 2;
const int kCrampsTrailDays = 2;

/// One predicted future cycle in the forward calendar.
class ForecastCycle {
  const ForecastCycle({
    required this.index,
    required this.start,
    required this.lengthDays,
    required this.periodLengthDays,
    required this.spreadDays,
    required this.tier,
    required this.fertileWindow,
  });

  /// 0-based; 0 is the first predicted cycle (the one anchored at the
  /// active estimate).
  final int index;

  /// Estimated start of this cycle's predicted bleed.
  final LocalDate start;

  /// Full estimated cycle length (the chaining step) — the span over which
  /// first-cycle numerals are shown.
  final int lengthDays;

  /// Estimated bleed (band) length in days.
  final int periodLengthDays;

  /// How many days either side of [start] the estimate may drift (shown in
  /// the explainer text only, never drawn).
  final int spreadDays;

  /// Confidence-appropriate visual weight for the band (KTD4): cycle 0
  /// carries the history's tier; later cycles step down one tier because
  /// the uncertainty compounds.
  final CycleConfidence tier;

  /// This cycle's own fertile-window/ovulation estimate (issue #143):
  /// [start] minus the assumed luteal-phase length, at this cycle's own
  /// [tier] — the ovulation this window describes precedes [start] (it
  /// belongs to the cycle *ending* in this predicted period, not the one
  /// starting from it).
  final FertileWindowEstimate fertileWindow;

  /// Estimated last bleed day of this cycle's band (inclusive).
  LocalDate get end => start.addDays(periodLengthDays - 1);

  @override
  String toString() =>
      'ForecastCycle(#$index ${start.iso}..${end.iso}, '
      'length: $lengthDays, spread: $spreadDays, tier: ${tier.name}, '
      'fertileWindow: $fertileWindow)';
}

/// The derived forecast state for one future date (KTD3: only ever a date
/// strictly after today). A cell can carry a band, a numeral (first
/// predicted cycle only), and/or the fixed-offset badges together.
class ForecastDayCell {
  const ForecastDayCell({
    required this.predictedBleed,
    required this.cycleDayNumber,
    required this.pmsBadge,
    required this.crampsBadge,
    required this.fertileWindow,
    required this.tier,
    required this.cycleIndex,
    this.fertileTier,
    this.fertileCycleIndex,
  });

  /// The date falls inside a predicted bleed band.
  final bool predictedBleed;

  /// 1-based cycle-day numeral; non-null on the first predicted cycle only
  /// (KTD5 — numerals never chain across later cycles).
  final int? cycleDayNumber;

  /// The date falls in the PMS window (estimate − 7 … − 1).
  final bool pmsBadge;

  /// The date falls in the cramps window (estimate − 2 … + 2).
  final bool crampsBadge;

  /// The date falls inside a predicted fertile window (issue #143:
  /// estimated ovulation − 5 … + 1, per `fertile_window.dart`).
  final bool fertileWindow;

  /// The cycle whose band/numeral/PMS/cramps badges cover this date — not
  /// necessarily the same cycle whose fertile window also touches it, see
  /// [fertileTier]/[fertileCycleIndex].
  final CycleConfidence tier;
  final int cycleIndex;

  /// The tier of the cycle whose *fertile window* covers this date (issue
  /// #143 review): a later, lower-confidence cycle's fertile window can
  /// land on a date an earlier cycle's band/numeral already claimed (e.g.
  /// cycle 1's fertile window sitting inside cycle 0's full-length numeral
  /// span) — carrying that source cycle's own tier separately from [tier]
  /// is what lets the calendar wash/explainer describe the fertile window
  /// at *its* confidence, rather than silently inheriting whichever cycle
  /// happened to create the cell first. Non-null exactly when
  /// [fertileWindow] is true.
  final CycleConfidence? fertileTier;

  /// The 0-based index of the cycle whose fertile window covers this date
  /// — see [fertileTier]. Non-null exactly when [fertileWindow] is true.
  final int? fertileCycleIndex;

  ForecastDayCell _withBadges({
    required bool pms,
    required bool cramps,
    bool fertile = false,
    CycleConfidence? fertileTier,
    int? fertileCycleIndex,
  }) =>
      ForecastDayCell(
        predictedBleed: predictedBleed,
        cycleDayNumber: cycleDayNumber,
        pmsBadge: pmsBadge || pms,
        crampsBadge: crampsBadge || cramps,
        fertileWindow: fertileWindow || fertile,
        tier: tier,
        cycleIndex: cycleIndex,
        fertileTier: fertile ? fertileTier : this.fertileTier,
        fertileCycleIndex:
            fertile ? fertileCycleIndex : this.fertileCycleIndex,
      );

  @override
  String toString() =>
      'ForecastDayCell(bleed: $predictedBleed, cycleDay: $cycleDayNumber, '
      'pms: $pmsBadge, cramps: $crampsBadge, fertile: $fertileWindow, '
      'tier: ${tier.name}, fertileTier: ${fertileTier?.name})';
}

/// Steps a confidence tier down one level for every cycle past the first
/// (KTD4): `high` degrades to `learning`; `learning` and `irregular`
/// already read as rough and stay put.
CycleConfidence degradeForecastTier(CycleConfidence tier) =>
    tier == CycleConfidence.high ? CycleConfidence.learning : tier;

/// Derives the forward forecast: cycles chained off the active estimate by
/// the (rounded) mean cycle length, until a cycle's start passes the end of
/// the navigable horizon (today's month + [horizonMonths]).
///
/// The first cycle anchors at [ActivePrediction.estimatedNextStart] — skip
/// advancement (#132's `kSkipAdvanceCycles`) is already folded into that
/// date, so a skipped cycle moves the whole forecast with the estimate.
List<ForecastCycle> deriveForecast({
  required ActivePrediction prediction,
  required CycleHistoryView history,
  required LocalDate today,
  int horizonMonths = kForecastHorizonMonths,
}) {
  final step = prediction.meanCycleLengthDays.round();
  if (step <= 0) return const [];
  final periodLength =
      (history.meanPeriodLengthDays?.round() ?? kDefaultPredictedPeriodDays)
          .clamp(1, step);
  final baseTier = history.confidence ?? CycleConfidence.learning;
  final baseSpread = history.variationDays ?? 0;
  final horizonEnd = _endOfHorizonMonth(today, horizonMonths);

  final cycles = <ForecastCycle>[];
  var start = prediction.estimatedNextStart;
  while (!start.isAfter(horizonEnd) && cycles.length < kForecastMaxCycles) {
    final index = cycles.length;
    final tier = index == 0 ? baseTier : degradeForecastTier(baseTier);
    cycles.add(
      ForecastCycle(
        index: index,
        start: start,
        lengthDays: step,
        periodLengthDays: periodLength,
        spreadDays: baseSpread + index * kForecastSpreadGrowthPerCycle,
        tier: tier,
        // Issue #143: each cycle's own fertile window precedes *that*
        // cycle's predicted period start, at that cycle's own (already
        // degrading) tier — the same [fertileWindowFor] core
        // [estimateFertileWindow] uses for the live estimate, so the two
        // call sites can never drift onto different formulas.
        fertileWindow: fertileWindowFor(start: start, tier: tier),
      ),
    );
    start = start.addDays(step);
  }
  return List.unmodifiable(cycles);
}

/// Per-date forecast lookup for the calendar grid, keyed by ISO date. Only
/// dates strictly after [today] are present (KTD3 — the past stays
/// factual); the widget additionally suppresses forecast rendering on any
/// date that carries a logged entry.
///
/// [pms] (Issue #220) is the profile's predicted PMS phase, or null when
/// the profile is below the 3-logged-interval hard minimum — the PMS
/// badge is only ever drawn inside a non-null estimate's band, so below
/// the threshold no PMS badge exists anywhere (the issue's "no band
/// rather than a noisy one").
///
/// Split into three helpers (issue #143 review, CI CRAP gate — this method
/// alone scored complexity 12): [_markCycleDays] lays down each cycle's own
/// band/numeral cells first, [_markLiveEstimateBadges] adds the PMS/cramps
/// badges off the live estimate, and [_markFertileWindows] layers every
/// cycle's own fertile window on top last, so a fertile day can correctly
/// land on (and update) a cell an earlier step already created.
Map<String, ForecastDayCell> forecastDayCells({
  required List<ForecastCycle> cycles,
  required LocalDate today,
  PmsEstimate? pms,
}) {
  final cells = <String, ForecastDayCell>{};
  for (final cycle in cycles) {
    _markCycleDays(cells, cycle, today);
  }
  if (cycles.isEmpty) return cells;
  _markLiveEstimateBadges(cells, cycles.first, today, pms: pms);
  _markFertileWindows(cells, cycles, today);
  return cells;
}

/// Lays down one [cycle]'s own band/numeral cells (KTD3/KTD5): the first
/// predicted cycle walks its full length (numerals cover the whole cycle,
/// not just the band); later cycles walk the band only. Cycles never
/// overlap, so a date already present is left alone (defensive).
void _markCycleDays(
  Map<String, ForecastDayCell> cells,
  ForecastCycle cycle,
  LocalDate today,
) {
  final spanDays =
      cycle.index == 0 ? cycle.lengthDays : cycle.periodLengthDays;
  for (var i = 0; i < spanDays; i++) {
    final date = cycle.start.addDays(i);
    if (!date.isAfter(today)) continue;
    final iso = date.iso;
    if (cells.containsKey(iso)) continue; // defensive: cycles never overlap
    cells[iso] = ForecastDayCell(
      predictedBleed: i < cycle.periodLengthDays,
      cycleDayNumber: cycle.index == 0 ? i + 1 : null,
      pmsBadge: false,
      crampsBadge: false,
      fertileWindow: false,
      tier: cycle.tier,
      cycleIndex: cycle.index,
    );
  }
}

/// The live-estimate badges (roadmap KTD7, Issue #220): cramps keep their
/// fixed offset window off the live (next) [estimateCycle]; PMS is drawn
/// only from a non-null [pms] estimate's own band — the 6-cycle onset/
/// length averages anchored before this cycle's start — and never from a
/// fixed lead. Both never repeat for later forecast cycles (unlike the
/// fertile windows below).
void _markLiveEstimateBadges(
  Map<String, ForecastDayCell> cells,
  ForecastCycle estimateCycle,
  LocalDate today, {
  PmsEstimate? pms,
}) {
  final estimate = estimateCycle.start;
  final tier = estimateCycle.tier;
  final pmsEstimate = pms;
  if (pmsEstimate != null) {
    var date = pmsEstimate.predictedStart;
    while (!date.isAfter(pmsEstimate.predictedEnd)) {
      _markBadge(
        cells,
        date,
        today,
        pms: true,
        cramps: false,
        tier: tier,
        cycleIndex: 0,
      );
      date = date.addDays(1);
    }
  }
  for (var i = -kCrampsLeadDays; i <= kCrampsTrailDays; i++) {
    _markBadge(
      cells,
      estimate.addDays(i),
      today,
      pms: false,
      cramps: true,
      tier: tier,
      cycleIndex: 0,
    );
  }
}

/// Issue #143: every forecasted [cycles] entry marks its own fertile
/// window (not only the next one, unlike [_markLiveEstimateBadges] above)
/// — the calendar surfaces a fertile band ahead of each future predicted
/// period, not just the nearest, each at that cycle's own tier.
void _markFertileWindows(
  Map<String, ForecastDayCell> cells,
  List<ForecastCycle> cycles,
  LocalDate today,
) {
  for (final cycle in cycles) {
    var date = cycle.fertileWindow.windowStart;
    while (!date.isAfter(cycle.fertileWindow.windowEnd)) {
      _markBadge(
        cells,
        date,
        today,
        pms: false,
        cramps: false,
        fertile: true,
        tier: cycle.tier,
        cycleIndex: cycle.index,
      );
      date = date.addDays(1);
    }
  }
}

void _markBadge(
  Map<String, ForecastDayCell> cells,
  LocalDate date,
  LocalDate today, {
  required bool pms,
  required bool cramps,
  required CycleConfidence tier,
  required int cycleIndex,
  bool fertile = false,
}) {
  if (!date.isAfter(today)) return;
  final existing = cells[date.iso];
  cells[date.iso] = existing == null
      ? ForecastDayCell(
          predictedBleed: false,
          cycleDayNumber: null,
          pmsBadge: pms,
          crampsBadge: cramps,
          fertileWindow: fertile,
          tier: tier,
          cycleIndex: cycleIndex,
          fertileTier: fertile ? tier : null,
          fertileCycleIndex: fertile ? cycleIndex : null,
        )
      : existing._withBadges(
          pms: pms,
          cramps: cramps,
          fertile: fertile,
          fertileTier: tier,
          fertileCycleIndex: cycleIndex,
        );
}

/// The last day of the month [horizonMonths] after [today]'s month — the
/// navigable horizon the forecast must cover.
LocalDate _endOfHorizonMonth(LocalDate today, int horizonMonths) {
  final total = today.year * 12 + (today.month - 1) + horizonMonths + 1;
  return LocalDate(total ~/ 12, total % 12 + 1, 1).addDays(-1);
}
