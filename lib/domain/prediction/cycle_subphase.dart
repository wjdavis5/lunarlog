/// Six biological hormonal subphases of the menstrual cycle (Issue #236, A2-23).
///
/// Derived from calendar-method cycle predictions and the estimated ovulation
/// back-calculation ([estimateFertileWindow] in `fertile_window.dart`).
///
/// **Subphases**:
/// 1. [earlyFollicular]: Cycle Day 1 through bleed days (menses). Estrogen &
///    progesterone at baseline.
/// 2. [lateFollicular]: Post-menses through pre-ovulation. Estradiol rises as
///    the dominant follicle develops.
/// 3. [ovulation]: 3-day window centered around estimated ovulation. LH surge
///    triggers egg release; estrogen peaks.
/// 4. [earlyLuteal]: Days immediately post-ovulation. Corpus luteum forms and
///    initiates progesterone secretion.
/// 5. [midLuteal]: Peak luteal phase. Progesterone peaks; endometrium reaches
///    receptivity.
/// 6. [lateLuteal]: Premenstrual phase. Progesterone and estrogen drop sharply;
///    withdrawal triggers PMS and menses.
///
/// **Constraints & Framing**:
/// - Descriptive biological education only: no individualised medical advice,
///   no diagnostic assertions, no cross-user aggregation.
/// - Whenever the underlying prediction's confidence tier is not
///   [CycleConfidence.high], or the cycle is overdue, explainer copy is
///   honestly hedged to indicate statistical estimation rather than certainty.
library;

import '../models/local_date.dart';
import 'fertile_window.dart';
import 'prediction.dart';

/// One of the six biological subphases of the menstrual cycle.
enum CycleSubphase {
  earlyFollicular,
  lateFollicular,
  ovulation,
  earlyLuteal,
  midLuteal,
  lateLuteal;

  /// Stable string identifier.
  String get id => switch (this) {
        CycleSubphase.earlyFollicular => 'early_follicular',
        CycleSubphase.lateFollicular => 'late_follicular',
        CycleSubphase.ovulation => 'ovulation',
        CycleSubphase.earlyLuteal => 'early_luteal',
        CycleSubphase.midLuteal => 'mid_luteal',
        CycleSubphase.lateLuteal => 'late_luteal',
      };

  /// User-facing display title.
  String get displayName => switch (this) {
        CycleSubphase.earlyFollicular => 'Early Follicular (Period)',
        CycleSubphase.lateFollicular => 'Late Follicular',
        CycleSubphase.ovulation => 'Ovulation Window',
        CycleSubphase.earlyLuteal => 'Early Luteal',
        CycleSubphase.midLuteal => 'Mid Luteal',
        CycleSubphase.lateLuteal => 'Late Luteal (Premenstrual)',
      };

  /// Short summary of hormonal activity.
  String get hormonalSummary => switch (this) {
        CycleSubphase.earlyFollicular =>
          'Estrogen and progesterone are at baseline levels as the uterine lining sheds.',
        CycleSubphase.lateFollicular =>
          'Estrogen rises steadily as ovarian follicles mature, rebuilding the uterine lining.',
        CycleSubphase.ovulation =>
          'Luteinizing hormone (LH) surges, prompting egg release. Estrogen reaches its peak.',
        CycleSubphase.earlyLuteal =>
          'The corpus luteum forms and begins secreting progesterone, raising body temperature.',
        CycleSubphase.midLuteal =>
          'Progesterone peaks, stabilizing the uterine lining and supporting potential implantation.',
        CycleSubphase.lateLuteal =>
          'Progesterone and estrogen decline sharply if no pregnancy occurs, initiating premenstrual changes.',
      };

  /// Primary educational article ID in the bundled cycle-literacy library.
  String get primaryArticleId => switch (this) {
        CycleSubphase.earlyFollicular => 'menstrual-cycle-phases',
        CycleSubphase.lateFollicular => 'understanding-follicular-phase',
        CycleSubphase.ovulation => 'understanding-ovulation',
        CycleSubphase.earlyLuteal => 'luteal-phase-and-progesterone',
        CycleSubphase.midLuteal => 'pms-and-progesterone',
        CycleSubphase.lateLuteal => 'why-cramps-happen',
      };

  /// Recommended tracking focus for this subphase.
  String get whatToTrack => switch (this) {
        CycleSubphase.earlyFollicular =>
          'Flow intensity, cramps, pelvic discomfort, fatigue, and headaches.',
        CycleSubphase.lateFollicular =>
          'Energy levels, skin changes, mood shifts, and developing cervical fluid.',
        CycleSubphase.ovulation =>
          'Cervical fluid consistency (clear, stretchy), basal temperature shift, and pelvic sensations.',
        CycleSubphase.earlyLuteal =>
          'Basal body temperature increase, drying cervical fluid, and appetite changes.',
        CycleSubphase.midLuteal =>
          'Bloating, breast tenderness, mood changes, and cravings.',
        CycleSubphase.lateLuteal =>
          'Cramps, sleep quality, irritability, backache, and spotting.',
      };
}

/// Sourced, calculated context for an active cycle's subphase.
class CycleSubphaseInfo {
  const CycleSubphaseInfo({
    required this.subphase,
    required this.cycleDay,
    required this.startCycleDay,
    required this.endCycleDay,
    required this.startDate,
    required this.endDate,
    required this.isHedged,
    required this.hedgedNotice,
    required this.biologicalExplainer,
    required this.source,
    required this.reviewDate,
  });

  /// The active subphase.
  final CycleSubphase subphase;

  /// The current cycle day (1-based).
  final int cycleDay;

  /// Start cycle day for this subphase (inclusive).
  final int startCycleDay;

  /// End cycle day for this subphase (inclusive).
  final int endCycleDay;

  /// Calendar start date of the subphase window.
  final LocalDate startDate;

  /// Calendar end date of the subphase window.
  final LocalDate endDate;

  /// Whether the estimate carries statistical uncertainty hedging.
  final bool isHedged;

  /// Explanatory hedging notice when confidence is learning/irregular or late.
  final String? hedgedNotice;

  /// Plain-language, expert-sourced biological explainer.
  final String biologicalExplainer;

  /// Named clinical/academic source.
  final String source;

  /// Review date of the copy.
  final String reviewDate;

  /// Range label (e.g. "Cycle Days 1–5").
  String get cycleDayRangeText => startCycleDay == endCycleDay
      ? 'Cycle Day $startCycleDay'
      : 'Cycle Days $startCycleDay–$endCycleDay';

  static const String kSourceCitation =
      'ACOG Patient Education FAQ049; Speroff\'s Clinical Gynecologic Endocrinology (9th ed.)';
  static const String kReviewDate = '2026-09-12';
}

/// Derives the active [CycleSubphaseInfo] for [today] given [prediction].
CycleSubphaseInfo deriveSubphase({
  required ActivePrediction prediction,
  required LocalDate today,
}) {
  final cycleDay = prediction.cycleDay;
  final meanLength = prediction.meanCycleLengthDays.round().clamp(15, 60);
  final bleedLength = prediction.meanPeriodLengthDays > 0
      ? prediction.meanPeriodLengthDays.round().clamp(1, 10)
      : kDefaultPeriodLengthDays;

  // Ovulation day estimate (anchored on next period start minus luteal phase).
  final estimatedOvulation =
      prediction.estimatedNextStart.addDays(-kDefaultLutealPhaseDays);
  final rawOvulationCycleDay =
      estimatedOvulation.difference(prediction.lastEpisodeStart) + 1;
  final minOvulationDay = bleedLength + 2;
  final maxOvulationDay = (meanLength - 2) >= minOvulationDay
      ? meanLength - 2
      : minOvulationDay;
  final ovulationDay = rawOvulationCycleDay.clamp(minOvulationDay, maxOvulationDay);

  // Subphase boundaries (cycle-day ranges):
  // 1. Early Follicular: Day 1 to bleed length (or while duringEpisode is true).
  final earlyFollicularEnd = prediction.duringEpisode
      ? (cycleDay > bleedLength ? cycleDay : bleedLength)
      : bleedLength;

  // 2. Late Follicular: day after bleed to day before ovulation window.
  final lateFollicularStart = earlyFollicularEnd + 1;
  final ovulationStart = ovulationDay - 1;
  final lateFollicularEnd = (ovulationStart - 1) >= lateFollicularStart
      ? ovulationStart - 1
      : lateFollicularStart;

  // 3. Ovulation: 3 days (ovulationDay - 1 to ovulationDay + 1).
  final effectiveOvulationStart = lateFollicularEnd + 1;
  final ovulationEnd = ovulationDay + 1;

  // 4, 5, 6. Luteal subphases: proportionally divide the post-ovulation span.
  final lutealStart = ovulationEnd + 1;
  final lutealEnd = meanLength >= (lutealStart + 2) ? meanLength : (lutealStart + 2);
  final lutealDays = lutealEnd - lutealStart + 1;

  final earlyDuration = (lutealDays / 3).round().clamp(1, lutealDays - 2);
  final earlyLutealStart = lutealStart;
  final earlyLutealEnd = earlyLutealStart + earlyDuration - 1;

  final remainingAfterEarly = lutealDays - earlyDuration;
  final midDuration = (remainingAfterEarly / 2).round().clamp(1, remainingAfterEarly - 1);
  final midLutealStart = earlyLutealEnd + 1;
  final midLutealEnd = midLutealStart + midDuration - 1;

  final lateLutealStart = midLutealEnd + 1;
  final lateLutealEnd = lutealEnd;

  // Determine which subphase the current cycleDay falls into.
  final CycleSubphase subphase;
  final int subphaseStartCd;
  final int subphaseEndCd;

  if (prediction.duringEpisode || cycleDay <= earlyFollicularEnd) {
    subphase = CycleSubphase.earlyFollicular;
    subphaseStartCd = 1;
    subphaseEndCd = earlyFollicularEnd;
  } else if (cycleDay <= lateFollicularEnd) {
    subphase = CycleSubphase.lateFollicular;
    subphaseStartCd = lateFollicularStart;
    subphaseEndCd = lateFollicularEnd;
  } else if (cycleDay <= ovulationEnd) {
    subphase = CycleSubphase.ovulation;
    subphaseStartCd = effectiveOvulationStart;
    subphaseEndCd = ovulationEnd;
  } else if (cycleDay <= earlyLutealEnd) {
    subphase = CycleSubphase.earlyLuteal;
    subphaseStartCd = earlyLutealStart;
    subphaseEndCd = earlyLutealEnd;
  } else if (cycleDay <= midLutealEnd) {
    subphase = CycleSubphase.midLuteal;
    subphaseStartCd = midLutealStart;
    subphaseEndCd = midLutealEnd;
  } else {
    subphase = CycleSubphase.lateLuteal;
    subphaseStartCd = lateLutealStart;
    // If overdue, expand end cycle day to current cycle day so it's honest.
    subphaseEndCd = cycleDay > lateLutealEnd ? cycleDay : lateLutealEnd;
  }

  final subphaseStartDate =
      prediction.lastEpisodeStart.addDays(subphaseStartCd - 1);
  final subphaseEndDate =
      prediction.lastEpisodeStart.addDays(subphaseEndCd - 1);

  final isHedged = prediction.tier != CycleConfidence.high || prediction.isLate;
  final hedgedNotice = isHedged
      ? (prediction.isLate
          ? 'Cycle is running longer than average. Subphase estimates remain in late luteal awaiting your next period.'
          : 'Subphase timing is estimated from your cycle average. Exact hormonal transitions vary from cycle to cycle.')
      : null;

  return CycleSubphaseInfo(
    subphase: subphase,
    cycleDay: cycleDay,
    startCycleDay: subphaseStartCd,
    endCycleDay: subphaseEndCd,
    startDate: subphaseStartDate,
    endDate: subphaseEndDate,
    isHedged: isHedged,
    hedgedNotice: hedgedNotice,
    biologicalExplainer: subphase.hormonalSummary,
    source: CycleSubphaseInfo.kSourceCitation,
    reviewDate: CycleSubphaseInfo.kReviewDate,
  );
}
