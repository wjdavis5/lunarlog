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
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/ui/account/account_mismatch_screen.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/password_recovery_screen.dart';
import 'package:lunarlog/ui/account/restoring_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProfileController>();
    final gate = Provider.of<GateController?>(context);
    final auth = Provider.of<AuthController?>(context);
    final sync = Provider.of<SyncStatusController?>(context);
    _maybeConsumeLaunchPayload(gate, controller);
    if (!controller.loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // AE8: the recovery latch is honored only once the device gate is
    // open (no gate provided means an un-gated harness).
    if (auth != null &&
        auth.pendingRecovery &&
        (gate == null || gate.unlocked)) {
      return const PasswordRecoveryScreen();
    }
    if (sync != null) {
      final phase = sync.phase;
      if (phase != SyncPhase.awaitingUploadConsent) _consentDeclined = false;
      switch (phase) {
        case SyncPhase.accountMismatch:
          return const AccountMismatchScreen();
        case SyncPhase.awaitingUploadConsent:
          if (!_consentDeclined) {
            return UploadConsentScreen(
              onNotNow: () => setState(() => _consentDeclined = true),
            );
          }
        case SyncPhase.restoring:
          return const RestoringScreen();
        case SyncPhase.idle:
        case SyncPhase.pushing:
        case SyncPhase.pulling:
        case SyncPhase.paused:
        case SyncPhase.error:
          break;
      }
    }
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
}
