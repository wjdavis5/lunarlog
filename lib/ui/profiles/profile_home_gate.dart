/// The app's single home decision: loading → first-run flow (zero profiles)
/// → the active profile, or the picker when the pointer is missing, archived
/// or invalid. A richer navigation model is an open design decision; this is
/// deliberately the minimum.
///
/// U7 addition: consumes the launch payload seam
/// ([GateController.pendingLaunchProfileId]) — set by the shell before
/// content shows, honored only after the gate has opened, routing to the
/// firing profile's *overview* (U8 wires real notification taps into this).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart';
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProfileController>();
    final gate = Provider.of<GateController?>(context);
    _maybeConsumeLaunchPayload(gate, controller);
    if (!controller.loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
