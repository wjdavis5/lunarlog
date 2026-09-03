/// App composition root: constructs the drift-backed repositories over the
/// opened database and provides them plus the profile controller (KTD4),
/// the reminder coordinator (KTD7/U8) and the web guardrails (KTD9).
/// This is the only lib/ui-adjacent file that touches `lib/data` types
/// (besides `lib/app_lifecycle.dart`, which is composition-root territory).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/data/notifications/reminder_coordinator.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/overview/notification_availability.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_home_gate.dart';
import 'package:lunarlog/ui/web/dev_banner.dart';
import 'package:provider/provider.dart';

class LunarLogApp extends StatefulWidget {
  const LunarLogApp({
    super.key,
    required this.db,
    this.scheduler,
    this.authService,
    this.showWebBanner = kIsWeb,
  });

  final LunarLogDatabase db;

  /// Reminder scheduler; defaults to the flutter_local_notifications
  /// implementation on native platforms and the no-op on web (KTD9).
  final ReminderScheduler? scheduler;

  /// Account auth service (U4). When present an [AuthController] is
  /// provided to the subtree; when null nothing account-related is
  /// provided and the tree is exactly the pre-U4 one.
  final AuthService? authService;

  /// KTD9 web guardrail flag; injectable for tests.
  final bool showWebBanner;

  @override
  State<LunarLogApp> createState() => _LunarLogAppState();
}

class _LunarLogAppState extends State<LunarLogApp> {
  late final NotificationPermissionState _permissionState;
  ReminderCoordinator? _coordinator;

  @override
  void initState() {
    super.initState();
    _permissionState = NotificationPermissionState(
      NotificationAvailability.available,
    );
    // Reminders start only when the shell passes a scheduler (main.dart
    // does on production platforms). Without one — e.g. in widget tests —
    // no notification machinery is touched at all.
    if (widget.scheduler != null) {
      unawaited(_startReminders());
    }
  }

  Future<void> _startReminders() async {
    // Repos are provided to the *subtree* below this widget; build the
    // coordinator's instances directly from the database instead of
    // reading them from this context.
    final gate = context.read<GateController?>();
    final dayEntries = DriftDayEntriesRepository(widget.db.storage);
    final coordinator = ReminderCoordinator(
      scheduler: widget.scheduler!,
      permissionState: _permissionState,
      activeProfiles:
          DriftProfilesRepository(widget.db.storage).watch(),
      predictionFor: CyclePredictionService(dayEntries).watch,
    );
    _coordinator = coordinator;
    await coordinator.start(
      onLaunchFromNotification: gate?.setPendingLaunchProfileId,
    );
  }

  @override
  void dispose() {
    unawaited(_coordinator?.dispose());
    _permissionState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = widget.authService;
    return MultiProvider(
      providers: [
        if (authService != null)
          ChangeNotifierProvider<AuthController>(
            create: (_) => AuthController(authService: authService),
          ),
        Provider<ProfilesRepository>.value(
          value: DriftProfilesRepository(widget.db.storage),
        ),
        Provider<DayEntriesRepository>.value(
          value: DriftDayEntriesRepository(widget.db.storage),
        ),
        Provider<SettingsStore>.value(
          value: DriftSettingsStore(widget.db.storage),
        ),
        Provider<CyclePredictionService>(
          create: (context) =>
              CyclePredictionService(context.read<DayEntriesRepository>()),
        ),
        // U6 seam: the overview hint reads this; the coordinator updates it
        // from the real permission query (U8).
        ChangeNotifierProvider.value(
          value: _permissionState,
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
        builder: (context, child) => WebGuardrails(
          showBanner: widget.showWebBanner,
          onWipe: widget.db.wipeAllData,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const ProfileHomeGate(),
      ),
    );
  }
}
