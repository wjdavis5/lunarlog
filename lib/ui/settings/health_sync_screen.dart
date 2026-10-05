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
/// the spotting rule), mirroring Clue's own disclosure.
///
/// **The write copy is per store (issue #1478).** Android writes to Health
/// Connect too, and what is written there differs from Apple Health: no
/// symptom or mood entries (Health Connect has no such types), and a period
/// interval record iOS does not have. So each write paragraph has an Apple
/// Health string and a Health Connect string, chosen by the store this
/// platform uses — never by "does this platform write", which used to
/// stand in for "is this an iPhone" and put "this phone's Health app" on
/// Android the moment its writes were switched on. `SettingsScreen` gates
/// this screen off on web and on desktop. The screen itself only ever
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
import '../../domain/health/health_access_state.dart';
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
/// Arb-backed since issue #1004, tranche 5 (`healthSyncSourceName*`).
String _sourceName(AppLocalizations l10n, HealthImportPlatform platform) =>
    switch (platform) {
      HealthImportPlatform.appleHealth => l10n.healthSyncSourceNameAppleHealth,
      HealthImportPlatform.healthConnect =>
        l10n.healthSyncSourceNameHealthConnect,
    };

/// What the permission probe says: the status line's state and, where the
/// store discloses it, the read-side answer on its own (Issue #1523).
typedef _Access = ({HealthAccessState? state, HealthPermissionStatus? read});

/// The human name of [platform]'s health store for titles and headings.
/// Arb-backed since issue #1004, tranche 5 (`healthSyncSourceTitle*`).
String _sourceTitle(AppLocalizations l10n, HealthImportPlatform platform) =>
    switch (platform) {
      HealthImportPlatform.appleHealth => l10n.healthSyncSourceTitleAppleHealth,
      HealthImportPlatform.healthConnect =>
        l10n.healthSyncSourceTitleHealthConnect,
    };

/// The unavailable copy for [platform]'s health store when the device
/// cannot run it. Arb-backed since issue #1004, tranche 5.
String _sourceUnavailableCopy(AppLocalizations l10n, HealthImportPlatform platform) =>
    switch (platform) {
      HealthImportPlatform.appleHealth =>
        l10n.healthSyncUnavailableAppleHealth,
      HealthImportPlatform.healthConnect =>
        l10n.healthSyncUnavailableHealthConnect,
    };

/// The neutral statement shown when an import read returned nothing usable
/// (Issues #217/#458). Deliberately says neither "nothing was tracked" nor
/// "permission denied": Apple Health never reveals a denied read, and the
/// import summary coalesces Health Connect's own denial signal into the same
/// neutral state, so the two are indistinguishable to the UI and it must not
/// imply it knows which happened.
String healthImportEmptyCopy(AppLocalizations l10n, HealthImportPlatform platform) =>
    switch (platform) {
      HealthImportPlatform.appleHealth =>
        l10n.healthSyncImportEmptyAppleHealth,
      HealthImportPlatform.healthConnect =>
        l10n.healthSyncImportEmptyHealthConnect,
    };

// The bind-screen intros, the forward-only/symptom/import-only
// explanations, and the deny/blocked copy are arb-backed since issue
// #1004, tranche 5 (`healthSync*` keys) — the consts this file used to
// carry are gone.

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
    this.storePlatform,
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

  /// Whether the write direction is wired on this platform — production
  /// passes `AppConfig.healthSyncWritesOn(defaultTargetPlatform)`, the same
  /// answer the composition root builds the write coordinator from (issue
  /// #1478). When false the write copy is replaced with import-only copy
  /// rather than claiming writes that will not happen.
  final bool writeEnabled;

  /// The OS health store this platform uses, which decides whose name and
  /// whose write copy the screen shows (issue #1478). Null falls back to
  /// the importer's own platform, and without an importer to the pre-#1478
  /// guess (Apple Health when writes are on, Health Connect when not) so a
  /// harness that passes neither renders what it always did.
  final HealthImportPlatform? storePlatform;

  /// The signed-in account's user id, or null when signed out — passed in
  /// rather than read from an `AuthController` here so this widget stays
  /// testable without standing up auth wiring (mirrors
  /// `ManageGuardiansScreen.currentUserId`).
  final String? signedInUserId;

  @override
  State<HealthSyncScreen> createState() => _HealthSyncScreenState();
}

class _HealthSyncScreenState extends State<HealthSyncScreen>
    with WidgetsBindingObserver {
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
  /// is (re-)opened or used. Since Issue #1515 it is the state of both
  /// directions where the store discloses read access, and the write state
  /// alone where it does not (see [_readAccessState]).
  HealthAccessState? _accessState;

  /// The read-side answer behind [_accessState] (Issue #1523): null where
  /// the store does not disclose read access (an iPhone) or no probe is
  /// wired. Kept so the line for an import that brought nothing back can
  /// leave out "or read access is off" when reading is known to be on.
  HealthPermissionStatus? _readStatus;

  /// The store this screen is about — drives every store name and the
  /// write copy below. See [HealthSyncScreen.storePlatform] for the order.
  HealthImportPlatform get _importPlatform {
    final store = widget.storePlatform ?? widget.importer?.platform;
    if (store != null) return store;
    return widget.writeEnabled
        ? HealthImportPlatform.appleHealth
        : HealthImportPlatform.healthConnect;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Issue #1478: the OS permission is decided on screens this one cannot
  /// see — the health store's own permission sheet, which the write path
  /// raises a moment after a profile is bound here, and the store's
  /// settings. Coming back from either is when the status line may have
  /// gone stale, so it is read again; before this it kept saying "not yet
  /// asked" after the person had just answered.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_refreshPermissionStatus());
  }

  Future<void> _refreshPermissionStatus() async {
    if (_loading) return;
    final access = await _readAccess();
    if (!mounted || _sameAccess(access)) return;
    setState(() => _setAccess(access));
  }

  bool _sameAccess(_Access access) =>
      access.state == _accessState && access.read == _readStatus;

  /// Stores a fresh probe answer. Call inside `setState`.
  void _setAccess(_Access access) {
    _accessState = access.state;
    _readStatus = access.read;
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
    final access = await _readAccess();
    if (!mounted) return;
    setState(() {
      _boundProfileId = bound;
      _profiles = profiles;
      _ownerUserIdByProfile = owners;
      _setAccess(access);
      _loading = false;
      _loadFailed = false;
    });
  }

  /// Issue #959: reads the OS permission state through the probe, best
  /// effort — a probe that throws (or is absent) must not fail the load or
  /// crash the screen. Absent is null (render nothing); a throw is
  /// [HealthAccessState.unavailable] (we genuinely cannot tell).
  ///
  /// Issue #1515: the write answer and, where the store discloses it, the
  /// read answer, folded into the one state the line shows by
  /// [healthAccessState]. The read answer rides along ([_Access.read]) for
  /// the import result line (Issue #1523).
  Future<_Access> _readAccess() async {
    final probe = widget.permissionProbe;
    if (probe == null) return (state: null, read: null);
    try {
      final write = await probe.permissionStatus();
      final read = await _readSideStatus(probe);
      return (state: healthAccessState(write: write, read: read), read: read);
    } catch (_) {
      return (state: HealthAccessState.unavailable, read: null);
    }
  }

  /// The read-side answer, or null where the store does not disclose read
  /// access (Issue #1515). Decided on the platform fact
  /// [HealthPermissionProbe.readAccessDisclosed], never by comparing the two
  /// answers: on an iPhone the question is not asked at all, so nothing the
  /// probe could answer there can put "reading only" on the line. A read
  /// probe that throws is "cannot tell", which leaves the line as the write
  /// answer alone.
  Future<HealthPermissionStatus?> _readSideStatus(
    HealthPermissionProbe probe,
  ) async {
    if (!probe.readAccessDisclosed) return null;
    try {
      return await probe.importPermissionStatus();
    } catch (_) {
      return HealthPermissionStatus.unavailable;
    }
  }

  /// Issue #959: the status line copy. The source name is the store this
  /// platform actually uses, in its sentence-initial form ([_sourceTitle]) —
  /// every status string opens with it, so the mid-sentence [_sourceName]
  /// would leave iOS reading "the Health app access: …" (Issue #1053).
  ///
  /// On an iPhone there is deliberately no read dimension: HealthKit's read
  /// authorization is opaque, so the line never claims to know (or denies)
  /// read access — it reports the write state only. On Android, Health
  /// Connect says which reads are granted, so the line tells the two
  /// directions apart (Issue #1515): someone who allowed reading and not
  /// writing is told exactly that, not "denied".
  String _permissionStatusText(AppLocalizations l10n, HealthAccessState state) {
    final source = _sourceTitle(l10n, _importPlatform);
    return switch (state) {
      HealthAccessState.granted => l10n.healthSyncPermissionGranted(source),
      HealthAccessState.notAsked => l10n.healthSyncPermissionNotAsked(source),
      HealthAccessState.denied => l10n.healthSyncPermissionDenied(source),
      HealthAccessState.unavailable =>
        l10n.healthSyncPermissionUnavailable(source),
      HealthAccessState.readingOnly =>
        l10n.healthSyncPermissionReadingOnly(source),
      HealthAccessState.writingOnly =>
        l10n.healthSyncPermissionWritingOnly(source),
    };
  }

  /// The status line plus — in the states the platform's settings screen is
  /// the way out of — the settings deep link (Issue #959). Null when no
  /// probe is wired, so an unconfigured build shows exactly what it showed
  /// before.
  Widget? _permissionStatusSection(AppLocalizations l10n) {
    final state = _accessState;
    if (state == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          key: const ValueKey('health-sync-permission-status'),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(_permissionStatusText(l10n, state)),
        ),
        // The settings link is offered only when it is actionable: a denied
        // permission, or (Issue #1515) one direction left off, is what the
        // operator can change in the health store's own settings.
        if (state.changedInSettings)
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
  String _denyReasonText(AppLocalizations l10n, HealthSyncCheck check) =>
      switch (check) {
        HealthSyncCheck.minorRequiresOwnershipTransfer =>
          l10n.healthSyncDenyMinorOff,
        HealthSyncCheck.notOwner => widget.signedInUserId == null
            ? l10n.healthSyncDenyNotOwnerSignedOut
            : l10n.healthSyncDenyNotOwner,
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
      final reason = _denyReasonText(AppLocalizations.of(context), result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reason.isEmpty
                ? AppLocalizations.of(context)
                    .healthSyncSyncFailed(profile.displayName)
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
        title: Text(
          AppLocalizations.of(dialogContext)
              .healthSyncBindTitle(profile.displayName),
        ),
        content: Text(
          widget.writeEnabled
              ? AppLocalizations.of(dialogContext).healthSyncBindWriteBody(
                  profile.displayName,
                  _sourceName(
                    AppLocalizations.of(dialogContext),
                    _importPlatform,
                  ),
                )
              : AppLocalizations.of(dialogContext).healthSyncBindImportBody(
                  profile.displayName,
                  _sourceName(
                    AppLocalizations.of(dialogContext),
                    _importPlatform,
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(dialogContext).healthSyncBindCancel),
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
    final confirmed = await _confirmUnbind(
      _boundProfileName(AppLocalizations.of(context)),
    );
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
  String _boundProfileName(AppLocalizations l10n) {
    for (final profile in _profiles) {
      if (profile.id == _boundProfileId) return profile.displayName;
    }
    return l10n.healthSyncUnboundProfileName;
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
        final source = _sourceName(l10n, _importPlatform);
        return AlertDialog(
          title: Text(l10n.healthSyncUnbindDialogTitle(name)),
          content: Text(
            widget.writeEnabled
                ? l10n.healthSyncUnbindDialogWriteBody(name, source)
                : l10n.healthSyncUnbindDialogImportBody(name, source),
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
      final access = await _readAccess();
      if (!mounted) return;
      setState(() {
        _importing = false;
        _importSummary = summary;
        _importProgress = null;
        // Issue #959: re-read the OS permission after the pass, so an
        // import that hit a revoked permission updates the status line
        // (and offers the settings link) without leaving the screen.
        _setAccess(access);
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
  String _blockedImportCopy(AppLocalizations l10n, HealthPlatformResult blocked) {
    final source = _sourceName(l10n, _importPlatform);
    return switch (blocked) {
      HealthPlatformRefused() =>
        l10n.healthSyncImportBlockedRefused(source),
      HealthPlatformUnavailable() =>
        _sourceUnavailableCopy(l10n, _importPlatform),
      HealthPlatformPermissionDenied() =>
        healthImportEmptyCopy(l10n, _importPlatform),
      HealthPlatformFailed() => l10n.healthSyncImportBlockedFailed,
      HealthPlatformAllowed() => healthImportEmptyCopy(l10n, _importPlatform),
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
    final source = _sourceName(l10n, _importPlatform);
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
        Text(l10n.healthSyncImportFailed),
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
      return l10n.healthSyncImporting(_sourceName(l10n, _importPlatform));
    }
    return l10n.healthSyncImportProgress(progress.samplesRead);
  }

  /// The line for a pass that ran and brought nothing back (Issue #1523).
  ///
  /// A pass that asked only for what changed since the last import found
  /// nothing new, and says so: that is no sign the store is empty or that
  /// reading is off, which is what the neutral copy used to tell someone
  /// whose earlier import was sitting on her calendar.
  ///
  /// A full read that came back empty keeps the neutral copy wherever the
  /// store will not say whether reading is allowed (an iPhone). Where it
  /// does say, and says it is allowed, "or read access is off" would
  /// contradict the status line on this same screen, so the line states
  /// only what is left: there is nothing from another app to import.
  String _emptyImportCopy(AppLocalizations l10n, HealthImportSummary summary) {
    if (summary.incremental) {
      return l10n.healthSyncImportNothingSinceLast(
        _sourceName(l10n, _importPlatform),
      );
    }
    if (_readStatus == HealthPermissionStatus.granted) {
      return l10n.healthSyncImportEmptyHealthConnectReadable;
    }
    return healthImportEmptyCopy(l10n, _importPlatform);
  }

  /// The lines for a finished pass: the blocked line, the neutral empty
  /// copy, or the stopped-early note plus the positive result lines.
  List<Widget> _importSummaryChildren(
    AppLocalizations l10n,
    HealthImportSummary summary,
  ) {
    if (summary.isBlocked) {
      return [Text(_blockedImportCopy(l10n, summary.blocked!))];
    }
    if (summary.isEmpty) return [Text(_emptyImportCopy(l10n, summary))];
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
      final l10n = AppLocalizations.of(context);
      return Scaffold(
        appBar: AppBar(
          title: Text(
            l10n.settingsHealthSyncTitle(
              _sourceTitle(l10n, _importPlatform),
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  key: const ValueKey('health-sync-load-error'),
                  AppLocalizations.of(context).healthSyncLoadFailed,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    setState(() => _loading = true);
                    unawaited(_load());
                  },
                  child:
                      Text(AppLocalizations.of(context).healthSyncRetry),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final l10n = AppLocalizations.of(context);
    final permissionSection = _permissionStatusSection(l10n);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.settingsHealthSyncTitle(_sourceTitle(l10n, _importPlatform)),
        ),
      ),
      // Issue #1521: what a person can do comes first, and what the screen
      // explains comes after it. The explanations used to stand above the
      // profile rows, so the only controls on the screen sat under six or
      // more paragraphs (below the fold on Android).
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.writeEnabled
                  ? _writeIntro(l10n)
                  : l10n.healthSyncImportIntro,
            ),
          ),
          for (final profile in _profiles) _profileTile(profile),
          // Issue #959: the OS permission state, shown per platform, with
          // the settings deep link only when it is denied.
          ?permissionSection,
          // Issues #217/#458: the import action appears only once a profile
          // is bound — the import writes into that profile and no other.
          if (_boundProfileId != null && widget.importer != null)
            _importTile(l10n),
          if (_importing || _importFailed || _importSummary != null)
            _importResult(),
          if (_boundProfileId != null)
            ListTile(
              key: const ValueKey('health-sync-unbind-tile'),
              leading: const Icon(Icons.link_off),
              title: Text(l10n.healthSyncUnbindAction),
              onTap: _unbind,
            ),
          ..._details(l10n),
        ],
      ),
    );
  }

  Widget _importTile(AppLocalizations l10n) => ListTile(
        key: const ValueKey('health-sync-import-tile'),
        leading: const Icon(Icons.download_outlined),
        title: Text(
          l10n.healthSyncImportFrom(_sourceName(l10n, _importPlatform)),
        ),
        subtitle: Text(l10n.healthSyncImportTileSubtitle),
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
      );

  /// Everything the screen explains, under headings, below the controls
  /// (Issue #1521).
  ///
  /// This is a disclosure surface (`docs/ops/play-health-declaration.md`),
  /// so the rule for it is strict: every sentence that was on the screen is
  /// still on it, unedited and in plain view. Nothing is collapsed, shortened
  /// or moved to another screen; only the order changed, and each group got
  /// a heading. A string is never split to fit a heading, which is why the
  /// first group is "How it works": its one paragraph covers both
  /// directions.
  List<Widget> _details(AppLocalizations l10n) => [
        const Divider(height: 32),
        _detailHeading(l10n.healthSyncSectionHowItWorks),
        if (widget.writeEnabled)
          _detail(
            'health-sync-forward-only-copy',
            _isHealthConnect
                ? l10n.healthSyncWriteForwardOnlyHealthConnect
                : l10n.healthSyncWriteForwardOnly,
          )
        else
          // Issue #458: a platform that wires only the import direction
          // gets this in place of the write copy, rather than a promise
          // of writes that never happen. Issue #1478: nothing else rides
          // along — the symptom line that used to follow said "days
          // logged with symptoms still sync their flow and spotting",
          // two lines under "nothing is written automatically".
          _detail('health-sync-import-only-copy', l10n.healthSyncImportOnly),
        if (widget.writeEnabled) ...[
          _detailHeading(l10n.healthSyncSectionWritten),
          ..._writtenCopy(l10n),
        ],
        _detailHeading(l10n.healthSyncSectionImported),
        // Issue #992: the scope decision, stated plainly. Reads are
        // full-history now, and the #993 background pass runs wherever
        // Health Connect offers the background-read feature and its
        // permission is granted (issue #1211: the permission is
        // requested at runtime with the rest of the set, and the
        // background worker skips cleanly without it); the copy below is
        // the user-facing statement of that.
        _detail('health-sync-full-history-copy', l10n.healthSyncFullHistoryNote),
        if (widget.writeEnabled) ...[
          _detailHeading(l10n.healthSyncSectionTurningOff),
          // Issue #186 (AC7): stopping sync or revoking the OS permission
          // never deletes what was already written.
          _detail(
            'health-sync-revocation-copy',
            _isHealthConnect
                ? l10n.healthSyncRevocationNoteHealthConnect
                : l10n.healthSyncRevocationNote,
          ),
        ],
        const SizedBox(height: 16),
      ];

  /// A heading over one group of [_details], announced as a heading.
  Widget _detailHeading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Semantics(
          header: true,
          child: Text(text, style: Theme.of(context).textTheme.titleSmall),
        ),
      );

  /// One paragraph of [_details], keyed as it always was.
  Widget _detail(String key, String text) => Padding(
        key: ValueKey(key),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(text),
      );

  bool get _isHealthConnect =>
      _importPlatform == HealthImportPlatform.healthConnect;

  /// The bind-screen intro for a platform that writes (issue #1478: the
  /// Apple Health string says "this phone's Health app").
  String _writeIntro(AppLocalizations l10n) => _isHealthConnect
      ? l10n.healthSyncWriteIntroHealthConnect
      : l10n.healthSyncWriteIntro;

  /// What is written, for the store this platform writes to: the "What is
  /// written" group of [_details].
  ///
  /// Issue #193: document the write surface the way Clue documents its own
  /// — one-way, forward-only (the forward-only paragraph is the "How it
  /// works" group), and the lossy mappings (superHeavy collapses to
  /// `heavy`; spotting follows the A3-4 in/outside-episode rule).
  ///
  /// Issue #1478: Health Connect gets its own strings. It is written a
  /// different set of things (listed in full, in Health Connect's own
  /// names), it has no symptom types at all — so where the iPhone screen
  /// says symptoms are written, this one says they are not (Issue #238's
  /// permanent platform limitation) — and nothing here may say "Health
  /// app".
  List<Widget> _writtenCopy(AppLocalizations l10n) {
    final healthConnect = _isHealthConnect;
    return [
      if (healthConnect) ...[
        _detail(
          'health-sync-written-types-copy',
          l10n.healthSyncWrittenTypesHealthConnect,
        ),
        // The one way a day logged before write access reaches Health
        // Connect: as the first day of a period that has a written day.
        _detail(
          'health-sync-period-record-copy',
          l10n.healthSyncPeriodRecordNoteHealthConnect,
        ),
      ],
      _detail(
        'health-sync-flow-collapse-copy',
        healthConnect
            ? l10n.healthSyncFlowCollapseNoteHealthConnect
            : l10n.healthSyncFlowCollapseNote,
      ),
      if (healthConnect)
        _detail(
          'health-sync-symptoms-android-limitation',
          l10n.settingsHealthSyncSymptomsAndroidLimitation,
        )
      else
        // Issue #238 / #918: disclosure of symptom and mood writes.
        _detail('health-sync-symptoms-copy', l10n.healthSyncWriteSymptoms),
    ];
  }

  /// One profile of the choice. Issue #1521: each row carries a radio mark,
  /// because a bare name did not look like something to tap; the chosen
  /// profile's is filled.
  Widget _profileTile(Profile profile) {
    final check = _eligibility(profile);
    final isBound = profile.id == _boundProfileId;
    return ListTile(
      key: ValueKey('health-sync-profile-${profile.id}'),
      leading: isBound
          ? const Icon(
              Icons.radio_button_checked,
              key: ValueKey('health-sync-bound-check'),
            )
          : const Icon(Icons.radio_button_unchecked),
      title: Text(profile.displayName),
      subtitle: check.isAllowed
          ? null
          : Text(_denyReasonText(AppLocalizations.of(context), check)),
      selected: isBound,
      enabled: check.isAllowed,
      onTap: check.isAllowed ? () => _tapProfile(profile) : null,
    );
  }
}
