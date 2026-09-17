/// Repository interface (R14/R16) for a profile's manual cycle corrections
/// (Issue #188's `cycle_overrides` storage), surfaced here as the
/// persistence seam issue #568 (b) needs: the history list's per-cycle
/// "omit from averages" toggle used to live entirely in a device-local
/// `SettingsStore` list (`CycleExclusionList`, `lib/domain/prediction/
/// cycle_history.dart`) — never synced, so an omission made on one device
/// silently did not follow to another, which is exactly the gap
/// `cycle_overrides` (a synced, RLS-protected table) was built to close.
///
/// This interface was originally narrow on purpose: it exposed only the
/// "excluded from average" axis of a cycle override, not the full
/// `CycleOverride` model ([manualStart]/[noteId] stay owned elsewhere) —
/// [CycleExclusionList] never needed more than an id-less per-date boolean
/// flag, and keeping the seam narrow meant a caller could not accidentally
/// clobber a manual-start boundary or a note while toggling an omission.
/// [listForProfile] widens it deliberately (Issue #140 review, LLA-084):
/// account export needs every live override's full fidelity (id,
/// manualStart, noteId included) to make a backup self-restorable, a need
/// [excludedCycleStarts]'s narrow boolean-set shape cannot serve.
///
/// Concrete drift-backed implementation lives in
/// `lib/data/repositories/drift_cycle_overrides_repository.dart`.
library;

import '../models/cycle_override.dart';

abstract interface class CycleOverridesRepository {
  /// Every LIVE (non-tombstoned) cycle override for [profileId], full
  /// fidelity (Issue #140 review, LLA-084) — used by account export so a
  /// restored backup can recreate each override's `manualStart`/`noteId`,
  /// not just the excluded-from-average flag [excludedCycleStarts] exposes.
  Future<List<CycleOverride>> listForProfile(String profileId);

  /// The ISO `yyyy-MM-dd` cycle-start dates currently excluded from
  /// averages for [profileId] (live, non-tombstoned overrides only).
  Future<Set<String>> excludedCycleStarts(String profileId);

  /// Reactive variant of [excludedCycleStarts]; emits again on every
  /// `cycle_overrides` write for [profileId] (a local toggle, or a
  /// synced edit from another device).
  Stream<Set<String>> watchExcludedCycleStarts(String profileId);

  /// Sets whether [cycleStartDate] is excluded from averages for
  /// [profileId], idempotently. Preserves an existing override's
  /// `manualStart`/`noteId` untouched when one already exists for that
  /// boundary; creates a fresh override (manualStart false, no note) when
  /// [excluded] is true and none exists yet. Setting [excluded] to false
  /// on an override that exists *only* to carry the exclusion (no manual
  /// start, no note) withdraws it entirely (a tombstone) rather than
  /// leaving an empty husk row behind.
  Future<void> setExcludedFromAverage({
    required String profileId,
    required String cycleStartDate,
    required bool excluded,
  });
}
