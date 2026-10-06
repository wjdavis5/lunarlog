/// Repository interface (R14/R16) for per-profile day entries. Every
/// operation is scoped to exactly one profile id (R3 isolation).
library;

import '../logging/day_entry_merge_event.dart';
import '../models/day_entry.dart';
import '../models/local_date.dart';
import '../models/observation.dart';

/// Issue #850 U5: the bounded "latest entry" capability the guardian
/// logistics card needs — a single most-recent live entry, never the
/// profile's full history.
///
/// Deliberately a separate interface from [DayEntriesRepository] rather
/// than an added method on it: an abstract member there would force every
/// one of the repository's ~40 test doubles to grow a stub, for a read only
/// this card performs. [DriftDayEntriesRepository] implements both, and the
/// card resolves it with an `is` check, so a tree whose entries repository
/// cannot answer it (a hand-rolled fake) simply renders the "nothing logged
/// yet" state instead of a second full-history subscription.
abstract interface class LatestDayEntryReader {
  /// The live day entry with the greatest civil date for [profileId], or
  /// null when the profile has no live entries. Tombstones are excluded.
  Future<DayEntry?> latestEntryFor(String profileId);
}

/// Issue #1071 follow-up: the per-row sync-state capability the day sheet
/// needs to decide whether a note's privacy choice is still open — whether
/// the note has actually been shared with the server at least once.
///
/// Deliberately a separate interface from [DayEntriesRepository] rather than
/// an added method on it, copying the narrow-seam pattern issue #850 U5 used
/// for its bounded latest-entry read: an abstract member there would force
/// every one of the repository's test doubles to grow a stub for a read only
/// the note toggle performs. [DriftDayEntriesRepository] implements both, and
/// the day sheet resolves it with an `is` check, so a tree whose entries
/// repository cannot answer it (a hand-rolled fake) simply treats the note as
/// never shared rather than reaching for a second store.
/// Issue #1561: what the health import needs to know about days she
/// deleted. [DayEntriesRepository.find] answers for live rows only, so a
/// deleted imported day looked like one that had never been imported, and
/// the next whole-history read inserted it again.
///
/// Kept off [DayEntriesRepository] itself, like the readers beside it: a
/// repository that does not implement it simply cannot answer, and the
/// import then behaves as it did before.
abstract interface class DeletedDayEntryReader {
  /// The health-store records behind what she deleted for [profileId] on
  /// this device, each with the moment of the deletion. The names are
  /// `healthImportDeletionId(source, sourceId)`. It is a record of her
  /// own deletions, written when she makes them, and not a reading of
  /// deleted rows: "Remove imported data" leaves deleted rows too, and
  /// must not keep a later import from bringing the days back.
  Future<Map<String, DateTime>> handDeletedRecords(String profileId);

  /// The deleted entry of [profileId] carrying this provenance, or null
  /// when there is none or the entry that carries it is live. However it
  /// came to be deleted: the import revives it instead of inserting a
  /// second row for the same record, which could never sync.
  Future<DayEntry?> findDeletedBySource({
    required String profileId,
    required DayEntrySource source,
    required String sourceId,
  });
}

abstract interface class DayEntrySyncStateReader {
  /// Whether (profileId, date) holds a live row with a non-empty note whose
  /// `dirty` flag is clear — i.e. the note has been pushed to the server at
  /// least once, so it is now visible to guardians and can never be made
  /// private again (the server's `enforce_day_entry_note_private` rule).
  ///
  /// `false` for a local-only row (it never pushes, so it stays `dirty`), a
  /// note written but not yet pushed (offline), an empty note, a tombstone, or
  /// no row at all — every case where the choice is still legal.
  Future<bool> hasBeenShared(String profileId, LocalDate date);
}

abstract interface class DayEntriesRepository {
  /// Upserts the live entry for (profileId, localDate). Tag codes are
  /// validated against the domain taxonomy. The returned model carries the
  /// storage-assigned row id and monotonic `updatedAt`.
  Future<DayEntry> save(DayEntry entry);

  /// Atomically saves [entry], upserts [observationsToUpsert], and soft-deletes
  /// any observation IDs in [observationIdsToDelete] within a single database
  /// transaction.
  ///
  /// Any failure during entry or observation processing rolls back the entire
  /// transaction.
  Future<DayEntry> saveDayEntryWithObservations({
    required DayEntry entry,
    List<Observation> observationsToUpsert = const [],
    List<String> observationIdsToDelete = const [],
  });

  /// The live entry for (profileId, localDate), or null.
  Future<DayEntry?> find(String profileId, LocalDate localDate);

  /// Live entries for the profile, ordered by civil date.
  Future<List<DayEntry>> listForProfile(String profileId);

  /// Whether [profileId] has any live day entry at all, without loading the
  /// entries themselves (issue #549) — for callers (e.g. the export tiles)
  /// that only need to know the profile has *some* history, not what it is.
  Future<bool> hasAnyEntries(String profileId);

  /// Reactive variant of [hasAnyEntries] (issue #642, LLA-010): a bounded
  /// existence signal — never the entries themselves — that re-emits on
  /// every write or tombstone affecting [profileId]'s day entries. Callers
  /// (the export tiles) that need to know *whether entries exist* should
  /// observe this directly rather than deriving it from some other stream's
  /// re-emissions (e.g. the profiles stream, which does not tick just
  /// because a day entry was logged).
  Stream<bool> watchHasAnyEntries(String profileId);

  /// Reactive variant of [listForProfile]; emits again on every write or
  /// tombstone affecting that profile (tombstoned rows excluded).
  ///
  /// [from]/[to] optionally narrow to an inclusive civil-date range (issue
  /// #197: the calendar's windowed subscription) instead of the profile's
  /// full history; omitting both (every existing caller) is unchanged.
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  });

  /// Tombstones the live entry for (profileId, localDate); idempotent.
  Future<void> delete(String profileId, LocalDate localDate);

  /// Issue #130: the same-date merge disclosures recorded for
  /// (profileId, date) that THIS device has not dismissed — the day
  /// sheet's quiet notice list, shown to every guardian. Window-filtered
  /// to the 30-day recovery window (the client mirror of the server's
  /// retention purge), so a notice never outlives its documented
  /// retention.
  Future<List<DayEntryMergeEvent>> mergeEventsForDay(
      String profileId, LocalDate date);

  /// Issue #130: dismisses one merge notice on this device only
  /// (device-local, never synced — another guardian's notice is
  /// untouched). Idempotent.
  Future<void> dismissMergeEvent(String profileId, String eventId);

  /// Issue #130: every merge disclosure recorded for the profile inside
  /// the 30-day recovery window — the local JSON export's read. NOT
  /// filtered on this device's dismissals (a dismissed notice is a display
  /// choice, not a deletion of the record), and window-filtered so the
  /// export never carries retained losing text the server has already
  /// purged.
  Future<List<DayEntryMergeEvent>> mergeEventsForProfile(String profileId);
}
