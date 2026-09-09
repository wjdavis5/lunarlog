/// Drift-backed [CareContentRepository] over the storage layer (Issue
/// #128). Every call is scoped to exactly one profile id (R3), mirroring
/// [DriftObservationsRepository].
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/models/care_note.dart' as domain;
import 'package:lunarlog/domain/models/visit_prep_item.dart' as domain;
import 'package:lunarlog/domain/repositories/care_content_repository.dart';

import 'mappers.dart';

class DriftCareContentRepository implements CareContentRepository {
  DriftCareContentRepository(this._storage);

  final LunarLogStorage _storage;

  @override
  Future<List<domain.CareNote>> listCareNotes(String profileId) async => [
        for (final row in await _storage.getCareNotesForProfile(profileId))
          careNoteToDomain(row),
      ];

  @override
  Stream<List<domain.CareNote>> watchCareNotes(String profileId) =>
      _storage
          .watchCareNotesForProfile(profileId)
          .map((rows) => rows.map(careNoteToDomain).toList());

  @override
  Future<domain.CareNote> saveCareNote({
    String? id,
    required String profileId,
    required String body,
  }) async =>
      careNoteToDomain(await _storage.upsertCareNote(
        id: id,
        profileId: profileId,
        body: body,
      ));

  @override
  Future<void> deleteCareNote(String id) =>
      _storage.softDeleteCareNote(id);

  @override
  Future<List<domain.VisitPrepItem>> listPrepItems(String profileId) async => [
        for (final row in await _storage.getVisitPrepItemsForProfile(profileId))
          visitPrepItemToDomain(row),
      ];

  @override
  Stream<List<domain.VisitPrepItem>> watchPrepItems(String profileId) =>
      _storage
          .watchVisitPrepItemsForProfile(profileId)
          .map((rows) => rows.map(visitPrepItemToDomain).toList());

  @override
  Future<domain.VisitPrepItem> addPrepItem({
    String? id,
    required String profileId,
    required String body,
  }) async =>
      visitPrepItemToDomain(await _storage.addVisitPrepItem(
        id: id,
        profileId: profileId,
        body: body,
      ));

  @override
  Future<domain.VisitPrepItem?> editPrepItem({
    required String id,
    required String body,
  }) async {
    final row = await _storage.editVisitPrepItem(id: id, body: body);
    return row == null ? null : visitPrepItemToDomain(row);
  }

  @override
  Future<domain.VisitPrepItem?> setPrepItemChecked({
    required String id,
    required bool checked,
    String? checkedByUserId,
  }) async {
    final row = await _storage.setVisitPrepItemChecked(
      id: id,
      checked: checked,
      checkedByUserId: checkedByUserId,
    );
    return row == null ? null : visitPrepItemToDomain(row);
  }

  @override
  Future<void> deletePrepItem(String id) =>
      _storage.softDeleteVisitPrepItem(id);

  @override
  Future<int> clearCheckedPrepItems(String profileId) =>
      _storage.clearCheckedVisitPrepItems(profileId);
}
