/// Postpartum mode (Issue #455): the pure computations behind the
/// day-count the overview surfaces, the "cycles have returned" signal, and
/// the exit-exclusion interval — the data-integrity sibling of Pregnancy
/// mode's `lib/domain/pregnancy.dart`.
///
/// Nothing here is Flutter and nothing is persisted (R14/R16 —
/// `test/architecture/layering_test.dart` enforces that): the mode start
/// lives in the synced `profile_modes.mode_started_on` column (#188), and
/// the exclusion rows live in `cycle_overrides` (#188), keyed per
/// cycle-start the way #132's omit-from-average consumer already reads
/// them.
///
/// The mode's prediction suppression while `postpartum` is active is
/// #528's generic life-stage branch (`lib/domain/prediction/
/// prediction_service.dart`), not this module: this file owns only the
/// mode's own math.
///
/// All date math is on civil dates ([LocalDate]); the caller supplies
/// `today` in the profile's local zone, matching `prediction.dart`'s
/// convention.
library;

import 'episodes/episodes.dart';
import 'mode_intervals.dart';
import 'models/local_date.dart';

/// Whole civil days on [today] since the profile entered Postpartum mode
/// ([modeStartedOn] is `profile_modes.mode_started_on`). Floored at 0 so a
/// `today` before the anchor — a clock rollback, or a date entered in
/// error — reads as day 0 rather than a negative count.
///
/// Issue #861: [birthDate] is `profile_modes.postpartum_birth_date`, the
/// optional actual birth date the operator can supply. When present it is
/// the anchor the count runs from (the number is then usefully "since
/// birth"); when absent the mode start remains the surrogate — stamped
/// when the operator selects Postpartum, which is the app's only recorded
/// proxy for that date. The caller supplies exactly one meaning, never
/// mixes them.
int daysSincePostpartumStart({
  required LocalDate modeStartedOn,
  required LocalDate today,
  LocalDate? birthDate,
}) {
  final days = today.difference(birthDate ?? modeStartedOn);
  return days < 0 ? 0 : days;
}

/// Whether any bleed has been logged on or after [modeStartedOn] — the
/// "first logged bleed in Postpartum mode" signal the overview's
/// cycles-have-returned offer is built on.
///
/// Deliberately dates-only (no episode grouping): the issue's trigger is a
/// logged bleed, and the offer that follows is never forced, so the
/// lochia/spotting that can follow birth simply surfaces the same offer
/// (the operator is the one who decides whether it means cycles have
/// returned). A null [modeStartedOn] (a mode entered before the column was
/// stamped) is an honest false rather than a guessed interval.
bool hasLoggedBleedSince({
  required Iterable<LocalDate> bleedDates,
  required LocalDate? modeStartedOn,
}) {
  if (modeStartedOn == null) return false;
  return bleedDates.any((date) => !date.isBefore(modeStartedOn));
}

/// The cycle-start dates the postpartum-exit exclusion (Issue #455 AC2)
/// must omit from cycle averages: every episode start inside the
/// half-open interval `[modeStartedOn, exitedOn)`.
///
/// Delegates to `intervalExclusionStarts` (`lib/domain/mode_intervals.dart`),
/// which documents why the bound is half-open and why every start inside the
/// interval gets its own `cycle_overrides` row. Unlike pregnancy (which
/// anchors at the last pre-pregnancy period before the mode was stamped —
/// Issue #823), the postpartum interval begins at the mode start (birth).
/// The postpartum interval can contain apparent cycle starts (lochia, then
/// spotting, then a first real period) whose spacing lands inside the
/// 15–60 day validity window and would otherwise poison the post-postpartum
/// mean.
Set<LocalDate> postpartumExclusionStarts({
  required Iterable<Episode> episodes,
  required LocalDate? modeStartedOn,
  required LocalDate exitedOn,
}) =>
    intervalExclusionStarts(
      episodes: episodes,
      modeStartedOn: modeStartedOn,
      exitedOn: exitedOn,
    );
