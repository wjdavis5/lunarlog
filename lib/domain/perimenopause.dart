/// Perimenopause mode (Issue #196): the mode-scoped domain facts that make
/// the Cycle View comparison-first and surface the perimenopause symptom
/// cluster, while leaving every other mode untouched.
///
/// **This is a life-stage mode, not a care mode.** It is the `profile_modes`
/// axis ([LifecycleMode], Issue #188), orthogonal to Issue #131's care-mode
/// axis (`ProfileMode`: standard/teen/caregiver/irregular). This file never
/// consults `ProfileMode`; the reconciliation between the two axes — how a
/// profile can be in perimenopause life-stage mode under any care-mode
/// framing — is recorded in `docs/clinical/perimenopause-mode.md`, which is
/// issue #196's written decision (AC5).
///
/// **What the mode changes, and what it deliberately does not:**
/// * Prediction is already suppressed for `perimenopause` by Issue #528
///   (`prediction_service.dart`'s `_suppressesPrediction`), so the ordinary
///   days-late countdown never renders — this module does not re-implement
///   that suppression, it is the reason [PerimenopauseComparisonStarts]
///   exists at all (comparison is what replaces the countdown). Predicating
///   on the same mode here keeps the two consumers reading one definition.
/// * The fertile-window estimate ([suppressesFertileWindow]) is hidden for
///   this mode — a precise-looking ovulation window is exactly the false
///   precision the mode's whole posture avoids.
/// * The day sheet surfaces the perimenopause symptom categories first
///   ([kPerimenopausePriorityCategories]/[perimenopauseCategoryOrder]) —
///   it reorders, it never hides a category (the same "not a euphemism for
///   a reduced app" rule `care_modes.dart` and `conceive.dart` apply).
/// * `hot_flashes` itself is a top-level category in **every** mode and is
///   never gated behind this one (AC4) — this file only ever reorders it.
///
/// Nothing here is Flutter and nothing is persisted (R14/R16 —
/// `test/architecture/layering_test.dart` enforces that). All date math is
/// on civil dates ([LocalDate]).
library;

import 'episodes/episodes.dart';
import 'models/lifecycle_mode.dart';
import 'models/local_date.dart';
import 'tags.dart';

/// Whether [mode] is the Perimenopause life-stage mode (Issue #188/#196).
///
/// A single named predicate rather than an inline `== LifecycleMode
/// .perimenopause` at each call site, so the mode's boundaries (`null` — no
/// `profile_modes` row yet — means "not perimenopause", exactly as
/// [LifecycleMode.fromDb] degrades) stay one definition.
bool isPerimenopauseMode(LifecycleMode? mode) =>
    mode == LifecycleMode.perimenopause;

/// Whether the fertile-window estimate (Issue #143) must be hidden for the
/// life-stage [mode] (Issue #196 AC1): true only for Perimenopause.
///
/// The estimate's whole value is a precise-looking ovulation window; in a
/// mode for cycles that are legitimately, naturally irregular that is false
/// precision, so the band, the legend entry, and the Analysis row are all
/// suppressed together. Prediction is already suppressed for this mode
/// (#528), so this is the belt-and-braces gate the issue names explicitly.
bool suppressesFertileWindow(LifecycleMode? mode) =>
    isPerimenopauseMode(mode);

/// Categories Perimenopause mode surfaces before the rest of the day sheet
/// (Issue #196 AC3).
///
/// The attested perimenopause symptom vocabulary lives under
/// [TagCategory.hotFlashes] (`hot_flashes`, `night_sweats`, `brain_fog`,
/// `hrt`, `vaginal_dryness` — the five codes Issue #456 pinned from Clue's
/// public sources); only five of the fourteen options Clue ships are
/// publicly attested, so the remaining ~9 are deliberately not invented
/// (`lib/domain/tags.dart`'s "no invented placeholder" discipline). This
/// list therefore prioritizes the categories that carry the mode's symptom
/// vocabulary — hot flashes first, then the sleep/energy/mind/feelings
/// cluster that host sleep disruption, fatigue, and brain-fog-adjacent
/// codes — rather than pretending to enumerate options that do not exist.
///
/// A plain ordered list so the intent is data, not a branch a future caller
/// has to re-derive.
const List<TagCategory> kPerimenopausePriorityCategories = [
  TagCategory.hotFlashes,
  TagCategory.sleep,
  TagCategory.energy,
  TagCategory.mind,
  TagCategory.feelings,
];

/// Returns [base] reordered so [kPerimenopausePriorityCategories] come
/// first, in the order named there, with every other category keeping its
/// previous relative order. Never adds or removes a category — Perimenopause
/// mode prioritizes, it does not hide (`care_modes.dart`'s "not a euphemism
/// for a reduced app" rule applies to this axis too). Mirrors
/// `conceive.dart`'s `conceiveCategoryOrder` exactly, so the two life-stage
/// reorderings share one shape.
List<TagCategory> perimenopauseCategoryOrder(List<TagCategory> base) => [
      for (final category in kPerimenopausePriorityCategories)
        if (base.contains(category)) category,
      for (final category in base)
        if (!kPerimenopausePriorityCategories.contains(category)) category,
    ];

/// The two cycle starts Perimenopause mode compares in the Cycle View: the
/// still-open (or newest) cycle and the one immediately before it — the
/// "current vs. previous" selection `cycle_comparison_view.dart`'s doc
/// comment names as issue #196's own caller of Issue #235's comparison.
class PerimenopauseComparisonStarts {
  const PerimenopauseComparisonStarts({
    required this.previous,
    required this.current,
  });

  /// The older of the two selected cycles (side A of the comparison).
  final LocalDate previous;

  /// The newer/current cycle (side B of the comparison).
  final LocalDate current;

  @override
  bool operator ==(Object other) =>
      other is PerimenopauseComparisonStarts &&
      other.previous == previous &&
      other.current == current;

  @override
  int get hashCode => Object.hash(previous, current);

  @override
  String toString() =>
      'PerimenopauseComparisonStarts(${previous.iso}..${current.iso})';
}

/// The last two cycle starts in [episodes], or null when fewer than two
/// cycles have been logged (Issue #196 AC2: the comparison view only ever
/// renders with two real cycles behind it, never a fabricated one).
///
/// **Completed cycles are preferred.** [CycleComparisonStats.lengthDeltaDays]
/// is null whenever either compared side is still open
/// (`cycle_comparison.dart`), and [deriveEpisodes] treats the newest start
/// as the open one by construction — so comparing "the newest two" would
/// make the length-change line permanently "still in progress". When the
/// profile has at least two *completed* cycles (three starts), this returns
/// those two, which is what change-spotting actually needs. With only one
/// completed cycle (two starts) it falls back to the last two starts, so
/// the bleed-day comparison and the full #235 screen still work; the length
/// line is then honestly "still in progress".
///
/// Sorted ascending first (the same `..sort()` `cycle_comparison.dart` uses),
/// so a caller that ran `deriveEpisodes` over unsorted input still gets the
/// chronological last two, not whichever happened to come last in the list.
PerimenopauseComparisonStarts? perimenopauseComparisonStarts(
  Iterable<Episode> episodes,
) {
  final starts =
      ([...episodes]..sort()).map((episode) => episode.start).toList();
  if (starts.length < 2) return null;
  // Last element is the open cycle; the two before it are the most recent
  // completed pair.
  if (starts.length >= 3) {
    return PerimenopauseComparisonStarts(
      previous: starts[starts.length - 3],
      current: starts[starts.length - 2],
    );
  }
  return PerimenopauseComparisonStarts(
    previous: starts[starts.length - 2],
    current: starts.last,
  );
}
