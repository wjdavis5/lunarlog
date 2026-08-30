/// Drift-backed [ProfilesRepository] over U2's storage layer.
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/models/profile.dart' as domain;
import 'package:lunarlog/domain/repositories/profiles_repository.dart';

import 'mappers.dart';

class DriftProfilesRepository implements ProfilesRepository {
  DriftProfilesRepository(this._storage);

  final LunarLogStorage _storage;

  DateTime _now() => DateTime.now().toUtc();

  @override
  Future<domain.Profile> create({
    required String displayName,
    required bool isMinor,
    int sortOrder = 0,
  }) =>
      _storage
          .upsertProfile(
            displayName: displayName,
            isMinor: isMinor,
            sortOrder: sortOrder,
          )
          .then(profileToDomain);

  @override
  Future<domain.Profile> update(domain.Profile profile) async {
    if (profile.id.isEmpty) {
      throw ArgumentError.value(profile.id, 'profile.id',
          'update requires an existing id (use create() for new profiles)');
    }
    return profileToDomain(await _storage.upsertProfile(
      id: profile.id,
      displayName: profile.displayName,
      isMinor: profile.isMinor,
      sortOrder: profile.sortOrder,
      archivedAt: profile.archivedAt,
    ));
  }

  @override
  Future<domain.Profile?> findById(String id) async {
    final rows = await _storage.getProfiles();
    for (final row in rows) {
      if (row.id == id) return profileToDomain(row);
    }
    return null;
  }

  @override
  Future<List<domain.Profile>> list() async =>
      [for (final row in await _storage.getProfiles()) profileToDomain(row)];

  @override
  Stream<List<domain.Profile>> watch() => _storage
      .watchProfiles()
      .map((rows) => [for (final row in rows) profileToDomain(row)]);

  @override
  Future<void> setArchived(String id, bool archived) async {
    final rows = await _storage.getProfiles();
    for (final row in rows) {
      if (row.id == id) {
        await _storage.upsertProfile(
          id: row.id,
          displayName: row.displayName,
          isMinor: row.isMinor,
          sortOrder: row.sortOrder,
          archivedAt: archived ? _now() : null,
        );
        return;
      }
    }
    throw StateError('cannot archive unknown or tombstoned profile: $id');
  }

  @override
  Future<void> delete(String id) => _storage.softDeleteProfile(id);
}
