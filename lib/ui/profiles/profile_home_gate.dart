/// The app's single home decision: loading → first-run flow (zero profiles)
/// → the active profile, or the picker when the pointer is missing, archived
/// or invalid. A richer navigation model is an open design decision; this is
/// deliberately the minimum.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
import 'package:lunarlog/ui/profiles/first_run_screen.dart';
import 'package:lunarlog/ui/profiles/profile_picker_screen.dart';
import 'package:provider/provider.dart';

class ProfileHomeGate extends StatelessWidget {
  const ProfileHomeGate({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProfileController>();
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
    return ProfileDetailScreen(profile: active);
  }
}
