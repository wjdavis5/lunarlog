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
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart';
import 'package:lunarlog/domain/export/account_export_writer.dart';
import 'package:lunarlog/domain/models/care_note.dart';
import 'package:lunarlog/domain/models/cycle_override.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/guardian_note.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/visit_prep_item.dart';
import 'package:lunarlog/domain/profiles/profile_erasure_service.dart';
import 'package:lunarlog/domain/repositories/account_export_snapshot_repository.dart';
import 'package:lunarlog/domain/repositories/care_content_repository.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart'
    show ProfileLifecycleMode;
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/export_account_collaborator.dart';
import 'package:lunarlog/ui/components/settings_section.dart';
import 'package:lunarlog/ui/components/destructive_button.dart';
import 'package:lunarlog/ui/settings/clinical_export_tile.dart';
import 'package:lunarlog/ui/settings/clinical_pdf_export_tile.dart';
import 'package:lunarlog/ui/settings/csv_export_tile.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/l10n/profile_erasure_failure_copy.dart';
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
    this.platform,
  });

  /// Injected collaborator for CSV export testing.
  final CsvExportCollaborator? exportCsv;

  /// Issue #472: "Purge imported data" — null (the R26 unconfigured-build
  /// posture, same gate every other network-backed tile in this app uses)
  /// hides the tile entirely.
  final ProfileErasureService? profileErasureService;

  /// Issue #883: the platform the purge dialog filters import sources by
  /// (Apple Health imports are iOS-only, Health Connect is Android-only).
  /// Null means [defaultTargetPlatform]; injectable so tests can pin a
  /// platform without touching the binding.
  final TargetPlatform? platform;

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
    return SettingsSection(
      id: 'your-data',
      title: AppLocalizations.of(context).settingsSectionYourData,
      children: _sectionChildren(context, profiles, signedIn),
    );
  }

  /// The full "Your data" section body: [_exportTile], [_importTile] and
  /// the tiles that follow (Issue #140 review, item 1 — split out of
  /// [build] itself so no single method carries every tile's
  /// conditionals). Issue #226: the heading itself moved up into
  /// [SettingsSection], so this list is body-only.
  List<Widget> _sectionChildren(
    BuildContext context,
    List<Profile> profiles,
    bool signedIn,
  ) {
    return [
      ..._exportTile(context, profiles, signedIn),
      ..._importTile(context),
      CsvExportTile(exportCsv: widget.exportCsv), // Issue #469
      const ClinicalExportTile(), // Issue #157
      const ClinicalPdfExportTile(), // Issue #154
      ..._purgeImportedDataTile(context, profiles), // Issue #472
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
    final l10n = AppLocalizations.of(context);
    return [
      ListTile(
        key: const ValueKey('your-data-export'),
        leading: const Icon(Icons.file_download_outlined),
        title: Text(l10n.yourDataExportTitle),
        subtitle: Text(
          signedIn
              ? l10n.yourDataExportSubtitleSignedIn
              : l10n.yourDataExportSubtitleLocal,
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
    final l10n = AppLocalizations.of(context);
    return [
      ListTile(
        key: const ValueKey('your-data-import'),
        leading: const Icon(Icons.file_upload_outlined),
        title: Text(l10n.yourDataImportTitle),
        subtitle: Text(l10n.yourDataImportSubtitle),
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
    final l10n = AppLocalizations.of(context);
    return [
      ListTile(
        key: const ValueKey('your-data-purge-imported'),
        leading: const Icon(Icons.filter_alt_off_outlined),
        title: Text(l10n.yourDataPurgeTitle),
        subtitle: Text(l10n.yourDataPurgeSubtitle),
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
  /// comment) — an unauthorized attempt surfaces through
  /// [profileErasureFailureCopy] like any other failure. Issue #883: the
  /// service itself now purges locally with or without a session, so a
  /// signed-out operator succeeds rather than collecting a false
  /// primary-guardian error.
  Future<void> _purgeImportedData(List<Profile> profiles) async {
    if (_purging) return;
    final service = widget.profileErasureService;
    if (service == null) return;
    // Captured before the first await (use_build_context_synchronously).
    final l10n = AppLocalizations.of(context);
    final selection = await showDialog<_PurgeSelection>(
      context: context,
      routeSettings: const RouteSettings(name: kRoutePurgeImportedDataDialog),
      builder: (ctx) => _PurgeImportedDataDialog(
        profiles: profiles,
        service: service,
        platform: widget.platform ?? defaultTargetPlatform,
      ),
    );
    if (selection == null || !mounted) return;

    setState(() {
      _purging = true;
      _purgeError = null;
    });
    try {
      await service.purgeImportedData(
        profileId: selection.profileId,
        source: selection.source,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.yourDataPurgedSnack(selection.source.label)),
          ),
        );
      }
    } catch (error) {
      debugPrint('lunarlog your-data: purge failed (${error.runtimeType})');
      if (mounted) {
        setState(() => _purgeError = _purgeErrorMessage(l10n, error));
      }
    } finally {
      if (mounted) setState(() => _purging = false);
    }
  }

  String _purgeErrorMessage(AppLocalizations l10n, Object error) {
    if (error is ProfileErasureFailure) {
      return profileErasureFailureCopy(l10n, error);
    }
    return l10n.profileErasureFailureOther;
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
      final customTagsByProfile = <String, List<CustomTag>>{};
      final guardianNotesByProfile = <String, List<GuardianNote>>{};
      for (final profile in profiles) {
        final snapshot = await snapshotRepo.forProfile(profile.id);
        entriesByProfile[profile.id] = snapshot.entries;
        observationsByProfile[profile.id] = snapshot.observations;
        profileModesByProfile[profile.id] = snapshot.profileMode;
        cycleOverridesByProfile[profile.id] = snapshot.cycleOverrides;
        mergeEventsByProfile[profile.id] = snapshot.mergeEvents;
        customTagsByProfile[profile.id] = snapshot.customTags;
        guardianNotesByProfile[profile.id] = snapshot.guardianNotes;
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
        customTagsByProfile: customTagsByProfile,
        guardianNotesByProfile: guardianNotesByProfile,
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

/// Issue #883: whether [source] can even exist on [platform] — Apple
/// Health imports are iOS-only, Health Connect is Android-only, and the
/// rest are platform-agnostic. Keeps the purge dialog from offering a
/// source the current device can never have produced (it used to list
/// "Health Connect (Android)" on iOS).
bool isPurgeSourceValidOn(
  PurgeableImportSource source,
  TargetPlatform platform,
) {
  switch (source) {
    case PurgeableImportSource.healthkit:
    case PurgeableImportSource.appleHealthObservations:
      return platform == TargetPlatform.iOS;
    case PurgeableImportSource.healthConnect:
      return platform == TargetPlatform.android;
    case PurgeableImportSource.clueImport:
    case PurgeableImportSource.fileImport:
    case PurgeableImportSource.wearable:
      return true;
  }
}

/// "Purge imported data"'s picker (Issue #472): a profile dropdown and a
/// source dropdown, styled destructively since the purge is irreversible
/// from this device's point of view (the underlying import file, if kept,
/// can always re-import). A [StatefulWidget] with its own selection state
/// (the `_EnterCodeDialog`/`_ProfileEditDialog` precedent) rather than
/// closures capturing mutable locals across `showDialog`'s builder, which
/// Flutter may invoke more than once.
///
/// Issue #883: the source list is filtered to the current platform, the
/// default is a source the selected profile actually has rows for (never
/// a no-op "Clue import" default), and a live count preview names exactly
/// how many rows the purge would remove — the best guard against deleting
/// the wrong source. A profile with no imported rows offers no purge at
/// all instead of a silent no-op.
class _PurgeImportedDataDialog extends StatefulWidget {
  const _PurgeImportedDataDialog({
    required this.profiles,
    required this.service,
    required this.platform,
  });

  final List<Profile> profiles;
  final ProfileErasureService service;
  final TargetPlatform platform;

  @override
  State<_PurgeImportedDataDialog> createState() =>
      _PurgeImportedDataDialogState();
}

class _PurgeImportedDataDialogState extends State<_PurgeImportedDataDialog> {
  late String _profileId = widget.profiles.first.id;

  /// Per-source live counts for [_profileId]; null while the local read is
  /// still in flight.
  Map<PurgeableImportSource, int>? _counts;
  bool _loading = true;
  bool _loadFailed = false;

  /// The selected source, or null when no platform-valid source has any
  /// rows (or while loading) — [AlertDialog]'s Purge action is disabled in
  /// both cases.
  PurgeableImportSource? _source;

  List<PurgeableImportSource> get _availableSources => [
        for (final source in PurgeableImportSource.values)
          if (isPurgeSourceValidOn(source, widget.platform)) source,
      ];

  @override
  void initState() {
    super.initState();
    unawaited(_loadCounts(_profileId));
  }

  Future<void> _loadCounts(String profileId) async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _counts = null;
      _source = null;
    });
    try {
      final counts = await widget.service.importedDataCounts(profileId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _counts = counts;
        _source = _defaultSourceFor(counts);
      });
    } catch (error) {
      debugPrint('lunarlog your-data: purge counts failed '
          '(${error.runtimeType})');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  PurgeableImportSource? _defaultSourceFor(
    Map<PurgeableImportSource, int> counts,
  ) {
    for (final source in _availableSources) {
      if ((counts[source] ?? 0) > 0) return source;
    }
    return null;
  }

  bool get _hasAnyRows =>
      _counts != null && _availableSources.any((s) => (_counts![s] ?? 0) > 0);

  int get _selectedCount => _source == null ? 0 : (_counts?[_source] ?? 0);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.yourDataPurgeTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.yourDataPurgeDialogBody),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.yourDataPurgeProfileLabel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            DropdownButton<String>(
              key: const ValueKey('purge-profile-dropdown'),
              value: _profileId,
              isExpanded: true,
              onChanged: _loading
                  ? null
                  : (value) {
                      if (value == null || value == _profileId) return;
                      setState(() => _profileId = value);
                      unawaited(_loadCounts(value));
                    },
              items: [
                for (final profile in widget.profiles)
                  DropdownMenuItem<String>(
                    value: profile.id,
                    child: Text(profile.displayName),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ..._sourceSection(context, l10n),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.yourDataPurgeCancel),
        ),
        DestructiveButton(
          onPressed: _source == null || _selectedCount == 0
              ? null
              : () => Navigator.of(context)
                  .pop(_PurgeSelection(_profileId, _source!)),
          child: Text(l10n.yourDataPurgeConfirm),
        ),
      ],
    );
  }

  List<Widget> _sourceSection(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ];
    }
    if (_loadFailed) {
      return [
        InlineError(
          key: const ValueKey('purge-counts-error'),
          message: l10n.profileErasureFailureOther,
        ),
      ];
    }
    if (!_hasAnyRows) {
      return [
        Text(
          l10n.purgeImportedDataNoRows,
          key: const ValueKey('purge-no-rows'),
        ),
      ];
    }
    final source = _source;
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          l10n.yourDataImportSourceLabel,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DropdownButton<PurgeableImportSource>(
        key: const ValueKey('purge-source-dropdown'),
        value: source,
        isExpanded: true,
        onChanged: (value) =>
            setState(() => _source = value ?? _source),
        items: [
          for (final source in _availableSources)
            DropdownMenuItem<PurgeableImportSource>(
              value: source,
              child: Text(source.label),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (source != null)
        Text(
          l10n.purgeImportedDataPreview(_selectedCount, source.label),
          key: const ValueKey('purge-count-preview'),
        ),
    ];
  }
}
