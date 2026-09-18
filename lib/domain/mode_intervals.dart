/// Shared interval-exclusion math for leaving a life-stage mode whose span
/// must not feed cycle averages (Issues #192 Pregnancy, #455 Postpartum).
///
/// A mode that pauses prediction also accumulates a stretch of history the
/// ordinary averaging model must never read as cycles: the pregnancy-long
/// "cycle" plus any breakthrough episodes, or the postpartum interval plus
/// any lochia/spotting episodes. Both modes need the exact same computation
/// — "every episode start inside `[modeStartedOn, exitedOn)`" — so it lives
/// here once and each mode's own module ([pregnancyExclusionStarts],
/// [postpartumExclusionStarts]) delegates to it rather than restating the
/// half-open bound.
///
/// The `cycle_overrides` schema (#188) is keyed by single cycle-start dates
/// (#132's consumption mechanism), so "exclude the interval" is realized as
/// one row per start inside it. The half-open bound deliberately keeps a
/// period starting exactly on the exit date out of the exclusion: that is
/// the first real cycle of the resumed/returned cycle and the recovery data
/// the mean needs.
///
/// Pure Dart with no drift/Flutter imports (R14/R16) —
/// `test/architecture/layering_test.dart` enforces that.
library;

import 'episodes/episodes.dart';
import 'models/lifecycle_mode.dart';
import 'models/local_date.dart';

/// Whether leaving [mode] has a discrete interval worth offering to
/// exclude from cycle averages (Issues #192 Pregnancy, #455 Postpartum).
///
/// `tracking`/`conceive` have no mode interval, and `perimenopause` is an
/// open-ended stage rather than a span with a start and an exit, so none
/// of those offers an exclusion.
bool hasModeIntervalExclusion(LifecycleMode mode) =>
    mode == LifecycleMode.pregnancy || mode == LifecycleMode.postpartum;

/// The cycle-start dates to omit from cycle averages for a mode interval:
/// every episode start inside the half-open interval
/// `[modeStartedOn, exitedOn)`.
///
/// A null [modeStartedOn] (a mode entered before the column was stamped)
/// excludes nothing — an honest empty set the caller can surface, rather
/// than a guessed interval.
Set<LocalDate> intervalExclusionStarts({
  required Iterable<Episode> episodes,
  required LocalDate? modeStartedOn,
  required LocalDate exitedOn,
}) {
  if (modeStartedOn == null) return const {};
  return {
    for (final episode in episodes)
      if (!episode.start.isBefore(modeStartedOn) &&
          episode.start.isBefore(exitedOn))
        episode.start,
  };
}
