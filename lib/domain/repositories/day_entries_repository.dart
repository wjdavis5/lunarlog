/// Repository interface (R14/R16) for per-profile day entries. Every
/// operation is scoped to exactly one profile id (R3 isolation).
library;

import '../logging/day_entry_merge_event.dart';
import '../models/day_entry.dart';
import '../models/local_date.dart';
import '../models/observation.dart';

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
