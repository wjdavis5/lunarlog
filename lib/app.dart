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
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/domain/sync/local_row_counts.dart'
    show LocalRowCounter;
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
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
    this.syncEngine,
    this.onTeardown,
    this.resetDevice,
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

  /// Cloud sync engine (U5), owned by `LunarLogRoot`. When present a
  /// [SyncStatusController] is provided to the subtree; when null nothing
  /// sync-related is provided.
  final SyncEngine? syncEngine;

  /// Receives this widget's asynchronous teardown (the reminder
  /// coordinator's disposal) when it unmounts, so the root can await it
  /// before closing the database (KTD16 prep).
  final void Function(Future<void> teardown)? onTeardown;

  /// The device reset (KTD16). `LunarLogRoot` provides it above this
  /// widget, so it is normally read from the context; an explicit value
  /// (tests) takes precedence. When neither exists the web wipe falls back
  /// to [LunarLogDatabase.wipeAllData] alone.
  final DeviceResetCallback? resetDevice;

  /// KTD9 web guardrail flag; injectable for tests.
  final bool showWebBanner;

  @override
  State<LunarLogApp> createState() => _LunarLogAppState();
}

class _LunarLogAppState extends State<LunarLogApp> {
  late final NotificationPermissionState _permissionState;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  ReminderCoordinator? _coordinator;
  AuthController? _authController;

  @override
  void initState() {
    super.initState();
    _permissionState = NotificationPermissionState(
      NotificationAvailability.available,
    );
    final authService = widget.authService;
    if (authService != null) {
      final controller = AuthController(authService: authService)
        ..addListener(_onAuthChanged);
      _authController = controller;
      if (controller.signedIn) _clearAwaitingConfirmation();
    }
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

  /// AS10: a signed-in session (the confirmation link opened on this
  /// device) retires the device-local "awaiting confirmation" note, and
  /// the passwordless "sign-in email sent" note with it (#2 U4; KTD3).
  void _onAuthChanged() {
    if (_authController?.signedIn ?? false) _clearAwaitingConfirmation();
  }

  void _clearAwaitingConfirmation() {
    final settings = DriftSettingsStore(widget.db.storage);
    unawaited(settings.set(SettingsKeys.awaitingConfirmationEmail, ''));
    unawaited(settings.set(SettingsKeys.awaitingMagicLinkEmail, ''));
  }

  @override
  void dispose() {
    _authController?.dispose();
    _authController = null;
    final teardown = _coordinator?.dispose() ?? Future<void>.value();
    _coordinator = null;
    final onTeardown = widget.onTeardown;
    if (onTeardown != null) {
      onTeardown(teardown);
    } else {
      unawaited(teardown);
    }
    _permissionState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authController = _authController;
    final syncEngine = widget.syncEngine;
    final resetDevice = widget.resetDevice ??
        Provider.of<DeviceResetCallback?>(context, listen: false);
    return MultiProvider(
      providers: [
        if (authController != null)
          ChangeNotifierProvider<AuthController>.value(value: authController),
        if (resetDevice != null)
          Provider<DeviceResetCallback>.value(
            value: resetDevice,
            updateShouldNotify: (_, _) => false,
          ),
        // Upload-consent counts (R14): the only place `lib/ui` learns how
        // many rows this device holds, tombstones included.
        Provider<LocalRowCounter>.value(
          value: widget.db.storage.countAllRows,
          updateShouldNotify: (_, _) => false,
        ),
        if (syncEngine != null)
          ChangeNotifierProvider<SyncStatusController>(
            create: (_) => SyncStatusController(engine: syncEngine),
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
        navigatorKey: _navigatorKey,
        title: 'lunarlog',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00696F)),
        ),
        // KTD16: the web wipe is the device reset when one is provided.
        builder: (context, child) => WebGuardrails(
          showBanner: widget.showWebBanner,
          onWipe: resetDevice ?? widget.db.wipeAllData,
          navigatorKey: _navigatorKey,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const ProfileHomeGate(),
      ),
    );
  }
}
