/// "Export clinical summary (PDF)" tile (Issue #154).
///
/// A standalone [StatefulWidget] matching [ClinicalExportTile]'s shape (live
/// profiles watch, injectable export collaborator, profile chooser when
/// several live profiles exist, inline error banner on failure) — so it
/// ships as a single wiring line in `your_data_section.dart`. It reuses the
/// shared [showExportRangePickerSheet] and the #459
/// [FhirExportRange]/[resolveFhirExportRangePreset] machinery rather than
/// introducing a second range UI, and the same [CycleExclusionList] the
/// history list and FHIR export already honor.
///
/// The PDF is generated entirely on-device by
/// `lib/domain/export/clinical_pdf.dart`; this tile never touches the
/// network. It is deliberately separate from the FHIR tile: the PDF must
/// work standalone, and #157 already owns the FHIR entry point.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/export/clinical_pdf.dart';
import '../../domain/export/clinical_pdf_summary.dart';
import '../../domain/export/clinical_pdf_writer.dart';
import '../../domain/export/fhir_export_range.dart';
import '../../domain/logging/custom_tag_registry.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/local_date.dart';
import '../../domain/models/profile.dart';
import '../../domain/prediction/cycle_history.dart' show CycleExclusionList;
import '../../domain/repositories/day_entries_repository.dart';
import '../../domain/repositories/observations_repository.dart';
import '../../domain/repositories/profile_modes_repository.dart';
import '../../domain/repositories/profiles_repository.dart';
import '../../domain/repositories/tag_registry_repository.dart';
import '../../l10n/app_localizations.dart';
import '../components/inline_error.dart';
import '../overview/estimate_copy.dart' show kEstimateDisclaimer;
import 'entry_existence_watch_mixin.dart';
import 'export_range_picker_sheet.dart' show fhirExportRangePresetLabel, showExportRangePickerSheet;

/// Injectable seam for PDF delivery (mirrors `FhirExportCollaborator`):
/// tests substitute a fake that records the call.
typedef ClinicalPdfExportCollaborator = Future<void> Function({
  required Uint8List pdfBytes,
  required DateTime exportedAt,
});

/// Failure copy is arb-backed (`settingsClinicalExportFailure`, shared
/// with the FHIR tile) and resolved through [AppLocalizations] at render
/// time (issue #1004, tranche 5).

/// Arb-backed subtitles (`settingsClinicalPdfSubtitle*`) since issue
/// #1004, tranche 5.
String _subtitleFor(
  AppLocalizations l10n, {
  required bool hasEntries,
  required List<Profile> liveProfiles,
}) {
  if (!hasEntries) {
    return l10n.settingsClinicalPdfSubtitleNoEntries;
  }
  if (liveProfiles.length == 1) {
    return l10n.settingsClinicalPdfSubtitleOneProfile(
      liveProfiles.single.displayName,
    );
  }
  return l10n.settingsClinicalPdfSubtitleGeneric;
}

List<Profile> _liveProfiles(List<Profile> profiles) =>
    [for (final profile in profiles) if (profile.archivedAt == null) profile];

class ClinicalPdfExportTile extends StatefulWidget {
  const ClinicalPdfExportTile({super.key, this.exportPdf});

  /// PDF export collaborator; null means the tree-provided
  /// [ClinicalPdfWriter] (the real platform writer). Injectable so tests
  /// never touch `path_provider`/`share_plus`.
  final ClinicalPdfExportCollaborator? exportPdf;

  @override
  State<ClinicalPdfExportTile> createState() => _ClinicalPdfExportTileState();
}

class _ClinicalPdfExportTileState extends State<ClinicalPdfExportTile>
    with EntryExistenceWatchMixin<ClinicalPdfExportTile> {
  StreamSubscription<List<Profile>>? _profilesSub;
  List<Profile>? _profiles;
  bool _exporting = false;

  /// Issue #1004 (tranche 5): failure state only — the copy resolves
  /// through `AppLocalizations` at render time.
  bool _exportFailed = false;

  @override
  void initState() {
    super.initState();
    _profilesSub = context.read<ProfilesRepository?>()?.watch().listen(
      (profiles) {
        if (!mounted) return;
        setState(() => _profiles = profiles);
        watchEntryExistence(
          context.read<DayEntriesRepository?>(),
          _liveProfiles(profiles).map((profile) => profile.id),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
          'lunarlog clinical-pdf: profiles watch failed '
          '(${error.runtimeType})',
        );
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
    // Explicit gate: this tile stands on its own (see its doc comment), so
    // it must not depend on a parent's web gate.
    if (kIsWeb) return const SizedBox.shrink();
    final profiles = _profiles;
    if (profiles == null) return const SizedBox.shrink();
    final liveProfiles = _liveProfiles(profiles);
    if (liveProfiles.isEmpty) return const SizedBox.shrink();
    final canExport = !_exporting && hasAnyEntries;
    final error = _exportFailed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const ValueKey('clinical-pdf-export'),
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: Text(
            AppLocalizations.of(context).clinicalPdfExportTitle,
          ),
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
        if (error)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: InlineError(
              key: const ValueKey('clinical-pdf-export-error'),
              message:
                  AppLocalizations.of(context).settingsClinicalExportFailure,
            ),
          ),
      ],
    );
  }

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

  Future<Profile?> _chooseProfile(
    BuildContext context,
    List<Profile> liveProfiles,
  ) => showDialog<Profile>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(
        AppLocalizations.of(dialogContext).clinicalPdfExportForProfileTitle,
      ),
      children: [
        for (final profile in liveProfiles)
          SimpleDialogOption(
            key: ValueKey('clinical-pdf-export-profile-${profile.id}'),
            onPressed: () => Navigator.of(dialogContext).pop(profile),
            child: Text(profile.displayName),
          ),
      ],
    ),
  );

  /// Asks [profile]'s date range (via the shared picker, opening on the six
  /// most-recent completed cycles), then builds and delivers the PDF.
  /// Mirrors `ClinicalExportTile._export`'s sequence, including asking for
  /// the range before flipping `_exporting` so the spinner never animates
  /// over an open modal.
  Future<void> _export(BuildContext context, Profile profile) async {
    if (_exporting) return;
    final deps = _PdfExportDeps.read(context);
    // Resolved before any `await` so the PDF's range label can localize
    // without touching `context` across an async gap (issue #1004).
    final l10n = AppLocalizations.of(context);
    final dayEntries = await deps.entries.listForProfile(profile.id);
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
    });
    try {
      final exportedAt = DateTime.now().toUtc();
      final bytes = await _buildPdf(
        deps,
        l10n,
        profile,
        dayEntries,
        range,
        exportedAt,
      );
      await _deliver(deps.writer, bytes, exportedAt);
    } catch (error) {
      debugPrint(
        'lunarlog clinical-pdf: export failed (${error.runtimeType})',
      );
      if (mounted) setState(() => _exportFailed = true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Reads the profile's remaining data and renders the document, entirely
  /// on-device. The only derived figures are descriptive statistics over
  /// logged lengths, so the shared estimate disclaimer accompanies them —
  /// never a fertility or conception estimate, which this document does not
  /// compute.
  Future<Uint8List> _buildPdf(
    _PdfExportDeps deps,
    AppLocalizations l10n,
    Profile profile,
    List<DayEntry> dayEntries,
    FhirExportRange range,
    DateTime exportedAt,
  ) async {
    final observations = await deps.observations.listForProfile(profile.id);
    final omittedCycleStarts =
        await deps.exclusions?.load(profile.id) ?? const <LocalDate>{};
    final mode = await deps.modes?.find(profile.id);
    final customTags =
        await deps.tagRegistry?.listForProfile(profile.id) ?? const <CustomTag>[];
    return buildClinicalPdfDocument(
      buildClinicalPdfSummary(
        profile: profile,
        dayEntries: dayEntries,
        observations: observations,
        customTags: customTags,
        range: range,
        rangeLabel: _rangeLabelFor(l10n, range),
        generatedAt: exportedAt,
        omittedCycleStarts: omittedCycleStarts,
        birthControlMethod: mode?.birthControlMethod,
        derivedValueDisclaimers: const [kEstimateDisclaimer],
      ),
    );
  }

  /// Hands [bytes] to the injected collaborator (a test), else the
  /// tree-provided writer.
  Future<void> _deliver(
    ClinicalPdfWriter? writer,
    Uint8List bytes,
    DateTime exportedAt,
  ) async {
    final collaborator = widget.exportPdf;
    if (collaborator != null) {
      await collaborator(pdfBytes: bytes, exportedAt: exportedAt);
      return;
    }
    if (writer != null) {
      await writer.exportAndShare(pdfBytes: bytes, exportedAt: exportedAt);
      return;
    }
    throw StateError('No ClinicalPdfWriter or collaborator available');
  }

  /// A custom range names its explicit start/end dates; every preset uses
  /// the picker's own label. Arb-backed since issue #1004, tranche 5 —
  /// note this label ships inside the PDF document, so its arb value is
  /// document copy too. The `'start'`/`'end'` fallbacks only fire for a
  /// malformed custom range the picker itself can never produce (both
  /// endpoints are enforced) and stay literal: they are defensive
  /// placeholders, not sentences.
  static String _rangeLabelFor(AppLocalizations l10n, FhirExportRange range) {
    if (range.preset != FhirExportRangePreset.custom) {
      return fhirExportRangePresetLabel(l10n, range.preset);
    }
    final start = range.start?.iso ?? 'start';
    final end = range.end?.iso ?? 'end';
    return l10n.settingsClinicalPdfRangeCustom(start, end);
  }
}

/// The repositories and writer the PDF export reads, resolved from the
/// widget tree once before any `await`.
class _PdfExportDeps {
  const _PdfExportDeps({
    required this.writer,
    required this.exclusions,
    required this.entries,
    required this.observations,
    required this.modes,
    required this.tagRegistry,
  });

  final ClinicalPdfWriter? writer;
  final CycleExclusionList? exclusions;
  final DayEntriesRepository entries;
  final ObservationsRepository observations;
  final ProfileModesRepository? modes;
  final TagRegistryRepository? tagRegistry;

  static _PdfExportDeps read(BuildContext context) => _PdfExportDeps(
    writer: context.read<ClinicalPdfWriter?>(),
    exclusions: context.read<CycleExclusionList?>(),
    entries: context.read<DayEntriesRepository>(),
    observations: context.read<ObservationsRepository>(),
    modes: context.read<ProfileModesRepository?>(),
    tagRegistry: context.read<TagRegistryRepository?>(),
  );
}
