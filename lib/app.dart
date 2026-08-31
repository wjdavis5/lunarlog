/// App composition root: constructs the drift-backed repositories over the
/// opened database and provides them plus the profile controller (KTD4).
/// This is the only lib/ui-adjacent file that touches `lib/data` types
/// (besides `lib/app_lifecycle.dart`, which is composition-root territory).
///
/// The gate shell and fail-closed startup handling live in
/// `lib/app_lifecycle.dart` (U7).
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/overview/notification_availability.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_home_gate.dart';
import 'package:provider/provider.dart';

class LunarLogApp extends StatelessWidget {
  const LunarLogApp({super.key, required this.db});

  final LunarLogDatabase db;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ProfilesRepository>.value(
          value: DriftProfilesRepository(db.storage),
        ),
        Provider<DayEntriesRepository>.value(
          value: DriftDayEntriesRepository(db.storage),
        ),
        Provider<SettingsStore>.value(
          value: DriftSettingsStore(db.storage),
        ),
        Provider<CyclePredictionService>(
          create: (context) =>
              CyclePredictionService(context.read<DayEntriesRepository>()),
        ),
        // U6 seam for U8: defaults to available; U8 injects the real
        // notification-permission state.
        Provider<NotificationAvailability>.value(
          value: NotificationAvailability.available,
        ),
        ChangeNotifierProvider(
          create: (context) => ProfileController(
            profilesRepository: context.read<ProfilesRepository>(),
            settingsStore: context.read<SettingsStore>(),
          )..load(),
        ),
      ],
      child: MaterialApp(
        title: 'lunarlog',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00696F)),
        ),
        home: const ProfileHomeGate(),
      ),
    );
  }
}
