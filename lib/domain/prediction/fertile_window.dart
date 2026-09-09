/// Fertile-window and ovulation estimation (issue #143, enabled by #142's
/// removal of the "no fertility tracking" policy): pure calendar-method
/// back-calculation over the same logged-cycle history [prediction.dart]
/// already estimates the next period from. No new user input is required —
/// this is arithmetic on dates the app already has.
///
/// **Method** (#142's parity-audit finding A2-7, Clue-matched): estimated
/// ovulation is the next predicted period start minus an assumed
/// luteal-phase length ([kDefaultLutealPhaseDays], 14 days — Clue's own
/// published constant). The fertile window is the days immediately before
/// and including that estimated ovulation day
/// ([kFertileWindowLeadDays] before … [kFertileWindowTrailDays] after,
/// i.e. ovulation − 5 … ovulation + 1): sperm can survive several days
/// inside the body, while the egg itself is viable only about a day, so the
/// fertile window is asymmetric around ovulation rather than centered on
/// it.
///
/// **Confidence:** this estimate never derives its own tier — it always
/// carries the exact same [CycleConfidence] the period prediction it is
/// computed from already has (issue #213's tiering, reused unchanged, per
/// the issue's own instruction not to invent a second confidence
/// vocabulary). A fertile window is never shown with more apparent
/// precision than the period estimate it is derived from.
///
/// **Limits, stated plainly because this estimate is easy to over-trust:**
/// this is calendar math only, informed by nothing but logged period start
/// dates — no basal body temperature, cervical mucus/fluid, or ovulation
/// test result feeds it (that signal-logging taxonomy work is out of scope
/// for this file, tracked separately as issue #144). The 14-day luteal
/// default is a population average, not a measurement of this person's own
/// luteal phase, which can genuinely differ. **This is not a contraception
/// method** — see [kFertileWindowDisclaimer] in
/// `lib/ui/overview/estimate_copy.dart`, shipped next to every rendering of
/// this estimate.
///
/// **Reads the rolled estimate (review note):** [estimateFertileWindow] and
/// [currentFertileWindow] both key off [ActivePrediction.estimatedNextStart]
/// — issue #221's *rolled* date once a cycle goes late, not
/// [ActivePrediction.originalEstimatedNextStart]. That means the window
/// jumps forward a full mean-cycle-length step the same moment the period
/// estimate itself rolls, rather than drifting a day at a time — an
/// intentional consequence of reusing the period estimate's own
/// [PredictedCycle.start] unchanged (this file never derives a second,
/// independent ovulation date), not a bug to fix here.
///
/// **Short-cycle overlap (review note, undocumented until now, not yet
/// fixed):** at a mean cycle length ≤ 19 days, `windowStart` (ovulation −
/// [kFertileWindowLeadDays], i.e. the anchoring period start − 19) falls on
/// or before the *previous* cycle's predicted bleed band's own end date,
/// so the fertile window can render one or more days inside what the
/// calendar is simultaneously drawing as the previous predicted period.
/// Neither [fertileWindowFor] nor any caller clamps this away today; a
/// future fix should either clamp the window to start no earlier than the
/// previous cycle's predicted bleed end, or continue documenting the drop
/// explicitly here if the product decision is to leave it (cycles this
/// short are already `irregular`-tier by [confidenceTierFor]'s own
/// thresholds in the overwhelming majority of real histories, so this is a
/// narrow edge case rather than a common one).
library;

import '../models/local_date.dart';
import 'prediction.dart';

/// Default assumed luteal-phase length in days (Clue's own published
/// constant, per #142's parity audit) — the gap between ovulation and the
/// next period's start this estimate assumes absent any better signal.
const int kDefaultLutealPhaseDays = 14;

/// The fertile window starts this many days before estimated ovulation
/// (sperm survival) …
const int kFertileWindowLeadDays = 5;

/// … and ends this many days after it (egg viability). Provisional, like
/// [kDefaultLutealPhaseDays]: Clue does not publish its exact window width,
/// so this is this issue's own named, documented choice rather than a
/// verified clinical value.
const int kFertileWindowTrailDays = 1;

/// One estimated fertile window: the calendar-method ovulation day and the
/// range of days around it, at the same confidence [tier] as the period
/// prediction it was derived from.
class FertileWindowEstimate {
  const FertileWindowEstimate({
    required this.estimatedOvulation,
    required this.windowStart,
    required this.windowEnd,
    required this.tier,
  });

  /// Estimated ovulation day: the anchoring period start minus the assumed
  /// luteal-phase length.
  final LocalDate estimatedOvulation;

  /// First day of the estimated fertile window (inclusive).
  final LocalDate windowStart;

  /// Last day of the estimated fertile window (inclusive).
  final LocalDate windowEnd;

  /// The same [CycleConfidence] tier the underlying period estimate
  /// carries — never a separately derived value.
  final CycleConfidence tier;

  @override
  String toString() =>
      'FertileWindowEstimate(ovulation: ${estimatedOvulation.iso}, '
      'window: ${windowStart.iso}..${windowEnd.iso}, tier: ${tier.name})';
}

/// Back-calculates a [FertileWindowEstimate] from one predicted period
/// [start] at the given [tier] — the shared core [estimateFertileWindow]
/// and `forecast.dart`'s per-cycle derivation both build on, so the two
/// call sites can never drift onto two different formulas.
FertileWindowEstimate fertileWindowFor({
  required LocalDate start,
  required CycleConfidence tier,
  int lutealPhaseDays = kDefaultLutealPhaseDays,
}) {
  final ovulation = start.addDays(-lutealPhaseDays);
  return FertileWindowEstimate(
    estimatedOvulation: ovulation,
    windowStart: ovulation.addDays(-kFertileWindowLeadDays),
    windowEnd: ovulation.addDays(kFertileWindowTrailDays),
    tier: tier,
  );
}

/// The fertile-window estimate for the *next* predicted cycle, from a live
/// [prediction] — `null` when [prediction] is `null` (the caller's own
/// [NotEnoughHistory] case: too little history to estimate anything, so
/// nothing here either, per the issue's own acceptance criteria). Reuses
/// [prediction]'s own [ActivePrediction.tier] and
/// [ActivePrediction.estimatedNextStart] unchanged — this file never
/// derives a confidence tier of its own.
FertileWindowEstimate? estimateFertileWindow(
  ActivePrediction? prediction, {
  int lutealPhaseDays = kDefaultLutealPhaseDays,
}) {
  if (prediction == null) return null;
  return fertileWindowFor(
    start: prediction.estimatedNextStart,
    tier: prediction.tier,
    lutealPhaseDays: lutealPhaseDays,
  );
}

/// The fertile-window estimate that is still current as of [prediction]'s
/// own `today` (issue #143 review): [estimateFertileWindow] always
/// describes the *next* cycle's window even once that window has entirely
/// passed (`windowEnd` before `today`) — which reads as "the current
/// estimate" on screen when it is really stale history. This instead walks
/// [ActivePrediction.forecast] in order and returns the first
/// [fertileWindowFor] whose `windowEnd` has not yet passed, carrying that
/// forecast cycle's own [PredictedCycle.tier] — never the live estimate's
/// tier — so a window shown from a further-out, lower-confidence cycle
/// reads at that cycle's own confidence rather than the first cycle's.
///
/// `null` when [prediction] is `null` (the [NotEnoughHistory] case) or
/// every forecasted cycle's window has already passed (an empty or
/// entirely stale [ActivePrediction.forecast] — unreachable in practice
/// since the forecast spans well past today, kept so the caller can simply
/// hide the row rather than render something misleading).
FertileWindowEstimate? currentFertileWindow(
  ActivePrediction? prediction, {
  int lutealPhaseDays = kDefaultLutealPhaseDays,
}) {
  if (prediction == null) return null;
  for (final cycle in prediction.forecast) {
    final window = fertileWindowFor(
      start: cycle.start,
      tier: cycle.tier,
      lutealPhaseDays: lutealPhaseDays,
    );
    if (!window.windowEnd.isBefore(prediction.today)) return window;
  }
  return null;
}
