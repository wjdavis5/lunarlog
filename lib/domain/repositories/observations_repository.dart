/// Repository interface (R14/R16) for per-profile observations (Issue
/// #240). Every operation is scoped to exactly one profile id (R3
/// isolation), mirroring [DayEntriesRepository].
library;

import '../models/local_date.dart';
import '../models/observation.dart';
import '../models/observation_category.dart';

abstract interface class ObservationsRepository {
  /// Live (non-tombstoned) observations for the profile, ordered by id.
  /// Used by account export (Issue #240; `kAccountExportSchemaVersion` v3)
  /// so an exported profile's `observations` key is honest rather than
  /// always empty. Issue #247: a live day entry whose stored `flow` is
  /// still the deprecated `spotting` alias (predates this migration's
  /// server-side backfill, or a peer that hasn't synced yet) is
  /// represented here by a synthesised `category: 'spotting'` observation
  /// alongside any already-persisted one — never duplicated, and never
  /// written back to storage by this read.
  Future<List<Observation>> listForProfile(String profileId);

  /// Live observations attached to [dayEntryId] (Issue #247) — used by
  /// `DaySheet` to find (and edit) the day's `spotting` observation, if
  /// any. Unlike [listForProfile], this does **not** synthesise a
  /// spotting row for a legacy `flow = 'spotting'` day entry (see that
  /// method's doc comment) — a caller that needs the alias applied should
  /// go through [listForProfile] instead.
  Future<List<Observation>> listForDayEntry(String dayEntryId);

  /// [listForDayEntry], plus the same legacy `flow = 'spotting'` alias
  /// synthesis [listForProfile] applies — but scoped to this one day entry
  /// via a single-row day-entry lookup, not a full profile scan (issue
  /// #549). For a caller (`DaySheet`'s spotting toggle) that needs the
  /// alias for exactly one day and would otherwise have to pay for
  /// [listForProfile]'s full decode of every observation and every day
  /// entry the profile has ever logged just to answer a one-day question.
  Future<List<Observation>> listForDayEntryWithLegacyAlias(String dayEntryId);

  /// Creates or updates [observation], keyed by its `id` (a fresh one is
  /// generated when `observation.id` is empty) — mirrors
  /// [DayEntriesRepository.save]'s upsert-by-identity shape, but identity
  /// here is the row's own id (Issue #240: a day entry can carry many
  /// live observations, so there is no same-date uniqueness to resolve
  /// against).
  Future<Observation> save(Observation observation);

  /// Tombstones the observation [id]. No-op if not held locally.
  Future<void> delete(String id);
}

/// Optional capability of an [ObservationsRepository] (issue #795): a
/// date-scoped, spotting-category read that never scans the profile's full
/// observation history. It is itself an [ObservationsRepository] (so a
/// repository implementing it can be type-promoted to it), but kept as a
/// separate interface rather than a new member on [ObservationsRepository]
/// so existing `implements` fakes keep compiling; callers go through
/// [SpottingObservationsRead.spottingIsosInRange], which falls back to
/// [ObservationsRepository.listForProfile] when a repository does not
/// implement this capability.
abstract interface class SpottingObservationsRangeRepository
    implements ObservationsRepository {
  /// Live `category: 'spotting'` observations for [profileId] whose
  /// `localDate` falls in the inclusive range [from]..[to], including the
  /// legacy `flow = 'spotting'` alias synthesis [listForProfile] applies.
  Future<List<Observation>> listSpottingObservationsInRange({
    required String profileId,
    required LocalDate from,
    required LocalDate to,
  });
}

/// Range-scoped spotting reads for any [ObservationsRepository] (issue
/// #795). The calendar only needs the ISO dates carrying a live spotting
/// observation inside its already-subscribed entries window; dispatching
/// to [SpottingObservationsRangeRepository.listSpottingObservationsInRange]
/// scopes the query to that window (and to the spotting category), while
/// the [ObservationsRepository.listForProfile] fallback keeps repositories
/// without the capability — including test fakes — working unchanged.
extension SpottingObservationsRead on ObservationsRepository {
  /// The ISO dates in [from]..[to] carrying a live spotting observation.
  /// With a null [from]/[to] (no window established yet) this degrades to
  /// the full [ObservationsRepository.listForProfile] read.
  Future<Set<String>> spottingIsosInRange({
    required String profileId,
    LocalDate? from,
    LocalDate? to,
  }) async {
    final repository = this;
    final List<Observation> observations;
    if (from != null &&
        to != null &&
        repository is SpottingObservationsRangeRepository) {
      observations = await repository.listSpottingObservationsInRange(
        profileId: profileId,
        from: from,
        to: to,
      );
    } else {
      observations = await listForProfile(profileId);
    }
    return {
      for (final observation in observations)
        if (observation.category == ObservationCategory.spotting &&
            (from == null || !observation.localDate.isBefore(from)) &&
            (to == null || !observation.localDate.isAfter(to)))
          observation.localDate.iso,
    };
  }
}
