/// Settings screen for binding "this device's health-store profile" (Issue
/// #153): lists every profile, showing why each ineligible one is refused,
/// lets the operator bind an eligible one behind a confirm dialog naming
/// what binding means, and offers an unbind action once one is bound.
///
/// Live on iOS since issue #193 and on Android since issue #458: binding a
/// profile is the opt-in, and the write path it arms (wired in `app.dart`)
/// is forward-only from the authorization moment (no backfill of days
/// logged before sync was turned on). Issues #217/#458 add the read
/// direction — a user-initiated import from the bound platform's store
/// (Apple Health / Health Connect) that never runs on its own. The copy
/// below documents the one lossy write mapping (`superHeavy` → `heavy`, the
/// same collapse Clue documents for its own Apple Health integration, plus
/// the spotting rule), mirroring Clue's own disclosure. `SettingsScreen`
/// gates this screen off on web and on desktop. The screen itself only ever
/// changes the device-local [SettingsKeys.healthStoreProfileId] setting via
/// [HealthSyncBinding]; unbinding tears the write flow down through the
/// binding stream the write coordinator watches (cursor + native mirror),
/// so no unbind side effects live here.
///
/// `lib/domain/health/health_sync_policy.dart`'s doc comment is the
/// canonical statement of the guard every write entry point must call
/// before this epic may write anything.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../domain/health/health_deviation.dart';
import '../../domain/health/health_import.dart';
import '../../domain/health/health_platform.dart';
import '../../domain/health/health_sync_binding.dart';
import '../../domain/health/health_sync_policy.dart';
import '../../domain/models/profile.dart';
import '../../domain/repositories/profile_guardians_repository.dart'
    show GuardiansForProfile;
import '../../domain/repositories/profiles_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../observability/route_names.dart';

// [GuardiansForProfile] (issue #575: declared once, next to
// ProfileGuardiansRepository, rather than redeclared in every one of its
// four call sites) resolves the guardian rows for one profile, mapped to
// the domain model. Production wiring passes
// `ProfileGuardiansRepository.getForProfile` directly (a plain method
// tear-off satisfies this exactly); this is a bare function type rather
// than the concrete repository so the widget can be tested with a simple
// fake, no database required (R14/R16 — storage types never cross into
// `lib/ui/`; this goes one step further and drops the repository *class*
// dependency too, since nothing here needs anything else it exposes).

/// The human name of [platform]'s health store, used in every import-copy
/// string so the screen names the store the runner actually reads.
String _sourceName(HealthImportPlatform platform) => switch (platform) {
      HealthImportPlatform.appleHealth => 'Apple Health',
      HealthImportPlatform.healthConnect => 'Health Connect',
    };

/// The neutral statement shown when an import read returned nothing usable
/// (Issues #217/#458). Deliberately says neither "nothing was tracked" nor
/// "permission denied": Apple Health never reveals a denied read, and the
/// import summary coalesces Health Connect's own denial signal into the same
/// neutral state, so the two are indistinguishable to the UI and it must not
/// imply it knows which happened.
String healthImportEmptyCopy(HealthImportPlatform platform) =>
    switch (platform) {
      HealthImportPlatform.appleHealth =>
        'Apple Health returned no menstrual-flow data. '
            "Apple Health doesn't tell apps whether read access is allowed, so "
            'this can mean nothing was tracked, or that access is off.',
      HealthImportPlatform.healthConnect =>
        'Health Connect returned no menstrual-flow data. '
            'This can mean nothing was tracked, or that read access is off.',
    };

/// The bind screen's intro copy on a platform whose write direction is
/// wired (iOS).
const String kHealthSyncWriteIntro =
    'Choose the one profile whose data this phone may ever write to its '
    "Health app. Every other profile stays out of this phone's Health app "
    'entirely.';

/// The bind screen's intro copy on a platform where only import is wired
/// (Android, Issue #458) — it must not promise writes that will not happen.
const String kHealthSyncImportIntro =
    'Choose the one profile this phone may import health data into. Every '
    "other profile stays out of this phone's Health app entirely.";

/// The forward-only write explanation (iOS).
const String kHealthSyncWriteForwardOnly =
    'Only days logged after sync is turned on are written — nothing already '
    'in the app is sent on its own. Separately, you can choose to import '
    'menstrual flow from the Health app; nothing is read unless you start '
    'that import yourself.';

/// The symptom and mood write explanation (iOS, Issues #238/#918).
const String kHealthSyncWriteSymptoms =
    'Symptoms you tag — cramps, headache, bloating, and mood — are written to '
    'the Health app as symptom entries. Mood tags are written as \'Mood Changes\' '
    'without saying which mood.';

/// The import-only explanation (Android, Issue #458).
const String kHealthSyncImportOnly =
    'Only menstrual flow and spotting written by other apps appear here, and '
    'only when you start an import yourself — nothing is read or written '
    'automatically.';

class HealthSyncScreen extends StatefulWidget {
  const HealthSyncScreen({
    super.key,
    required this.profilesRepository,
    required this.guardiansForProfile,
    required this.binding,
    required this.signedInUserId,
    this.importer,
    this.deviationInsights,
    this.permissionProbe,
    this.writeEnabled = true,
  });

  final ProfilesRepository profilesRepository;
  final GuardiansForProfile guardiansForProfile;
  final HealthSyncBinding binding;

  /// The OS-permission seam (Issue #959). Null on a build with no native
  /// permission surface (web/desktop, or a harness that does not wire one),
  /// in which case no status line or settings link is rendered. The screen
  /// reads only [HealthPermissionProbe] — never the write port — so it can
  /// display the OS consent without gaining the ability to write.
  final HealthPermissionProbe? permissionProbe;

  /// The user-initiated import seam (Issues #217/#458). Null on a build
  /// where the import runner is absent (tests, an unconfigured build, a
  /// platform with no health store), in which case the import tile is
  /// hidden entirely.
  final HealthImportRunner? importer;

  /// Issue #799: the device-local deviation insight seam. When wired, a
  /// successful import also refreshes the bound profile's "Apple Health
  /// noticed…" snapshot, which the overview renders; null (tests, an
  /// unconfigured build, a platform with no health store) simply skips it.
  final HealthDeviationInsights? deviationInsights;

  /// Whether the write direction is wired on this platform. False on
  /// Android as of Issue #458, where only the read/import runner is wired
  /// (writes stay behind #202's device checklist), so the write-specific
  /// copy is replaced with import-only copy rather than claiming writes
  /// that will not happen.
  final bool writeEnabled;

  /// The signed-in account's user id, or null when signed out — passed in
  /// rather than read from an `AuthController` here so this widget stays
  /// testable without standing up auth wiring (mirrors
  /// `ManageGuardiansScreen.currentUserId`).
  final String? signedInUserId;

  @override
  State<HealthSyncScreen> createState() => _HealthSyncScreenState();
}

class _HealthSyncScreenState extends State<HealthSyncScreen> {
  bool _loading = true;
  bool _loadFailed = false;
  String? _boundProfileId;
  List<Profile> _profiles = const [];
  Map<String, String?> _ownerUserIdByProfile = const {};

  /// Issues #217/#458 import state: whether a pass is running, the last
  /// summary, and whether the pass threw (an unexpected storage error — the
  /// runner itself reports expected failures as a [HealthImportSummary]).
  bool _importing = false;
  bool _importFailed = false;
  HealthImportSummary? _importSummary;

  /// Issue #992: the running sample count of a full-history pass, so a long
  /// import shows progress rather than a bare spinner. Null until the first
  /// page reports.
  HealthImportProgress? _importProgress;

  /// Issue #1017: marks the result block so a finished pass can scroll it
  /// into view — the import tile sits at the bottom of the page, so the
  /// result otherwise renders below the fold and the tap looks like a no-op.
  final GlobalKey _resultKey = GlobalKey();

  /// Issue #959: the OS permission state read from [permissionProbe] — null
  /// when no probe is wired (nothing is rendered then). Re-read on every
  /// load and after each user-initiated import, so a revocation made in OS
  /// settings while the app was backgrounded is reflected when this screen
  /// is (re-)opened or used.
  HealthPermissionStatus? _permissionStatus;

  /// The platform the runner reads — drives the copy below. Defaults to
  /// Apple Health only for the (never-shown) case where the importer is
  /// absent; every rendered path is guarded by a non-null importer.
  HealthImportPlatform get _importPlatform =>
      widget.importer?.platform ?? HealthImportPlatform.appleHealth;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Loads the bound profile id, every non-archived profile, and each
  /// one's resolved owner. A throwing repository (or guardian lookup)
  /// used to leave [_loading] `true` forever, spinning indefinitely
  /// (review fix) — `catchError` guarantees the spinner always resolves,
  /// showing an error state instead.
  Future<void> _load() => _doLoad().catchError((Object _) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      });

  Future<void> _doLoad() async {
    final bound = await widget.binding.boundProfileId();
    final allProfiles = await widget.profilesRepository.list();
    // Archived profiles are excluded from the picker (review fix): an
    // archived profile is no longer in active use and should not be
    // offered as a bindable health-store profile.
    final profiles = [
      for (final profile in allProfiles)
        if (profile.archivedAt == null) profile,
    ];
    final owners = <String, String?>{};
    for (final profile in profiles) {
      final guardians = await widget.guardiansForProfile(profile.id);
      owners[profile.id] = ownerUserIdFor(guardians);
    }
    final permissionStatus = await _readPermissionStatus();
    if (!mounted) return;
    setState(() {
      _boundProfileId = bound;
      _profiles = profiles;
      _ownerUserIdByProfile = owners;
      _permissionStatus = permissionStatus;
      _loading = false;
      _loadFailed = false;
    });
  }

  /// Issue #959: reads the OS permission state through the probe, best
  /// effort — a probe that throws (or is absent) must not fail the load or
  /// crash the screen. Absent is null (render nothing); a throw is
  /// [HealthPermissionStatus.unavailable] (we genuinely cannot tell).
  Future<HealthPermissionStatus?> _readPermissionStatus() async {
    final probe = widget.permissionProbe;
    if (probe == null) return null;
    try {
      return await probe.permissionStatus();
    } catch (_) {
      return HealthPermissionStatus.unavailable;
    }
  }

  /// Issue #959: the status line copy. The source name is the store this
  /// platform actually uses. Note there is deliberately no read dimension:
  /// HealthKit's read authorization is opaque, so the line never claims to
  /// know (or denies) read access — it reports the write/access state only.
  String _permissionStatusText(
    AppLocalizations l10n,
    HealthPermissionStatus status,
  ) {
    final source = _sourceName(_importPlatform);
    return switch (status) {
      HealthPermissionStatus.granted =>
        l10n.healthSyncPermissionGranted(source),
      HealthPermissionStatus.notAsked =>
        l10n.healthSyncPermissionNotAsked(source),
      HealthPermissionStatus.denied =>
        l10n.healthSyncPermissionDenied(source),
      HealthPermissionStatus.unavailable =>
        l10n.healthSyncPermissionUnavailable(source),
    };
  }

  /// The status line plus — only in the denied state — the platform
  /// settings deep link (Issue #959). Null when no probe is wired, so an
  /// unconfigured build shows exactly what it showed before.
  Widget? _permissionStatusSection(AppLocalizations l10n) {
    final status = _permissionStatus;
    if (status == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          key: const ValueKey('health-sync-permission-status'),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(_permissionStatusText(l10n, status)),
        ),
        // The settings link is offered only when it is actionable: a denied
        // permission is the one state the operator can fix in OS settings.
        if (status == HealthPermissionStatus.denied)
          ListTile(
            key: const ValueKey('health-sync-open-settings'),
            leading: const Icon(Icons.settings_outlined),
            title: Text(l10n.healthSyncPermissionOpenSettings),
            onTap: () => widget.permissionProbe?.openPermissionSettings(),
          ),
      ],
    );
  }

  /// Whether binding [profile] right now would be allowed — evaluated
  /// against the *proposed* binding, so only the minor and ownership
  /// checks can produce a deny here; matches what [HealthSyncBinding.bind]
  /// itself checks. `minorBindingAllowed` is always
  /// `AppConfig.healthSyncMinorBindingAllowed` — the single source of
  /// truth [HealthSyncBinding] documents, never a value this screen
  /// invents itself.
  HealthSyncCheck _eligibility(Profile profile) => widget.binding.canBind(
        profile: profile,
        signedInUserId: widget.signedInUserId,
        ownerUserId: _ownerUserIdByProfile[profile.id],
        minorBindingAllowed: AppConfig.healthSyncMinorBindingAllowed,
      );

  /// [check]'s user-facing deny reason, or the empty string for a non-deny
  /// result. [HealthSyncCheck.notOwner] reads differently depending on
  /// *why* the account check failed (review fix, tightened by Issue #882
  /// review round 2): a signed-out caller gets an actionable "sign in and
  /// sync" prompt, distinct from an actual non-owner being told they
  /// simply aren't this profile's owner. Since #882 [notOwner] is only
  /// reachable when an owner actually resolved (a profile with no
  /// `ownerUserId` is allowed), so the two cases are exactly "nobody is
  /// signed in to prove ownership" and "a different account owns it".
  String _denyReasonText(HealthSyncCheck check) =>
      switch (check) {
        HealthSyncCheck.minorRequiresOwnershipTransfer =>
          'Minor profiles sync on the same terms as any other profile. '
              'This build has minor health sync turned off.',
        HealthSyncCheck.notOwner => widget.signedInUserId == null
            ? 'Sign in and sync once so this device can confirm you own '
                'this profile.'
            : "You are not this profile's owner — only its accepted "
                'primary guardian can bind health sync.',
        HealthSyncCheck.noBinding ||
        HealthSyncCheck.profileNotBound ||
        HealthSyncCheck.allowed =>
          '',
      };

  Future<void> _tapProfile(Profile profile) async {
    if (!_eligibility(profile).isAllowed) return;
    final confirmed = await _confirmBind(profile);
    if (!confirmed || !mounted) return;
    final result = await widget.binding.bind(
      profile: profile,
      signedInUserId: widget.signedInUserId,
      ownerUserId: _ownerUserIdByProfile[profile.id],
      minorBindingAllowed: AppConfig.healthSyncMinorBindingAllowed,
    );
    if (!mounted) return;
    if (!result.isAllowed) {
      // Surfaced rather than discarded (review fix): a deny here means
      // eligibility changed out from under the operator between this
      // screen's last load and the confirm dialog closing (e.g. the
      // binding on this device, or this profile's ownership, changed on
      // another device mid-flow).
      final reason = _denyReasonText(result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reason.isEmpty
                ? "Couldn't sync ${profile.displayName} — try again."
                : reason,
          ),
        ),
      );
    }
    await _load();
  }

  Future<bool> _confirmBind(Profile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: kRouteHealthSyncBindDialog),
      builder: (dialogContext) => AlertDialog(
        title: Text('Sync ${profile.displayName} to this phone?'),
        content: Text(
          widget.writeEnabled
              ? "Only ${profile.displayName}'s data will ever be written to "
                  "this phone's Health app. This phone can sync one profile at "
                  'a time — choosing a different profile later replaces this '
                  'one.'
              : "Only ${profile.displayName}'s data will ever be imported "
                  "from this phone's Health app. This phone can sync one "
                  'profile at a time — choosing a different profile later '
                  'replaces this one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('health-sync-confirm-bind'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              AppLocalizations.of(dialogContext).healthSyncConfirmSyncAction,
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Confirms before tearing the binding down (Issue #893). Unbinding is the
  /// reverse of a decision the app treats as consequential — binding is
  /// guarded by this same confirm-plus-system-sheet shape — so it must not be
  /// a single bare tap on a tile sitting directly under Import. Confirming
  /// also drops the last import result, so no summary outlives the binding
  /// that produced it.
  Future<void> _unbind() async {
    final confirmed = await _confirmUnbind(_boundProfileName());
    if (!confirmed || !mounted) return;
    await widget.binding.unbind();
    if (!mounted) return;
    setState(() {
      _importSummary = null;
      _importFailed = false;
    });
    await _load();
  }

  /// The bound profile's display name, or a neutral stand-in when the bound
  /// id no longer resolves in this screen's (non-archived) profile list.
  String _boundProfileName() {
    for (final profile in _profiles) {
      if (profile.id == _boundProfileId) return profile.displayName;
    }
    return 'this profile';
  }

  /// The unbind confirmation (Issue #893), deliberately mirroring
  /// [_confirmBind]'s shape, route name and voice: it names the profile and
  /// states what stops happening, and nothing already logged is deleted.
  Future<bool> _confirmUnbind(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: kRouteHealthSyncUnbindDialog),
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.healthSyncUnbindDialogTitle(name)),
          content: Text(
            widget.writeEnabled
                ? l10n.healthSyncUnbindDialogWriteBody(name)
                : l10n.healthSyncUnbindDialogImportBody(name),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.healthSyncUnbindCancel),
            ),
            FilledButton(
              key: const ValueKey('health-sync-confirm-unbind'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.healthSyncUnbindConfirm),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  /// Runs one user-initiated import (Issue #217). The runner owns the guard,
  /// the full-history paged read, and the merge; this only sequences,
  /// renders progress, and renders the summary. An unexpected throw (a
  /// storage error the runner does not classify) becomes the generic
  /// failure line rather than a crash.
  Future<void> _runImport() async {
    final importer = widget.importer;
    if (importer == null || _importing) return;
    setState(() {
      _importing = true;
      _importFailed = false;
      _importSummary = null;
      _importProgress = null;
    });
    try {
      final summary = await importer.importNow(
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _importProgress = progress);
        },
      );
      // Issue #799: after a pass, refresh the bound profile's computed
      // cycle-deviation snapshot for the overview card. Best-effort and
      // read-only — a failure here must never turn a successful import into
      // a reported failure, so it is swallowed and the pass result stands.
      try {
        await widget.deviationInsights?.refresh();
      } catch (_) {
        // Ignored: the snapshot is a display cache, not part of the import.
      }
      final permissionStatus = await _readPermissionStatus();
      if (!mounted) return;
      setState(() {
        _importing = false;
        _importSummary = summary;
        _importProgress = null;
        // Issue #959: re-read the OS permission after the pass, so an
        // import that hit a revoked permission updates the status line
        // (and offers the settings link) without leaving the screen.
        _permissionStatus = permissionStatus;
      });
      _announceResult(summary);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _importProgress = null;
        _importFailed = true;
      });
      _revealResult();
    }
  }

  /// Issue #1017: bring the result into view and, for a completed pass that
  /// read something, announce its headline in a SnackBar so the result is
  /// impossible to miss. A blocked/empty pass has no headline to announce;
  /// scrolling alone reveals its copy. Split out of [_runImport] so that
  /// method stays under the CRAP threshold.
  void _announceResult(HealthImportSummary summary) {
    _revealResult();
    if (summary.isBlocked || summary.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _completedSummaryHeadline(AppLocalizations.of(context), summary),
        ),
      ),
    );
  }

  /// The copy for a pass that ended before reading — a guard refusal or a
  /// platform outcome. A [HealthPlatformPermissionDenied] deliberately
  /// renders the same neutral ambiguity copy as an empty result, since the
  /// import summary never distinguishes the two.
  String _blockedImportCopy(HealthPlatformResult blocked) {
    final source = _sourceName(_importPlatform);
    return switch (blocked) {
      HealthPlatformRefused() =>
        "This profile can't import from $source right now.",
      HealthPlatformUnavailable() => "$source isn't available on this device.",
      HealthPlatformPermissionDenied() => healthImportEmptyCopy(_importPlatform),
      HealthPlatformFailed() =>
        "Couldn't finish the import. Please try again.",
      HealthPlatformAllowed() => healthImportEmptyCopy(_importPlatform),
    };
  }

  /// The completion headline for a pass that actually read something. Issue
  /// #1017: the headline alone states the imported and skipped counts — the
  /// pre-#992 "Updated N days" and "N days already matched" lines restated
  /// them with different verbs, so they are gone. When nothing was imported,
  /// say so plainly instead of "Imported 0 days".
  String _completedSummaryHeadline(
    AppLocalizations l10n,
    HealthImportSummary summary,
  ) {
    if (summary.importedDays == 0 && summary.spottingDaysWritten == 0) {
      return l10n.healthSyncImportSummaryNothingNew(
        summary.skippedAlreadyLoggedDays,
      );
    }
    return l10n.healthSyncImportSummaryHeadline(
      summary.importedDays,
      summary.skippedAlreadyLoggedDays,
    );
  }

  /// The positive result lines for a pass that read samples. Empty when
  /// every sample was a no-op. Issue #902: rows placed from this phone's own
  /// zone (the source recorded none) get their own line — never the "Skipped"
  /// wording — and the skip line is reserved for samples that truly could not
  /// be placed. Issue #1017: that zone provenance is shown only when some
  /// samples were actually skipped for lack of a zone, so a clean run does
  /// not carry a line that reads as a warning about nothing.
  List<String> _importResultLines(
    AppLocalizations l10n,
    HealthImportSummary summary,
  ) {
    final source = _sourceName(_importPlatform);
    return [
      // Issue #992/#1017: one completion headline, then only the detail
      // lines that add information the headline does not already carry.
      _completedSummaryHeadline(l10n, summary),
      if (summary.spottingDaysWritten > 0)
        l10n.healthSyncImportAddedSpotting(summary.spottingDaysWritten, source),
      if (summary.daysKeptManual > 0)
        l10n.healthSyncImportKeptManual(summary.daysKeptManual),
      if (summary.samplesWithoutZone > 0) ...[
        if (summary.samplesFromDeviceZone > 0)
          l10n.healthSyncImportPlacedDeviceZone(summary.samplesFromDeviceZone),
        l10n.healthSyncImportSkippedNoZone(summary.samplesWithoutZone),
      ],
      if (summary.samplesUnsupported > 0)
        l10n.healthSyncImportSkippedUnsupported(summary.samplesUnsupported),
    ];
  }

  /// Issue #1017: scrolls the result block into view after a pass finishes,
  /// so the tap that started it cannot look like it did nothing. Deferred to
  /// a post-frame callback because the result is not in the tree until the
  /// `setState` that precedes this has built.
  void _revealResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final resultContext = _resultKey.currentContext;
      if (resultContext == null) return;
      unawaited(
        Scrollable.ensureVisible(
          resultContext,
          duration: const Duration(milliseconds: 300),
          alignment: 0.5,
        ),
      );
    });
  }

  /// The result block: progress while running, then either the failure
  /// line, the blocked line, the neutral empty copy, or the positive lines.
  Widget _importResult() {
    final l10n = AppLocalizations.of(context);
    final children = <Widget>[];
    if (_importing) {
      children.add(Text(_importingCopy(l10n)));
    } else if (_importFailed) {
      children.add(
        const Text("Couldn't finish the import. Please try again."),
      );
    } else if (_importSummary != null) {
      children.addAll(_importSummaryChildren(l10n, _importSummary!));
    }
    return Padding(
      key: const ValueKey('health-sync-import-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        key: _resultKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  /// The progress line while a pass runs (Issue #992): the running sample
  /// count once the first page has reported, otherwise the bare store name.
  String _importingCopy(AppLocalizations l10n) {
    final progress = _importProgress;
    if (progress == null) {
      return 'Importing from ${_sourceName(_importPlatform)}…';
    }
    return l10n.healthSyncImportProgress(progress.samplesRead);
  }

  /// The lines for a finished pass: the blocked line, the neutral empty
  /// copy, or the stopped-early note plus the positive result lines.
  List<Widget> _importSummaryChildren(
    AppLocalizations l10n,
    HealthImportSummary summary,
  ) {
    if (summary.isBlocked) {
      return [Text(_blockedImportCopy(summary.blocked!))];
    }
    if (summary.isEmpty) {
      return [Text(healthImportEmptyCopy(_importPlatform))];
    }
    return [
      // Issue #992: a pass stopped by the page cap or a repeated cursor says
      // so plainly rather than pretending it finished.
      if (summary.pageLimitReached || summary.repeatedCursor)
        Text(l10n.healthSyncImportStoppedEarly),
      for (final line in _importResultLines(l10n, summary)) Text(line),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          key: ValueKey('health-sync-loading'),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_loadFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Health app sync')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  key: ValueKey('health-sync-load-error'),
                  "Couldn't load profiles for health sync.",
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    setState(() => _loading = true);
                    unawaited(_load());
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final permissionSection =
        _permissionStatusSection(AppLocalizations.of(context));
    return Scaffold(
      appBar: AppBar(title: const Text('Health app sync')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.writeEnabled
                  ? kHealthSyncWriteIntro
                  : kHealthSyncImportIntro,
            ),
          ),
          // Issue #959: the OS permission state, shown per platform, with
          // the settings deep link only when it is denied.
          ?permissionSection,
          if (widget.writeEnabled) ...[
            // Issue #193: document the write surface the way Clue documents
            // its own — one-way, forward-only, and the one lossy mapping
            // (superHeavy collapses to Apple's `heavy`; spotting follows the
            // A3-4 in/outside-episode rule). Issue #217 adds the read
            // direction: user-initiated import only, and the original
            // "nothing is ever read back" claim is rewritten to say so.
            const Padding(
              key: ValueKey('health-sync-forward-only-copy'),
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(kHealthSyncWriteForwardOnly),
            ),
            const Padding(
              key: ValueKey('health-sync-flow-collapse-copy'),
              padding: EdgeInsets.all(16),
              child: Text(
                'Super heavy days are written to the Health app as Heavy. '
                'Spotting logged inside a period is written as Light '
                'bleeding; spotting between periods is written as '
                'intermenstrual bleeding.',
              ),
            ),
            // Issue #238 / #918: disclosure of symptom and mood writes.
            const Padding(
              key: ValueKey('health-sync-symptoms-copy'),
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(kHealthSyncWriteSymptoms),
            ),
            // Issue #186 (AC7): what happens on revocation/unmapping. Stopping
            // sync or revoking this phone's Health app permission never deletes
            // what was already written — the samples stay in the Health app,
            // which may consider them theirs.
            const Padding(
              key: ValueKey('health-sync-revocation-copy'),
              padding: EdgeInsets.all(16),
              child: Text(
                'Turning sync off, or later revoking this phone\'s Health app '
                'permission, leaves everything already written in the Health '
                'app in place. To remove it, delete it in the Health app '
                'itself.',
              ),
            ),
          ] else ...[
            // Issue #458: Android wires only the import direction, so the
            // write-specific copy above is replaced rather than left to
            // promise writes that never happen.
            const Padding(
              key: ValueKey('health-sync-import-only-copy'),
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(kHealthSyncImportOnly),
            ),
            // Issue #238: Health Connect has no symptom category types, so
            // symptom tags are never exported on Android. State the
            // permanent platform limitation rather than let an Android user
            // see a silent difference.
            Padding(
              key: const ValueKey('health-sync-symptoms-android-limitation'),
              padding: const EdgeInsets.all(16),
              child: Text(
                AppLocalizations.of(context)
                    .settingsHealthSyncSymptomsAndroidLimitation,
              ),
            ),
          ],
          // Issue #992: the scope decision, stated plainly. Reads are
          // full-history now; background sync (READ_HEALTH_DATA_IN_BACKGROUND)
          // remains deliberately deferred.
          Padding(
            key: const ValueKey('health-sync-full-history-copy'),
            padding: const EdgeInsets.all(16),
            child: Text(
              AppLocalizations.of(context).healthSyncFullHistoryNote,
            ),
          ),
          for (final profile in _profiles) _profileTile(profile),
          // Issues #217/#458: the import action appears only once a profile
          // is bound — the import writes into that profile and no other.
          if (_boundProfileId != null && widget.importer != null)
            ListTile(
              key: const ValueKey('health-sync-import-tile'),
              leading: const Icon(Icons.download_outlined),
              title: Text('Import from ${_sourceName(_importPlatform)}'),
              subtitle: Text(
                AppLocalizations.of(context).healthSyncImportTileSubtitle,
              ),
              trailing: _importing
                  ? const SizedBox(
                      key: ValueKey('health-sync-import-progress'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              enabled: !_importing,
              onTap: _runImport,
            ),
          if (_importing || _importFailed || _importSummary != null)
            _importResult(),
          if (_boundProfileId != null)
            ListTile(
              key: const ValueKey('health-sync-unbind-tile'),
              leading: const Icon(Icons.link_off),
              title: const Text('Stop syncing to this phone'),
              onTap: _unbind,
            ),
        ],
      ),
    );
  }

  Widget _profileTile(Profile profile) {
    final check = _eligibility(profile);
    final isBound = profile.id == _boundProfileId;
    return ListTile(
      key: ValueKey('health-sync-profile-${profile.id}'),
      title: Text(profile.displayName),
      subtitle:
          check.isAllowed ? null : Text(_denyReasonText(check)),
      trailing: isBound
          ? const Icon(Icons.check_circle, key: ValueKey('health-sync-bound-check'))
          : null,
      enabled: check.isAllowed,
      onTap: check.isAllowed ? () => _tapProfile(profile) : null,
    );
  }
}
