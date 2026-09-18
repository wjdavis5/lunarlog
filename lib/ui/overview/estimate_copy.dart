/// Shared next-period-estimate disclaimer copy (R17): every estimate,
/// in every profile mode, sits next to this exact non-medical disclaimer,
/// without exception.
///
/// Issue #316 review: this constant used to live in `overview_panel.dart`,
/// which made `today_card.dart` import `overview_panel.dart` for it while
/// `overview_panel.dart` also imports `today_card.dart` to mount
/// [TodayCard] -- a mutual import between the two files. Pulled out to its
/// own tiny library so neither file needs the other for this one constant;
/// `overview_panel.dart` re-exports it (`export`) so `month_calendar.dart`'s
/// existing `show kEstimateDisclaimer` import of `overview_panel.dart`
/// keeps compiling unchanged.
library;

const String kEstimateDisclaimer = 'Estimates only — not medical advice.';

/// Fertile-window/ovulation-specific disclaimer (issue #143, per #142's
/// parity-audit finding A2-7): adapted from Clue's own published disclaimer
/// for this exact estimate, not paraphrased loosely. Renders in addition to
/// (never instead of) [kEstimateDisclaimer] next to every rendering of a
/// [FertileWindowEstimate] — the two estimates carry different risks: a
/// wrong period-date guess is an inconvenience, a fertile-window estimate
/// mistaken for contraception is not.
const String kFertileWindowDisclaimer =
    'This estimate must not be used to prevent pregnancy. It is not birth '
    'control and not a backup to birth control. It is based on a '
    'population-average luteal-phase length, and does not account for '
    'your own cycle variation. It has not been tested in a research '
    'study.';

/// The Conceive-mode conception-likelihood estimator's stated evidence
/// basis (issue #204 AC3): a plain-language line naming exactly which
/// study's numbers are used and that this is a substitute for Clue's
/// proprietary algorithm, not a reproduction of it. Rendered next to the
/// curve in the Cycle View and repeated in `docs/clinical/
/// conceive-estimator.md`, so the in-app claim and the written record can
/// never drift.
const String kConceiveEvidenceBasis =
    'Conception likelihood uses the day-by-day probabilities published by '
    'Wilcox, Weinberg & Baird (New England Journal of Medicine, 1995). It '
    "is a documented substitute for Clue's Dynamic Optimal Timing (DOT) "
    'algorithm, which is not public and could not be reproduced here.';

/// Conceive-mode conception-likelihood disclaimer (issue #204): the same
/// contraception and evidence-basis treatment issue #143's fertile-window
/// estimate carries, plus the explicit distinction the issue's acceptance
/// criteria require — a reader must be able to tell which prediction they
/// are looking at. Renders in addition to (never instead of)
/// [kEstimateDisclaimer] and [kFertileWindowDisclaimer] next to every
/// rendering of a [ConceptionEstimate].
const String kConceiveDisclaimer =
    'This conception likelihood must not be used to prevent pregnancy. It '
    'is not birth control and not a backup to birth control. It is not a '
    'test or a diagnosis, and it cannot tell you whether you are fertile '
    'today. It is computed from period start dates alone — a logged '
    'ovulation test or basal body temperature reading never changes it. '
    'It differs from the fertile-window estimate on Insights, which is '
    'plain calendar arithmetic around an assumed ovulation day. This '
    'estimator has not been tested in a research study.';
