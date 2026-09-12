/// App composition root: consumes the [AppDependencies] bundle — built by
/// the composition module (`lib/composition/app_dependencies.dart`) and
/// passed by `LunarLogRoot` — and provides those contracts plus the profile
/// controller (KTD4), the reminder coordinator (KTD7/U8) and the web
/// guardrails (KTD9). Issue #418 (AC1): this widget takes exactly one
/// injection idiom — the bundle, always supplied by the production path.
/// Tests build the bundle explicitly via `buildAppDependencies` (see
/// `test/composition/app_dependencies_test.dart`); there is no implicit
/// fallback construction here. Lifecycle coordinators below are consumed
/// from `lib/composition/` builders (AC2), never constructed inline.
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/composition/app_dependencies.dart';
import 'package:lunarlog/config.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/notifications/reminder_action_executor.dart';
import 'package:lunarlog/data/notifications/reminder_coordinator.dart';
import 'package:lunarlog/data/notifications/reminder_window_publisher.dart';
import 'package:lunarlog/domain/health/health_flow_write_coordinator.dart';
import 'package:lunarlog/domain/account/account_deletion_service.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/export/account_export_remote_source.dart';
import 'package:lunarlog/domain/export/account_export_writer.dart';
import 'package:lunarlog/domain/export/csv_export_writer.dart';
import 'package:lunarlog/domain/export/fhir_bundle_writer.dart';
import 'package:lunarlog/domain/feedback/device_diagnostics_collector.dart';
import 'package:lunarlog/domain/import/account_import_coordinator.dart';
import 'package:lunarlog/domain/import/import_file_reader.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/onboarding/onboarding_cycle_answers.dart';
import 'package:lunarlog/domain/repositories/activity_feed_repository.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/sharing/prediction_projection_publisher.dart';
import 'package:lunarlog/domain/notifications/notification_preferences_service.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/care_content_repository.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/domain/notifications/reminder_payload.dart';
import 'package:lunarlog/domain/notifications/reminder_scheduler.dart';
import 'package:lunarlog/domain/notifications/reminder_window_remote.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/domain/util/timezone.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/device_reset_callback.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/domain/sync/local_row_counts.dart'
    show LocalRowCounter;
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/routes.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart'
    show confirmedHealthSyncUserId;
import 'package:lunarlog/observability/sentry_bootstrap.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_home_gate.dart';
import 'package:lunarlog/ui/sharing/accept_invite_sheet.dart';
import 'package:lunarlog/ui/sharing/accept_prediction_connection_sheet.dart';
import 'package:lunarlog/ui/sharing/claim_profile_sheet.dart';
import 'package:lunarlog/ui/sharing/prediction_connection_calendar_screen.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:lunarlog/ui/web/dev_banner.dart';
import 'package:provider/provider.dart';

class LunarLogApp extends StatefulWidget {
  const LunarLogApp({
    super.key,
    required this.db,
    required this.dependencies,
    this.inviteLinks,
    this.initialInviteCode,
    this.initialInviteProfileId,
    this.initialInviteKind,
    this.onTeardown,
    this.resetDevice,
    this.removePushRegistration,
    this.removeAllPushRegistrations,
    this.showWebBanner = kIsWeb,
  });

  final LunarLogDatabase db;

  /// The dependency bundle, built by the composition module
  /// (`buildAppDependencies`) and supplied by `LunarLogRoot` once the
  /// database is open (Issue #418, AC1: the single injection idiom).
  /// Production always passes it; tests build it explicitly via
  /// `buildAppDependencies` with the collaborators under test.
  final AppDependencies dependencies;

  /// Test-only construction path (Issue #418, AC1): builds [dependencies]
  /// from individual collaborators via `buildAppDependencies`, so widget
  /// tests can mount this widget without a `LunarLogRoot`. Explicit and
  /// documented — production never uses this; `LunarLogRoot` always passes
  /// a pre-built bundle to the default constructor above.
  @visibleForTesting
  factory LunarLogApp.withCollaborators({
    Key? key,
    required LunarLogDatabase db,
    AuthService? authService,
    SyncEngine? syncEngine,
    SharingService? sharingService,
    FeedbackService? feedbackService,
    AccountDeletionService? accountDeletionService,
    OwnershipTransferService? ownershipTransferService,
    PredictionConnectionService? predictionConnectionService,
    NotificationPreferencesService? notificationPreferencesService,
    AccountExportRemoteSource? accountExportRemoteSource,
    ReminderWindowRemote? reminderWindowUpsert,
    ReminderScheduler? scheduler,
    Stream<Uri>? inviteLinks,
    String? initialInviteCode,
    String? initialInviteProfileId,
    String? initialInviteKind,
    void Function(Future<void> teardown)? onTeardown,
    DeviceResetCallback? resetDevice,
    RemovePushRegistrationCallback? removePushRegistration,
    RemoveAllPushRegistrationsCallback? removeAllPushRegistrations,
    bool showWebBanner = kIsWeb,
  }) =>
      LunarLogApp(
        key: key,
        db: db,
        dependencies: buildAppDependencies(
          db: db,
          authService: authService,
          syncEngine: syncEngine,
          sharingService: sharingService,
          feedbackService: feedbackService,
          accountDeletionService: accountDeletionService,
          ownershipTransferService: ownershipTransferService,
          predictionConnectionService: predictionConnectionService,
          notificationPreferencesService: notificationPreferencesService,
          accountExportRemoteSource: accountExportRemoteSource,
          reminderWindowUpsert: reminderWindowUpsert,
          scheduler: scheduler,
          currentUserIdProvider: () => authService?.currentUserId,
          pushEnabled: AppConfig.hasPush && !kIsWeb,
          buildDefaultScheduler: false,
        ),
        inviteLinks: inviteLinks,
        initialInviteCode: initialInviteCode,
        initialInviteProfileId: initialInviteProfileId,
        initialInviteKind: initialInviteKind,
        onTeardown: onTeardown,
        resetDevice: resetDevice,
        removePushRegistration: removePushRegistration,
        removeAllPushRegistrations: removeAllPushRegistrations,
        showWebBanner: showWebBanner,
      );

  /// `lunarlog://invite?code=...` links — or their HTTPS universal-link twin
  /// `https://<domain>/invite?code=...` (issue #129) — filtered by main.dart
  /// (or injected by tests). When present and the bundle carries a sharing
  /// service, an incoming link presents [AcceptInviteSheet] - after sign-in
  /// if the recipient is not authenticated yet (the code is latched across
  /// the gate in between).
  final Stream<Uri>? inviteLinks;

  /// The invite code from a cold-start link, if any (R9).
  final String? initialInviteCode;

  /// The `profile` parameter of the cold-start invite link, if any.
  final String? initialInviteProfileId;

  /// The `kind` parameter of the cold-start invite link, if any (`claim`
  /// routes to [ClaimProfileSheet] instead of [AcceptInviteSheet]; U10).
  final String? initialInviteKind;

  /// Receives this widget's asynchronous teardown (the reminder
  /// coordinator's disposal) when it unmounts, so the root can await it
  /// before closing the database (KTD16 prep).
  final void Function(Future<void> teardown)? onTeardown;

  /// The device reset (KTD16). `LunarLogRoot` provides it above this
  /// widget, so it is normally read from the context; an explicit value
  /// (tests) takes precedence. When neither exists the web wipe falls back
  /// to [LunarLogDatabase.wipeAllData] alone.
  final DeviceResetCallback? resetDevice;

  /// Explicit push-device-registration removal (#1 review fix). Same
  /// override shape as [resetDevice]: `LunarLogRoot` provides it above this
  /// widget in production, an explicit value (tests) takes precedence, and
  /// a signed-out flow that has neither simply skips removal (push was
  /// never started).
  final RemovePushRegistrationCallback? removePushRegistration;

  /// Explicit removal of every push registration for the current user,
  /// across every device (round-2 review #9). Same override shape as
  /// [removePushRegistration]: `LunarLogRoot` provides it above this widget
  /// in production, an explicit value (tests) takes precedence, and a
  /// signed-out flow that has neither simply skips it.
  final RemoveAllPushRegistrationsCallback? removeAllPushRegistrations;

  /// KTD9 web guardrail flag; injectable for tests.
  final bool showWebBanner;

  @override
  State<LunarLogApp> createState() => _LunarLogAppState();
}

class _LunarLogAppState extends State<LunarLogApp>
    with WidgetsBindingObserver {
  // The dependency bundle this widget's lifetime is bound to, supplied by
  // the composition root (`LunarLogRoot`). AC1: the single injection idiom
  // — production always passes it; tests build it via `buildAppDependencies`.
  late final AppDependencies _deps;

  // KTD3/R5: one instance of each repository for this widget's lifetime,
  // built once in [initState] from the (stable) database and shared by the
  // reminder coordinator and the provider tree below.
  late final ProfilesRepository _profiles;
  late final DayEntriesRepository _dayEntries;
  late final ObservationsRepository _observations;
  late final CareContentRepository _careContent;
  late final SettingsStore _settings;
  late final CyclePredictionService _prediction;
  late final CycleHistoryService _cycleHistory;
  late final CycleExclusionList _cycleExclusions;
  late final NotificationPermissionState _permissionState;

  /// Issue #218: the profile-modes repository backing the onboarding
  /// birth-control/method persistence seam (`ProfileController` writes
  /// through it; #216's form is the UI half).
  late final ProfileModesRepository _profileModes;

  // Domain-typed contracts `lib/ui` reads instead of constructing the
  // concrete `lib/data` implementations inline (R1/R7/R8). Built once here
  // in [initState] and provided to the tree below.
  late final ProfileGuardiansRepository _profileGuardians;
  late final ActivityFeedRepository _activityFeed;
  late final OnboardingCycleAnswersRecorder _onboardingCycleAnswers;
  late final DeviceDiagnosticsCollector _deviceDiagnostics;
  late final AccountExportWriter _accountExportWriter;
  late final FhirBundleWriter _fhirBundleWriter;
  late final CsvExportWriter _csvExportWriter;
  late final AttachmentSource _attachmentSource;
  late final ImportFileReader _importFileReader;
  late final AccountImportCoordinator _accountImportCoordinator;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  // U2 Approach 1b: allocated once, not per build. `build` re-runs on every
  // `setState` (the invite-link and auth-change paths both trigger one),
  // and Navigator.didUpdateWidget compares observers by identity -- a fresh
  // list on every build would detach and re-attach a new observer each
  // time, discarding any in-flight route transaction.
  late final List<NavigatorObserver> _navigatorObservers =
      sentryNavigatorObservers();
  ReminderCoordinator? _coordinator;

  /// Executes reminder notification action-button taps (Issue #136),
  /// latching them while the device gate is locked (KTD4) and writing on
  /// unlock. Non-null only when a scheduler was provided.
  ReminderActionExecutor? _actionExecutor;

  /// The per-profile reminder configuration store (Issue #136) backing
  /// the coordinator; provided to the tree for the reminder settings
  /// screen. Non-null only when a scheduler was provided.
  ReminderConfigService? _reminderConfigService;
  ReminderWindowPublisher? _reminderWindowPublisher;
  PredictionProjectionPublisher? _predictionProjectionPublisher;
  HealthFlowWriteCoordinator? _healthFlowCoordinator;
  AuthController? _authController;
  StreamSubscription<Uri>? _inviteSub;
  String? _pendingInviteCode;
  String? _profileIdOfPendingInvite;
  String? _pendingInviteKind;
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
    unawaited(resolveCurrentTimeZone());
    // AC1: the one bundle this widget's lifetime is bound to, supplied by
    // the composition root. No fallback construction here.
    _deps = widget.dependencies;
    _profiles = _deps.profiles;
    _dayEntries = _deps.dayEntries;
    _observations = _deps.observations;
    _careContent = _deps.careContent;
    _settings = _deps.settings;
    // Issue #132: the device-local omission list joins both streams, so
    // estimates and history re-derive (and reminders replan) whenever the
    // operator omits, restores, or skips a cycle. Issue #218: the profiles
    // repository joins too, so a profile with onboarding-supplied cycle
    // facts but fewer than three logged cycles gets a provisional
    // prediction (and re-derives whenever the facts are edited).
    _prediction = _deps.prediction;
    _profileModes = _deps.profileModes;
    _cycleHistory = _deps.cycleHistory;
    _cycleExclusions = _deps.cycleExclusions;
    _permissionState = NotificationPermissionState(
      NotificationAvailability.available,
    );
    // R1/R7/R8: the concrete implementations `lib/ui` used to construct
    // inline, built once here and provided to the tree as domain contracts.
    _profileGuardians = _deps.profileGuardians;
    _activityFeed = _deps.activityFeed;
    _onboardingCycleAnswers = _deps.onboardingCycleAnswers;
    _deviceDiagnostics = _deps.deviceDiagnostics;
    _accountExportWriter = _deps.accountExportWriter;
    _fhirBundleWriter = _deps.fhirBundleWriter;
    _csvExportWriter = _deps.csvExportWriter;
    _attachmentSource = _deps.attachmentSource;
    _importFileReader = _deps.importFileReader;
    _accountImportCoordinator = _deps.accountImportCoordinator;
    _initAuthController();
    _initHealthFlowWriter();
    _buildReminderCoordinator();
    _initReminderWindowPublisher();
    // Issue #373: started on its own, never nested inside the push-gated
    // reminder publisher above - the prediction service is constructed on
    // every build with a Supabase client (web and no-push included), so
    // its publisher must start on every one of them too.
    _startPredictionProjectionPublisher();
    WidgetsBinding.instance.addObserver(this);
    // U8/R9: invite deep links. The cold-start code is latched here; live
    // links arrive on the stream. Presentation waits for a signed-in
    // session when needed.
    _inviteSub = widget.inviteLinks?.listen(_handleInviteLink);
    _scheduleInitialInvitePresentation();
  }

  /// Wires [_authController] from [LunarLogApp.authService], if the shell
  /// provided one. Extracted out of [initState] (issue #168 CRAP gate) so
  /// this branching doesn't count against that method's complexity.
  void _initAuthController() {
    final authService = _deps.authService;
    if (authService == null) return;
    final controller = AuthController(authService: authService)
      ..addListener(_onAuthChanged);
    _authController = controller;
    if (controller.signedIn) _clearAwaitingConfirmation();
  }

  /// Reminders start only when the shell passes a scheduler (main.dart
  /// does on production platforms). Without one — e.g. in widget tests —
  /// no notification machinery is touched at all. Extracted out of
  /// [initState] (issue #168 CRAP gate) so this branching doesn't count
  /// against that method's complexity.
  void _buildReminderCoordinator() {
    // R9: the scheduler (and its constructor-injected settings store) comes
    // from the composition bundle. Null disables reminders entirely.
    final scheduler = _deps.scheduler;
    if (scheduler == null) return;
    // Issue #136: the per-profile reminder configuration service and the
    // action executor live exactly as long as the coordinator does — no
    // scheduler (widget-test harnesses, web) means neither is built and
    // no provider is registered. AC2: construction lives in
    // `lib/composition/`; this method only wires the gate callbacks.
    final configService = buildReminderConfigService(_settings);
    _reminderConfigService = configService;
    final gate = context.read<GateController?>();
    _actionExecutor = buildReminderActionExecutor(
      dayEntries: _dayEntries,
      observations: _observations,
      configService: configService,
      isUnlocked: gate == null ? null : () => gate.unlocked,
      addUnlockListener: gate?.addListener,
      removeUnlockListener: gate?.removeListener,
    );
    // The coordinator is constructed synchronously, right here, so the
    // provider tree below (`build`'s `_coordinator != null` check) sees a
    // non-null instance on this very first build. Only the actual
    // `start()` call is deferred to a post-frame callback (see
    // [_scheduleReminderStart]).
    final coordinator = buildReminderCoordinator(
      scheduler: scheduler,
      permissionState: _permissionState,
      activeProfiles: _profiles.watch(),
      predictionFor: _prediction.watch,
      localSettings: configService,
      // Issue #183: the raw profile_modes birth-control row feeds the
      // adherence kinds. The watcher rides the drift row stream, so a
      // recorded-method change (onboarding answer, profile-settings edit,
      // sync pull) replans and re-routes the reminder onto the new
      // method's cadence.
      birthControlStateFor: (profileId) => widget.db.storage
          .watchProfileMode(profileId)
          .map((row) => row == null
              ? null
              : (
                    method: row.birthControlMethod,
                    startedOn: row.birthControlStartedOn,
                    stoppedOn: row.birthControlStoppedOn,
                  )),
    );
    _coordinator = coordinator;
    _scheduleReminderStart(coordinator);
  }

  /// Defers `coordinator.start()` (via [_startReminders]) to a post-frame
  /// callback. Extracted out of [_buildReminderCoordinator] (issue #168
  /// CRAP gate) so this branching doesn't count against that method's
  /// complexity.
  void _scheduleReminderStart(ReminderCoordinator coordinator) {
    final gate = context.read<GateController?>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_startReminders(coordinator, gate));
    });
  }

  /// Issue #5, U6/U8: keep the server's reminder-window snapshot in step
  /// with the local prediction. Both collaborators come from the same
  /// AppConfig.hasPush gate (app_lifecycle.dart), so this either starts
  /// with both present or not at all - R17 holds with zero conditionals
  /// beyond this null check. Extracted out of [initState] (issue #168
  /// CRAP gate) so this branching doesn't count against that method's
  /// complexity.
  void _initReminderWindowPublisher() {
    // AC2: construction lives in `lib/composition/`; this method only
    // starts the returned instance.
    final publisher = buildReminderWindowPublisher(
      notificationPreferencesService: _deps.notificationPreferencesService,
      reminderWindowUpsert: _deps.reminderWindowUpsert,
      activeProfiles: _profiles.watch(),
      predictionFor: _prediction.watch,
      isSignedIn: _isSignedIn,
    );
    if (publisher == null) return;
    _reminderWindowPublisher = publisher;
    publisher.start();
  }

  /// Issue #151: keep the server's derived-phase snapshot in step for the
  /// profiles this account shares predictions OUT. Starts only when a
  /// [PredictionConnectionService] is configured - an unconfigured build
  /// has nothing to publish to and never constructs the publisher, the
  /// same zero-conditional gating the reminder publisher uses. Issue #373:
  /// that is the ONLY gate - it is deliberately not tied to the
  /// `AppConfig.hasPush`/web gate the reminder publisher sits behind,
  /// because the service (and so the whole sharing UI) exists without push.
  void _startPredictionProjectionPublisher() {
    // AC2: construction lives in `lib/composition/`; this method only
    // starts the returned instance.
    final publisher = buildPredictionProjectionPublisher(
      service: _deps.predictionConnectionService,
      activeProfiles: _profiles.watch(),
      predictionFor: _prediction.watch,
      isSignedIn: _isSignedIn,
    );
    if (publisher == null) return;
    _predictionProjectionPublisher = publisher;
    publisher.start();
  }

  /// Issue #373: the sharer's device is the only place a projection can be
  /// computed, and the stream-driven publisher only fires on a prediction
  /// change - so a recipient who redeemed a code while this app was in the
  /// background would otherwise wait for the sharer's next cycle event.
  /// Re-publishing every connected profile on resume bounds that wait to
  /// the sharer's next foreground, cheaply (one narrow select per resume).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_predictionProjectionPublisher?.republishConnected());
  }

  /// Issue #193: the one-way, opt-in, forward-only menstrual-flow write
  /// path. AC2: construction lives in `lib/composition/` (which owns the
  /// iOS-only gating too); this method only starts the returned instance.
  /// Widget-test harnesses and web never get one.
  void _initHealthFlowWriter() {
    final coordinator = buildHealthFlowWriteCoordinator(
      settings: _settings,
      profiles: _profiles,
      dayEntries: _dayEntries,
      observations: _observations,
      guardiansForProfile: _profileGuardians.getForProfile,
      // The Settings picker's own tested resolver (issue #153): null
      // unless a session is actually signed in — the same guard fact both
      // call sites must agree on.
      signedInUserId: () => confirmedHealthSyncUserId(_authController),
      minorBindingAllowed: AppConfig.healthSyncMinorBindingAllowed,
    );
    if (coordinator == null) return;
    _healthFlowCoordinator = coordinator;
    coordinator.start();
  }

  bool _isSignedIn() => _authController?.signedIn ?? false;

  /// Schedules the cold-start invite presentation, if `main.dart` (or a
  /// test) passed an initial invite code. Extracted out of [initState]
  /// (issue #168 CRAP gate) so this branching doesn't count against that
  /// method's complexity.
  void _scheduleInitialInvitePresentation() {
    final initialInviteCode = widget.initialInviteCode;
    if (initialInviteCode == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybePresentInvite(
        initialInviteCode,
        widget.initialInviteProfileId,
        widget.initialInviteKind,
      );
    });
  }

  void _handleInviteLink(Uri uri) {
    if (!mounted) return;
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) return;
    _maybePresentInvite(
      code,
      uri.queryParameters['profile'],
      uri.queryParameters['kind'],
    );
  }

  /// U10: `kind == 'claim'` routes to [ClaimProfileSheet] (needs the
  /// bundle's [OwnershipTransferService]); issue #151: `kind ==
  /// 'prediction'` routes to [AcceptPredictionConnectionSheet] (needs the
  /// bundle's [PredictionConnectionService]); anything else (null or
  /// unrecognised) keeps the ordinary [AcceptInviteSheet] path (needs the
  /// bundle's [SharingService]) unchanged.
  void _maybePresentInvite(String code, String? profileId, String? kind) {
    final isClaim = kind == 'claim';
    final isPrediction = kind == 'prediction';
    final collaboratorPresent = isClaim
        ? _deps.ownershipTransferService != null
        : isPrediction
            ? _deps.predictionConnectionService != null
            : _deps.sharingService != null;
    if (!collaboratorPresent || _inviteSheetOpen) return;
    if (_authController?.signedIn ?? false) {
      _presentSheet(code, profileId, kind);
    } else {
      // R9/R27: an unauthenticated recipient signs in (or creates an
      // account) first; the code (and its kind) stays latched until the
      // session appears.
      setState(() {
        _pendingInviteCode = code;
        _profileIdOfPendingInvite = profileId;
        _pendingInviteKind = kind;
      });
    }
  }

  void _presentSheet(String code, String? profileId, String? kind) {
    if (kind == 'claim') {
      _showClaimSheet(code, profileId);
    } else if (kind == 'prediction') {
      _showPredictionConnectionSheet(code);
    } else {
      _showInviteSheet(code, profileId);
    }
  }

  void _showInviteSheet(String code, String? profileId) {
    final sharing = _deps.sharingService;
    if (sharing == null || _inviteSheetOpen) return;
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) {
      setState(() {
        _pendingInviteCode = code;
        _profileIdOfPendingInvite = profileId;
        _pendingInviteKind = null;
      });
      return;
    }
    _inviteSheetOpen = true;
    setState(() {
      _pendingInviteCode = null;
      _profileIdOfPendingInvite = null;
      _pendingInviteKind = null;
    });
    unawaited(
      // Issue #182: named `AcceptInviteSheet` (kRouteAcceptInviteSheet) so
      // it appears in the Sentry route observer -- previously unnamed, on
      // the reasoning that its content varies per invite (a code and an
      // optional profile), the same shape ProfileDetailScreen's "one name
      // for the screen, whatever data it displays" already covers.
      showModalBottomSheet<void>(
        context: ctx,
        isScrollControlled: true,
        showDragHandle: true,
        routeSettings: const RouteSettings(name: kRouteAcceptInviteSheet),
        builder: (_) => AcceptInviteSheet(
          rawToken: code,
          sharingService: sharing,
          initialProfileId: profileId,
        ),
      ).whenComplete(() => _inviteSheetOpen = false),
    );
  }

  /// U10 (R11/R27): the `kind=claim` counterpart of [_showInviteSheet],
  /// sharing the same [_inviteSheetOpen] re-entrancy guard so only one
  /// invite/claim sheet is ever open at once.
  void _showClaimSheet(String code, String? profileId) {
    final service = _deps.ownershipTransferService;
    if (service == null || _inviteSheetOpen) return;
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) {
      setState(() {
        _pendingInviteCode = code;
        _profileIdOfPendingInvite = profileId;
        _pendingInviteKind = 'claim';
      });
      return;
    }
    _inviteSheetOpen = true;
    setState(() {
      _pendingInviteCode = null;
      _profileIdOfPendingInvite = null;
      _pendingInviteKind = null;
    });
    unawaited(
      // Issue #182: named `ClaimProfileSheet` (kRouteClaimProfileSheet),
      // the kind=claim counterpart of the AcceptInviteSheet naming above.
      showModalBottomSheet<void>(
        context: ctx,
        isScrollControlled: true,
        showDragHandle: true,
        routeSettings: const RouteSettings(name: kRouteClaimProfileSheet),
        builder: (_) => ClaimProfileSheet(
          rawToken: code,
          service: service,
          initialProfileId: profileId,
        ),
      ).whenComplete(() => _inviteSheetOpen = false),
    );
  }

  /// Issue #151: the kind=prediction counterpart of [_showClaimSheet],
  /// sharing the same [_inviteSheetOpen] re-entrancy guard. The cold-start
  /// latch clears `_pendingInviteKind` on the navigator-missing fallback
  /// by passing the kind through from the caller; a deep link arriving
  /// live never latches.
  void _showPredictionConnectionSheet(String code) {
    final service = _deps.predictionConnectionService;
    if (service == null || _inviteSheetOpen) return;
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) {
      setState(() {
        _pendingInviteCode = code;
        _profileIdOfPendingInvite = null;
        _pendingInviteKind = 'prediction';
      });
      return;
    }
    _inviteSheetOpen = true;
    setState(() {
      _pendingInviteCode = null;
      _profileIdOfPendingInvite = null;
      _pendingInviteKind = null;
    });
    unawaited(
      showModalBottomSheet<void>(
        context: ctx,
        isScrollControlled: true,
        showDragHandle: true,
        routeSettings:
            const RouteSettings(name: kRouteAcceptPredictionConnectionSheet),
        builder: (_) => AcceptPredictionConnectionSheet(
          rawToken: code,
          service: service,
          onAccepted: (result) {
            // Push the phase-only calendar for the newly connected
            // profile (the sheet pops itself first).
            final navContext = _navigatorKey.currentContext;
            if (navContext == null) return;
            Navigator.of(navContext).push(
              buildNamedRoute<void>(
                name: kRoutePredictionCalendarScreen,
                builder: (_) => PredictionConnectionCalendarScreen(
                  profileId: result.profileId,
                  profileName: result.profileName,
                  service: service,
                ),
              ),
            );
          },
        ),
      ).whenComplete(() => _inviteSheetOpen = false),
    );
  }

  /// Issue #168: runs the coordinator's automatic startup permission
  /// request (`coordinator.start()`, which now requests the Android
  /// permission unconditionally, same as Darwin already did) inside the
  /// same system-UI window as the explicit, user-triggered re-request in
  /// [_requestNotificationPermission]. Called from a post-frame callback
  /// scheduled in `initState` — never directly from `initState` itself,
  /// because opening a `duringSystemUi` window notifies listeners
  /// synchronously, and `LunarLogRootState` (still mid-build at that point,
  /// since this widget builds inside it) reacts to gate changes with a
  /// bare `setState(() {})`, which throws ("setState() or
  /// markNeedsBuild() called during build"). Deferring past the frame's
  /// build phase avoids that crash while still covering the automatic
  /// prompt the same way as the manual one.
  Future<void> _startReminders(
    ReminderCoordinator coordinator,
    GateController? gate,
  ) {
    Future<void> run() => coordinator.start(
          onLaunchFromNotification: _handleReminderLaunch,
        );
    return gate != null ? gate.duringSystemUi(run) : run();
  }

  /// Issue #136: routes a notification tap. A plain tap keeps the
  /// pre-existing seam — the firing profile's overview opens after the
  /// gate. An action-button tap ("Started"/"Spotting"/"Not yet") goes to
  /// the executor instead, which writes only after the gate unlocks
  /// (KTD4) and never routes.
  void _handleReminderLaunch(ReminderLaunch launch) {
    if (!mounted) return;
    if (launch.isAction) {
      _actionExecutor?.handleAction(launch);
      return;
    }
    context.read<GateController?>()?.setPendingLaunchProfileId(
          launch.profileId,
        );
  }

  /// Issue #168: backs [RequestNotificationPermissionCallback] for the
  /// overview hint's "Turn on reminders" tap. Wrapped in the gate's
  /// system-UI window (like [unlock]/[reauthenticate]) because the OS
  /// permission dialog reports the same backgrounding lifecycle event a
  /// real departure does — without this a denial (or even a grant) could
  /// be read as the operator having left and re-lock the app right after
  /// they tapped the hint.
  Future<void> _requestNotificationPermission() async {
    final coordinator = _coordinator;
    if (coordinator == null) return;
    final gate = context.read<GateController?>();
    if (gate != null) {
      await gate.duringSystemUi(coordinator.requestPermission);
    } else {
      await coordinator.requestPermission();
    }
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
        _presentSheet(code, _profileIdOfPendingInvite, _pendingInviteKind);
      }
    }
  }

  void _clearAwaitingConfirmation() {
    unawaited(_settings.set(SettingsKeys.awaitingConfirmationEmail, ''));
    unawaited(_settings.set(SettingsKeys.awaitingMagicLinkEmail, ''));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inviteSub?.cancel();
    _inviteSub = null;
    _authController?.dispose();
    _authController = null;
    _actionExecutor?.dispose();
    _actionExecutor = null;
    final coordinatorTeardown = _coordinator?.dispose() ?? Future<void>.value();
    _coordinator = null;
    final publisherTeardown =
        _reminderWindowPublisher?.dispose() ?? Future<void>.value();
    final projectionPublisherTeardown =
        _predictionProjectionPublisher?.dispose() ?? Future<void>.value();
    _reminderWindowPublisher = null;
    _predictionProjectionPublisher = null;
    final healthFlowTeardown =
        _healthFlowCoordinator?.dispose() ?? Future<void>.value();
    _healthFlowCoordinator = null;
    final teardown = Future.wait([
      coordinatorTeardown,
      publisherTeardown,
      projectionPublisherTeardown,
      healthFlowTeardown,
    ]).then((_) {});
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
    final syncEngine = _deps.syncEngine;
    final resetDevice = widget.resetDevice ??
        Provider.of<DeviceResetCallback?>(context, listen: false);
    final removePushRegistration = widget.removePushRegistration ??
        Provider.of<RemovePushRegistrationCallback?>(context, listen: false);
    final removeAllPushRegistrations = widget.removeAllPushRegistrations ??
        Provider.of<RemoveAllPushRegistrationsCallback?>(context,
            listen: false);
    return MultiProvider(
      providers: [
        if (authController != null)
          ChangeNotifierProvider<AuthController>.value(value: authController),
        if (resetDevice != null)
          Provider<DeviceResetCallback>.value(
            value: resetDevice,
            updateShouldNotify: (_, _) => false,
          ),
        if (removePushRegistration != null)
          Provider<RemovePushRegistrationCallback>.value(
            value: removePushRegistration,
            updateShouldNotify: (_, _) => false,
          ),
        if (removeAllPushRegistrations != null)
          Provider<RemoveAllPushRegistrationsCallback>.value(
            value: removeAllPushRegistrations,
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
        // R1/R7/R8: domain-typed seams `lib/ui` reads instead of resolving
        // the raw storage object or constructing the concrete `lib/data`
        // implementations itself.
        Provider<ProfileGuardiansRepository>.value(value: _profileGuardians),
        Provider<ActivityFeedRepository>.value(value: _activityFeed),
        Provider<OnboardingCycleAnswersRecorder>.value(
            value: _onboardingCycleAnswers),
        Provider<DeviceDiagnosticsCollector>.value(value: _deviceDiagnostics),
        Provider<AccountExportWriter>.value(value: _accountExportWriter),
        Provider<FhirBundleWriter>.value(value: _fhirBundleWriter),
        Provider<CsvExportWriter>.value(value: _csvExportWriter),
        Provider<AttachmentSource>.value(value: _attachmentSource),
        Provider<ImportFileReader>.value(value: _importFileReader),
        Provider<AccountImportCoordinator>.value(
            value: _accountImportCoordinator),
        if (_deps.sharingService != null)
          Provider<SharingService>.value(value: _deps.sharingService!),
        if (_deps.ownershipTransferService != null)
          Provider<OwnershipTransferService>.value(
              value: _deps.ownershipTransferService!),
        if (_deps.predictionConnectionService != null)
          Provider<PredictionConnectionService>.value(
              value: _deps.predictionConnectionService!),
        if (_predictionProjectionPublisher != null)
          Provider<PredictionProjectionPublisher>.value(
              value: _predictionProjectionPublisher!),
        if (_deps.feedbackService != null)
          Provider<FeedbackService>.value(value: _deps.feedbackService!),
        if (_deps.accountDeletionService != null)
          Provider<AccountDeletionService>.value(
              value: _deps.accountDeletionService!),
        if (_deps.notificationPreferencesService != null)
          Provider<NotificationPreferencesService>.value(
              value: _deps.notificationPreferencesService!),
        if (_deps.accountExportRemoteSource != null)
          Provider<AccountExportRemoteSource>.value(
              value: _deps.accountExportRemoteSource!),
        Provider<ProfilesRepository>.value(value: _profiles),
        Provider<DayEntriesRepository>.value(value: _dayEntries),
        Provider<ObservationsRepository>.value(value: _observations),
        Provider<CareContentRepository>.value(value: _careContent),
        Provider<SettingsStore>.value(value: _settings),
        // Issue #136: the per-profile reminder configuration store. Present
        // whenever reminders are (a scheduler was provided); the reminder
        // settings screen reads and writes through it, and the coordinator
        // replans from its `changes` stream.
        if (_reminderConfigService != null)
          Provider<ReminderConfigService>.value(
            value: _reminderConfigService!,
          ),
        // Issue #218: the onboarding persistence seam for the
        // birth-control-method and goal/mode answers (#216's form calls
        // ProfileController with them; profile-settings editing uses the
        // same repository).
        Provider<ProfileModesRepository>.value(value: _profileModes),
        Provider<CyclePredictionService>.value(value: _prediction),
        Provider<CycleHistoryService>.value(value: _cycleHistory),
        Provider<CycleExclusionList>.value(value: _cycleExclusions),
        // U6 seam: the overview hint reads this; the coordinator updates it
        // from the real permission query (U8).
        ChangeNotifierProvider.value(
          value: _permissionState,
        ),
        // Issue #168: the overview hint's "Turn on reminders" action.
        // `_coordinator` is constructed synchronously in `initState`
        // (before the post-frame callback that calls `_startReminders`
        // even gets scheduled), so it is already non-null by this first
        // build whenever a scheduler was provided; null here (no
        // scheduler) means availability never leaves `available` and the
        // hint the button lives in never renders.
        if (_coordinator != null)
          Provider<RequestNotificationPermissionCallback>.value(
            value: RequestNotificationPermissionCallback(
              _requestNotificationPermission,
            ),
            updateShouldNotify: (_, _) => false,
          ),
        ChangeNotifierProvider(
          create: (context) => ProfileController(
            profilesRepository: context.read<ProfilesRepository>(),
            settingsStore: context.read<SettingsStore>(),
            profileModesRepository: context.read<ProfileModesRepository>(),
          )..load(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        navigatorObservers: _navigatorObservers,
        title: 'lunarlog',
        theme: AppTheme.lightTheme,
        // Issue #160: localization scaffolding. `en` is the only supported
        // locale today; the delegates (AppLocalizations plus Flutter's own
        // material/cupertino/widgets delegates) make every screen's copy
        // resolve through AppLocalizations and date/month names resolve
        // through intl. Adding a locale = adding an ARB + listing it here
        // (via AppLocalizations.supportedLocales).
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // KTD16: the web wipe is the device reset when one is provided.
        builder: (context, child) => WebGuardrails(
          showBanner: widget.showWebBanner,
          onWipe: resetDevice ?? widget.db.wipeAllData,
          navigatorKey: _navigatorKey,
          child: child ?? const SizedBox.shrink(),
        ),
        // U2 Approach 3: `home:` cannot carry a RouteSettings name (it is
        // always built with WidgetsApp.defaultRouteName, `/`, which
        // scrubRouteName's shape check rejects), and `initialRoute`/
        // `onGenerateInitialRoutes` cannot coexist with `home:` (WidgetsApp
        // asserts the two are mutually exclusive). onGenerateRoute is the
        // one mechanism that produces the registered ProfileHomeGate name
        // for the initial route -- guarded to the default route name so it
        // stays exactly that (this app never calls Navigator.pushNamed):
        // returning null for any other name lets Flutter's own
        // unknown-route handling fire instead of silently rendering the
        // home screen under an unrelated route name.
        onGenerateRoute: (settings) => settings.name == Navigator.defaultRouteName
            ? MaterialPageRoute<void>(
                settings: const RouteSettings(name: kRouteProfileHomeGate),
                builder: (_) => const ProfileHomeGate(),
              )
            : null,
      ),
    );
  }
}
