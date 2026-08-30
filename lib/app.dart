/// App composition root: constructs the drift-backed repositories over the
/// opened database and provides them plus the profile controller (KTD4).
/// This is the only lib/ui-adjacent file that touches `lib/data` types.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
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

/// Basic startup failure surface for U4: DB-open/quarantine/key errors from
/// U2's factory land here instead of crashing silently. The full fail-closed
/// treatment (recovery guidance, blocking UI) is U7's.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'lunarlog',
      home: Scaffold(
        appBar: AppBar(title: const Text('lunarlog could not start')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Something went wrong while opening local data. '
                'Nothing on this device was changed.',
              ),
              const SizedBox(height: 16),
              SelectableText(error.toString()),
            ],
          ),
        ),
      ),
    );
  }
}
