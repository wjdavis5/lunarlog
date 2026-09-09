/// Repository interface (R14/R16) for per-profile observations (Issue
/// #240). Every operation is scoped to exactly one profile id (R3
/// isolation), mirroring [DayEntriesRepository].
library;

import '../models/observation.dart';

abstract interface class ObservationsRepository {
  /// Live (non-tombstoned) observations for the profile, ordered by id.
  /// Used by account export (Issue #240; `kAccountExportSchemaVersion` v3)
  /// so an exported profile's `observations` key is honest rather than
  /// always empty.
  Future<List<Observation>> listForProfile(String profileId);
}
