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
/// a logged day always renders as logged, KTD3), and the vocabulary is
/// bleed-estimate only: no fertility or ovulation wording exists here.
library;

import '../models/local_date.dart';
import 'cycle_history.dart';
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

/// PMS badges cover estimate − [kPmsLeadDays] … estimate − 1 (roadmap
/// KTD7), only while an estimate is active.
const int kPmsLeadDays = 7;

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

  /// Estimated last bleed day of this cycle's band (inclusive).
  LocalDate get end => start.addDays(periodLengthDays - 1);

  @override
  String toString() =>
      'ForecastCycle(#$index ${start.iso}..${end.iso}, '
      'length: $lengthDays, spread: $spreadDays, tier: ${tier.name})';
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
    required this.tier,
    required this.cycleIndex,
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

  /// The cycle whose band/window covers this date.
  final CycleConfidence tier;
  final int cycleIndex;

  ForecastDayCell _withBadges({required bool pms, required bool cramps}) =>
      ForecastDayCell(
        predictedBleed: predictedBleed,
        cycleDayNumber: cycleDayNumber,
        pmsBadge: pmsBadge || pms,
        crampsBadge: crampsBadge || cramps,
        tier: tier,
        cycleIndex: cycleIndex,
      );

  @override
  String toString() =>
      'ForecastDayCell(bleed: $predictedBleed, cycleDay: $cycleDayNumber, '
      'pms: $pmsBadge, cramps: $crampsBadge, tier: ${tier.name})';
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
    cycles.add(
      ForecastCycle(
        index: index,
        start: start,
        lengthDays: step,
        periodLengthDays: periodLength,
        spreadDays: baseSpread + index * kForecastSpreadGrowthPerCycle,
        tier: index == 0 ? baseTier : degradeForecastTier(baseTier),
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
Map<String, ForecastDayCell> forecastDayCells({
  required List<ForecastCycle> cycles,
  required LocalDate today,
}) {
  final cells = <String, ForecastDayCell>{};
  for (final cycle in cycles) {
    // The first predicted cycle walks its full length (numerals cover the
    // whole cycle, not just the band); later cycles walk the band only.
    final spanDays = cycle.index == 0
        ? cycle.lengthDays
        : cycle.periodLengthDays;
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
        tier: cycle.tier,
        cycleIndex: cycle.index,
      );
    }
  }
  if (cycles.isEmpty) return cells;
  final estimate = cycles.first.start;
  final estimateTier = cycles.first.tier;
  for (var i = kPmsLeadDays; i >= 1; i--) {
    _markBadge(
      cells,
      estimate.addDays(-i),
      today,
      pms: true,
      cramps: false,
      tier: estimateTier,
    );
  }
  for (var i = -kCrampsLeadDays; i <= kCrampsTrailDays; i++) {
    _markBadge(
      cells,
      estimate.addDays(i),
      today,
      pms: false,
      cramps: true,
      tier: estimateTier,
    );
  }
  return cells;
}

void _markBadge(
  Map<String, ForecastDayCell> cells,
  LocalDate date,
  LocalDate today, {
  required bool pms,
  required bool cramps,
  required CycleConfidence tier,
}) {
  if (!date.isAfter(today)) return;
  final existing = cells[date.iso];
  cells[date.iso] = existing == null
      ? ForecastDayCell(
          predictedBleed: false,
          cycleDayNumber: null,
          pmsBadge: pms,
          crampsBadge: cramps,
          tier: tier,
          cycleIndex: 0,
        )
      : existing._withBadges(pms: pms, cramps: cramps);
}

/// The last day of the month [horizonMonths] after [today]'s month — the
/// navigable horizon the forecast must cover.
LocalDate _endOfHorizonMonth(LocalDate today, int horizonMonths) {
  final total = today.year * 12 + (today.month - 1) + horizonMonths + 1;
  return LocalDate(total ~/ 12, total % 12 + 1, 1).addDays(-1);
}
