/// Repository interface (R14/R16) for per-profile day entries. Every
/// operation is scoped to exactly one profile id (R3 isolation).
library;

import '../models/day_entry.dart';
import '../models/local_date.dart';

abstract interface class DayEntriesRepository {
  /// Upserts the live entry for (profileId, localDate). Tag codes are
  /// validated against the domain taxonomy. The returned model carries the
  /// storage-assigned row id and monotonic `updatedAt`.
  Future<DayEntry> save(DayEntry entry);

  /// The live entry for (profileId, localDate), or null.
  Future<DayEntry?> find(String profileId, LocalDate localDate);

  /// Live entries for the profile, ordered by civil date.
  Future<List<DayEntry>> listForProfile(String profileId);

  /// Reactive variant of [listForProfile]; emits again on every write or
  /// tombstone affecting that profile (tombstoned rows excluded).
  Stream<List<DayEntry>> watchForProfile(String profileId);

  /// Tombstones the live entry for (profileId, localDate); idempotent.
  Future<void> delete(String profileId, LocalDate localDate);
}
