/// Drift-backed [GuardianNotesRepository] over the storage layer (Issue
/// #801). Every call is scoped to exactly one profile id (R3), mirroring
/// [DriftCareContentRepository].
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/models/guardian_note.dart' as domain;
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/guardian_notes_repository.dart';

import 'mappers.dart';

class DriftGuardianNotesRepository implements GuardianNotesRepository {
  DriftGuardianNotesRepository(this._storage);

  final LunarLogStorage _storage;

  @override
  Future<List<domain.GuardianNote>> listForProfile(String profileId) async => [
        for (final row in await _storage.getGuardianNotesForProfile(profileId))
          guardianNoteToDomain(row),
      ];

  @override
  Stream<List<domain.GuardianNote>> watchForProfile(String profileId) =>
      _storage
          .watchGuardianNotesForProfile(profileId)
          .map((rows) => rows.map(guardianNoteToDomain).toList());

  @override
  Future<domain.GuardianNote?> findOwnNoteForDate({
    required String profileId,
    required LocalDate localDate,
    required String? authorUserId,
  }) async {
    if (authorUserId == null) return null;
    final row = await _storage.findLiveGuardianNoteForDate(
      profileId: profileId,
      localDate: localDate.iso,
      authorUserId: authorUserId,
    );
    return row == null ? null : guardianNoteToDomain(row);
  }

  @override
  Future<domain.GuardianNote> save({
    String? id,
    required String profileId,
    required LocalDate localDate,
    required String tz,
    required String body,
    String? loggedByUserId,
  }) async =>
      guardianNoteToDomain(await _storage.upsertGuardianNote(
        id: id,
        profileId: profileId,
        localDate: localDate.iso,
        tz: tz,
        body: body,
        loggedByUserId: loggedByUserId,
      ));

  @override
  Future<void> delete(String id) => _storage.softDeleteGuardianNote(id);
}
