/// Drift-backed [ImportedDataPurgeRepository] over U2's storage layer.
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/health/health_import_deletions.dart';
import 'package:lunarlog/domain/repositories/imported_data_purge_repository.dart';

class DriftImportedDataPurgeRepository
    implements ImportedDataPurgeRepository {
  DriftImportedDataPurgeRepository(this._storage);

  final ImportedDataPurgeStore _storage;

  @override
  Future<Map<String, int>> liveSourceCounts(String profileId) =>
      _storage.liveImportedSourceCounts(profileId);

  @override
  Future<void> applyLocalPurge({
    required String profileId,
    required String source,
  }) async {
    await _storage.applyLocalImportedDataPurge(
      profileId: profileId,
      source: source,
    );
    // Issue #1561: removing a source's imported data is a clean slate for
    // it. What she had deleted one by one from that source is forgotten,
    // so a later import brings everything the store holds.
    final key = healthImportDeletionsKey(profileId);
    final before = decodeHealthImportDeletions(await _storage.getSetting(key));
    final after = forgetHealthImportSource(before, source);
    if (after.length == before.length) return;
    await _storage.setSetting(
      key: key,
      value: encodeHealthImportDeletions(after),
    );
  }
}
