/// In-memory [GuardianNoteStore] for repository tests (Issue #551, part 1
/// follow-up): the `guardian_notes` surface
/// [DriftGuardianNotesRepository] calls, holding rows keyed by id,
/// filtering tombstones from live reads, and re-emitting every watch on
/// change — with no drift database.
///
/// The SQL semantics it stands in for (tombstone payload clearing, the
/// author-ownership query) are pinned by `storage_guardian_notes_test.dart`;
/// this fake exists so the repository's own mapping and author guard can be
/// tested in isolation.
library;

import 'dart:async';

import 'package:lunarlog/data/db/db.dart' show GuardianNoteData;
import 'package:lunarlog/data/db/storage.dart';

class FakeGuardianNoteStore implements GuardianNoteStore {
  FakeGuardianNoteStore();

  final Map<String, GuardianNoteData> _rows = <String, GuardianNoteData>{};
  final Map<String, StreamController<List<GuardianNoteData>>> _controllers =
      <String, StreamController<List<GuardianNoteData>>>{};
  int _nextId = 0;

  /// The clock every fake write stamps `updated_at` with.
  DateTime now = DateTime.utc(2026, 1, 1);

  @override
  Future<List<GuardianNoteData>> getGuardianNotesForProfile(
    String profileId, {
    bool includeTombstones = false,
  }) async =>
      _live(profileId, includeTombstones);

  @override
  Future<GuardianNoteData?> getGuardianNoteById(String id) async => _rows[id];

  @override
  Stream<List<GuardianNoteData>> watchGuardianNotesForProfile(
    String profileId, {
    bool includeTombstones = false,
  }) =>
      _controllers
          .putIfAbsent(profileId,
              () => _broadcast(() => _live(profileId, includeTombstones)))
          .stream;

  @override
  Future<GuardianNoteData?> findLiveGuardianNoteForDate({
    required String profileId,
    required String localDate,
    required String? authorUserId,
  }) async {
    for (final row in _rows.values) {
      if (row.profileId == profileId &&
          row.localDate == localDate &&
          row.loggedByUserId == authorUserId &&
          row.deletedAt == null) {
        return row;
      }
    }
    return null;
  }

  @override
  Future<GuardianNoteData> upsertGuardianNote({
    String? id,
    required String profileId,
    required String localDate,
    required String tz,
    required String body,
    String? loggedByUserId,
    DateTime? updatedAt,
  }) async {
    final existing = id == null ? null : _rows[id];
    final row = GuardianNoteData(
      id: id ?? 'guardian-note-${_nextId++}',
      profileId: profileId,
      localDate: localDate,
      tz: tz,
      body: body,
      updatedAt: updatedAt ?? now,
      dirty: true,
      localRev: (existing?.localRev ?? 0) + 1,
      loggedByUserId: loggedByUserId,
    );
    _rows[row.id] = row;
    _notify(profileId);
    return row;
  }

  @override
  Future<void> softDeleteGuardianNote(String id) async {
    final row = _rows[id];
    if (row == null) return;
    _rows[id] = GuardianNoteData(
      id: row.id,
      profileId: row.profileId,
      localDate: row.localDate,
      tz: row.tz,
      body: row.body,
      updatedAt: now,
      deletedAt: now,
      dirty: true,
      localRev: row.localRev + 1,
      loggedByUserId: row.loggedByUserId,
    );
    _notify(row.profileId);
  }

  List<GuardianNoteData> _live(String profileId, bool includeTombstones) => [
        for (final row in _rows.values)
          if (row.profileId == profileId &&
              (includeTombstones || row.deletedAt == null))
            row,
      ];

  void _notify(String profileId) =>
      _controllers[profileId]?.add(_live(profileId, false));

  static StreamController<T> _broadcast<T>(T Function() current) {
    // ignore: close_sinks
    late StreamController<T> controller;
    controller = StreamController<T>.broadcast(
      onListen: () => controller.add(current()),
    );
    return controller;
  }

  /// Closes every watch stream. Call from `addTearDown`.
  Future<void> close() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}
