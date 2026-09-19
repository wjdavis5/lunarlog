/// Shared export-collaborator seam (Issue #222): pulled out of
/// `lib/ui/account/account_section.dart` so `AccountSection` (the
/// "Export first" affordance inside the delete-confirmation dialog) and
/// `lib/ui/settings/your_data_section.dart` ("Export my data", now reachable
/// without a cloud account) wire the same [AccountExportWriter] collaborator
/// from exactly one place instead of two copies drifting apart.
library;

import '../../domain/export/account_export_writer.dart';
import '../../domain/logging/custom_tag_registry.dart';
import '../../domain/logging/day_entry_merge_event.dart';
import '../../domain/models/care_note.dart';
import '../../domain/models/cycle_override.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/guardian_note.dart';
import '../../domain/models/observation.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/visit_prep_item.dart';
import '../../domain/repositories/profile_modes_repository.dart'
    show ProfileLifecycleMode;

/// The app's version string as carried into an export document (Issue #17
/// U5/U6). Kept in step with `pubspec.yaml`'s `version:` by hand - `lib/ui`
/// must not read it from a plugin (KTD6 keeps that off the pure builder,
/// and there is no reason to add the dependency just for this one string).
const String kAppVersionForExport = '1.0.0+1';

/// One line, no email/token/exception text (Issue #17 U6; R10).
const String kAccountExportFailureCopy =
    'Could not export your data. Please try again.';

/// Injectable seam for the export step (Issue #17 U5/U6): the default
/// builds the real platform writer; tests substitute a fake that just
/// records the call (or throws) without touching `path_provider`/
/// `share_plus`.
typedef ExportAccountCollaborator = Future<void> Function({
  required List<Profile> profiles,
  required Map<String, List<DayEntry>> entriesByProfile,
  Map<String, List<Observation>> observationsByProfile,
  Map<String, List<CareNote>> careNotesByProfile,
  Map<String, List<VisitPrepItem>> visitPrepByProfile,
  Map<String, ProfileLifecycleMode?> profileModesByProfile,
  Map<String, List<CycleOverride>> cycleOverridesByProfile,
  Map<String, List<DayEntryMergeEvent>> mergeEventsByProfile,
  Map<String, List<CustomTag>> customTagsByProfile,
  Map<String, List<GuardianNote>> guardianNotesByProfile,
  required String appVersion,
});

/// Builds the default collaborator around the tree-provided
/// [AccountExportWriter] (Issue #248's remote source is already baked into
/// that writer at construction - see `AccountExportWriter`'s own doc). A
/// factory, not a bare top-level function, so a caller can read the writer
/// from `context` at call time. Issue #240 widened
/// [ExportAccountCollaborator] with an optional `observationsByProfile`
/// parameter (default `const {}`), so existing test doubles only need that
/// parameter declared, not necessarily used. Issue #128 widens it the same
/// way with `careNotesByProfile`/`visitPrepByProfile`; Issue #140 review
/// (LLA-084) with `profileModesByProfile`/`cycleOverridesByProfile`;
/// Issue #130 with `mergeEventsByProfile`; Issue #824 with `customTagsByProfile`;
/// Issue #870 with `guardianNotesByProfile`.
ExportAccountCollaborator defaultExportAccountCollaborator(
  AccountExportWriter writer,
) =>
    ({
      required List<Profile> profiles,
      required Map<String, List<DayEntry>> entriesByProfile,
      Map<String, List<Observation>> observationsByProfile = const {},
      Map<String, List<CareNote>> careNotesByProfile = const {},
      Map<String, List<VisitPrepItem>> visitPrepByProfile = const {},
      Map<String, ProfileLifecycleMode?> profileModesByProfile = const {},
      Map<String, List<CycleOverride>> cycleOverridesByProfile = const {},
      Map<String, List<DayEntryMergeEvent>> mergeEventsByProfile = const {},
      Map<String, List<CustomTag>> customTagsByProfile = const {},
      Map<String, List<GuardianNote>> guardianNotesByProfile = const {},
      required String appVersion,
    }) =>
        writer.exportAndShare(
          profiles: profiles,
          entriesByProfile: entriesByProfile,
          observationsByProfile: observationsByProfile,
          careNotesByProfile: careNotesByProfile,
          visitPrepByProfile: visitPrepByProfile,
          profileModesByProfile: profileModesByProfile,
          cycleOverridesByProfile: cycleOverridesByProfile,
          mergeEventsByProfile: mergeEventsByProfile,
          customTagsByProfile: customTagsByProfile,
          guardianNotesByProfile: guardianNotesByProfile,
          appVersion: appVersion,
        );
