/// Repository interface (R14/R16) for per-profile day entries. Every
/// operation is scoped to exactly one profile id (R3 isolation).
library;

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
}
