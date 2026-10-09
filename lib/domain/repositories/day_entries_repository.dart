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

/// Issue #1561: what the health import needs to know about days she
/// deleted. [DayEntriesRepository.find] answers for live rows only, so a
/// deleted imported day looked like one that had never been imported, and
/// the next whole-history read inserted it again.
///
/// Kept off [DayEntriesRepository] itself, like the readers above: a
/// repository that does not implement it simply cannot answer, and the
/// import then behaves as it did before.
abstract interface class DeletedDayEntryReader {
  /// The health-store records she deleted from [profileId] on this
  /// device, each with the moment of its deletion, named
  /// `healthImportDeletionId(source, sourceId)`. The device writes it when
  /// she deletes a day or removes an entry. It is not a reading of deleted
  /// rows: removing a store's imported data leaves deleted rows too, and
  /// must not keep a later import from bringing the days back.
  Future<Map<String, DateTime>> deletedHealthRecords(String profileId);

  /// Forgets the records named in [deletedAt]: the import found each on a
  /// live row again, so its deletion was undone. Each is forgotten only if
  /// it still carries the moment given, which is the one the import read:
  /// a record deleted again in the meantime is kept.
  Future<void> forgetDeletedHealthRecords(
    String profileId,
    Map<String, DateTime> deletedAt,
  );
}

/// Issue #1587 (item 1): the delete an *undo* performs. The plain
/// [DayEntriesRepository.delete] remembers the health-store records on the
/// row ([DeletedDayEntryReader]), which is what "I removed this store data"
/// means — but an undo is removing a row *she* created (`undoQuickLog`,
/// the day sheet's cycle-start undo), and a record a background import
/// attached to that row was not hers to remove. Without this, Undo shadowed
/// that record forever: the next import would not bring it back.
///
/// Kept off [DayEntriesRepository] itself, like the readers above, so the
/// ~40 test doubles that implement the repository need no new member: the
/// two undo paths resolve it with an `is` check and fall back to the plain
/// delete when it is absent.
abstract interface class UndoDayEntryDeleter {
  /// Deletes (profileId, localDate) exactly as
  /// [DayEntriesRepository.delete] does — same tombstones, sync
  /// dirty-marking and observation cascade — except that the health-store
  /// records the row carries are *not* remembered as deleted. The store's
  /// records may therefore be imported again on a later pass.
  Future<void> deleteForUndo(String profileId, LocalDate localDate);
}

/// Issue #1616 item 1: the reset the health import's removal performs on a
/// day it keeps. A plain [DayEntriesRepository.save] cannot express it —
/// the storage layer reads a `manual`/null/null save against an imported
/// row as "provenance unspecified" and keeps the stored source (right for
/// a bare save, wrong for this reset) — so it gets its own narrow seam,
/// like the readers and [UndoDayEntryDeleter] above.
abstract interface class ImportedFlowResetter {
  /// Takes the imported flow off the day at [localDate] and makes the row
  /// hers: flow `none`, source `manual`, no record. No-op when there is no
  /// live row.
  Future<void> clearImportedFlow(String profileId, LocalDate localDate);
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
