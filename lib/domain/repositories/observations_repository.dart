/// Repository interface (R14/R16) for per-profile observations (Issue
/// #240). Every operation is scoped to exactly one profile id (R3
/// isolation), mirroring [DayEntriesRepository].
library;

import '../models/observation.dart';

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
