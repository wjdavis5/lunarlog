/// In-memory [CareContentStore] for repository tests (Issue #551, part 1
/// follow-up): the `care_notes`/`visit_prep_items` surface
/// [DriftCareContentRepository] calls, holding rows keyed by id, filtering
/// tombstones from live reads, scoping visit-prep reads by `kind`, and
/// re-emitting every watch on change — with no drift database.
///
/// The SQL it stands in for (tombstone payload clearing, the `kind` column's
/// CHECK) is pinned by `storage_care_content_test.dart`; this fake exists so
/// the repository's own mapping and `kind` routing can be tested in
/// isolation.
library;

import 'dart:async';

import 'package:lunarlog/data/db/db.dart'
    show CareNoteData, VisitPrepItemData;
import 'package:lunarlog/data/db/storage.dart';

class FakeCareContentStore implements CareContentStore {
  FakeCareContentStore();

  final Map<String, CareNoteData> _notes = <String, CareNoteData>{};
  final Map<String, VisitPrepItemData> _prep =
      <String, VisitPrepItemData>{};
  final Map<String, StreamController<List<CareNoteData>>> _noteControllers =
      <String, StreamController<List<CareNoteData>>>{};
  final Map<String, StreamController<List<VisitPrepItemData>>> _prepControllers =
      <String, StreamController<List<VisitPrepItemData>>>{};
  int _nextId = 0;

  /// The clock every fake write stamps `updated_at` with.
  DateTime now = DateTime.utc(2026, 1, 1);

  @override
  Future<List<CareNoteData>> getCareNotesForProfile(
    String profileId, {
    bool includeTombstones = false,
  }) async =>
      _liveNotes(profileId, includeTombstones);

  @override
  Stream<List<CareNoteData>> watchCareNotesForProfile(
    String profileId, {
    bool includeTombstones = false,
  }) =>
      _noteControllers
          .putIfAbsent(profileId,
              () => _broadcast(() => _liveNotes(profileId, includeTombstones)))
          .stream;

  @override
  Future<CareNoteData> upsertCareNote({
    String? id,
    required String profileId,
    required String body,
    DateTime? updatedAt,
  }) async {
    final existing = id == null ? null : _notes[id];
    final row = CareNoteData(
      id: id ?? 'care-note-${_nextId++}',
      profileId: profileId,
      body: body,
      updatedAt: updatedAt ?? now,
      dirty: true,
      localRev: (existing?.localRev ?? 0) + 1,
      loggedByUserId: existing?.loggedByUserId,
    );
    _notes[row.id] = row;
    _noteControllers[profileId]?.add(_liveNotes(profileId, false));
    return row;
  }

  @override
  Future<void> softDeleteCareNote(String id) async {
    final row = _notes[id];
    if (row == null) return;
    _notes[id] = CareNoteData(
      id: row.id,
      profileId: row.profileId,
      body: row.body,
      updatedAt: now,
      deletedAt: now,
      dirty: true,
      localRev: row.localRev + 1,
      loggedByUserId: row.loggedByUserId,
    );
    _noteControllers[row.profileId]?.add(_liveNotes(row.profileId, false));
  }

  @override
  Future<List<VisitPrepItemData>> getVisitPrepItemsForProfile(
    String profileId, {
    bool includeTombstones = false,
    String? kind,
  }) async =>
      _livePrep(profileId, includeTombstones, kind);

  @override
  Stream<List<VisitPrepItemData>> watchVisitPrepItemsForProfile(
    String profileId, {
    bool includeTombstones = false,
    String? kind,
  }) =>
      _prepControllers
          .putIfAbsent(
              _prepKey(profileId, kind),
              () => _broadcast(() =>
                  _livePrep(profileId, includeTombstones, kind)))
          .stream;

  @override
  Future<VisitPrepItemData> addVisitPrepItem({
    String? id,
    required String profileId,
    required String body,
    String kind = 'visit_prep',
    DateTime? updatedAt,
  }) async {
    final row = VisitPrepItemData(
      id: id ?? 'prep-${_nextId++}',
      profileId: profileId,
      body: body,
      kind: kind,
      isChecked: false,
      updatedAt: updatedAt ?? now,
      dirty: true,
      localRev: 0,
    );
    _prep[row.id] = row;
    _notifyPrep(profileId);
    return row;
  }

  @override
  Future<VisitPrepItemData?> editVisitPrepItem({
    required String id,
    required String body,
    DateTime? updatedAt,
  }) async {
    final row = _prep[id];
    if (row == null) return null;
    final updated = _copyPrep(row, body: body, updatedAt: updatedAt ?? now);
    _prep[id] = updated;
    _notifyPrep(row.profileId);
    return updated;
  }

  @override
  Future<VisitPrepItemData?> setVisitPrepItemChecked({
    required String id,
    required bool checked,
    String? checkedByUserId,
    DateTime? updatedAt,
  }) async {
    final row = _prep[id];
    if (row == null) return null;
    final updated = _copyPrep(
      row,
      isChecked: checked,
      checkedByUserId: checked ? checkedByUserId : null,
      clearCheckedBy: !checked,
      updatedAt: updatedAt ?? now,
    );
    _prep[id] = updated;
    _notifyPrep(row.profileId);
    return updated;
  }

  @override
  Future<void> softDeleteVisitPrepItem(String id) async {
    final row = _prep[id];
    if (row == null) return;
    _prep[id] = _copyPrep(
      row,
      body: '',
      isChecked: false,
      clearCheckedBy: true,
      deletedAt: now,
      updatedAt: now,
    );
    _notifyPrep(row.profileId);
  }

  @override
  Future<int> clearCheckedVisitPrepItems(
    String profileId, {
    String kind = 'visit_prep',
  }) async {
    var cleared = 0;
    for (final row in _livePrep(profileId, false, kind).toList()) {
      if (!row.isChecked) continue;
      _prep[row.id] = _copyPrep(
        row,
        isChecked: false,
        clearCheckedBy: true,
        deletedAt: now,
        updatedAt: now,
      );
      cleared++;
    }
    if (cleared > 0) _notifyPrep(profileId);
    return cleared;
  }

  VisitPrepItemData _copyPrep(
    VisitPrepItemData row, {
    String? body,
    bool? isChecked,
    String? checkedByUserId,
    bool clearCheckedBy = false,
    DateTime? deletedAt,
    required DateTime updatedAt,
  }) =>
      VisitPrepItemData(
        id: row.id,
        profileId: row.profileId,
        body: body ?? row.body,
        kind: row.kind,
        isChecked: isChecked ?? row.isChecked,
        checkedByUserId:
            clearCheckedBy ? null : (checkedByUserId ?? row.checkedByUserId),
        checkedAt: clearCheckedBy ? null : row.checkedAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        dirty: true,
        localRev: row.localRev + 1,
        loggedByUserId: row.loggedByUserId,
      );

  List<CareNoteData> _liveNotes(String profileId, bool includeTombstones) => [
        for (final row in _notes.values)
          if (row.profileId == profileId &&
              (includeTombstones || row.deletedAt == null))
            row,
      ];

  List<VisitPrepItemData> _livePrep(
    String profileId,
    bool includeTombstones,
    String? kind,
  ) =>
      [
        for (final row in _prep.values)
          if (row.profileId == profileId &&
              (kind == null || row.kind == kind) &&
              (includeTombstones || row.deletedAt == null))
            row,
      ];

  String _prepKey(String profileId, String? kind) =>
      kind == null ? '$profileId::*' : '$profileId::$kind';

  void _notifyPrep(String profileId) {
    for (final entry in _prepControllers.entries) {
      if (entry.key.startsWith('$profileId::')) {
        entry.value.add(_livePrep(profileId, false, _kindOf(entry.key)));
      }
    }
  }

  String? _kindOf(String key) {
    final kind = key.split('::').last;
    return kind == '*' ? null : kind;
  }

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
    for (final controller in _noteControllers.values) {
      await controller.close();
    }
    for (final controller in _prepControllers.values) {
      await controller.close();
    }
  }
}
