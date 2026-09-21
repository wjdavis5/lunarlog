/// The app's single home decision: loading → first-run flow (zero profiles)
/// → the active profile (issue #182: rendered inside [AppShell], the app's
/// bottom-nav shell), or the picker when the pointer is missing, archived or
/// invalid.
///
/// U7 addition: consumes the launch payload seam
/// ([GateController.pendingLaunchProfileId]) — set by the shell before
/// content shows, honored only after the gate has opened, routing to the
/// firing profile's *overview* (U8 wires real notification taps into this).
///
/// U6 additions, evaluated before the profile decision and only when the
/// corresponding controller is provided (nullable reads keep older
/// harnesses untouched): the password-recovery screen while the auth
/// service holds a recovery latch *and* the device gate is unlocked (AE8);
/// the account-mismatch screen (AE5); the upload-consent screen until
/// declined for this session (the Settings tile reopens it); and the
/// data-free restoring step during the bind-time pull (AE13).
///
/// #2 U3 addition (KTD4, R7, AE4): a link failure latched by the auth
/// service ([AuthController.pendingLinkFailure] — expired, reused, or
/// foreign-device link, or a network failure during the exchange) is
/// surfaced once, as a `SnackBar` keyed `auth-link-failure` carrying
/// [authFailureCopy], and only after the device gate reports unlocked. It
/// is consumed through the same microtask-plus-guard shape as the launch
/// payload so a rebuild never repeats it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/ui/account/account_mismatch_screen.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/password_recovery_screen.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/restore_error_screen.dart';
import 'package:lunarlog/ui/account/restoring_screen.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/upload_consent_screen.dart';
import 'package:lunarlog/ui/components/app_shell.dart';
import 'package:lunarlog/ui/l10n/auth_failure_copy.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/first_run_screen.dart';
import 'package:lunarlog/ui/profiles/profile_picker_screen.dart';
import 'package:provider/provider.dart';

class ProfileHomeGate extends StatefulWidget {
  const ProfileHomeGate({super.key});

  @override
  State<ProfileHomeGate> createState() => _ProfileHomeGateState();
}

class _ProfileHomeGateState extends State<ProfileHomeGate> {
  /// Profile id delivered by the launch payload; its detail screen opens on
  /// the Overview tab until the operator switches profiles.
  String? _overviewLaunchId;

  /// LLA-008: a monotonic counter, incremented once per successfully-routed
  /// launch payload (not per profile) -- distinguishes "the same profile
  /// was named by *another* notification" from "nothing new happened",
  /// which `_overviewLaunchId` alone cannot (it only ever holds one
  /// value). [AppShell.launchToken] reads this only when the active
  /// profile still matches `_overviewLaunchId`, and resets to Today on
  /// every value change -- including a same-profile relaunch, which a
  /// profile-id-only comparison would miss entirely.
  int _overviewLaunchSeq = 0;

  /// Guards against scheduling duplicate consumption microtasks while the
  /// payload is still set across consecutive builds.
  String? _consuming;

  /// "Not now" on the inline consent screen: the home shows again and the
  /// status tile carries "Upload pending — tap to review" (AS4). Cleared
  /// as soon as the engine leaves `awaitingUploadConsent`.
  bool _consentDeclined = false;

  /// Guards against scheduling duplicate link-failure consumption
  /// microtasks across consecutive builds (#2 U3).
  bool _consumingLinkFailure = false;

  /// Keeps an empty, bound account out of first-run while a restore retry is
  /// moving through pushing/pulling. Cleared when the retry reaches idle.
  bool _restoreRetryPending = false;

  /// Finding #3 in #37 / Issue #250: when restore fails persistently, allows
  /// the operator to continue into first-run profile creation in offline mode.
  bool _restoreBypassed = false;

  /// Guards against scheduling duplicate warm-recovery pop microtasks
  /// across consecutive builds (LLA-007).
  bool _consumingRecoveryPop = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProfileController>();
    final gate = Provider.of<GateController?>(context);
    final auth = Provider.of<AuthController?>(context);
    final sync = Provider.of<SyncStatusController?>(context);
    _maybeConsumeLaunchPayload(gate, controller);
    _maybeShowLinkFailure(gate, auth);
    _maybeSurfaceRecovery(auth, gate);
    if (!controller.loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _recoveryScreen(auth, gate) ??
        _syncPhaseScreen(sync) ??
        _restoreErrorScreen(sync, controller, auth) ??
        _profileScreen(controller);
  }

  bool _canShowRestoreError(
    SyncStatusController? sync,
    ProfileController controller,
    AuthController? auth,
  ) {
    if (_restoreBypassed || sync == null) return false;
    final isBound =
        sync.snapshot.boundUserId != null || auth?.currentUser != null;
    if (!isBound || !controller.needsFirstRun || sync.phase == SyncPhase.idle) {
      _restoreRetryPending = false;
      _restoreBypassed = false;
      return false;
    }
    return sync.phase == SyncPhase.error || _restoreRetryPending;
  }

  /// Finding #3 in #37 (Issue #39): when an account is bound and the local
  /// database has no profiles ([ProfileController.needsFirstRun]), a failed
  /// restore ([SyncPhase.error]) presents a dedicated retry screen rather than
  /// falling through to first-run profile creation, preventing divergent data.
  /// Issue #250: offers "Continue without syncing" and "Sign out" escape
  /// actions so a persistently failing restore never permanently locks the user out.
  Widget? _restoreErrorScreen(
    SyncStatusController? sync,
    ProfileController controller,
    AuthController? auth,
  ) {
    if (!_canShowRestoreError(sync, controller, auth)) return null;
    return RestoreErrorScreen(
      onRetry: () {
        setState(() => _restoreRetryPending = true);
        sync!.requestSync();
      },
      onContinueWithoutSyncing: () => setState(() => _restoreBypassed = true),
      onSignOut: () => auth?.signOut(scope: AuthSignOutScope.local),
    );
  }

  /// AE8: the recovery latch is honored only once the device gate is open
  /// (no gate provided means an un-gated harness). Returns null when
  /// recovery isn't showing, so [build] falls through to the next check.
  Widget? _recoveryScreen(AuthController? auth, GateController? gate) {
    if (auth != null &&
        auth.pendingRecovery &&
        (gate == null || gate.unlocked)) {
      return const PasswordRecoveryScreen();
    }
    return null;
  }

  /// LLA-007: [_recoveryScreen] only changes what *this* widget renders,
  /// but this widget is the app's home/root route (see `app.dart`'s
  /// `onGenerateRoute`) — any route pushed above it (Settings, sign-in,
  /// a profile detail screen, ...) keeps covering it, so a recovery link
  /// that arrives "warm" (the app already running, not a cold start) has
  /// its screen change underneath whatever the operator already had open,
  /// invisible until they manually navigate all the way back. Once the
  /// same gate [_recoveryScreen] itself checks admits recovery, this pops
  /// every pushed route back to home so the recovery step is
  /// navigator-wide, not just root-wide. Deferred off the build path,
  /// mirroring [_maybeShowLinkFailure] — `Navigator.pop` cannot run
  /// during build — and guarded the same way against scheduling more
  /// than one pop per build cycle.
  void _maybeSurfaceRecovery(AuthController? auth, GateController? gate) {
    final showingRecovery =
        auth != null && auth.pendingRecovery && (gate == null || gate.unlocked);
    if (!showingRecovery || _consumingRecoveryPop) return;
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) return;
    _consumingRecoveryPop = true;
    scheduleMicrotask(() {
      _consumingRecoveryPop = false;
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  /// The U6 sync-status screens (account mismatch, upload consent,
  /// restoring). Returns null when the current phase has no screen of its
  /// own, so [build] falls through to the profile decision.
  Widget? _syncPhaseScreen(SyncStatusController? sync) {
    if (sync == null) return null;
    final phase = sync.phase;
    if (phase != SyncPhase.awaitingUploadConsent) _consentDeclined = false;
    return _screenForSyncPhase(phase);
  }

  /// Maps a single sync phase to its screen. `idle`, `pushing`, `pulling`,
  /// `paused` and `error` have none — same as the other phases once
  /// `awaitingUploadConsent` has already been declined this session.
  ///
  /// A switch *expression* (not an if-chain): every [SyncPhase] value is
  /// named explicitly (no `_` wildcard), so adding a new phase without
  /// updating this method is a compile error, not a silently-null screen.
  Widget? _screenForSyncPhase(SyncPhase phase) => switch (phase) {
        SyncPhase.accountMismatch => const AccountMismatchScreen(),
        SyncPhase.awaitingUploadConsent =>
          _consentDeclined ? null : _uploadConsentScreen(),
        SyncPhase.restoring => const RestoringScreen(),
        SyncPhase.idle ||
        SyncPhase.paused ||
        SyncPhase.pushing ||
        SyncPhase.pulling ||
        SyncPhase.error =>
          null,
      };

  Widget _uploadConsentScreen() {
    return UploadConsentScreen(
      onNotNow: () => setState(() => _consentDeclined = true),
    );
  }

  /// The base home decision once loading, recovery and sync-status screens
  /// are all out of the way: first-run, the picker, or the active profile.
  /// Issue #804: the first-run screen also stays up while its household
  /// setup flow is still active (`firstRunFlowActive`) — the zero-profiles
  /// rule alone would unmount it the moment the first creation lands.
  Widget _profileScreen(ProfileController controller) {
    if (controller.needsFirstRun || controller.firstRunFlowActive) {
      return const FirstRunScreen();
    }
    final active = controller.activeProfile;
    if (controller.pickerVisible || active == null) {
      return const ProfilePickerScreen();
    }
    // Issue #182: AppShell is the single entry point every active profile
    // mounts inside now (a Today/Calendar/Insights/More bottom nav) --
    // ProfileDetailScreen remains only for the archived-profile read-only
    // view, still pushed explicitly from the picker.
    return AppShell(
      profile: active,
      launchToken:
          active.id == _overviewLaunchId ? _overviewLaunchSeq : null,
    );
  }

  void _maybeConsumeLaunchPayload(
      GateController? gate, ProfileController controller) {
    final pending = gate?.pendingLaunchProfileId;
    if (pending == null || pending == _consuming || !controller.loaded) {
      return;
    }
    _consuming = pending;
    // Deferred: mutates controller/notifyListeners, which cannot happen
    // during build.
    scheduleMicrotask(() {
      // LLA-008: reset the guard first, mirroring _maybeShowLinkFailure's
      // "reset first so a *later* one can show again" pattern -- without
      // this, _consuming stuck at this profile id for the rest of this
      // State's lifetime (it was never reset anywhere), silently dropping
      // every later notification tap that named the *same* profile.
      _consuming = null;
      if (!mounted) return;
      gate!.clearPendingLaunchProfileId();
      final exists =
          controller.activeProfiles.any((profile) => profile.id == pending);
      if (!exists) {
        // Unknown or archived id: fall through to the normal home decision.
        return;
      }
      setState(() {
        _overviewLaunchId = pending;
        _overviewLaunchSeq++;
      });
      unawaited(controller.selectProfile(pending));
    });
  }

  /// AE4: a latched link failure is shown once, only after the device gate
  /// is open (no gate provided means an un-gated harness), and consumed
  /// off the build path (#2 U3; KTD4, R7).
  void _maybeShowLinkFailure(GateController? gate, AuthController? auth) {
    final failure = auth?.pendingLinkFailure;
    if (failure == null || _consumingLinkFailure) return;
    if (gate != null && !gate.unlocked) return;
    _consumingLinkFailure = true;
    scheduleMicrotask(() {
      // Reset first so a *later* failure can show again; the pending
      // value is null after consumption, so this build cycle is inert.
      _consumingLinkFailure = false;
      if (!mounted) return;
      auth!.consumeLinkFailure();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        key: const ValueKey('auth-link-failure'),
        content: Text(authFailureCopy(AppLocalizations.of(context), failure)),
      ));
    });
  }
}
