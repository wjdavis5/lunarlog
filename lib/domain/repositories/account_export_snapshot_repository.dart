/// Repository interface (R14/R16) for a coherent, point-in-time export read
/// (Issue #140 review, LLA-084/LLA-094 — export's "backup omits state" and
/// "orphan observation" findings, both closed by the same seam): a
/// profile's live day entries, observations, life-stage mode, and cycle
/// overrides, read together inside one storage transaction rather than as
/// separate, independently-timed repository calls.
///
/// Before this existed, `YourDataSection`/`AccountSection`'s export flow
/// called `DayEntriesRepository.listForProfile` and
/// `ObservationsRepository.listForProfile` as two SEPARATE awaits — a
/// concurrent sync landing a new day entry and its observation between
/// those two reads could produce an export whose `observations` key
/// references a `local_date` missing from that same export's `dayEntries`,
/// which `parseAccountImport`'s own `_rejectOrphanObservations` then
/// rejects outright, as if the file were corrupt. [forProfile] closes that
/// gap by reading everything for one profile inside a single
/// [LunarLogStorage] transaction, so a concurrent write either lands
/// entirely before or entirely after the read, never straddling it.
///
/// Folding `profileMode`/`cycleOverrides` into the SAME coherent read
/// (rather than adding a third, separately-timed call) is deliberate:
/// LLA-084 needs them in the export anyway, and there is no reason to pay
/// for a second transaction when this one already exists.
///
/// Concrete drift-backed implementation lives in
/// `lib/data/repositories/drift_account_export_snapshot_repository.dart`.
library;

import '../logging/custom_tag_registry.dart';
import '../logging/day_entry_merge_event.dart';
import '../models/cycle_override.dart';
import '../models/day_entry.dart';
import '../models/observation.dart';
import 'profile_modes_repository.dart' show ProfileLifecycleMode;

/// One profile's coherently-read export state — see this file's own doc
/// comment.
typedef AccountExportSnapshot = ({
  List<DayEntry> entries,
  List<Observation> observations,
  ProfileLifecycleMode? profileMode,
  List<CycleOverride> cycleOverrides,
  List<DayEntryMergeEvent> mergeEvents,
  List<CustomTag> customTags,
});

abstract interface class AccountExportSnapshotRepository {
  /// [profileId]'s live day entries, observations, life-stage mode (null
  /// when no `profile_modes` row was ever written for it), cycle
  /// overrides, window-live same-date merge disclosures (Issue #130
  /// — the 30-day recovery window, so an export never carries retained
  /// losing text the server has already purged), and live custom tag registry
  /// entries (Issue #824), read together as one atomic, point-in-time snapshot.
  Future<AccountExportSnapshot> forProfile(String profileId);
}
