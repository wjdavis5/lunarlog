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
import '../../domain/models/profile.dart';
import '../../domain/prediction/cycle_history.dart';
import '../../domain/repositories/day_entries_repository.dart';
import '../../domain/repositories/observations_repository.dart';
import '../../domain/repositories/profiles_repository.dart';
import '../../domain/repositories/settings_store.dart';
import '../../l10n/app_localizations.dart';
import '../components/inline_error.dart';
import 'entry_existence_watch_mixin.dart';
import 'export_access.dart';

/// Injectable seam for CSV delivery: tests pass a fake recording the call.
typedef CsvExportCollaborator = Future<void> Function({
  required String cyclesCsv,
  required String dailyLogCsv,
  required DateTime exportedAt,
});

/// Failure copy for CSV export, matching privacy discipline (no exception details).
const String kCsvExportFailureCopy =
    'Could not export your cycle data as CSV. Please try again.';

String _subtitleFor({required bool hasEntries, required List<Profile> liveProfiles}) {
  if (!hasEntries) {
    return 'Add at least one day entry to export CSV tables.';
  }
  if (liveProfiles.length == 1) {
    return "Export ${liveProfiles.single.displayName}'s cycle data as "
        'spreadsheet-compatible CSV files.';
  }
  return 'Export your cycles and daily log as spreadsheet-compatible CSV files.';
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
    final error = _error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const ValueKey('csv-export-tile'),
          leading: const Icon(Icons.table_view_outlined),
          title: Text(AppLocalizations.of(context).settingsCsvExportTitle),
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

  Future<void> _export(BuildContext context, Profile profile) async {
    if (_exporting) return;
    // Read everything off `context` before the first `await` (the same
    // `use_build_context_synchronously` discipline the FHIR/PDF tiles use).
    final csvWriter = context.read<CsvExportWriter?>();
    final entriesRepo = context.read<DayEntriesRepository>();
    final observationsRepo = context.read<ObservationsRepository>();
    final settingsStore = context.read<SettingsStore?>();
    final l10n = AppLocalizations.of(context);

    // Issue #115 G4: resolve the operator's lens and the minor-profile gate
    // before any export work. A refusal surfaces the honest "not available"
    // copy and never touches the writer.
    final access = await resolveExportAccessOrRefuse(
      context,
      profile,
      () => setState(() => _error = l10n.exportMinorGuardianUnavailable),
    );
    if (access == null) return;

    setState(() {
      _exporting = true;
      _error = null;
    });

    try {
      final dayEntries = await entriesRepo.listForProfile(profile.id);
      final observations = await observationsRepo.listForProfile(profile.id);

      final rawOmissions = settingsStore != null
          ? await settingsStore.get(omittedCyclesSettingKey(profile.id))
          : null;
      final omittedCycleStarts = parseOmittedCycles(rawOmissions);

      final exportedAt = DateTime.now().toUtc();
      // Issue #115 G4: a guardian-lens export emits no private note text.
      final redactedEntries = redactForLens(dayEntries, access.lens);
      final cyclesCsv = buildCyclesCsv(
        entries: redactedEntries,
        omittedCycleStarts: omittedCycleStarts,
      );
      final dailyLogCsv = buildDailyLogCsv(
        entries: redactedEntries,
        observations: observations,
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
      } else if (csvWriter != null) {
        await csvWriter.exportAndShare(
          cyclesCsv: cyclesCsv,
          dailyLogCsv: dailyLogCsv,
          exportedAt: exportedAt,
        );
      } else {
        throw StateError('No CsvExportWriter or collaborator available');
      }
    } catch (error) {
      debugPrint('lunarlog csv-export: export failed (${error.runtimeType})');
      if (mounted) setState(() => _error = kCsvExportFailureCopy);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}
