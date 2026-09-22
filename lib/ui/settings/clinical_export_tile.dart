/// "Export clinical summary (FHIR)" tile (Issue #157). A standalone
/// `StatefulWidget` — not folded into `YourDataSection`'s own `build`,
/// which PR #325 is mid-flight restructuring — so this ships as a single
/// wiring line in `your_data_section.dart` instead of a conflicting diff
/// inside that method. Mirrors `YourDataSection`'s own shape (profiles
/// watch, injectable export collaborator, `InlineError` on failure) but
/// owns its own state independently.
///
/// v1 exports live (non-archived) profiles only. Profile selection (#157
/// review fix): with exactly one live profile, the tile's own subtitle
/// names it and export needs no extra tap; with several, a [SimpleDialog]
/// chooser runs before the Bundle is built. The exported *file* still never
/// carries a name (`fhirBundleFileName` stays a bare date) — the chooser
/// only decides which profile's data goes in, not what to call the file.
/// Issue #459 added a date-range selection step between the profile choice
/// and the Bundle build, opening on the six most-recent completed cycles
/// by default — see `export_range_picker_sheet.dart`,
/// `domain/export/fhir_export_range.dart`, and
/// `docs/clinical/fhir-export.md`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/export/export_redaction.dart';
import '../../domain/export/fhir_bundle.dart';
import '../../domain/export/fhir_bundle_writer.dart';
import '../../domain/export/fhir_export_range.dart';
import '../../domain/models/local_date.dart';
import '../../domain/models/profile.dart';
import '../../domain/prediction/cycle_history.dart' show CycleExclusionList;
import '../../domain/prediction/prediction.dart';
import '../../domain/repositories/day_entries_repository.dart';
import '../../domain/repositories/observations_repository.dart';
import '../../domain/repositories/profiles_repository.dart';
import '../../l10n/app_localizations.dart';
import '../account/export_account_collaborator.dart' show kAppVersionForExport;
import '../components/inline_error.dart';
import 'entry_existence_watch_mixin.dart';
import 'export_access.dart';
import 'export_range_picker_sheet.dart';

/// Injectable seam for FHIR delivery (mirrors
/// `ExportAccountCollaborator`): the default uses the tree-provided
/// [FhirBundleWriter]; tests substitute a fake that just records the call.
typedef FhirExportCollaborator = Future<void> Function({
  required Map<String, Object?> bundle,
  required DateTime exportedAt,
});

/// One line, no health content, no exception text (mirrors
/// `kAccountExportFailureCopy`'s R10 discipline).
const String kClinicalExportFailureCopy =
    'Could not export your clinical summary. Please try again.';

/// [liveProfiles] excludes archived profiles (see [_liveProfiles]). With
/// exactly one, its name goes straight into the subtitle (#157 review fix,
/// "Export Riley's clinical summary") once there is something to export;
/// with none or several, the copy stays generic — several because the
/// tile doesn't yet know which one the chooser will pick.
String _subtitleFor({required bool hasEntries, required List<Profile> liveProfiles}) {
  if (!hasEntries) {
    return 'Add at least one day entry to export a clinical summary.';
  }
  if (liveProfiles.length == 1) {
    return "Export ${liveProfiles.single.displayName}'s clinical summary.";
  }
  return 'Share an IPS-shaped FHIR R4 document with your cycle data, coded '
      'and self-reported.';
}

/// Live (non-archived) profiles, in the order [profiles] already carries
/// (mirrors `ProfileController`'s and `HealthSyncScreen`'s own `archivedAt
/// == null` filter — #157 review fix: the tile previously exported
/// `profiles.first` unconditionally, archived included).
List<Profile> _liveProfiles(List<Profile> profiles) =>
    [for (final profile in profiles) if (profile.archivedAt == null) profile];

class ClinicalExportTile extends StatefulWidget {
  const ClinicalExportTile({super.key, this.exportFhir});

  /// FHIR export collaborator; null means the tree-provided
  /// [FhirBundleWriter] (the real platform writer). Injectable so tests
  /// never touch `path_provider`/`share_plus`.
  final FhirExportCollaborator? exportFhir;

  @override
  State<ClinicalExportTile> createState() => _ClinicalExportTileState();
}

class _ClinicalExportTileState extends State<ClinicalExportTile>
    with EntryExistenceWatchMixin<ClinicalExportTile> {
  StreamSubscription<List<Profile>>? _profilesSub;
  List<Profile>? _profiles;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _profilesSub = context.read<ProfilesRepository?>()?.watch().listen(
      (profiles) {
        if (!mounted) return;
        setState(() => _profiles = profiles);
        // Issue #642, LLA-010: a bounded existence stream per live profile,
        // decoupled from this profiles-stream tick — see
        // `EntryExistenceWatchMixin`'s doc comment for why deriving it from
        // this tick alone went stale under the app shell's retained
        // IndexedStack.
        watchEntryExistence(
          context.read<DayEntriesRepository?>(),
          _liveProfiles(profiles).map((profile) => profile.id),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
            'lunarlog clinical-export: profiles watch failed (${error.runtimeType})');
        if (mounted) setState(() => _profiles = null);
      },
    );
  }

  @override
  void dispose() {
    unawaited(_profilesSub?.cancel());
    disposeEntryExistenceWatch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Explicit gate (#157 review fix), not inherited from the parent
    // `YourDataSection`'s own `kIsWeb` check — this tile is meant to stand
    // on its own (it already owns its state independently, per this file's
    // doc comment), so it must not depend on being hosted behind another
    // widget's web gate to stay off web.
    if (kIsWeb) return const SizedBox.shrink();
    final profiles = _profiles;
    if (profiles == null) return const SizedBox.shrink();
    final liveProfiles = _liveProfiles(profiles);
    if (liveProfiles.isEmpty) return const SizedBox.shrink();
    final canExport = !_exporting && hasAnyEntries;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const ValueKey('clinical-export-fhir'),
          leading: const Icon(Icons.medical_information_outlined),
          title: Text(
            AppLocalizations.of(context).settingsClinicalExportFhirTitle,
          ),
          subtitle: Text(
            _subtitleFor(hasEntries: hasAnyEntries, liveProfiles: liveProfiles),
          ),
          enabled: canExport,
          trailing: _exporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: canExport ? () => _handleTap(context, liveProfiles) : null,
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: InlineError(
              key: const ValueKey('clinical-export-fhir-error'),
              message: error,
            ),
          ),
      ],
    );
  }

  /// One live profile exports straight away; several ask which one first
  /// (#157 review fix — the tile used to export `profiles.first`
  /// unconditionally). A cancelled chooser (`chosen == null`) or the
  /// widget unmounting while it was open both simply do nothing.
  Future<void> _handleTap(
    BuildContext context,
    List<Profile> liveProfiles,
  ) async {
    if (liveProfiles.length == 1) {
      await _export(context, liveProfiles.single);
      return;
    }
    final chosen = await _chooseProfile(context, liveProfiles);
    if (chosen == null || !context.mounted) return;
    await _export(context, chosen);
  }

  /// A [SimpleDialog] listing [liveProfiles] by display name; resolves to
  /// the tapped profile, or `null` if dismissed without a choice.
  Future<Profile?> _chooseProfile(
    BuildContext context,
    List<Profile> liveProfiles,
  ) =>
      showDialog<Profile>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(
            AppLocalizations.of(dialogContext).clinicalPdfExportForProfileTitle,
          ),
          children: [
            for (final profile in liveProfiles)
              _profileOption(dialogContext, profile),
          ],
        ),
      );

  SimpleDialogOption _profileOption(BuildContext dialogContext, Profile profile) =>
      SimpleDialogOption(
        key: ValueKey('clinical-export-fhir-profile-${profile.id}'),
        onPressed: () => Navigator.of(dialogContext).pop(profile),
        child: Text(profile.displayName),
      );

  /// Asks [profile]'s date range first (#459 — see
  /// `showExportRangePickerSheet`; a cancelled picker does nothing, the
  /// same "no choice, no export" discipline [_handleTap]'s profile chooser
  /// already uses), then builds the Bundle (see [buildFhirDocumentBundle])
  /// and hands it to the export collaborator; failures render as copy
  /// beneath the tile, mirroring `YourDataSection._export`.
  ///
  /// [prediction] is always computed from [profile]'s *full* history
  /// (independent of the chosen range) — the cycle-length/last-menstrual-
  /// period statistics it feeds should read the same regardless of how far
  /// back the exported document's own Observations reach; only the raw
  /// flow/symptom entries embedded in the document are narrowed to the
  /// chosen range, via [FhirExportRange.filterEntries]/
  /// [FhirExportRange.filterObservations].
  Future<void> _export(BuildContext context, Profile profile) async {
    if (_exporting) return;
    // Read before the first `await` below (`use_build_context_synchronously`).
    final fhirWriter = context.read<FhirBundleWriter>();
    final exclusions = context.read<CycleExclusionList?>();
    final entriesRepo = context.read<DayEntriesRepository>();
    final observationsRepo = context.read<ObservationsRepository>();
    final l10n = AppLocalizations.of(context);

    // Issue #115 G4: resolve the operator's lens and the minor-profile gate
    // before the range picker and the build. A refusal surfaces the honest
    // "not available" copy and never calls the collaborator.
    final access = await resolveExportAccessOrRefuse(
      context,
      profile,
      () => setState(() => _error = l10n.exportMinorGuardianUnavailable),
    );
    if (access == null) return;

    // Issue #459 review: the range picker is asked *before* `_exporting`
    // flips true, not inside the same try/finally as the actual export
    // work below. `_exporting` drives the tile's indeterminate
    // `CircularProgressIndicator` (see `build`); that indicator, once
    // animating, never settles on its own (`pumpAndSettle` has nothing to
    // wait out), so keeping it running for as long as the picker sheet
    // sits open waiting on the operator would hang `pumpAndSettle`-driven
    // tests indefinitely — and would show a spinner over a modal the
    // operator hasn't dismissed yet, which reads as the export already
    // running when nothing has started.
    final dayEntries = await entriesRepo.listForProfile(profile.id);
    if (!context.mounted) return;
    final range = await showExportRangePickerSheet(
      context,
      entries: dayEntries,
      today: LocalDate.today(),
    );
    if (range == null || !context.mounted) return;

    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final observations = await observationsRepo.listForProfile(profile.id);
      final exportedAt = DateTime.now().toUtc();
      final omittedCycleStarts = await _omittedCycleStartsFor(exclusions, profile.id);
      final prediction = computePredictionFromEntries(
        entries: dayEntries,
        today: LocalDate.today(),
        omittedCycleStarts: omittedCycleStarts,
      );
      final bundle = buildFhirDocumentBundle(
        profile: profile,
        // Issue #115 G4: a guardian-lens export carries no private note text
        // (FHIR never reads DayEntry.note anyway; the shared step keeps the
        // rule uniform across formats).
        dayEntries: redactForLens(range.filterEntries(dayEntries), access.lens),
        observations: range.filterObservations(observations),
        prediction: prediction is ActivePrediction ? prediction : null,
        exportedAt: exportedAt,
        appVersion: kAppVersionForExport,
      );
      await (widget.exportFhir ?? fhirWriter.exportAndShare)(
        bundle: bundle,
        exportedAt: exportedAt,
      );
    } catch (error) {
      debugPrint(
          'lunarlog clinical-export: export failed (${error.runtimeType})');
      if (mounted) setState(() => _error = kClinicalExportFailureCopy);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Issue #648 review / LLA-067: the same cycle-start exclusion set the
  /// history list and overview panel already honor (`CycleExclusionList`,
  /// synced via `cycle_overrides` since issue #568 (b)) — without this, the
  /// clinical export's own cycle-length/last-menstrual-period statistics
  /// silently recomputed from every logged cycle, including ones the
  /// operator explicitly excluded, so the exported document could disagree
  /// with the very averages the app's own UI displays for the same profile.
  /// A null [exclusions] (no collaborator wired — a test, or unconfigured
  /// build) degrades to "nothing excluded", the same fail-open default
  /// every other optional collaborator in this codebase uses.
  static Future<Set<LocalDate>> _omittedCycleStartsFor(
    CycleExclusionList? exclusions,
    String profileId,
  ) async {
    if (exclusions == null) return const {};
    return exclusions.load(profileId);
  }
}
