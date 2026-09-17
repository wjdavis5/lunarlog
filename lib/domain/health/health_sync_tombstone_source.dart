/// Full-fidelity (tombstones-included) read port for
/// [HealthSyncTombstoneCoordinator] (`lib/data/health/`; Issue #619,
/// LLA-018/LLA-020): `DayEntriesRepository.watchForProfile` and every
/// `ObservationsRepository` read filter tombstoned rows for UI consumers,
/// but tombstone-propagation's whole purpose is reacting to exactly the
/// rows those filters hide — a live-only stream can never carry the
/// deletion this coordinator exists to relay to the health store.
///
/// Deliberately its own narrow contract rather than an addition to either
/// UI-facing repository interface: no other consumer needs a
/// tombstone-inclusive stream, and extending a widely-implemented
/// interface (`DayEntriesRepository` alone has 15+ fakes across areas this
/// issue never touches) for one caller would be pure churn.
library;

import '../models/day_entry.dart';

/// One observation row as the tombstone coordinator needs it. Unlike
/// `Observation`/`observationToDomain` (`lib/data/repositories/mappers.dart`),
/// [category] stays nullable here rather than throwing on a tombstoned row:
/// a day-entry cascade-tombstone clears `category` exactly like every other
/// payload column (Issue #470), so recognising a spotting observation that
/// has just been deleted this way requires the coordinator to have already
/// seen it live with `category == 'spotting'` — never the post-tombstone
/// row alone, which carries no trace of what it used to be.
class HealthTombstoneObservation {
  const HealthTombstoneObservation({
    required this.id,
    required this.category,
    required this.deletedAt,
  });

  final String id;
  final String? category;
  final DateTime? deletedAt;
}

abstract interface class HealthSyncTombstoneSource {
  /// Every day entry for [profileId], live or tombstoned.
  Stream<List<DayEntry>> watchDayEntries(String profileId);

  /// Every observation for [profileId], live or tombstoned. Not
  /// pre-filtered by category server- or storage-side — a cascade
  /// tombstone clears it — so the caller must track spotting identity
  /// from an earlier, live emission instead.
  Stream<List<HealthTombstoneObservation>> watchObservations(
    String profileId,
  );
}
