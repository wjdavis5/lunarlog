/// "Export as CSV" tile (Issue #469).
///
/// Standalone [StatefulWidget] matching [ClinicalExportTile]'s shape:
/// live profiles watch, injectable collaborator, profile dialog chooser when
/// several live profiles exist, and inline error banner on failure.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/export/csv_export.dart';
import '../../domain/export/csv_export_writer.dart';
import '../../domain/export/export_redaction.dart';
import '../../domain/export/fhir_export_range.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/local_date.dart';
import '../../domain/models/profile.dart';
import '../../domain/prediction/cycle_history.dart' show CycleExclusionList;
import '../../domain/repositories/day_entries_repository.dart';
import '../../domain/repositories/observations_repository.dart';
import '../../domain/repositories/profiles_repository.dart';
import '../../l10n/app_localizations.dart';
import '../components/inline_error.dart';
import 'entry_existence_watch_mixin.dart';
import 'export_access.dart';
import 'export_range_picker_sheet.dart';

/// Injectable seam for CSV delivery: tests pass a fake recording the call.
typedef CsvExportCollaborator = Future<void> Function({
  required String cyclesCsv,
  required String dailyLogCsv,
  required DateTime exportedAt,
});

/// The tile's subtitle (issue #1004, tranche 5): resolved through
/// [AppLocalizations] so the copy stays arb-backed
/// (`settingsCsvExportSubtitle*`).
String _subtitleFor(
  AppLocalizations l10n, {
  required bool hasEntries,
  required List<Profile> liveProfiles,
}) {
  if (!hasEntries) {
    return l10n.settingsCsvExportSubtitleNoEntries;
  }
  if (liveProfiles.length == 1) {
    return l10n.settingsCsvExportSubtitleOneProfile(
      liveProfiles.single.displayName,
    );
  }
  return l10n.settingsCsvExportSubtitleGeneric;
}

List<Profile> _liveProfiles(List<Profile> profiles) =>
    [for (final profile in profiles) if (profile.archivedAt == null) profile];

class CsvExportTile extends StatefulWidget {
  const CsvExportTile({super.key, this.exportCsv});

  /// Injected export collaborator; null means the tree-provided [CsvExportWriter].
  final CsvExportCollaborator? exportCsv;

  @override
  State<CsvExportTile> createState() => _CsvExportTileState();
}

class _CsvExportTileState extends State<CsvExportTile>
    with EntryExistenceWatchMixin<CsvExportTile> {
  StreamSubscription<List<Profile>>? _profilesSub;
  List<Profile>? _profiles;
  bool _exporting = false;

  /// Issue #1004 (tranche 5): the failure copy this state used to store as
  /// a resolved English string resolves through `AppLocalizations` at
  /// render time.
  bool _exportFailed = false;

  /// Issue #115 G4: the minor-profile guard refused this export. Distinct
  /// from [_exportFailed] so the tile shows the honest "not available" copy
  /// rather than the generic failure line.
  bool _minorGuardRefused = false;

  /// The copy to render beneath the tile, or null when there is none.
  String? _errorCopy(AppLocalizations l10n) {
    if (_minorGuardRefused) return l10n.exportMinorGuardianUnavailable;
    if (_exportFailed) return l10n.settingsCsvExportFailure;
    return null;
  }

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
        debugPrint('lunarlog csv-export: profiles watch failed (${error.runtimeType})');
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
    if (kIsWeb) return const SizedBox.shrink();
    final profiles = _profiles;
    if (profiles == null) return const SizedBox.shrink();
    final liveProfiles = _liveProfiles(profiles);
    if (liveProfiles.isEmpty) return const SizedBox.shrink();
    final canExport = !_exporting && hasAnyEntries;
    final l10n = AppLocalizations.of(context);
    final error = _errorCopy(l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const ValueKey('csv-export-tile'),
          leading: const Icon(Icons.table_view_outlined),
          title: Text(AppLocalizations.of(context).settingsCsvExportTitle),
          subtitle: Text(
            _subtitleFor(
              AppLocalizations.of(context),
              hasEntries: hasAnyEntries,
              liveProfiles: liveProfiles,
            ),
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
              key: const ValueKey('csv-export-error'),
              message: error,
            ),
          ),
      ],
    );
  }

  Future<void> _handleTap(BuildContext context, List<Profile> liveProfiles) async {
    if (liveProfiles.length == 1) {
      await _export(context, liveProfiles.single);
      return;
    }
    final chosen = await _chooseProfile(context, liveProfiles);
    if (chosen == null || !context.mounted) return;
    await _export(context, chosen);
  }

  Future<Profile?> _chooseProfile(
    BuildContext context,
    List<Profile> liveProfiles,
  ) =>
      showDialog<Profile>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(AppLocalizations.of(dialogContext).settingsCsvExportForTitle),
          children: [
            for (final profile in liveProfiles)
              SimpleDialogOption(
                key: ValueKey('csv-export-profile-${profile.id}'),
                onPressed: () => Navigator.of(dialogContext).pop(profile),
                child: Text(profile.displayName),
              ),
          ],
        ),
      );

  /// Asks [profile]'s date range through the same shared picker the FHIR and
  /// PDF clinical exports use (Issue #115 G3: the picker opens on "last 6
  /// cycles"), then builds both CSV files and hands them to the writer.
  /// Mirrors the clinical tiles' sequence exactly: the range is asked
  /// *before* flipping [_exporting], so the tile's spinner never animates
  /// over an open modal, and a cancelled picker (`range == null`) exports
  /// nothing.
  Future<void> _export(BuildContext context, Profile profile) async {
    if (_exporting) return;
    // Read everything off `context` before the first `await` (the same
    // `use_build_context_synchronously` discipline the FHIR/PDF tiles use).
    final csvWriter = context.read<CsvExportWriter?>();
    final exclusions = context.read<CycleExclusionList?>();
    final entriesRepo = context.read<DayEntriesRepository>();
    final observationsRepo = context.read<ObservationsRepository>();

    // Issue #115 G4: resolve the operator's lens and the minor-profile gate
    // before any export work. A refusal surfaces the honest "not available"
    // copy and never touches the writer.
    final access = await resolveExportAccessOrRefuse(
      context,
      profile,
      () => setState(() {
        _minorGuardRefused = true;
        _exportFailed = false;
      }),
    );
    if (access == null) return;

    // The range picker's cycle-count presets resolve from the full history,
    // so entries are read once here and reused for the build below.
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
      _exportFailed = false;
      _minorGuardRefused = false;
    });
    try {
      await _buildAndDeliver(
        profile: profile,
        dayEntries: dayEntries,
        range: range,
        access: access,
        csvWriter: csvWriter,
        observationsRepo: observationsRepo,
        exclusions: exclusions,
      );
    } catch (error) {
      debugPrint('lunarlog csv-export: export failed (${error.runtimeType})');
      if (mounted) setState(() => _exportFailed = true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Builds both CSV strings from [dayEntries] and [profile]'s observations,
  /// then hands them to the injected collaborator (a test) or the
  /// tree-provided writer. Split out of [_export] so neither method carries
  /// the range-picker branches *and* the delivery branches past the CRAP
  /// gate's complexity budget; throws on a missing writer so [_export]'s
  /// catch reports it. [dayEntries] is the same full-history list the range
  /// picker resolved its presets from — each builder narrows to [range]
  /// itself, so `cycles.csv` and `daily_log.csv` trim to one boundary.
  Future<void> _buildAndDeliver({
    required Profile profile,
    required List<DayEntry> dayEntries,
    required FhirExportRange range,
    required ExportAccess access,
    required CsvExportWriter? csvWriter,
    required ObservationsRepository observationsRepo,
    required CycleExclusionList? exclusions,
  }) async {
    final observations = await observationsRepo.listForProfile(profile.id);
    // Issue #648 review / LLA-067: the same cycle-start exclusion set the
    // history list and overview panel already honor (`CycleExclusionList`,
    // synced via `cycle_overrides` since issue #568 (b)) — read through the
    // one shared path the FHIR/PDF tiles use (Issue #115 G3 removed this
    // tile's divergent `SettingsStore`/`parseOmittedCycles` read). A null
    // [exclusions] (no collaborator wired — a test, or unconfigured build)
    // degrades to "nothing excluded", the same fail-open default every other
    // optional collaborator in this codebase uses.
    final omittedCycleStarts =
        await exclusions?.load(profile.id) ?? const <LocalDate>{};

    final exportedAt = DateTime.now().toUtc();
    // Issue #115 G4: a guardian-lens export emits no private note text.
    final redactedEntries = redactForLens(dayEntries, access.lens);
    final cyclesCsv = buildCyclesCsv(
      entries: redactedEntries,
      omittedCycleStarts: omittedCycleStarts,
      range: range,
    );
    final dailyLogCsv = buildDailyLogCsv(
      entries: redactedEntries,
      observations: observations,
      range: range,
      // Issue #612, LLA-093: normalize bbt/weight to the profile's own
      // display-unit preference, the same numbers the app's own UI would
      // show for this profile (once that reading path itself exists —
      // see `measurement_unit.dart`'s doc comment).
      bbtUnit: profile.bbtUnit,
      weightUnit: profile.weightUnit,
    );

    final collaborator = widget.exportCsv;
    if (collaborator != null) {
      await collaborator(
        cyclesCsv: cyclesCsv,
        dailyLogCsv: dailyLogCsv,
        exportedAt: exportedAt,
      );
      return;
    }
    if (csvWriter != null) {
      await csvWriter.exportAndShare(
        cyclesCsv: cyclesCsv,
        dailyLogCsv: dailyLogCsv,
        exportedAt: exportedAt,
      );
      return;
    }
    throw StateError('No CsvExportWriter or collaborator available');
  }
}
