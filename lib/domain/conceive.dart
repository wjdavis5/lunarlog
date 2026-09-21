/// Conceive mode (Issue #204): the DOT-equivalent per-day conception
/// likelihood estimator and the mode's day-sheet category prioritization.
///
/// **This is a second, mode-scoped estimator, deliberately separate from
/// issue #143's calendar-method fertile-window estimate**
/// (`lib/domain/prediction/fertile_window.dart`). #143 answers "which days
/// are around the estimated ovulation day" with a binary window; this file
/// answers "how likely is conception from intercourse on each day of the
/// cycle" with a per-day probability curve. The two never share a
/// derivation — a caller that wants the fertile window uses
/// [currentFertileWindow]; a caller that wants the conception curve uses
/// [currentConceptionEstimate].
///
/// **Evidence basis (stated here and in the UI).** Clue's Conceive mode
/// uses Dynamic Optimal Timing (DOT), a proprietary model developed by the
/// Institute for Reproductive Health at Georgetown University, which
/// lunarlog cannot license or reproduce. This file ships a documented
/// substitute: the day-by-day conception probabilities published by
/// Wilcox, Weinberg & Baird, "Timing of sexual intercourse in relation to
/// ovulation", *N Engl J Med* 1995;333(23):1517-1521 — the same
/// population-average study the issue names as the fallback evidence
/// basis. Those are probabilities of clinical pregnancy from a single act
/// of intercourse on a given day relative to ovulation, not a personalised
/// prediction, and the estimator otherwise reuses the app's ordinary
/// period-date math ([kDefaultLutealPhaseDays] back from the predicted
/// next period start). It has not been validated in a research study, and
/// it is **not a contraception method** — see [kConceiveDisclaimer] in
/// `lib/ui/overview/estimate_copy.dart`, rendered next to every surface
/// that shows this curve.
///
/// **Computed from period start dates alone.** Neither [conceptionEstimateFor]
/// nor [conceiveEstimateFromHistory] takes a tag, a symptom, an ovulation
/// test, or a basal body temperature reading: those are logged for the
/// user's own reference only. Clue deliberately keeps DOT working from
/// period dates alone (tests/BBT narrow confidence for the #143 Period
/// Tracking estimate only), and `test/domain/conceive_test.dart` pins that
/// logging an ovulation test or a BBT reading leaves this estimator's
/// output byte-for-byte unchanged — a safety-relevant property, not an
/// implementation accident.
///
/// Nothing here is Flutter and nothing is persisted (R14/R16 —
/// `test/architecture/layering_test.dart` enforces that). All date math is
/// on civil dates ([LocalDate]); the caller supplies `today` in the
/// profile's local zone, matching `prediction.dart`'s convention.
library;

import 'episodes/episodes.dart';
import 'models/day_entry.dart';
import 'models/local_date.dart';
import 'prediction/fertile_window.dart' show kDefaultLutealPhaseDays;
import 'prediction/prediction.dart';
import 'tags.dart';

/// The published per-day conception probabilities used by this estimator,
/// keyed by the day offset from estimated ovulation (negative = before
/// ovulation, `0` = ovulation day), in chronological order.
///
/// The curve ends at day `0`. Wilcox, Weinberg & Baird (NEJM 1995,
/// doi:10.1056/NEJM199512073332301) report that conception occurred only
/// during the six-day period ending on the estimated day of ovulation, so
/// the study publishes no probability for the day after ovulation and none
/// is invented here.
///
/// Values are the point estimates from that study for the probability of
/// clinical pregnancy following a single act of intercourse on that day.
/// They are population averages, not a measurement of any individual's
/// fertility. A named, cited table rather than inline literals so the
/// evidence basis can never drift from the numbers.
const Map<int, double> kConceptionProbabilityByDayOffset = {
  -5: 0.10,
  -4: 0.16,
  -3: 0.14,
  -2: 0.27,
  -1: 0.31,
  0: 0.33,
};

/// One day's estimated conception likelihood: [probability] is the
/// published population-average probability (0..1) of clinical pregnancy
/// from a single act of intercourse on [date], under this estimator's
/// assumption that [date] sits at the corresponding offset from estimated
/// ovulation.
class ConceptionDayLikelihood {
  const ConceptionDayLikelihood({
    required this.date,
    required this.probability,
  });

  final LocalDate date;
  final double probability;

  @override
  bool operator ==(Object other) =>
      other is ConceptionDayLikelihood &&
      other.date == date &&
      other.probability == probability;

  @override
  int get hashCode => Object.hash(date, probability);

  @override
  String toString() => 'ConceptionDayLikelihood(${date.iso}, $probability)';
}

/// A full cycle's per-day conception-likelihood curve: the estimated
/// ovulation day, the six likelihood days in the study's window, the window
/// bounds, and the peak day — all at the same [tier] as the period estimate
/// the window was anchored on (never a second confidence vocabulary, the
/// #213/#143 rule).
class ConceptionEstimate {
  const ConceptionEstimate({
    required this.estimatedOvulation,
    required this.days,
    required this.fertileWindowStart,
    required this.fertileWindowEnd,
    required this.peakDay,
    required this.peakProbability,
    required this.tier,
  });

  /// The estimated ovulation day: the anchoring period start minus the
  /// assumed luteal-phase length.
  final LocalDate estimatedOvulation;

  /// The per-day curve in chronological order (ovulation − 5 … ovulation)
  /// — the six-day conception window the study reports.
  final List<ConceptionDayLikelihood> days;

  /// First day of the conception window (inclusive).
  final LocalDate fertileWindowStart;

  /// Last day of the conception window (inclusive).
  final LocalDate fertileWindowEnd;

  /// The day carrying [peakProbability].
  final LocalDate peakDay;

  /// The highest probability on the curve (the study's ovulation-day
  /// value, 0.33).
  final double peakProbability;

  /// The same [CycleConfidence] tier the underlying period estimate
  /// carries — never independently derived.
  final CycleConfidence tier;

  @override
  String toString() =>
      'ConceptionEstimate(ovulation: ${estimatedOvulation.iso}, '
      'window: ${fertileWindowStart.iso}..${fertileWindowEnd.iso}, '
      'peak: ${peakDay.iso} $peakProbability, tier: ${tier.name})';
}

/// Back-calculates a [ConceptionEstimate] from one predicted period
/// [nextPeriodStart] at the given [tier]: estimated ovulation is
/// [nextPeriodStart] minus [lutealPhaseDays] (Clue's own published
/// 14-day constant, shared with `fertile_window.dart` so the two
/// estimators can never disagree about the luteal assumption), and each
/// entry of [kConceptionProbabilityByDayOffset] lands on the
/// corresponding calendar day. Pure and date-only.
ConceptionEstimate conceptionEstimateFor({
  required LocalDate nextPeriodStart,
  required CycleConfidence tier,
  int lutealPhaseDays = kDefaultLutealPhaseDays,
}) {
  final ovulation = nextPeriodStart.addDays(-lutealPhaseDays);
  final days = [
    for (final entry in kConceptionProbabilityByDayOffset.entries)
      ConceptionDayLikelihood(
        date: ovulation.addDays(entry.key),
        probability: entry.value,
      ),
  ];
  var peak = days.first;
  for (final day in days) {
    if (day.probability > peak.probability) peak = day;
  }
  return ConceptionEstimate(
    estimatedOvulation: ovulation,
    days: List.unmodifiable(days),
    fertileWindowStart: days.first.date,
    fertileWindowEnd: days.last.date,
    peakDay: peak.date,
    peakProbability: peak.probability,
    tier: tier,
  );
}

/// The conception-likelihood curve that is still current as of
/// [prediction]'s own `today` (the same "first forecast cycle whose
/// window has not passed" rule [currentFertileWindow] applies to the #143
/// window): walks [ActivePrediction.forecast] and returns the first
/// estimate whose [ConceptionEstimate.fertileWindowEnd] has not yet
/// passed, carrying that forecast cycle's own [PredictedCycle.tier].
///
/// `null` when [prediction] is null (the caller's own too-little-history
/// case), when its basis is [PredictionBasis.regimenSchedule] (a pack
/// cadence asserts no ovulatory event — see [PredictionBasis]'s own doc
/// comment), or when every forecast window has already passed.
ConceptionEstimate? currentConceptionEstimate(ActivePrediction? prediction) {
  if (prediction == null) return null;
  // Issue #859: a stale history's estimate is rolled many cycles past the
  // last log — a conception curve derived from it would point at a cycle
  // nobody logged, so hide it.
  if (prediction.staleHistory) return null;
  if (prediction.basis == PredictionBasis.regimenSchedule) return null;
  for (final cycle in prediction.forecast) {
    final estimate = conceptionEstimateFor(
      nextPeriodStart: cycle.start,
      tier: cycle.tier,
    );
    if (!estimate.fertileWindowEnd.isBefore(prediction.today)) return estimate;
  }
  return null;
}

/// The Conceive-mode estimator computed from logged history alone: derives
/// the bleed episodes from [entries] (`bleedDatesOf`/`deriveEpisodes`, so
/// only flow-carrying days are read), runs the ordinary predictor, and
/// returns the current curve.
///
/// Deliberately takes no tags, observations, or measurements. A day entry
/// carrying `ovulation_positive`/`ovulation_peak`/`ovulation_negative`, or
/// a `bbt` observation row, is **not** an input here and can never move
/// the output — Clue keeps DOT working from period dates alone, and
/// tests/BBT only ever narrow the #143 Period Tracking estimate. This
/// function exists as the named seam that regression test pins.
ConceptionEstimate? conceiveEstimateFromHistory({
  required List<DayEntry> entries,
  required LocalDate today,
  Set<LocalDate> omittedCycleStarts = const {},
  ActiveBirthControl? birthControl,
}) {
  final episodes = deriveEpisodes(bleedDatesOf(entries));
  final prediction = computePrediction(
    episodes: episodes,
    today: today,
    omittedCycleStarts: omittedCycleStarts,
    birthControl: birthControl,
  );
  return currentConceptionEstimate(
    prediction is ActivePrediction ? prediction : null,
  );
}

/// Categories Conceive mode surfaces before the rest of the day sheet
/// (Issue #204 AC5): the two fertility-signal categories #253 shipped —
/// ovulation-test results and cervical fluid/discharge. They are logged
/// for the user's own reference; see this library's header for the
/// no-influence rule. A plain ordered list so the intent is data, not a
/// branch a future caller has to re-derive.
const List<TagCategory> kConceivePriorityCategories = [
  TagCategory.tests,
  TagCategory.discharge,
];

/// Returns [base] reordered so [kConceivePriorityCategories] come first,
/// in the order named there, with every other category keeping its
/// previous relative order. Never adds or removes a category — Conceive
/// mode prioritizes, it does not hide (`care_modes.dart`'s "not a
/// euphemism for a reduced app" rule applies to this axis too).
List<TagCategory> conceiveCategoryOrder(List<TagCategory> base) => [
      for (final category in kConceivePriorityCategories)
        if (base.contains(category)) category,
      for (final category in base)
        if (!kConceivePriorityCategories.contains(category)) category,
    ];
