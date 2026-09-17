/// Drift-backed [HealthSyncTombstoneSource] (Issue #619, LLA-018/LLA-020):
/// the concrete full-fidelity (tombstones-included) read side of the health
/// tombstone-propagation coordinator, wired in `app_dependencies.dart`
/// alongside the other Drift-backed repositories.
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/health/health_sync_tombstone_source.dart';
import 'package:lunarlog/domain/models/day_entry.dart' as domain;

import 'mappers.dart';

class DriftHealthSyncTombstoneSource implements HealthSyncTombstoneSource {
  DriftHealthSyncTombstoneSource(this._storage);

  final LunarLogStorage _storage;

  @override
  Stream<List<domain.DayEntry>> watchDayEntries(String profileId) => _storage
      .watchDayEntries(profileId: profileId, includeTombstones: true)
      .map((rows) => [for (final row in rows) dayEntryToDomain(row)]);

  @override
  Stream<List<HealthTombstoneObservation>> watchObservations(
    String profileId,
  ) =>
      _storage
          .watchObservationsForProfile(profileId, includeTombstones: true)
          .map((rows) => [
                for (final row in rows)
                  HealthTombstoneObservation(
                    id: row.id,
                    category: row.category,
                    deletedAt: row.deletedAt,
                  ),
              ]);
}
