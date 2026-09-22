/// In-memory [CycleStore] for repository tests (Issue #551, part 1
/// follow-up): the `profile_modes` and `cycle_overrides` surface
/// [DriftProfileModesRepository] and [DriftCycleOverridesRepository] call,
/// holding rows keyed by profile/id and re-emitting every watch on change —
/// with no drift database.
///
/// Mirrors the storage semantics those repositories rely on (one
/// `profile_modes` row per profile with a full-row upsert; `cycle_overrides`
/// tombstoned rather than removed and filtered from live reads) without
/// asserting them; the SQL itself is pinned by `test/data/db_test.dart` and
/// the `storage_*_test.dart` suites.
library;

import 'dart:async';

import 'package:lunarlog/data/db/db.dart' show CycleOverrideData, ProfileModeData;
import 'package:lunarlog/data/db/storage.dart';

class FakeCycleStore implements CycleStore {
  FakeCycleStore();

  final Map<String, ProfileModeData> _modes = <String, ProfileModeData>{};
  final Map<String, CycleOverrideData> _overrides =
      <String, CycleOverrideData>{};
  final Map<String, StreamController<ProfileModeData?>> _modeControllers =
      <String, StreamController<ProfileModeData?>>{};
  final Map<String, StreamController<List<CycleOverrideData>>>
      _overrideControllers =
      <String, StreamController<List<CycleOverrideData>>>{};
  int _nextId = 0;

  /// The clock every fake write stamps `updated_at` with; tests may override
  /// it, but none assert on the value.
  DateTime now = DateTime.utc(2026, 1, 1);

  @override
  Future<ProfileModeData?> getProfileMode(String profileId) async =>
      _modes[profileId];

  @override
  Stream<ProfileModeData?> watchProfileMode(String profileId) => _modeControllers
      .putIfAbsent(profileId,
          () => _broadcast(() => _modes[profileId]))
      .stream;

  @override
  Future<CycleOverrideData?> getCycleOverrideById(
    String id,
    String profileId,
  ) async {
    final row = _overrides[id];
    return row != null && row.profileId == profileId ? row : null;
  }

  @override
  Future<List<CycleOverrideData>> getCycleOverridesForProfile(
    String profileId, {
    bool includeTombstones = false,
  }) async =>
      _liveOverrides(profileId, includeTombstones);

  @override
  Stream<List<CycleOverrideData>> watchCycleOverridesForProfile(
    String profileId, {
    bool includeTombstones = false,
  }) =>
      _overrideControllers
          .putIfAbsent(
              profileId,
              () => _broadcast(
                  () => _liveOverrides(profileId, includeTombstones)))
          .stream;

  @override
  Future<ProfileModeData> upsertProfileMode({
    required String profileId,
    required String mode,
    String? modeStartedOn,
    String? estimatedDueDate,
    String? postpartumBirthDate,
    String? birthControlMethod,
    String? birthControlStartedOn,
    String? birthControlStoppedOn,
    bool healthSyncConsent = false,
    DateTime? updatedAt,
  }) async {
    final row = ProfileModeData(
      profileId: profileId,
      mode: mode,
      modeStartedOn: modeStartedOn,
      estimatedDueDate: estimatedDueDate,
      postpartumBirthDate: postpartumBirthDate,
      birthControlMethod: birthControlMethod,
      birthControlStartedOn: birthControlStartedOn,
      birthControlStoppedOn: birthControlStoppedOn,
      healthSyncConsent: healthSyncConsent,
      updatedAt: updatedAt ?? now,
      dirty: true,
      localRev: (_modes[profileId]?.localRev ?? 0) + 1,
    );
    _modes[profileId] = row;
    _modeControllers[profileId]?.add(row);
    return row;
  }

  @override
  Future<CycleOverrideData> upsertCycleOverride({
    String? id,
    required String profileId,
    required String cycleStartDate,
    bool excludedFromAverage = false,
    bool manualStart = false,
    String? noteId,
    DateTime? updatedAt,
  }) async {
    final existing = id == null ? null : _overrides[id];
    final row = CycleOverrideData(
      id: id ?? 'override-${_nextId++}',
      profileId: profileId,
      cycleStartDate: cycleStartDate,
      excludedFromAverage: excludedFromAverage,
      manualStart: manualStart,
      noteId: noteId,
      updatedAt: updatedAt ?? now,
      dirty: true,
      localRev: (existing?.localRev ?? 0) + 1,
    );
    _overrides[row.id] = row;
    _notifyOverrides(profileId);
    return row;
  }

  @override
  Future<void> softDeleteCycleOverride({
    required String id,
    required String profileId,
  }) async {
    final row = _overrides[id];
    if (row == null) return;
    _overrides[id] = CycleOverrideData(
      id: row.id,
      profileId: row.profileId,
      cycleStartDate: row.cycleStartDate,
      excludedFromAverage: false,
      manualStart: false,
      updatedAt: now,
      deletedAt: now,
      dirty: true,
      localRev: row.localRev + 1,
    );
    _notifyOverrides(profileId);
  }

  List<CycleOverrideData> _liveOverrides(
    String profileId,
    bool includeTombstones,
  ) =>
      [
        for (final row in _overrides.values)
          if (row.profileId == profileId &&
              (includeTombstones || row.deletedAt == null))
            row,
      ];

  void _notifyOverrides(String profileId) =>
      _overrideControllers[profileId]?.add(_liveOverrides(profileId, false));

  /// A broadcast controller that emits [current] to every first subscriber
  /// (so a write racing the subscription can never be lost before the seed
  /// lands, unlike an `async*` seed that only runs a microtask later). Closed
  /// by [close].
  static StreamController<T> _broadcast<T>(T Function() current) {
    // close_sinks can't trace the returned controller to close()'s map.
    // ignore: close_sinks
    late StreamController<T> controller;
    controller = StreamController<T>.broadcast(
      onListen: () => controller.add(current()),
    );
    return controller;
  }

  /// Closes every watch stream. Call from `addTearDown`.
  Future<void> close() async {
    for (final controller in _modeControllers.values) {
      await controller.close();
    }
    for (final controller in _overrideControllers.values) {
      await controller.close();
    }
  }
}
