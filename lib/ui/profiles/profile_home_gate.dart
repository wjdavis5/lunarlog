/// The app's single home decision: loading → first-run flow (zero profiles)
/// → the active profile, or the picker when the pointer is missing, archived
/// or invalid. A richer navigation model is an open design decision; this is
/// deliberately the minimum.
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
import 'package:lunarlog/ui/account/restore_error_screen.dart';
import 'package:lunarlog/ui/account/restoring_screen.dart';
import 'package:lunarlog/ui/account/sign_in_screen.dart'
    show authFailureCopy;
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/upload_consent_screen.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProfileController>();
    final gate = Provider.of<GateController?>(context);
    final auth = Provider.of<AuthController?>(context);
    final sync = Provider.of<SyncStatusController?>(context);
    _maybeConsumeLaunchPayload(gate, controller);
    _maybeShowLinkFailure(gate, auth);
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

  /// Finding #3 in #37 (Issue #39): when an account is bound and the local
  /// database has no profiles ([ProfileController.needsFirstRun]), a failed
  /// restore ([SyncPhase.error]) presents a dedicated retry screen rather than
  /// falling through to first-run profile creation, preventing divergent data.
  Widget? _restoreErrorScreen(
    SyncStatusController? sync,
    ProfileController controller,
    AuthController? auth,
  ) {
    if (sync == null) return null;
    final isBound = sync.snapshot.boundUserId != null ||
        (auth != null && auth.currentUser != null);
    if (isBound && controller.needsFirstRun && sync.phase == SyncPhase.error) {
      return RestoreErrorScreen(
        onRetry: () => sync.requestSync(),
      );
    }
    return null;
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
  Widget _profileScreen(ProfileController controller) {
    if (controller.needsFirstRun) {
      return const FirstRunScreen();
    }
    final active = controller.activeProfile;
    if (controller.pickerVisible || active == null) {
      return const ProfilePickerScreen();
    }
    return ProfileDetailScreen(
      profile: active,
      initiallyShowOverview: active.id == _overviewLaunchId,
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
      if (!mounted) return;
      gate!.clearPendingLaunchProfileId();
      final exists =
          controller.activeProfiles.any((profile) => profile.id == pending);
      if (!exists) {
        // Unknown or archived id: fall through to the normal home decision.
        return;
      }
      setState(() => _overviewLaunchId = pending);
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
        content: Text(authFailureCopy(failure)),
      ));
    });
  }
}
