/// "Export clinical summary (FHIR)" tile (Issue #157). A standalone
/// `StatefulWidget` — not folded into `YourDataSection`'s own `build`,
/// which PR #325 is mid-flight restructuring — so this ships as a single
/// wiring line in `your_data_section.dart` instead of a conflicting diff
/// inside that method. Mirrors `YourDataSection`'s own shape (profiles
/// watch, injectable export collaborator, `InlineError` on failure) but
/// owns its own state independently.
///
/// v1 exports live (non-archived) profiles only, no date-range UI yet —
/// `buildFhirDocumentBundle` itself is already per-profile/date-range
/// capable; this tile just doesn't expose the range choice yet. Profile
/// selection (#157 review fix): with exactly one live profile, the tile's
/// own subtitle names it and export needs no extra tap; with several, a
/// [SimpleDialog] chooser runs before the Bundle is built. The exported
/// *file* still never carries a name (`fhirBundleFileName` stays a bare
/// date) — the chooser only decides which profile's data goes in, not
/// what to call the file. See `docs/clinical/fhir-export.md` for the
/// date-range follow-up this still defers.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/export/fhir_bundle_writer.dart';
import '../../domain/export/fhir_bundle.dart';
import '../../domain/models/local_date.dart';
import '../../domain/models/profile.dart';
import '../../domain/prediction/prediction.dart';
import '../../domain/repositories/day_entries_repository.dart';
import '../../domain/repositories/observations_repository.dart';
import '../../domain/repositories/profiles_repository.dart';
import '../account/export_account_collaborator.dart' show kAppVersionForExport;
import '../components/inline_error.dart';

/// Injectable seam for FHIR delivery (mirrors
/// `ExportAccountCollaborator`): the default builds the real
/// [FhirBundleWriter]; tests substitute a fake that just records the call.
typedef FhirExportCollaborator = Future<void> Function({
  required Map<String, Object?> bundle,
  required DateTime exportedAt,
});

/// One line, no health content, no exception text (mirrors
/// `kAccountExportFailureCopy`'s R10 discipline).
const String kClinicalExportFailureCopy =
    'Could not export your clinical summary. Please try again.';

Future<void> _defaultFhirExportCollaborator({
  required Map<String, Object?> bundle,
  required DateTime exportedAt,
}) =>
    const FhirBundleWriter().exportAndShare(
      bundle: bundle,
      exportedAt: exportedAt,
    );

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

  /// FHIR export collaborator; null means [_defaultFhirExportCollaborator]
  /// (the real platform writer). Injectable so tests never touch
  /// `path_provider`/`share_plus`.
  final FhirExportCollaborator? exportFhir;

  @override
  State<ClinicalExportTile> createState() => _ClinicalExportTileState();
}

class _ClinicalExportTileState extends State<ClinicalExportTile> {
  StreamSubscription<List<Profile>>? _profilesSub;
  List<Profile>? _profiles;
  bool _hasEntries = false;
  bool _exporting = false;
  String? _error;

  /// Guards [_refreshHasEntries] against out-of-order completion (#157
  /// review fix): every profiles emission starts a fresh async scan of
  /// however many live profiles there are, and a slow older scan finishing
  /// after a newer one must not clobber the newer result with a stale one.
  /// Bumped at the *start* of each call; a call only applies its result if
  /// it is still the most recent one when it finishes.
  int _hasEntriesGeneration = 0;

  @override
  void initState() {
    super.initState();
    _profilesSub = context.read<ProfilesRepository?>()?.watch().listen(
      (profiles) {
        if (!mounted) return;
        setState(() => _profiles = profiles);
        // Re-evaluated on every emission (#157 review fix), not just once:
        // a profile being archived/unarchived or a day entry being added
        // elsewhere changes which live profiles exist and whether any of
        // them has entries, and the tile's enabled state must track that.
        unawaited(_refreshHasEntries(profiles));
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
            'lunarlog clinical-export: profiles watch failed (${error.runtimeType})');
        if (mounted) setState(() => _profiles = null);
      },
    );
  }

  /// Whether *any* live profile has at least one day entry — cheap: an
  /// `any`-shaped early-exit scan (#157 review fix) rather than always
  /// awaiting every live profile's full entry list, since the repository
  /// interface exposes no row-count query to check more cheaply still.
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
    final canExport = !_exporting && _hasEntries;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const ValueKey('clinical-export-fhir'),
          leading: const Icon(Icons.medical_information_outlined),
          title: const Text('Export clinical summary (FHIR)'),
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
          title: const Text('Export clinical summary for'),
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

  /// Builds the Bundle for [profile] (see [buildFhirDocumentBundle]) and
  /// hands it to the export collaborator; failures render as copy beneath
  /// the tile, mirroring `YourDataSection._export`.
  Future<void> _export(BuildContext context, Profile profile) async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final entriesRepo = context.read<DayEntriesRepository>();
      final observationsRepo = context.read<ObservationsRepository>();
      final dayEntries = await entriesRepo.listForProfile(profile.id);
      final observations = await observationsRepo.listForProfile(profile.id);
      final exportedAt = DateTime.now().toUtc();
      final prediction = computePredictionFromEntries(
        entries: dayEntries,
        today: LocalDate.today(),
      );
      final bundle = buildFhirDocumentBundle(
        profile: profile,
        dayEntries: dayEntries,
        observations: observations,
        prediction: prediction is ActivePrediction ? prediction : null,
        exportedAt: exportedAt,
        appVersion: kAppVersionForExport,
      );
      await (widget.exportFhir ?? _defaultFhirExportCollaborator)(
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
}
