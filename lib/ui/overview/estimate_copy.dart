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
