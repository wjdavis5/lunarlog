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
import '../../domain/models/profile.dart';
import '../../domain/prediction/cycle_history.dart';
import '../../domain/repositories/day_entries_repository.dart';
import '../../domain/repositories/observations_repository.dart';
import '../../domain/repositories/profiles_repository.dart';
import '../../domain/repositories/settings_store.dart';
import '../components/inline_error.dart';

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

class _CsvExportTileState extends State<CsvExportTile> {
  StreamSubscription<List<Profile>>? _profilesSub;
  List<Profile>? _profiles;
  bool _hasEntries = false;
  bool _exporting = false;
  String? _error;
  int _hasEntriesGeneration = 0;

  @override
  void initState() {
    super.initState();
    _profilesSub = context.read<ProfilesRepository?>()?.watch().listen(
      (profiles) {
        if (!mounted) return;
        setState(() => _profiles = profiles);
        unawaited(_refreshHasEntries(profiles));
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('lunarlog csv-export: profiles watch failed (${error.runtimeType})');
        if (mounted) setState(() => _profiles = null);
      },
    );
  }

  Future<void> _refreshHasEntries(List<Profile> profiles) async {
    final generation = ++_hasEntriesGeneration;
    final liveProfiles = _liveProfiles(profiles);
    final hasEntries = await _anyProfileHasEntries(liveProfiles);
    if (mounted && generation == _hasEntriesGeneration) {
      setState(() => _hasEntries = hasEntries);
    }
  }

  Future<bool> _anyProfileHasEntries(List<Profile> liveProfiles) async {
    final entriesRepo = context.read<DayEntriesRepository?>();
    if (entriesRepo == null) return false;
    for (final profile in liveProfiles) {
      final entries = await entriesRepo.listForProfile(profile.id);
      if (entries.isNotEmpty) return true;
    }
    return false;
  }

  @override
  void dispose() {
    unawaited(_profilesSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final profiles = _profiles;
    if (profiles == null) return const SizedBox.shrink();
    final liveProfiles = _liveProfiles(profiles);
    if (liveProfiles.isEmpty) return const SizedBox.shrink();
    final canExport = !_exporting && _hasEntries;
    final error = _error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const ValueKey('csv-export-tile'),
          leading: const Icon(Icons.table_view_outlined),
          title: const Text('Export as CSV'),
          subtitle: Text(
            _subtitleFor(hasEntries: _hasEntries, liveProfiles: liveProfiles),
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
          title: const Text('Export CSV data for'),
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
    final csvWriter = context.read<CsvExportWriter?>();
    setState(() {
      _exporting = true;
      _error = null;
    });

    try {
      final entriesRepo = context.read<DayEntriesRepository>();
      final observationsRepo = context.read<ObservationsRepository>();
      final settingsStore = context.read<SettingsStore?>();

      final dayEntries = await entriesRepo.listForProfile(profile.id);
      final observations = await observationsRepo.listForProfile(profile.id);

      final rawOmissions = settingsStore != null
          ? await settingsStore.get(omittedCyclesSettingKey(profile.id))
          : null;
      final omittedCycleStarts = parseOmittedCycles(rawOmissions);

      final exportedAt = DateTime.now().toUtc();
      final cyclesCsv = buildCyclesCsv(
        entries: dayEntries,
        omittedCycleStarts: omittedCycleStarts,
      );
      final dailyLogCsv = buildDailyLogCsv(
        entries: dayEntries,
        observations: observations,
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
