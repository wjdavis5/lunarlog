/// Settings screen for binding "this device's health-store profile" (Issue
/// #153): lists every profile, showing why each ineligible one is refused,
/// lets the operator bind an eligible one behind a confirm dialog naming
/// what binding means, and offers an unbind action once one is bound.
///
/// Live on iOS since issue #193: binding a profile is the opt-in, and the
/// write path it arms (wired in `app.dart`) is one-way — period days and
/// spotting are written to the OS health store and nothing is ever read
/// back — and forward-only from the authorization moment (no backfill of
/// days logged before sync was turned on). The copy below documents the
/// one lossy mapping (`superHeavy` → `heavy`, the same collapse Clue
/// documents for its own Apple Health integration, plus the spotting
/// rule), mirroring Clue's own disclosure. `SettingsScreen` still gates
/// this screen off on web, and off on Android until #202 wires Health
/// Connect's checklist. The screen itself only ever changes the
/// device-local [SettingsKeys.healthStoreProfileId] setting via
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
import '../../domain/health/health_import.dart';
import '../../domain/health/health_platform.dart';
import '../../domain/health/health_sync_binding.dart';
import '../../domain/health/health_sync_policy.dart';
import '../../domain/models/profile.dart';
import '../../domain/repositories/profile_guardians_repository.dart'
    show GuardiansForProfile;
import '../../domain/repositories/profiles_repository.dart';
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

/// The neutral statement shown when an import read returned nothing usable
/// (Issue #217). Deliberately says neither "nothing was tracked" nor
/// "permission denied": Apple Health never reveals a denied read, so the two
/// are indistinguishable and the UI must not imply it knows which happened.
const String kAppleHealthImportEmptyCopy =
    'Apple Health returned no menstrual-flow data for the last 30 days. '
    "Apple Health doesn't tell apps whether read access is allowed, so this "
    'can mean nothing was tracked, or that access is off.';

class HealthSyncScreen extends StatefulWidget {
  const HealthSyncScreen({
    super.key,
    required this.profilesRepository,
    required this.guardiansForProfile,
    required this.binding,
    required this.signedInUserId,
    this.importer,
  });

  final ProfilesRepository profilesRepository;
  final GuardiansForProfile guardiansForProfile;
  final HealthSyncBinding binding;

  /// The user-initiated import seam (Issue #217). Null on a build where the
  /// import runner is absent (tests, an unconfigured build), in which case
  /// the import tile is hidden entirely.
  final AppleHealthImportRunner? importer;

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

  /// Issue #217 import state: whether a pass is running, the last summary,
  /// and whether the pass threw (an unexpected storage error — the runner
  /// itself reports expected failures as a [AppleHealthImportSummary]).
  bool _importing = false;
  bool _importFailed = false;
  AppleHealthImportSummary? _importSummary;

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
    if (!mounted) return;
    setState(() {
      _boundProfileId = bound;
      _profiles = profiles;
      _ownerUserIdByProfile = owners;
      _loading = false;
      _loadFailed = false;
    });
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

  /// [check]'s user-facing deny reason for [profile], or the empty string
  /// for a non-deny result. [HealthSyncCheck.notOwner] reads differently
  /// depending on *why* ownership didn't resolve (review fix): a
  /// never-synced local-only user (no signed-in session yet, or this
  /// profile's guardians haven't synced) gets an actionable "sign in and
  /// sync" prompt, distinct from an actual non-owner being told they
  /// simply aren't this profile's owner.
  String _denyReasonText(Profile profile, HealthSyncCheck check) =>
      switch (check) {
        HealthSyncCheck.minorRequiresOwnershipTransfer =>
          "Minor profiles can sync only from the minor's own account "
              'after ownership transfer.',
        HealthSyncCheck.notOwner => widget.signedInUserId == null ||
                _ownerUserIdByProfile[profile.id] == null
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
      final reason = _denyReasonText(profile, result);
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
          "Only ${profile.displayName}'s data will ever be written to "
          "this phone's Health app. This phone can sync one profile at a "
          'time — choosing a different profile later replaces this one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('health-sync-confirm-bind'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Bind'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _unbind() async {
    await widget.binding.unbind();
    await _load();
  }

  /// Runs one user-initiated import (Issue #217). The runner owns the guard,
  /// the bounded window, and the merge; this only sequences and renders its
  /// summary. An unexpected throw (a storage error the runner does not
  /// classify) becomes the generic failure line rather than a crash.
  Future<void> _runImport() async {
    final importer = widget.importer;
    if (importer == null || _importing) return;
    setState(() {
      _importing = true;
      _importFailed = false;
      _importSummary = null;
    });
    try {
      final summary = await importer.importNow();
      if (!mounted) return;
      setState(() {
        _importing = false;
        _importSummary = summary;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _importFailed = true;
      });
    }
  }

  /// The copy for a pass that ended before reading — a guard refusal or a
  /// platform outcome. A [HealthPlatformPermissionDenied] deliberately
  /// renders the same neutral ambiguity copy as an empty result, since
  /// Apple Health never distinguishes the two.
  String _blockedImportCopy(HealthPlatformResult blocked) => switch (blocked) {
        HealthPlatformRefused() =>
          "This profile can't import from Apple Health right now.",
        HealthPlatformUnavailable() =>
          "Apple Health isn't available on this device.",
        HealthPlatformPermissionDenied() => kAppleHealthImportEmptyCopy,
        HealthPlatformFailed() =>
          "Couldn't finish the import. Please try again.",
        HealthPlatformAllowed() => kAppleHealthImportEmptyCopy,
      };

  /// The positive result lines for a pass that read samples. Empty when
  /// every sample was a no-op.
  List<String> _importResultLines(AppleHealthImportSummary summary) => [
        if (summary.daysWritten > 0)
          'Updated ${_days(summary.daysWritten)} from Apple Health.',
        if (summary.daysUnchanged > 0)
          '${_days(summary.daysUnchanged)} already matched.',
        if (summary.daysKeptManual > 0)
          'Kept your own logged value on ${_days(summary.daysKeptManual)}.',
        if (summary.samplesWithoutZone > 0)
          'Skipped ${_samples(summary.samplesWithoutZone)} with no recorded '
              'time zone.',
        if (summary.samplesUnsupported > 0)
          'Skipped ${_samples(summary.samplesUnsupported)} with no matching '
              'flow level.',
      ];

  static String _days(int n) => n == 1 ? '1 day' : '$n days';

  static String _samples(int n) => n == 1 ? '1 sample' : '$n samples';

  /// The result block: progress while running, then either the failure
  /// line, the blocked line, the neutral empty copy, or the positive lines.
  Widget _importResult() {
    final children = <Widget>[];
    if (_importing) {
      children.add(const Text('Importing from Apple Health…'));
    } else if (_importFailed) {
      children.add(
        const Text("Couldn't finish the import. Please try again."),
      );
    } else if (_importSummary != null) {
      final summary = _importSummary!;
      if (summary.isBlocked) {
        children.add(Text(_blockedImportCopy(summary.blocked!)));
      } else if (summary.isEmpty) {
        children.add(const Text(kAppleHealthImportEmptyCopy));
      } else {
        for (final line in _importResultLines(summary)) {
          children.add(Text(line));
        }
      }
    }
    return Padding(
      key: const ValueKey('health-sync-import-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
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
    return Scaffold(
      appBar: AppBar(title: const Text('Health app sync')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Choose the one profile whose data this phone may ever write '
              "to its Health app. Every other profile stays out of this "
              "phone's Health app entirely.",
            ),
          ),
          // Issue #193: document the write surface the way Clue documents
          // its own — one-way, forward-only, and the one lossy mapping
          // (superHeavy collapses to Apple's `heavy`; spotting follows the
          // A3-4 in/outside-episode rule). Issue #217 adds the read
          // direction: user-initiated import only, and the original
          // "nothing is ever read back" claim is rewritten to say so.
          const Padding(
            key: ValueKey('health-sync-forward-only-copy'),
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Only days logged after sync is turned on are written — '
              'nothing already in the app is sent on its own. Separately, '
              'you can choose to import menstrual flow from the Health app; '
              'nothing is read unless you start that import yourself.',
            ),
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
          // Issue #186 (AC9): the v1 scope decision, stated plainly.
          // Reads are limited to the last 30 days on both platforms;
          // full-history import (READ_HEALTH_DATA_HISTORY) and background
          // sync (READ_HEALTH_DATA_IN_BACKGROUND) are deliberately deferred
          // for v1.
          const Padding(
            key: ValueKey('health-sync-30-day-limit-copy'),
            padding: EdgeInsets.all(16),
            child: Text(
              'Reads are limited to the last 30 days. Full history import and '
              'background sync are not available yet.',
            ),
          ),
          for (final profile in _profiles) _profileTile(profile),
          // Issue #217: the import action appears only once a profile is
          // bound — the import writes into that profile and no other.
          if (_boundProfileId != null && widget.importer != null)
            ListTile(
              key: const ValueKey('health-sync-import-tile'),
              leading: const Icon(Icons.download_outlined),
              title: const Text('Import from Apple Health'),
              subtitle: const Text(
                'Bring in menstrual flow from the last 30 days.',
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
          check.isAllowed ? null : Text(_denyReasonText(profile, check)),
      trailing: isBound
          ? const Icon(Icons.check_circle, key: ValueKey('health-sync-bound-check'))
          : null,
      enabled: check.isAllowed,
      onTap: check.isAllowed ? () => _tapProfile(profile) : null,
    );
  }
}
