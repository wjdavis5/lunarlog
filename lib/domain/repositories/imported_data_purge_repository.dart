/// Local-only repository for the "Purge imported data" affordance (Issues
/// #472/#883): the source-scoped tombstone of one profile's imported rows,
/// and the per-source counts the purge dialog previews.
///
/// Storage-only (R14/R16): no network type crosses this boundary, and
/// neither method needs a session or a connection — the whole point of
/// Issue #883 is that this half works on a device-only profile that has
/// never been near an account.
library;

abstract interface class ImportedDataPurgeRepository {
  /// Live local row totals for [profileId], keyed by the raw `source`
  /// wire value — day entries plus observations. A source with no live
  /// rows is absent from the map (callers treat absent as zero).
  /// Local-only.
  Future<Map<String, int>> liveSourceCounts(String profileId);

  /// Tombstones [profileId]'s live `day_entries` and `observations` whose
  /// `source` equals [source], on this device only. Reuses the app's
  /// tombstone shape (payload cleared, `deleted_at` stamped, the
  /// provenance columns kept) — never a raw row removal — scoped to
  /// exactly one profile and one source, so every other profile and
  /// source survives untouched. Deliberately marks nothing dirty, the
  /// same posture as `ProfilesRepository.applyServerPurge`: when a server
  /// is involved it is reached through its own RPC, so a local tombstone
  /// must never be pushed back as a resurrection. Idempotent; a harmless
  /// no-op for an unknown profile or a source with nothing live.
  Future<void> applyLocalPurge({
    required String profileId,
    required String source,
  });
}
