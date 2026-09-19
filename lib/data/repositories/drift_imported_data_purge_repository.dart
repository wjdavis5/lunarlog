/// Drift-backed [ImportedDataPurgeRepository] over U2's storage layer.
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/repositories/imported_data_purge_repository.dart';

class DriftImportedDataPurgeRepository
    implements ImportedDataPurgeRepository {
  DriftImportedDataPurgeRepository(this._storage);

  final LunarLogStorage _storage;

  @override
  Future<Map<String, int>> liveSourceCounts(String profileId) =>
      _storage.liveImportedSourceCounts(profileId);

  @override
  Future<void> applyLocalPurge({
    required String profileId,
    required String source,
  }) =>
      _storage.applyLocalImportedDataPurge(
        profileId: profileId,
        source: source,
      );
}
