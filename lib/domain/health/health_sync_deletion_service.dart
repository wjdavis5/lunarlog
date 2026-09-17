/// The tombstone-propagation half of Issue #186's sync mechanics: when a
/// day entry is soft-deleted locally, the corresponding health-store sample
/// (whose external id is the entry's own ULID — Health Connect
/// `clientRecordId` / HealthKit `HKMetadataKeyExternalUUID`) is deleted so a
/// deleted lunarlog entry never leaves an orphaned sample in the store.
///
/// Pure Dart (R14/R16): the platform port and the repositories are injected
/// interfaces; the concrete coordinator lives in
/// `lib/data/health/health_sync_tombstone_coordinator.dart`.
library;

import 'health_platform.dart';

/// The outcome of one deletion pass: how many delete calls were issued and
/// whether any was refused/denied (counts only — no health content).
class HealthSyncDeletionReport {
  const HealthSyncDeletionReport({
    required this.attempted,
    required this.blocked,
  });

  /// Number of record ids handed to the platform for deletion.
  final int attempted;

  /// The first refusal/denial/unavailable outcome, or null when every delete
  /// was allowed.
  final HealthPlatformResult? blocked;
}

/// Deletes health-store samples for locally-tombstoned entries.
abstract interface class HealthSyncDeletionService {
  /// Deletes the store samples whose external id is in [recordIds] (the
  /// tombstoned day-entry ULIDs), under the currently bound profile's guard
  /// facts. A deleted id with no matching store sample is a harmless no-op.
  Future<HealthSyncDeletionReport> deleteSamples(List<String> recordIds);
}
