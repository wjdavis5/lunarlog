/// Drift-backed [ProfilesRepository] over U2's storage layer.
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/models/profile.dart' as domain;
import 'package:lunarlog/domain/models/profile_relationship.dart';
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
    int? birthYear,
    ProfileRelationship? relationship,
  }) =>
      _storage
          .upsertProfile(
            displayName: displayName,
            isMinor: isMinor,
            sortOrder: sortOrder,
            birthYear: birthYear,
            relationship: relationship?.toDb(),
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
      birthYear: profile.birthYear,
      relationship: profile.relationship?.toDb(),
    ));
  }

  @override
  Future<domain.Profile?> findById(String id) async {
    final row = await _storage.getProfile(id);
    return row == null ? null : profileToDomain(row);
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
    // getProfile excludes tombstones by default, so a tombstoned id reads as
    // null here and is rejected just as it was when this scanned getProfiles().
    final row = await _storage.getProfile(id);
    if (row == null) {
      throw StateError('cannot archive unknown or tombstoned profile: $id');
    }
    await _storage.upsertProfile(
      id: row.id,
      displayName: row.displayName,
      isMinor: row.isMinor,
      sortOrder: row.sortOrder,
      archivedAt: archived ? _now() : null,
      birthYear: row.birthYear,
      relationship: row.relationship,
    );
  }

  @override
  Future<void> delete(String id) => _storage.softDeleteProfile(id);
}
