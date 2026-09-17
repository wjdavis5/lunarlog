/// Drift-backed [TagRegistryRepository] over the storage layer (Issue
/// #257). Every call is scoped to exactly one profile id (R3), mirroring
/// [DriftCareContentRepository].
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart' as domain;
import 'package:lunarlog/domain/repositories/tag_registry_repository.dart';

import 'mappers.dart';

class DriftTagRegistryRepository implements TagRegistryRepository {
  DriftTagRegistryRepository(this._storage);

  final LunarLogStorage _storage;

  @override
  Future<List<domain.CustomTag>> listForProfile(String profileId) async => [
        for (final row in await _storage.getProfileTagRegistry(profileId))
          customTagToDomain(row),
      ];

  @override
  Stream<List<domain.CustomTag>> watchForProfile(String profileId) =>
      _storage
          .watchProfileTagRegistry(profileId)
          .map((rows) => rows.map(customTagToDomain).toList());

  @override
  Future<domain.CustomTag> create({
    required String profileId,
    required String label,
  }) async {
    final code = domain.customTagCodeFromLabel(label);
    if (code == null) {
      throw ArgumentError.value(label, 'label', 'derives no tag code');
    }
    return customTagToDomain(await _storage.upsertProfileTagRegistryEntry(
      profileId: profileId,
      code: code,
      displayName: label.trim(),
    ));
  }

  @override
  Future<domain.CustomTag> rename({
    required String tagId,
    required String label,
  }) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty || trimmed.length > domain.kMaxCustomTagLabelLength) {
      throw ArgumentError.value(label, 'label', 'invalid custom tag label');
    }
    final existing = await _storage.getProfileTagRegistryEntriesById(tagId);
    if (existing == null || existing.deletedAt != null) {
      throw ArgumentError.value(tagId, 'tagId', 'unknown custom tag');
    }
    return customTagToDomain(await _storage.upsertProfileTagRegistryEntry(
      id: tagId,
      profileId: existing.profileId,
      code: existing.code,
      displayName: trimmed,
    ));
  }

  @override
  Future<void> retire(String tagId) async {
    await _storage.retireProfileTagRegistryEntry(tagId);
  }
}
