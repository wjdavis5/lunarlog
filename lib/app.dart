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
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/domain/sync/local_row_counts.dart'
    show LocalRowCounter;
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_home_gate.dart';
import 'package:lunarlog/ui/sharing/accept_invite_sheet.dart';
import 'package:lunarlog/ui/web/dev_banner.dart';
import 'package:provider/provider.dart';

class LunarLogApp extends StatefulWidget {
  const LunarLogApp({
    super.key,
    required this.db,
    this.scheduler,
    this.authService,
    this.syncEngine,
    this.sharingService,
    this.inviteLinks,
    this.initialInviteCode,
    this.initialInviteProfileId,
    this.onTeardown,
    this.resetDevice,
    this.showWebBanner = kIsWeb,
  });

  final LunarLogDatabase db;
  final SharingService? sharingService;

  /// `lunarlog://invite?code=...` links (U8; R9/F2), filtered by main.dart
  /// (or injected by tests). When present and a sharing service exists,
  /// an incoming link presents [AcceptInviteSheet] - after sign-in if the
  /// recipient is not authenticated yet (the code is latched across the
  /// gate in between).
  final Stream<Uri>? inviteLinks;

  /// The invite code from a cold-start link, if any (R9).
  final String? initialInviteCode;

  /// The `profile` parameter of the cold-start invite link, if any.
  final String? initialInviteProfileId;

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
  // KTD3/R5: one instance of each repository for this widget's lifetime,
  // built once in [initState] from the (stable) database and shared by the
  // reminder coordinator and the provider tree below.
  late final ProfilesRepository _profiles;
  late final DayEntriesRepository _dayEntries;
  late final SettingsStore _settings;
  late final CyclePredictionService _prediction;
  late final NotificationPermissionState _permissionState;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  ReminderCoordinator? _coordinator;
  AuthController? _authController;
  StreamSubscription<Uri>? _inviteSub;
  String? _pendingInviteCode;
  String? _profileIdOfPendingInvite;
  bool _inviteSheetOpen = false;

  /// The repositories below capture [LunarLogApp.db] once, so swapping the
  /// database on a *mounted* app would leave them bound to the old (closed)
  /// one while `build`'s row counter read the new one. `LunarLogRoot` never
  /// does that — it nulls `_db` and waits a frame, so this element unmounts
  /// first — and this assert keeps that invariant explicit rather than
  /// incidental (KTD3).
  @override
  void didUpdateWidget(LunarLogApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      identical(oldWidget.db, widget.db),
      'LunarLogApp does not support swapping db in place; unmount it first '
      '(see _detachDatabaseFromTree in app_lifecycle.dart).',
    );
  }

  @override
  void initState() {
    super.initState();
    final storage = widget.db.storage;
    _profiles = DriftProfilesRepository(storage);
    _dayEntries = DriftDayEntriesRepository(storage);
    _settings = DriftSettingsStore(storage);
    _prediction = CyclePredictionService(_dayEntries);
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
    // U8/R9: invite deep links. The cold-start code is latched here; live
    // links arrive on the stream. Presentation waits for a signed-in
    // session when needed.
    _inviteSub = widget.inviteLinks?.listen(_handleInviteLink);
    final initialInviteCode = widget.initialInviteCode;
    if (initialInviteCode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybePresentInvite(initialInviteCode, widget.initialInviteProfileId);
      });
    }
  }

  void _handleInviteLink(Uri uri) {
    if (!mounted) return;
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) return;
    _maybePresentInvite(code, uri.queryParameters['profile']);
  }

  void _maybePresentInvite(String code, String? profileId) {
    if (widget.sharingService == null || _inviteSheetOpen) return;
    if (_authController?.signedIn ?? false) {
      _showInviteSheet(code, profileId);
    } else {
      // R9: an unauthenticated recipient signs in (or creates an account)
      // first; the code stays latched until the session appears.
      setState(() {
        _pendingInviteCode = code;
        _profileIdOfPendingInvite = profileId;
      });
    }
  }

  void _showInviteSheet(String code, String? profileId) {
    final sharing = widget.sharingService;
    if (sharing == null || _inviteSheetOpen) return;
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) {
      setState(() {
        _pendingInviteCode = code;
        _profileIdOfPendingInvite = profileId;
      });
      return;
    }
    _inviteSheetOpen = true;
    setState(() {
      _pendingInviteCode = null;
      _profileIdOfPendingInvite = null;
    });
    unawaited(
      showModalBottomSheet<void>(
        context: ctx,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => AcceptInviteSheet(
          rawToken: code,
          sharingService: sharing,
          initialProfileId: profileId,
        ),
      ).whenComplete(() => _inviteSheetOpen = false),
    );
  }

  Future<void> _startReminders() async {
    // This state owns the repositories (KTD3) and provides those same
    // instances to the subtree below, so the coordinator reads its streams
    // straight off the fields rather than allocating a parallel set.
    final gate = context.read<GateController?>();
    final coordinator = ReminderCoordinator(
      scheduler: widget.scheduler!,
      permissionState: _permissionState,
      activeProfiles: _profiles.watch(),
      predictionFor: _prediction.watch,
    );
    _coordinator = coordinator;
    await coordinator.start(
      onLaunchFromNotification: gate?.setPendingLaunchProfileId,
    );
  }

  /// AS10: a signed-in session (the confirmation link opened on this
  /// device) retires the device-local "awaiting confirmation" note, and
  /// the passwordless "sign-in email sent" note with it (#2 U4; KTD3).
  /// A latched invite code (R9) is presented once the session exists.
  void _onAuthChanged() {
    if (_authController?.signedIn ?? false) {
      _clearAwaitingConfirmation();
      final code = _pendingInviteCode;
      if (code != null) {
        _showInviteSheet(code, _profileIdOfPendingInvite);
      }
    }
  }

  void _clearAwaitingConfirmation() {
    unawaited(_settings.set(SettingsKeys.awaitingConfirmationEmail, ''));
    unawaited(_settings.set(SettingsKeys.awaitingMagicLinkEmail, ''));
  }

  @override
  void dispose() {
    _inviteSub?.cancel();
    _inviteSub = null;
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
        Provider<LunarLogStorage>.value(value: widget.db.storage),
        if (widget.sharingService != null)
          Provider<SharingService>.value(value: widget.sharingService!),
        Provider<ProfilesRepository>.value(value: _profiles),
        Provider<DayEntriesRepository>.value(value: _dayEntries),
        Provider<SettingsStore>.value(value: _settings),
        Provider<CyclePredictionService>.value(value: _prediction),
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
