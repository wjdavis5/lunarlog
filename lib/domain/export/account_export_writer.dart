/// Contract for writing and sharing the JSON account export (Issue #17,
/// U5; R4).
///
/// The UI needs to hand a built export document to the platform share sheet
/// but must not depend on the `path_provider`/`share_plus` adapter in
/// `lib/data/export/`; the contract takes and returns only domain models.
library;

import '../logging/custom_tag_registry.dart';
import '../logging/day_entry_merge_event.dart';
import '../models/care_note.dart';
import '../models/cycle_override.dart';
import '../models/day_entry.dart';
import '../models/guardian_note.dart';
import '../models/observation.dart';
import '../models/profile.dart';
import '../models/visit_prep_item.dart';
import '../repositories/profile_modes_repository.dart' show ProfileLifecycleMode;
import 'account_export_remote_source.dart';

abstract interface class AccountExportWriter {
  /// The optional server-side export source; null for an unconfigured build
  /// or a caller that skips it (see [AccountExportRemoteSource]).
  AccountExportRemoteSource? get remoteSource;

  /// Builds the export document from the supplied domain data, writes it to
  /// a temp file, and hands that file to the platform share sheet.
  Future<void> exportAndShare({
    required List<Profile> profiles,
    required Map<String, List<DayEntry>> entriesByProfile,
    Map<String, List<Observation>> observationsByProfile = const {},
    Map<String, List<CareNote>> careNotesByProfile = const {},
    Map<String, List<VisitPrepItem>> visitPrepByProfile = const {},
    // Issue #140 review, LLA-084 (kAccountExportSchemaVersion v9).
    Map<String, ProfileLifecycleMode?> profileModesByProfile = const {},
    Map<String, List<CycleOverride>> cycleOverridesByProfile = const {},
    // Issue #130 (kAccountExportSchemaVersion v11).
    Map<String, List<DayEntryMergeEvent>> mergeEventsByProfile = const {},
    // Issue #824 (kAccountExportSchemaVersion v12).
    Map<String, List<CustomTag>> customTagsByProfile = const {},
    // Issue #870 (kAccountExportSchemaVersion v13).
    Map<String, List<GuardianNote>> guardianNotesByProfile = const {},
    required String appVersion,
  });
}
