/// App root (U7, KTD7, KTD11, KTD16): the [LunarLogRoot] state machine that
/// opens the database only after the gate unlocks (AE4) and owns the sync
/// engine's lifecycle.
///
/// * Device reset (KTD16): [LunarLogRootState.resetDevice] is the one
///   destructive path — sign-out, "sign out everywhere", the mismatch
///   screen's "remove this device's data" and the web wipe all call it
///   through the [DeviceResetCallback] provided to the tree.
///
/// Split out of `lib/app_lifecycle.dart` (issue #433): this file owns the
/// [LunarLogRoot] widget plus [LunarLogRootState], [GateShell],
/// [PrivacyCover], the [SyncEngineBuilder] typedef and the push/notification
/// callback classes. The gate state machine lives in
/// `lib/gate_controller.dart`. `lib/app_lifecycle.dart` remains as a thin
/// re-export barrel so existing import sites keep working.
///
/// This file is composition-root territory (like `main.dart`): it is
/// allowed to touch `lib/data` types to wire the drift settings store into
/// the controller.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/composition/app_dependencies.dart';
import 'package:lunarlog/config.dart';
import 'package:lunarlog/data/account/supabase_account_deletion_service.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/export/supabase_account_export_remote_source.dart';
import 'package:lunarlog/data/feedback/supabase_feedback_service.dart';
import 'package:lunarlog/data/notifications/push_registration_coordinator.dart';
import 'package:lunarlog/data/sharing/supabase_ownership_transfer_service.dart';
import 'package:lunarlog/data/sharing/supabase_prediction_connection_service.dart';
import 'package:lunarlog/data/sharing/supabase_sharing_service.dart';
import 'package:lunarlog/data/sync/realtime_sync_coordinator.dart';
import 'package:lunarlog/data/sync/supabase_sync_engine.dart';
import 'package:lunarlog/data/sync/sync_transport.dart';
import 'package:lunarlog/domain/account/account_deletion_service.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/export/account_export_remote_source.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/domain/gate/app_gate.dart';
import 'package:lunarlog/domain/notifications/notification_preferences_service.dart';
import 'package:lunarlog/domain/notifications/reminder_scheduler.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/gate_controller.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/startup/startup.dart' as startup;
import 'package:lunarlog/ui/account/device_reset_callback.dart';
import 'package:lunarlog/ui/gate/lock_screen.dart';
import 'package:lunarlog/ui/startup/fail_closed_screen.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show Sentry;
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:uuid/uuid.dart';

/// Builds the sync engine over an opened database (KTD11). The default
/// constructs [SupabaseSyncEngine]; tests inject a recorder.
typedef SyncEngineBuilder = SyncEngine Function({
  required LunarLogDatabase db,
  required AuthService authService,
  required SyncTransport transport,
  required GateController gate,
});

SyncEngine defaultSyncEngineBuilder({
  required LunarLogDatabase db,
  required AuthService authService,
  required SyncTransport transport,
  required GateController gate,
}) =>
    SupabaseSyncEngine(
      storage: db.storage,
      transport: transport,
      auth: authService,
      gate: gate,
      gateUnlocked: () => gate.unlocked,
    );

/// The device reset callback type lives next to the account UI that
/// consumes it ([DeviceResetCallback] in
/// `lib/ui/account/device_reset_callback.dart`); this composition root only
/// provides it (KTD16).

/// Explicit push-device-registration removal (#1 review fix), provided
/// alongside [DeviceResetCallback] so a sign-out UI flow that does *not* go
/// through [LunarLogRootState.resetDevice] (e.g. `AccountMismatchScreen`'s
/// "Switch account", `AccountSection`'s "sign out everywhere") can still
/// remove this device's push registration while the session is still
/// authenticated, before calling the auth service's own signOut(). Always
/// best-effort (never throws) and a no-op when push was never started
/// (unconfigured build, web, or no session yet). Null in harnesses that
/// mount `LunarLogApp` directly without passing one, exactly like
/// [DeviceResetCallback].
///
/// Deliberately a wrapper class, not a bare `typedef ... = Future&lt;void&gt;
/// Function()` (as first written, and as [DeviceResetCallback] itself is):
/// Dart's generics use *structural* equality for function types, so a
/// second same-shaped typedef used as a distinct `Provider<T>` type is
/// indistinguishable at runtime from [DeviceResetCallback] - both reify to
/// `Provider<Future<void> Function()>` - and one silently shadows the other
/// in the provider tree depending on nesting order. `Provider.of`/
/// `context.read` would then hand an `AccountMismatchScreen` calling
/// `context.read<DeviceResetCallback?>()` this callback instead, or vice
/// versa, with no compile-time or runtime signal that anything was wrong.
/// Caught by `test/ui/account_test.dart`'s sign-out order assertions during
/// review; the wrapper class gives this a distinct nominal type so it can
/// never collide with [DeviceResetCallback] or any future same-shaped
/// callback.
class RemovePushRegistrationCallback {
  const RemovePushRegistrationCallback(this._call);

  final Future<void> Function() _call;

  Future<void> call() => _call();
}

/// Removes every push registration for the current user across every
/// device, not just this one (round-2 review #9) - provided alongside
/// [RemovePushRegistrationCallback] for flows where the user explicitly
/// asked to be signed out *everywhere* (`AccountSection`'s "sign out
/// everywhere", which already calls `signOut(scope: global)` to revoke
/// every device's session server-side). Without this, another device's
/// `push_devices` row and FCM token survive that call and keep receiving
/// this user's caregiver alerts, since that device's own coordinator only
/// reacts to its *own* auth-state stream noticing the revoked session -
/// which by then runs as anon (no grant on `push_devices` at all) - or
/// never reacts at all if the app is not foregrounded before the session
/// is next used. Same wrapper-class rationale as
/// [RemovePushRegistrationCallback] (see its doc comment) - a bare
/// same-shaped typedef would collide with it and [DeviceResetCallback] in
/// the provider tree. Null in harnesses that mount `LunarLogApp` directly
/// without passing one.
class RemoveAllPushRegistrationsCallback {
  const RemoveAllPushRegistrationsCallback(this._call);

  final Future<void> Function() _call;

  Future<void> call() => _call();
}

/// Overview hint seam (issue #168): the "Turn on reminders" tap runs
/// through this so `lib/ui` never touches `ReminderCoordinator` directly —
/// same wrapper-class rationale as [RemovePushRegistrationCallback] (a bare
/// same-shaped typedef could collide with it in the provider tree).
/// `LunarLogApp`'s implementation wraps the call in
/// [GateController.duringSystemUi], since the OS permission dialog is
/// system UI exactly like the biometric prompt: without that, a lifecycle
/// report the dialog produces while it's up could be read as a real
/// departure and re-lock the app right after the tap that was meant to
/// turn reminders on. Null when no reminder coordinator was ever started
/// (no scheduler, or a harness that mounts `LunarLogApp` directly).
class RequestNotificationPermissionCallback {
  const RequestNotificationPermissionCallback(this._call);

  final Future<void> Function() _call;

  Future<void> call() => _call();
}

/// This install's stable push-registration device id (Issue #5, U7; R19):
/// read from [settings] if already generated, otherwise minted once and
/// persisted. Split out of [LunarLogRootState._startPushRegistration] so the
/// id-resolution branch is directly unit-testable against a fake
/// [SettingsStore].
@visibleForTesting
Future<String> resolvePushDeviceId(
  SettingsStore settings, {
  String Function() generateId = _defaultGenerateDeviceId,
}) async {
  final existing = await settings.get(SettingsKeys.pushDeviceId);
  if (existing != null && existing.isNotEmpty) return existing;
  final generated = generateId();
  await settings.set(SettingsKeys.pushDeviceId, generated);
  return generated;
}

String _defaultGenerateDeviceId() => const Uuid().v4();

/// `'ios'` or `'android'` — the value `push_devices.platform` stores
/// (Issue #5, U7). Split out for the same reason as [resolvePushDeviceId].
@visibleForTesting
String pushPlatformName() =>
    defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

/// App root and state machine: locked → (credential) → database open →
/// app; or locked forever on repeated declines; or fail-closed screen on
/// any open/quarantine/key failure. The database is opened only after the
/// first successful authentication on gated platforms (AE4).
///
/// Also owns the sync engine's lifecycle (KTD11): built right after the
/// database opens when both [authService] and [syncTransport] are present,
/// awaited-disposed before the database can close.
class LunarLogRoot extends StatefulWidget {
  const LunarLogRoot({
    super.key,
    required this.gate,
    required this.dbOpener,
    this.launchProfileId,
    this.scheduler,
    this.buildDefaultScheduler = false,
    this.authService,
    this.syncTransport,
    this.sharingService,
    this.feedbackService,
    this.accountDeletionService,
    this.ownershipTransferService,
    this.predictionConnectionService,
    this.notificationPreferencesService,
    this.accountExportRemoteSource,
    this.supabaseClient,
    this.inviteLinks,
    this.initialInviteCode,
    this.initialInviteProfileId,
    this.initialInviteKind,
    this.syncEngineBuilder = defaultSyncEngineBuilder,
    this.deleteLocalDatabase = startup.deleteLocalDatabase,
    this.isWeb = kIsWeb,
    this.inactivityTimeout = kDefaultInactivityTimeout,
    this.inactivityTimerFactory = defaultInactivityTimerFactory,
  });

  final AppGate gate;

  /// Opens (and never quarantines silently — throws U2's typed errors).
  final Future<LunarLogDatabase> Function() dbOpener;

  /// Initial launch payload for the seam (U8 sets this for real).
  final String? launchProfileId;

  /// Reminder scheduler (U8); null disables reminders entirely.
  final ReminderScheduler? scheduler;

  /// When true and no [scheduler] is injected, the composition factory
  /// builds the platform default (with its settings store) after the
  /// database opens. `main.dart` sets this for production; tests leave it
  /// false so they get no scheduler unless they inject one.
  final bool buildDefaultScheduler;

  /// Account auth service (U4), started by the bootstrap before the first
  /// frame; null when the build has no Supabase configuration (KTD11), in
  /// which case no account UI is provided at all.
  final AuthService? authService;

  /// Cloud sync transport (U10); null together with [authService] when the
  /// build has no Supabase configuration. The engine is built only when
  /// both are present (KTD11).
  final SyncTransport? syncTransport;

  final SharingService? sharingService;

  /// In-app feedback service (Issue #6, U6), injectable for tests. When
  /// null (and a Supabase client is present) the composition factory
  /// constructs the production [SupabaseFeedbackService].
  final FeedbackService? feedbackService;

  /// Account deletion seam (#17 U4; KTD8), injectable for tests. When null
  /// (and [supabaseClient] is present) the composition factory constructs
  /// the production [SupabaseAccountDeletionService], exactly as it does
  /// for [sharingService] - see issue #76/PR #83, the precedent behind
  /// building both in the same place a `SupabaseClient` is in scope.
  final AccountDeletionService? accountDeletionService;

  /// Child ownership transfer seam (Issue #4, U7), injectable for tests.
  /// When null (and [supabaseClient] is present) the composition factory
  /// constructs the production [SupabaseOwnershipTransferService] — see
  /// issue #76/PR #83, the precedent behind building both in the same place
  /// a `SupabaseClient` is in scope.
  final OwnershipTransferService? ownershipTransferService;

  /// Prediction-only connection seam (Issue #151), injectable for tests.
  /// When null (and [supabaseClient] is present) the composition factory
  /// constructs the production [SupabasePredictionConnectionService] - same
  /// KTD8 precedent.
  final PredictionConnectionService? predictionConnectionService;

  /// Caregiver alert preference service (Issue #5, U6/U8), injectable for
  /// tests. When null the composition factory constructs the production
  /// [SupabaseNotificationPreferencesService] only when push is enabled and
  /// a Supabase client is present (R17) - an unconfigured build never
  /// provides one, so Manage guardians' Notifications tile is absent with
  /// zero conditionals in the caller.
  final NotificationPreferencesService? notificationPreferencesService;

  /// Server-side export seam (Issue #248), injectable for tests. When null
  /// (and [supabaseClient] is present) the composition factory constructs
  /// the production [SupabaseAccountExportRemoteSource] - same KTD8
  /// precedent.
  final AccountExportRemoteSource? accountExportRemoteSource;

  /// The Supabase client from the successful bootstrap. When present it is
  /// handed to the composition factory, which constructs the production
  /// [SupabaseSharingService], [SupabaseFeedbackService],
  /// [SupabaseAccountDeletionService], [SupabaseOwnershipTransferService],
  /// [SupabasePredictionConnectionService], and
  /// [SupabaseAccountExportRemoteSource] (unless each was injected), so
  /// those features are live in production builds. The root itself still
  /// constructs the [RealtimeSyncCoordinator] alongside the sync engine.
  final SupabaseClient? supabaseClient;

  /// `lunarlog://invite?code=...` links — or their HTTPS universal-link twin
  /// `https://<domain>/invite?code=...` (issue #129) — filtered upstream by
  /// main.dart. Null in tests and unconfigured builds.
  final Stream<Uri>? inviteLinks;

  /// The invite code from a cold-start link, if any (R9: the link is
  /// latched across the sign-in gate).
  final String? initialInviteCode;

  /// The `profile` parameter of the cold-start invite link, if any.
  final String? initialInviteProfileId;

  /// The `kind` parameter of the cold-start invite link, if any (`claim`
  /// for a child-ownership-transfer link; U10) — passed through to
  /// [LunarLogApp.initialInviteKind].
  final String? initialInviteKind;

  /// Test seam: how the engine is built once the database is open.
  @visibleForTesting
  final SyncEngineBuilder syncEngineBuilder;

  /// Device-reset primitive (KTD16), injectable for tests. On native the
  /// default deletes this install's database file and siblings; on web
  /// ([isWeb]) it does not run and the database is wiped table by table
  /// instead.
  final Future<void> Function() deleteLocalDatabase;
  final bool isWeb;

  final Duration inactivityTimeout;
  final InactivityTimerFactory inactivityTimerFactory;

  @override
  State<LunarLogRoot> createState() => LunarLogRootState();
}

/// Public so [resetDevice] is documented API; tests reach it through the
/// provided [DeviceResetCallback] rather than the state object.
class LunarLogRootState extends State<LunarLogRoot> {
  late final GateController _gate;
  LunarLogDatabase? _db;
  SyncEngine? _syncEngine;

  /// The composition bundle handed to [LunarLogApp]. Built after the database
  /// opens (KTD7), with or without a Supabase client, and cleared on engine
  /// disposal so the widget never sees a bundle bound to a closed database.
  AppDependencies? _deps;
  RealtimeSyncCoordinator? _realtimeCoordinator;
  PushRegistrationCoordinator? _pushCoordinator;

  /// The app subtree's teardown (reminder coordinator disposal), captured
  /// when [LunarLogApp] unmounts so a device reset (KTD16) can await it
  /// before closing the database.
  Future<void>? _appTeardown;
  Object? _error;
  bool _opening = false;
  bool _firstUnlockAttempted = false;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _gate = GateController(
      gate: widget.gate,
      inactivityTimeout: widget.inactivityTimeout,
      inactivityTimerFactory: widget.inactivityTimerFactory,
    )..addListener(_onGateChanged);
    if (widget.launchProfileId != null) {
      _gate.setPendingLaunchProfileId(widget.launchProfileId);
    }
    unawaited(applyPlatformPrivacyProtections());
    if (_gate.unlocked) {
      // Un-gated platform (web): open straight away.
      unawaited(_openDatabase());
    } else {
      // Cold start presents the credential automatically (F3); every later
      // prompt after a decline or re-lock is an explicit retry tap.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _firstUnlockAttempted || !_gate.locked) return;
        _firstUnlockAttempted = true;
        unawaited(_gate.unlock());
      });
    }
  }

  Future<void> _openDatabase() async {
    if (_opening || _db != null || _error != null) return;
    _opening = true;
    try {
      final db = await widget.dbOpener();
      _db = db;
      // AC2: the settings store is built in `lib/composition/`, never here.
      _gate.attachSettings(buildCompositionSettingsStore(db));
      _startSyncEngine(db);
    } catch (error, stackTrace) {
      // U7 (KTD12): the message can embed a database path or SQL; log the
      // type only and let Sentry (a no-op without a DSN) keep the scrubbed
      // exception and stack.
      debugPrint('lunarlog startup failed: ${error.runtimeType}');
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
      _error = error;
    } finally {
      _opening = false;
      if (mounted) setState(() {});
    }
  }

  /// KTD11: the engine exists only when the build has both collaborators;
  /// null collaborators build nothing, so harnesses without them are
  /// untouched. The composition factory (`buildAppDependencies`) builds the
  /// bundle, including every Supabase-backed service. AC2: the realtime
  /// and push coordinators are constructed in `lib/composition/` and only
  /// started here, next to the engine they drive.
  void _startSyncEngine(LunarLogDatabase db) {
    final authService = widget.authService;
    final transport = widget.syncTransport;
    final client = widget.supabaseClient;
    SyncEngine? engine = _syncEngine;
    if (authService != null && transport != null && engine == null) {
      if (!mounted) return;
      engine = widget.syncEngineBuilder(
        db: db,
        authService: authService,
        transport: transport,
        gate: _gate,
      );
      _syncEngine = engine;
      engine.start();

      if (client != null) {
        final coordinator = buildRealtimeSyncCoordinator(
          client: client,
          syncEngine: engine,
          storage: db.storage,
          auth: authService,
        );
        _realtimeCoordinator = coordinator;
        coordinator.start();

        // Issue #5, U7/U8: push registration and the Notifications screen.
        // Gated by AppConfig.hasPush (R17, R18) — an unconfigured or web
        // build never constructs any of this, so it never touches
        // firebase_messaging and Manage guardians shows no Notifications tile.
        if (AppConfig.hasPush && !widget.isWeb) {
          unawaited(_startPushRegistration(db, authService, client));
        }
      }
    }
    // KTD7: the bundle is built once the database is open, client or not —
    // the local-only (unconfigured) build still needs every drift-backed
    // contract. The Supabase-backed services resolve to null without a
    // client, preserving the unconfigured-build posture (R14).
    _deps = buildAppDependencies(
      db: db,
      client: client,
      authService: authService,
      syncEngine: engine,
      sharingService: widget.sharingService,
      feedbackService: widget.feedbackService,
      accountDeletionService: widget.accountDeletionService,
      ownershipTransferService: widget.ownershipTransferService,
      predictionConnectionService: widget.predictionConnectionService,
      notificationPreferencesService: widget.notificationPreferencesService,
      accountExportRemoteSource: widget.accountExportRemoteSource,
      // The shared import coordinator resolves the acting user live, so its
      // view-only guard and sharing notice see the signed-in account — the
      // same source `LunarLogApp`'s own fallback bundle uses.
      currentUserIdProvider: () => authService?.currentUserId,
      scheduler: widget.scheduler,
      // R17/R18: push-backed services exist only when push is configured and
      // this is not web — the same gate `_startPushRegistration` uses below.
      pushEnabled: AppConfig.hasPush && !widget.isWeb,
      // The shell owns the platform default scheduler; build it here, with
      // the settings store, rather than constructing a throwaway in main.
      buildDefaultScheduler: widget.buildDefaultScheduler,
    );
  }

  /// Resolves (generating and persisting once) this install's stable
  /// push-registration device id, then starts the coordinator (R19). Split
  /// from [resolvePushDeviceId] and [pushPlatformName] so this method's own
  /// branching stays low — the id-resolution and platform-name decisions are
  /// unit-tested directly, since this method itself only ever runs behind
  /// `AppConfig.hasPush`, which is always false under `flutter test`.
  Future<void> _startPushRegistration(
    LunarLogDatabase db,
    AuthService authService,
    SupabaseClient client,
  ) async {
    // AC2: the settings store and the coordinator are built in
    // `lib/composition/`; this method only resolves the device id and
    // starts the returned instance.
    final deviceId = await resolvePushDeviceId(
        buildCompositionSettingsStore(db));
    if (!mounted) return;

    final coordinator = buildPushRegistrationCoordinator(
      client: client,
      deviceId: deviceId,
      platform: pushPlatformName(),
      authStates: authService.states,
      currentAuthState: () => authService.state,
      onTap: _gate.setPendingLaunchProfileId,
    );
    _pushCoordinator = coordinator;
    await coordinator.start();
  }

  /// Stops the engine and waits for its in-flight batch or page, so the
  /// database can be closed afterwards (KTD11). The realtime coordinator
  /// goes first: it can still request syncs. The first step of a device
  /// reset (KTD16): call it, unmount the app, await [_awaitAppTeardown],
  /// then close the database.
  Future<void> _disposeSyncEngine() async {
    final coordinator = _realtimeCoordinator;
    _realtimeCoordinator = null;
    await coordinator?.dispose();
    final pushCoordinator = _pushCoordinator;
    _pushCoordinator = null;
    await pushCoordinator?.dispose();
    _deps = null;
    final engine = _syncEngine;
    _syncEngine = null;
    await engine?.dispose();
  }

  /// Waits for the unmounted app subtree's asynchronous teardown (the
  /// reminder coordinator), if one was captured.
  Future<void> _awaitAppTeardown() async {
    final teardown = _appTeardown;
    _appTeardown = null;
    await teardown;
  }

  /// Ordered teardown on root disposal: engine first (it is the only thing
  /// that queries the database on its own), then the app subtree's
  /// asynchronous disposal, which the framework already unmounted.
  Future<void> _teardown() async {
    await _disposeSyncEngine();
    await _awaitAppTeardown();
  }

  void _onGateChanged() {
    // AE4: nothing touches the database until a credential was accepted.
    // During a reset the database is deliberately closed; the reset itself
    // reopens it once the file and key are gone (KTD16).
    if (_gate.unlocked && _db == null && _error == null && !_resetting) {
      unawaited(_openDatabase());
    }
    if (mounted) setState(() {});
  }

  /// KTD16: the one destructive path. In order: await the engine's
  /// disposal; drop the database from the tree and await a frame so
  /// [LunarLogApp] (its coordinator, controllers, repository streams and
  /// the gate's settings watch) has unmounted and nothing can query the
  /// closing database; await that subtree's asynchronous teardown; wipe
  /// (web) and close the database; on native delete the file and its
  /// siblings *then* the key, so a crash in between can never leave a keyed
  /// file that would quarantine the next open; sign the session out locally
  /// and on the server — best effort, so its failure never skips a local
  /// step (the local session is removed by the service regardless of the
  /// server's answer) — *before* the reopen, so the fresh database's first
  /// sync cycle never sees the account being signed out and binds to it;
  /// finally reopen through `dbOpener` (which mints a fresh key) and start
  /// a fresh engine.
  ///
  /// A second call while one is running is ignored. A local step failing
  /// fails closed: the root shows the fail-closed screen rather than
  /// reopening over a half-reset install.
  Future<void> resetDevice() async {
    if (_resetting) return;
    _resetting = true;
    try {
      // #1 (review fix): explicitly remove this device's push registration
      // while the session is still authenticated - before _disposeSyncEngine
      // below disposes the coordinator (cancelling its auth-state
      // subscription, so it would otherwise never see the sign-out that
      // follows) and before _signOutLocally clears the session (after which
      // any registry call would run as anon and RLS would silently deny it).
      await _pushCoordinator?.removeRegistration();
      await _disposeSyncEngine();
      final db = _db;
      await _detachDatabaseFromTree(db);
      await _awaitAppTeardown();
      final deleted = await _deleteDatabase(db);
      if (!deleted) return;
      await _signOutLocally();
      // Per-session diagnostics must not cross the account boundary this
      // reset draws: on a shared device, a support ticket filed by whoever
      // signs in next must never carry breadcrumbs recorded under the
      // family that just signed out.
      defaultBreadcrumbLog.clear();
      if (mounted) await _openDatabase();
    } finally {
      _resetting = false;
    }
  }

  /// Drops [db] from the tree (if it was open) and awaits a frame so
  /// [LunarLogApp] and everything under it has unmounted and nothing can
  /// query the closing database. First step of [resetDevice] after the
  /// sync engine is disposed.
  Future<void> _detachDatabaseFromTree(LunarLogDatabase? db) async {
    if (db == null) return;
    if (mounted) setState(() => _db = null);
    await WidgetsBinding.instance.endOfFrame;
  }

  /// Wipes (web) and closes [db], then on native deletes the database file
  /// and its siblings. Returns whether the step succeeded; on failure it
  /// records `_error` (fail-closed) and the caller must stop [resetDevice]
  /// before sign-out and reopen.
  Future<bool> _deleteDatabase(LunarLogDatabase? db) async {
    try {
      if (db != null) {
        if (widget.isWeb) await db.wipeAllData();
        await db.close();
      }
      if (!widget.isWeb) {
        await widget.deleteLocalDatabase();
      }
      return true;
    } catch (error, stackTrace) {
      // U7 (KTD12): the message can embed a database path or SQL — the
      // delete step throws path-bearing FileSystemExceptions out of
      // lib/startup as well as SQL-bearing drift/sqlite errors; log the
      // type only and let Sentry (a no-op without a DSN) keep the scrubbed
      // exception and stack. The scrubber reduces these to the type name
      // too (issue #97), so nothing leaves the device either way.
      debugPrint('lunarlog reset failed: ${error.runtimeType}');
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
      _error = error;
      if (mounted) setState(() {});
      return false;
    }
  }

  /// Local-only sign-out, run *before* the reopen so the fresh database's
  /// first sync cycle never sees the account being signed out and binds to
  /// it. `AuthSignOutScope.local` clears only this device's session; it does
  /// **not** revoke sessions on the user's other devices. The call can still
  /// throw (network or plugin failure) — the catch swallows it so the reset
  /// always completes, logging the failure rather than surfacing it.
  Future<void> _signOutLocally() async {
    final auth = widget.authService;
    if (auth == null) return;
    try {
      await auth.signOut(scope: AuthSignOutScope.local);
    } catch (error) {
      debugPrint(
          'lunarlog reset: local sign-out failed (${error.runtimeType})');
    }
  }

  @override
  void dispose() {
    // The engine detaches from the gate synchronously (before its first
    // await), so this ordering keeps the listener removal ahead of the
    // controller's disposal; the rest of the teardown completes on its own.
    unawaited(_teardown());
    _gate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_error != null) {
      content = FailClosedApp(error: _error!);
    } else if (_db != null && _deps != null) {
      // AC1: the production path always passes the bundle — no separate
      // scheduler/auth/engine params.
      content = LunarLogApp(
        db: _db!,
        dependencies: _deps!,
        inviteLinks: widget.inviteLinks,
        initialInviteCode: widget.initialInviteCode,
        initialInviteProfileId: widget.initialInviteProfileId,
        initialInviteKind: widget.initialInviteKind,
        onTeardown: (done) => _appTeardown = done,
      );
    } else if (_gate.locked) {
      // Behind the lock before the first unlock: a static, data-free
      // placeholder — nothing renders, not even a spinner.
      content = const MaterialApp(home: Scaffold(body: SizedBox.expand()));
    } else {
      content = const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    // The shell (Stack/Listener) renders *above* the content's
    // MaterialApp, so nothing else provides a text direction — not even in
    // the real app, where runApp() has no Directionality ancestor either.
    return ChangeNotifierProvider<GateController>.value(
      value: _gate,
      child: Provider<DeviceResetCallback>.value(
        value: resetDevice,
        updateShouldNotify: (_, _) => false,
        child: Provider<RemovePushRegistrationCallback>.value(
          value: _removePushRegistrationCallback,
          updateShouldNotify: (_, _) => false,
          child: Provider<RemoveAllPushRegistrationsCallback>.value(
            value: _removeAllPushRegistrationsCallback,
            updateShouldNotify: (_, _) => false,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: GateShell(controller: _gate, child: content),
            ),
          ),
        ),
      ),
    );
  }

  // The two getters below are split out of build() (rather than inlined, as
  // RemovePushRegistrationCallback's originally was) so each null-aware
  // `_pushCoordinator?....() ?? Future.value()` closure's own decision point
  // scores against its own tiny method under the CRAP gate (tool/quality/
  // crap_gate.dart) instead of compounding onto build()'s own already-large
  // complexity/coverage budget - `_pushCoordinator` is always null under
  // `flutter test` (AppConfig.hasPush is compile-time false there), so
  // neither closure body can ever be driven to full coverage by this
  // suite, and build() is exactly the kind of large, branch-heavy method
  // where one more permanently-uncovered branch tips its CRAP score over
  // the gate's threshold.

  RemovePushRegistrationCallback get _removePushRegistrationCallback =>
      RemovePushRegistrationCallback(
        () async => _pushCoordinator?.removeRegistration() ?? Future.value(),
      );

  RemoveAllPushRegistrationsCallback get _removeAllPushRegistrationsCallback =>
      RemoveAllPushRegistrationsCallback(
        () async =>
            _pushCoordinator?.removeAllRegistrations() ?? Future.value(),
      );
}

/// Wraps the app content with the activity listener and the lock/cover
/// layers. Content is kept offstage and input-blocked while hidden so no
/// data paints and no stray tap reaches it.
class GateShell extends StatelessWidget {
  const GateShell({super.key, required this.controller, required this.child});

  final GateController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final gate = context.watch<GateController>();
    final hidden = gate.locked || gate.obscured;
    return Listener(
      onPointerDown: (_) => gate.noteActivity(),
      onPointerMove: (_) => gate.noteActivity(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AbsorbPointer(
            absorbing: hidden,
            child: Visibility(
              visible: !hidden,
              maintainState: true,
              child: child,
            ),
          ),
          if (gate.obscured && !gate.locked) const PrivacyCover(),
          if (gate.locked) LockScreen(controller: controller),
        ],
      ),
    );
  }
}

/// Opaque cover shown whenever the lifecycle is not resumed: the
/// app-switcher snapshot sees this, never data (R7).
class PrivacyCover extends StatelessWidget {
  const PrivacyCover({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      key: ValueKey('privacy-cover'),
      // Deliberate literal (issue #176): opaque black regardless of theme —
      // this is what the app-switcher snapshot must show, never a theme
      // role (which a future dark-theme tweak could lighten).
      color: Color(0xFF000000),
      child: SizedBox.expand(),
    );
  }
}
