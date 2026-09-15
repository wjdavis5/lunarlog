/// Settings "Your data" section (Issue #222; source: B-17). Reachable
/// without a cloud account: the section itself renders on any non-web
/// platform, independent of sign-in state and even with zero profiles on
/// this device — the whole point of "Import from file" (Issue #140) is
/// restoring a device that has *no* profiles yet (a fresh install, or the
/// README's documented "lost device, no account, no backup" case). "Export
/// my data" stays additionally gated on at least one profile existing —
/// there is nothing to export otherwise.
///
/// "Export my data" used to live only inside `AccountSection`, gated
/// `if (signedIn && ...)` (Issue #17) - a user who declined the account
/// step at first run (an explicitly supported path, `first_run_screen.dart`
/// "Not now") had local-only data and no way to export it, even though the
/// underlying document (`lib/domain/export/account_export.dart`) never
/// actually needed an account; only that UI gate did. This section is that
/// fix: the tile moved here, above the Account section in
/// `settings_screen.dart`, and now renders for a signed-out operator too.
/// `AccountSection` keeps its own, independent use of the same
/// [ExportAccountCollaborator] seam for the delete-confirmation dialog's
/// "Export first" step - the two do not share any state. "Delete account"
/// stays in the Account section unchanged: it is inherently account-scoped
/// and does not belong here.
///
/// Not gated behind a fresh device-credential re-auth of its own: neither
/// was `AccountSection`'s pre-#222 export tile (only "Add"/"Remove" a
/// sign-in method and "Delete account" ever called
/// `GateController.reauthenticate` there) - reaching Settings at all
/// already sits behind the app's own lock, and this section changes nothing
/// about that.
///
/// "Import from file" (Issue #140) pushes `ImportScreen`
/// (`lib/ui/settings/import_screen.dart`) via `kRouteImportScreen` — the
/// screen itself owns picking, parsing, previewing, and applying an
/// import; this section is just the entry point, matching "Export my
/// data"'s own thin-tile shape.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart';
import 'package:lunarlog/domain/export/account_export_writer.dart';
import 'package:lunarlog/domain/models/care_note.dart';
import 'package:lunarlog/domain/models/cycle_override.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/visit_prep_item.dart';
import 'package:lunarlog/domain/profiles/profile_erasure_service.dart';
import 'package:lunarlog/domain/repositories/account_export_snapshot_repository.dart';
import 'package:lunarlog/domain/repositories/care_content_repository.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart'
    show ProfileLifecycleMode;
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/export_account_collaborator.dart';
import 'package:lunarlog/ui/components/destructive_button.dart';
import 'package:lunarlog/ui/settings/clinical_export_tile.dart';
import 'package:lunarlog/ui/settings/csv_export_tile.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/routes.dart';
import 'package:provider/provider.dart';

class YourDataSection extends StatefulWidget {
  const YourDataSection({
    super.key,
    this.showExport,
    this.showImport,
    this.exportAccount,
    this.exportCsv,
    this.profileErasureService,
  });

  /// Injected collaborator for CSV export testing.
  final CsvExportCollaborator? exportCsv;

  /// Issue #472: "Purge imported data" — null (the R26 unconfigured-build
  /// posture, same gate every other network-backed tile in this app uses)
  /// hides the tile entirely.
  final ProfileErasureService? profileErasureService;

  /// Whether "Export my data" may render at all; null means "not web"
  /// (matches `AccountSection`'s pre-#222 `showExportAndDelete` default -
  /// R11 never shipped either tile on web). Injectable so tests simulate
  /// web without actually running on it.
  final bool? showExport;

  /// Whether "Import from file" may render at all (Issue #140); null means
  /// "not web", the same default as [showExport]. Injectable so tests
  /// simulate web without actually running on it.
  final bool? showImport;

  /// Export collaborator; null means [defaultExportAccountCollaborator]
  /// (the real platform writer). Injectable so tests never touch
  /// `path_provider`/`share_plus`.
  final ExportAccountCollaborator? exportAccount;

  @override
  State<YourDataSection> createState() => _YourDataSectionState();
}

class _YourDataSectionState extends State<YourDataSection> {
  StreamSubscription<List<Profile>>? _profilesSub;
  List<Profile>? _profiles;
  bool _exporting = false;
  String? _exportError;

  /// Issue #472: "Purge imported data" busy/error state — parallel to
  /// [_exporting]/[_exportError] above, independent of the export tile.
  bool _purging = false;
  String? _purgeError;

  bool get _canExport => widget.showExport ?? !kIsWeb;
  bool get _canImport => widget.showImport ?? !kIsWeb;

  @override
  void initState() {
    super.initState();
    // Mirrors `SettingsScreen`'s own initState (a one-off `context.read`
    // for a Provider-injected singleton is safe here, unlike
    // `context.watch`/`Provider.of(listen: true)`): a nullable repository
    // means an unconfigured build (e.g. a test with none provided) simply
    // never sees any profiles, same as "no profiles yet".
    _profilesSub = context.read<ProfilesRepository?>()?.watch().listen(
      (profiles) {
        if (mounted) setState(() => _profiles = profiles);
      },
      onError: (Object error, StackTrace stackTrace) {
        // A broken profiles stream shouldn't surface as an unhandled zone
        // error; treat it like "no profiles yet" and hide the section.
        debugPrint('lunarlog your-data: profiles watch failed ($error)');
        if (mounted) setState(() => _profiles = null);
      },
    );
  }

  @override
  void dispose() {
    unawaited(_profilesSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles;
    if ((!_canExport && !_canImport) || profiles == null) {
      return const SizedBox.shrink();
    }
    final auth = Provider.of<AuthController?>(context);
    // A `passwordRecovery` session counts as signed in for rendering
    // purposes here too (issue #23, AC4).
    final signedIn = auth?.state.hasUsableSession ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _sectionChildren(context, profiles, signedIn),
    );
  }

  /// The full "Your data" section body: heading, [_exportTile], [_importTile],
  /// trailing divider (Issue #140 review, item 1 — split out of [build]
  /// itself so no single method carries every tile's conditionals).
  List<Widget> _sectionChildren(
    BuildContext context,
    List<Profile> profiles,
    bool signedIn,
  ) {
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('Your data', style: theme.textTheme.titleSmall),
      ),
      ..._exportTile(context, profiles, signedIn),
      ..._importTile(context),
      CsvExportTile(exportCsv: widget.exportCsv), // Issue #469
      const ClinicalExportTile(), // Issue #157
      ..._purgeImportedDataTile(context, profiles), // Issue #472
      const Divider(),
    ];
  }

  /// "Export my data" — empty when [_canExport] is false or there are no
  /// profiles yet (nothing to export, unlike import: Issue #140 is exactly
  /// for restoring a device that has none). [signedIn] only changes the
  /// tile's subtitle copy (Issue #222: an export names the account's
  /// server data only when signed in - a signed-out export is local-only,
  /// `serverIncluded: false`, see `buildMergedAccountExport`).
  List<Widget> _exportTile(
    BuildContext context,
    List<Profile> profiles,
    bool signedIn,
  ) {
    if (!_canExport || profiles.isEmpty) return const [];
    final exportError = _exportError;
    return [
      ListTile(
        key: const ValueKey('your-data-export'),
        leading: const Icon(Icons.file_download_outlined),
        title: const Text('Export my data'),
        subtitle: Text(
          signedIn
              ? 'Save your profiles, day entries, care notes, and visit-prep '
                  "lists as a JSON file, including your account's server data."
              : 'Save your profiles, day entries, care notes, and visit-prep '
                  'lists as a JSON file.',
        ),
        enabled: !_exporting,
        trailing: _exporting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onTap: !_exporting ? () => _export(context) : null,
      ),
      if (exportError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: InlineError(
            key: const ValueKey('your-data-export-error'),
            message: exportError,
          ),
        ),
    ];
  }

  /// "Import from file" (Issue #140) — empty when [_canImport] is false.
  List<Widget> _importTile(BuildContext context) {
    if (!_canImport) return const [];
    return [
      ListTile(
        key: const ValueKey('your-data-import'),
        leading: const Icon(Icons.file_upload_outlined),
        title: const Text('Import from file'),
        subtitle: const Text(
          'Restore profiles and day entries from a JSON file this app '
          'exported.',
        ),
        onTap: () => pushNamedScreen(context, kRouteImportScreen),
      ),
    ];
  }

  /// "Purge imported data" (Issue #472) — empty when no
  /// [ProfileErasureService] is configured or there are no profiles yet
  /// (nothing to pick from). Deliberately not role-gated client-side
  /// (unlike Manage Guardians' "Delete profile permanently"): the server
  /// enforces the primary-guardian requirement identically for every
  /// caller, and this tile does not know each listed profile's guardian
  /// role in advance — an unauthorized attempt simply surfaces the honest
  /// error below rather than being hidden.
  List<Widget> _purgeImportedDataTile(
    BuildContext context,
    List<Profile> profiles,
  ) {
    final service = widget.profileErasureService;
    if (service == null || profiles.isEmpty) return const [];
    final purgeError = _purgeError;
    return [
      ListTile(
        key: const ValueKey('your-data-purge-imported'),
        leading: const Icon(Icons.filter_alt_off_outlined),
        title: const Text('Purge imported data'),
        subtitle: const Text(
          'Remove only the entries a specific import brought in — manually '
          'logged data is never touched.',
        ),
        enabled: !_purging,
        trailing: _purging
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onTap: !_purging ? () => _purgeImportedData(profiles) : null,
      ),
      if (purgeError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: InlineError(
            key: const ValueKey('your-data-purge-error'),
            message: purgeError,
          ),
        ),
    ];
  }

  /// Opens [_PurgeImportedDataDialog] to collect a profile + source, then
  /// runs the purge. Never role-gated client-side (see the tile's doc
  /// comment) — an unauthorized attempt surfaces through [_purgeErrorMessage]
  /// like any other failure.
  Future<void> _purgeImportedData(List<Profile> profiles) async {
    if (_purging) return;
    final selection = await showDialog<_PurgeSelection>(
      context: context,
      routeSettings: const RouteSettings(name: kRoutePurgeImportedDataDialog),
      builder: (ctx) => _PurgeImportedDataDialog(profiles: profiles),
    );
    if (selection == null || !mounted) return;

    setState(() {
      _purging = true;
      _purgeError = null;
    });
    try {
      await widget.profileErasureService!.purgeImportedData(
        profileId: selection.profileId,
        source: selection.source,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purged ${selection.source.label} data')),
        );
      }
    } catch (error) {
      debugPrint('lunarlog your-data: purge failed (${error.runtimeType})');
      if (mounted) setState(() => _purgeError = _purgeErrorMessage(error));
    } finally {
      if (mounted) setState(() => _purging = false);
    }
  }

  String _purgeErrorMessage(Object error) {
    if (error is ProfileErasureNetworkFailure) {
      return "Can't purge while offline. Check your connection and try "
          'again.';
    }
    if (error is ProfileErasureUnauthorizedFailure) {
      return 'Only that profile\'s primary guardian can purge its data.';
    }
    return 'Failed to purge imported data. Check connection and try again.';
  }

  /// "Export my data" (mirrors `AccountSection`'s pre-#222 `_exportAccount`
  /// / `_runExport`, independently of that section's own collaborator):
  /// one export at a time, failures render as copy beneath the tile rather
  /// than an exception.
  Future<void> _export(BuildContext context) async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _exportError = null;
    });
    try {
      final profilesRepo = context.read<ProfilesRepository>();
      // Issue #140 review, LLA-094: entries/observations (plus, LLA-084,
      // profileMode/cycleOverrides) are read together per profile through
      // this one coherent snapshot seam, not as separate, independently-
      // timed repository calls — see `AccountExportSnapshotRepository`'s
      // own doc comment for the orphan-observation gap that closes.
      final snapshotRepo = context.read<AccountExportSnapshotRepository>();
      final careContentRepo = context.read<CareContentRepository>();
      // Read before the first `await` below (not after -
      // `use_build_context_synchronously`), same as `AccountSection`'s
      // `_runExport`. The writer already carries its optional server-side
      // remote source from construction; an unconfigured build's writer
      // resolves to a local-only document (no `server` key).
      final exportWriter = context.read<AccountExportWriter>();
      final profiles = await profilesRepo.list();
      final entriesByProfile = <String, List<DayEntry>>{};
      final observationsByProfile = <String, List<Observation>>{};
      final careNotesByProfile = <String, List<CareNote>>{};
      final visitPrepByProfile = <String, List<VisitPrepItem>>{};
      final profileModesByProfile = <String, ProfileLifecycleMode?>{};
      final cycleOverridesByProfile = <String, List<CycleOverride>>{};
      final mergeEventsByProfile = <String, List<DayEntryMergeEvent>>{};
      for (final profile in profiles) {
        final snapshot = await snapshotRepo.forProfile(profile.id);
        entriesByProfile[profile.id] = snapshot.entries;
        observationsByProfile[profile.id] = snapshot.observations;
        profileModesByProfile[profile.id] = snapshot.profileMode;
        cycleOverridesByProfile[profile.id] = snapshot.cycleOverrides;
        mergeEventsByProfile[profile.id] = snapshot.mergeEvents;
        careNotesByProfile[profile.id] =
            await careContentRepo.listCareNotes(profile.id);
        visitPrepByProfile[profile.id] =
            await careContentRepo.listPrepItems(profile.id);
      }
      await (widget.exportAccount ??
          defaultExportAccountCollaborator(exportWriter))(
        profiles: profiles,
        entriesByProfile: entriesByProfile,
        observationsByProfile: observationsByProfile,
        careNotesByProfile: careNotesByProfile,
        visitPrepByProfile: visitPrepByProfile,
        profileModesByProfile: profileModesByProfile,
        cycleOverridesByProfile: cycleOverridesByProfile,
        mergeEventsByProfile: mergeEventsByProfile,
        appVersion: kAppVersionForExport,
      );
    } catch (error) {
      debugPrint('lunarlog your-data: export failed (${error.runtimeType})');
      if (mounted) setState(() => _exportError = kAccountExportFailureCopy);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

/// The result of [_PurgeImportedDataDialog]: which profile and which
/// import source to purge.
class _PurgeSelection {
  const _PurgeSelection(this.profileId, this.source);

  final String profileId;
  final PurgeableImportSource source;
}

/// "Purge imported data"'s picker (Issue #472): a profile dropdown and a
/// source dropdown, styled destructively since the purge is irreversible
/// from this device's point of view (the underlying import file, if kept,
/// can always re-import). A [StatefulWidget] with its own selection state
/// (the `_EnterCodeDialog`/`_ProfileEditDialog` precedent) rather than
/// closures capturing mutable locals across `showDialog`'s builder, which
/// Flutter may invoke more than once.
class _PurgeImportedDataDialog extends StatefulWidget {
  const _PurgeImportedDataDialog({required this.profiles});

  final List<Profile> profiles;

  @override
  State<_PurgeImportedDataDialog> createState() =>
      _PurgeImportedDataDialogState();
}

class _PurgeImportedDataDialogState extends State<_PurgeImportedDataDialog> {
  late String _profileId = widget.profiles.first.id;
  PurgeableImportSource _source = PurgeableImportSource.values.first;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Purge imported data'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Only entries and observations tagged with the chosen import '
              'source are removed. Manually logged data, and the profile '
              'itself, are never touched.',
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Profile',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            DropdownButton<String>(
              key: const ValueKey('purge-profile-dropdown'),
              value: _profileId,
              isExpanded: true,
              onChanged: (value) =>
                  setState(() => _profileId = value ?? _profileId),
              items: [
                for (final profile in widget.profiles)
                  DropdownMenuItem<String>(
                    value: profile.id,
                    child: Text(profile.displayName),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Import source',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            DropdownButton<PurgeableImportSource>(
              key: const ValueKey('purge-source-dropdown'),
              value: _source,
              isExpanded: true,
              onChanged: (value) =>
                  setState(() => _source = value ?? _source),
              items: [
                for (final source in PurgeableImportSource.values)
                  DropdownMenuItem<PurgeableImportSource>(
                    value: source,
                    child: Text(source.label),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        DestructiveButton(
          onPressed: () => Navigator.of(context)
              .pop(_PurgeSelection(_profileId, _source)),
          child: const Text('Purge'),
        ),
      ],
    );
  }
}
