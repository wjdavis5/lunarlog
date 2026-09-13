/// Drift-backed [CycleOverridesRepository] (issue #568 (b)): the narrow
/// "excluded from average" seam over Issue #188's `cycle_overrides`
/// storage that [CycleExclusionList] (`lib/domain/prediction/
/// cycle_history.dart`) reads and writes through instead of the
/// device-local `SettingsStore` list it used before this issue.
library;

import 'package:lunarlog/data/db/db.dart' show CycleOverrideData;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/repositories/cycle_overrides_repository.dart';

class DriftCycleOverridesRepository implements CycleOverridesRepository {
  DriftCycleOverridesRepository(this._storage);

  final LunarLogStorage _storage;

  @override
  Future<Set<String>> excludedCycleStarts(String profileId) async {
    final overrides = await _storage.getCycleOverridesForProfile(profileId);
    return _excludedStartsOf(overrides);
  }

  @override
  Stream<Set<String>> watchExcludedCycleStarts(String profileId) =>
      _storage
          .watchCycleOverridesForProfile(profileId)
          .map(_excludedStartsOf);

  Set<String> _excludedStartsOf(List<CycleOverrideData> overrides) => {
        for (final override in overrides)
          if (override.excludedFromAverage) override.cycleStartDate,
      };

  @override
  Future<void> setExcludedFromAverage({
    required String profileId,
    required String cycleStartDate,
    required bool excluded,
  }) async {
    final existing = await _liveOverrideAt(profileId, cycleStartDate);
    if (existing == null) {
      // Nothing to withdraw, and nothing to create for a no-op "un-exclude"
      // of a boundary that was never excluded.
      if (!excluded) return;
      await _storage.upsertCycleOverride(
        profileId: profileId,
        cycleStartDate: cycleStartDate,
        excludedFromAverage: true,
      );
      return;
    }
    if (!excluded && !existing.manualStart && existing.noteId == null) {
      // This override exists only to carry the exclusion flag — withdraw
      // it entirely (a tombstone) rather than leave an empty husk row with
      // every flag false.
      await _storage.softDeleteCycleOverride(
          id: existing.id, profileId: profileId);
      return;
    }
    // Preserve manualStart/noteId untouched — this is a full-row upsert
    // (LunarLogStorage.upsertCycleOverride's own shape, the
    // ProfileModesRepository precedent), so an unrelated caller's manual
    // boundary or note must never be silently cleared by an omission
    // toggle.
    await _storage.upsertCycleOverride(
      id: existing.id,
      profileId: profileId,
      cycleStartDate: cycleStartDate,
      excludedFromAverage: excluded,
      manualStart: existing.manualStart,
      noteId: existing.noteId,
    );
  }

  /// The live (non-tombstoned) override at [profileId]/[cycleStartDate],
  /// or null. [LunarLogStorage.getCycleOverridesForProfile] already filters
  /// tombstones by default, so no extra check is needed here.
  Future<CycleOverrideData?> _liveOverrideAt(
    String profileId,
    String cycleStartDate,
  ) async {
    final overrides = await _storage.getCycleOverridesForProfile(profileId);
    for (final override in overrides) {
      if (override.cycleStartDate == cycleStartDate) return override;
    }
    return null;
  }
}
