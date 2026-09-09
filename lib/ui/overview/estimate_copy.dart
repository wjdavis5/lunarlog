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
