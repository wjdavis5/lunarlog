/// Pregnancy mode (Issue #192): the pure computations behind due-date
/// derivation, the week-of-pregnancy counter, and the exit-exclusion
/// interval — the data-integrity half of the issue ("a pregnancy today
/// permanently poisons the cycle mean with no correction" is the bug this
/// module closes, together with the `cycle_overrides` rows
/// [pregnancyExclusionStarts] enumerates).
///
/// Nothing here is Flutter and nothing is persisted (R14/R16 —
/// `test/architecture/layering_test.dart` enforces that): the due date
/// itself lives in the synced `profile_modes.estimated_due_date` column
/// (this issue's migration), and the exclusion rows live in
/// `cycle_overrides` (#188), keyed per cycle-start the way #132's
/// omit-from-average consumer already reads them.
///
/// All date math is on civil dates ([LocalDate]); the caller supplies
/// `today` in the profile's local zone, matching `prediction.dart`'s
/// convention.
library;

import 'episodes/episodes.dart';
import 'mode_intervals.dart';
import 'models/local_date.dart';

/// Naegele's rule, the 280-day gestation Clue's own week calculation is
/// built on (support.helloclue.com/hc/en-us/articles/4824164467220):
/// estimated due date = last period start + 280 days. Named here so the
/// week counter and the due-date derivation can never disagree about the
/// gestation length they share.
const int kGestationDays = 280;

/// The estimated due date for a pregnancy whose last recorded period
/// started on [lastPeriodStart]: [kGestationDays] days later (Naegele's
/// rule). Pure; a manual override simply never calls this.
LocalDate estimatedDueDateFromLastPeriod(LocalDate lastPeriodStart) =>
    lastPeriodStart.addDays(kGestationDays);

/// Gestational age in whole elapsed days on [today], derived backwards
/// from the [dueDate] (the same back-calculation Clue documents: the due
/// date is fixed at LMP + 280, so "days of gestation elapsed" is 280
/// minus the days remaining). Negative before the last period start —
/// callers wanting a displayable week clamp through [pregnancyWeekOf].
int gestationalAgeDays({required LocalDate dueDate, required LocalDate today}) =>
    kGestationDays - dueDate.difference(today);

/// The current week of pregnancy on [today], 0-based in gestational-age
/// terms and floored at 0 (a `today` before the implied last period start
/// — a bad manual due date, or a clock rollback — reads as week 0, never
/// a negative week):
///
/// ```text
/// week = max(0, floor(gestationalAgeDays / 7))
///      = max(0, floor((280 - (dueDate - today)) / 7))
/// ```
///
/// So the day the last period started reads week 0, day 7 reads week 1,
/// and the due date itself reads week 40. Past the due date the count
/// keeps growing (an overdue pregnancy is gestational weeks 41, 42, …) —
/// the honest number, not a frozen 40.
int pregnancyWeekOf({required LocalDate dueDate, required LocalDate today}) {
  final days = gestationalAgeDays(dueDate: dueDate, today: today);
  return days < 0 ? 0 : days ~/ 7;
}

/// Whole civil days from [today] to [dueDate] (negative once overdue) —
/// the "days to go" line the Pregnancy card renders next to the week.
int daysUntilDueDate({required LocalDate dueDate, required LocalDate today}) =>
    dueDate.difference(today);

/// The cycle-start dates the pregnancy-exit exclusion (Issue #192 AC4/5)
/// must omit from cycle averages: every episode start inside the
/// half-open interval `[modeStartedOn, exitedOn)`.
///
/// Why every start in the interval, not just one row at
/// [modeStartedOn]: `cycle_overrides` is keyed by single cycle-start
/// dates (#132's consumption mechanism — the history list's omit toggle
/// and the predictor's `omittedCycleStarts` both read it that way), and
/// the pregnancy interval can contain *several* apparent cycle starts —
/// the pregnancy-long "cycle" that starts at the last pre-pregnancy
/// period, plus any mid-pregnancy breakthrough-bleeding episodes. A
/// 280-day apparent cycle is already outside the 15–60 validity window
/// and never feeds the mean, but a mid-pregnancy episode pair (e.g.
/// 45 and 49 days apart) lands *inside* the window and is exactly the
/// mean-poisoning this issue exists to correct — so every cycle that
/// *starts* inside the interval gets an exclusion row. Writing one row
/// per start through `CycleOverridesRepository.setExcludedFromAverage`
/// is how "a `cycle_overrides` row with `excluded_from_average = true`
/// spanning `mode_started_on` through the exit date" is realized on the
/// #188 schema, which has no interval columns.
///
/// [exitedOn] is the date the mode moved off `pregnancy` (the new mode's
/// own `mode_started_on`); a period starting exactly on [exitedOn] is the
/// first *real* post-pregnancy cycle and is deliberately NOT excluded —
/// that half-open bound is what keeps the exclusion from eating the
/// recovery data the mean needs. A null [modeStartedOn] (a pregnancy
/// entered before this issue stamped the column) excludes nothing — an
/// honest empty set the caller can surface, rather than a guessed
/// interval.
Set<LocalDate> pregnancyExclusionStarts({
  required Iterable<Episode> episodes,
  required LocalDate? modeStartedOn,
  required LocalDate exitedOn,
}) =>
    intervalExclusionStarts(
      episodes: episodes,
      modeStartedOn: modeStartedOn,
      exitedOn: exitedOn,
    );
