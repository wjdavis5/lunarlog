/// The single place every concrete data-layer implementation is constructed.
///
/// Both composition roots (`lib/main.dart`/`lib/app_lifecycle.dart` and
/// `lib/app.dart`) delegate here: `LunarLogRoot` builds an [AppDependencies]
/// once the database is open and passes it to `LunarLogApp`; `LunarLogApp`
/// falls back to building one from its own (test-injectable) collaborators
/// when none is supplied. `lib/ui` never sees this type — it reads the
/// individual domain contracts from the provider tree.
library;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'package:lunarlog/config.dart';
import 'package:lunarlog/data/account/supabase_account_deletion_service.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/diagnostics/device_diagnostics_collector.dart';
import 'package:lunarlog/data/export/account_export_writer.dart';
import 'package:lunarlog/data/export/csv_export_writer.dart';
import 'package:lunarlog/data/export/fhir_bundle_writer.dart';
import 'package:lunarlog/data/export/supabase_account_export_remote_source.dart';
import 'package:lunarlog/data/feedback/image_picker_attachment_source.dart';
import 'package:lunarlog/data/feedback/supabase_feedback_service.dart';
import 'package:lunarlog/data/health/health_channel.dart';
import 'package:lunarlog/data/health/health_flow_write_coordinator.dart';
import 'package:lunarlog/data/health/health_flow_write_service.dart';
import 'package:lunarlog/data/import/account_importer.dart';
import 'package:lunarlog/data/import/import_file_picker.dart';
import 'package:lunarlog/data/notifications/firebase_push_token_source.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/data/notifications/push_registration_coordinator.dart';
import 'package:lunarlog/data/notifications/reminder_action_executor.dart';
import 'package:lunarlog/data/notifications/reminder_coordinator.dart';
import 'package:lunarlog/data/notifications/reminder_window_publisher.dart';
import 'package:lunarlog/data/notifications/supabase_notification_preferences_service.dart';
import 'package:lunarlog/data/notifications/supabase_push_device_registry.dart';
import 'package:lunarlog/data/notifications/supabase_reminder_window_remote.dart';
import 'package:lunarlog/data/repositories/drift_activity_feed_repository.dart';
import 'package:lunarlog/data/repositories/drift_care_content_repository.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_onboarding_cycle_answers_recorder.dart';
import 'package:lunarlog/data/repositories/drift_profile_modes_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/repositories/drift_profile_guardians_repository.dart';
import 'package:lunarlog/data/sharing/supabase_ownership_transfer_service.dart';
import 'package:lunarlog/data/sharing/supabase_prediction_connection_service.dart';
import 'package:lunarlog/data/sharing/supabase_sharing_service.dart';
import 'package:lunarlog/data/sharing/prediction_projection_publisher.dart';
import 'package:lunarlog/data/sync/realtime_sync_coordinator.dart';
import 'package:lunarlog/domain/account/account_deletion_service.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/export/account_export_remote_source.dart';
import 'package:lunarlog/domain/feedback/device_diagnostics_collector.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/domain/export/account_export_writer.dart';
import 'package:lunarlog/domain/export/csv_export_writer.dart';
import 'package:lunarlog/domain/export/fhir_bundle_writer.dart';
import 'package:lunarlog/domain/import/account_import_coordinator.dart';
import 'package:lunarlog/domain/import/import_file_reader.dart';
import 'package:lunarlog/domain/notifications/notification_preferences_service.dart';
import 'package:lunarlog/domain/notifications/reminder_scheduler.dart';
import 'package:lunarlog/domain/notifications/reminder_window_remote.dart';
import 'package:lunarlog/domain/onboarding/onboarding_cycle_answers.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/activity_feed_repository.dart';
import 'package:lunarlog/domain/repositories/care_content_repository.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/health/health_flow_write_coordinator.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/domain/sharing/prediction_projection_publisher.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';

/// An immutable bundle of the app's data-layer dependencies, typed as domain
/// contracts. The optional cloud fields are null exactly when the build has
/// no Supabase configuration (the unconfigured-build posture, R14).
class AppDependencies {
  AppDependencies({
    required this.profiles,
    required this.dayEntries,
    required this.observations,
    required this.careContent,
    required this.settings,
    required this.profileModes,
    required this.profileGuardians,
    required this.activityFeed,
    required this.onboardingCycleAnswers,
    required this.deviceDiagnostics,
    required this.accountExportWriter,
    required this.fhirBundleWriter,
    required this.csvExportWriter,
    required this.attachmentSource,
    required this.importFileReader,
    required this.accountImportCoordinator,
    required this.prediction,
    required this.cycleHistory,
    required this.cycleExclusions,
    this.authService,
    this.syncEngine,
    this.sharingService,
    this.feedbackService,
    this.accountDeletionService,
    this.ownershipTransferService,
    this.predictionConnectionService,
    this.notificationPreferencesService,
    this.accountExportRemoteSource,
    this.reminderWindowUpsert,
    this.scheduler,
  });

  final ProfilesRepository profiles;
  final DayEntriesRepository dayEntries;
  final ObservationsRepository observations;
  final CareContentRepository careContent;
  final SettingsStore settings;
  final ProfileModesRepository profileModes;
  final ProfileGuardiansRepository profileGuardians;
  final ActivityFeedRepository activityFeed;
  final OnboardingCycleAnswersRecorder onboardingCycleAnswers;
  final DeviceDiagnosticsCollector deviceDiagnostics;
  final AccountExportWriter accountExportWriter;
  final FhirBundleWriter fhirBundleWriter;
  final CsvExportWriter csvExportWriter;
  final AttachmentSource attachmentSource;
  final ImportFileReader importFileReader;
  final AccountImportCoordinator accountImportCoordinator;
  final CyclePredictionService prediction;
  final CycleHistoryService cycleHistory;
  final CycleExclusionList cycleExclusions;

  final AuthService? authService;
  final SyncEngine? syncEngine;
  final SharingService? sharingService;
  final FeedbackService? feedbackService;
  final AccountDeletionService? accountDeletionService;
  final OwnershipTransferService? ownershipTransferService;
  final PredictionConnectionService? predictionConnectionService;
  final NotificationPreferencesService? notificationPreferencesService;
  final AccountExportRemoteSource? accountExportRemoteSource;

  /// Publishes a profile's prediction window to the server (Issue #5). Null
  /// without a push-capable Supabase client.
  final ReminderWindowRemote? reminderWindowUpsert;

  /// The reminder scheduler (R9). Null disables reminders entirely (widget
  /// tests that pass none). The production platform default is built with
  /// its settings store constructor-injected, so no post-construction
  /// mutation is needed.
  final ReminderScheduler? scheduler;
}

/// Builds the bundle from the app's low-level primitives.
///
/// The drift-backed dependencies are always constructed from [db]. The
/// Supabase-backed services are constructed from [client] + [syncEngine]
/// unless an explicit override is supplied (the test seam); every optional
/// field stays null when its inputs are absent, preserving the
/// unconfigured-build posture.
AppDependencies buildAppDependencies({
  required LunarLogDatabase db,
  SupabaseClient? client,
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
  String? Function()? currentUserIdProvider,
  bool pushEnabled = false,
  bool buildDefaultScheduler = false,
}) {
  final storage = db.storage;
  final profiles = DriftProfilesRepository(storage);
  final dayEntries = DriftDayEntriesRepository(storage);
  final observations = DriftObservationsRepository(storage);
  final settings = DriftSettingsStore(storage);
  final profileGuardians = DriftProfileGuardiansRepository(storage);
  final accountImporter = DriftAccountImporter(storage);

  // Issue #418, AC5: client-derived services gate on `client != null &&
  // authService != null` — the old `_startSyncEngine` required auth (and
  // transport, via the engine) alongside the client, not the client alone.
  final cloudEnabled = client != null && authService != null;

  final builtAccountExportRemoteSource = _resolve(
    accountExportRemoteSource,
    cloudEnabled,
    () => SupabaseAccountExportRemoteSource(client: client!),
  );

  return AppDependencies(
    profiles: profiles,
    dayEntries: dayEntries,
    observations: observations,
    careContent: DriftCareContentRepository(storage),
    settings: settings,
    profileModes: DriftProfileModesRepository(storage),
    profileGuardians: profileGuardians,
    activityFeed: DriftActivityFeedRepository(storage),
    onboardingCycleAnswers: DriftOnboardingCycleAnswersRecorder(storage),
    deviceDiagnostics: PlatformDeviceDiagnosticsCollector(),
    accountExportWriter: PlatformAccountExportWriter(
      remoteSource: builtAccountExportRemoteSource,
    ),
    fhirBundleWriter: const PlatformFhirBundleWriter(),
    csvExportWriter: const PlatformCsvExportWriter(),
    attachmentSource: ImagePickerAttachmentSource(),
    importFileReader: const PickImportFileReader(),
    accountImportCoordinator: DriftAccountImportCoordinator(
      profilesRepository: profiles,
      dayEntriesRepository: dayEntries,
      observationsRepository: observations,
      storage: storage,
      guardiansForProfile: profileGuardians.getForProfile,
      currentUserIdProvider: currentUserIdProvider,
      importer: accountImporter,
    ),
    prediction: CyclePredictionService(dayEntries,
        settings: settings, profiles: profiles),
    cycleHistory: CycleHistoryService(dayEntries, settings: settings),
    cycleExclusions: CycleExclusionList(settings),
    authService: authService,
    syncEngine: syncEngine,
    sharingService: _resolve(
      sharingService,
      cloudEnabled && syncEngine != null,
      () => SupabaseSharingService(client: client!, syncEngine: syncEngine!),
    ),
    feedbackService: _resolve(
      feedbackService,
      cloudEnabled,
      () => SupabaseFeedbackService(client: client!),
    ),
    accountDeletionService: _resolve(
      accountDeletionService,
      cloudEnabled,
      () => SupabaseAccountDeletionService(client: client!),
    ),
    ownershipTransferService: _resolve(
      ownershipTransferService,
      cloudEnabled && syncEngine != null,
      () => SupabaseOwnershipTransferService(
          client: client!, syncEngine: syncEngine!),
    ),
    predictionConnectionService: _resolve(
      predictionConnectionService,
      cloudEnabled,
      () => SupabasePredictionConnectionService(client: client!),
    ),
    notificationPreferencesService: _resolve(
      notificationPreferencesService,
      cloudEnabled && pushEnabled,
      () => SupabaseNotificationPreferencesService(client: client!),
    ),
    accountExportRemoteSource: builtAccountExportRemoteSource,
    reminderWindowUpsert: _resolve(
      reminderWindowUpsert,
      cloudEnabled && pushEnabled,
      () => SupabaseReminderWindowRemote(client!),
    ),
    // R9: the scheduler's settings store is constructor-injected here, once
    // the database (and so the settings store) exists. `buildDefaultScheduler`
    // lets the shell opt into the platform default without `main.dart`
    // constructing a throwaway instance first; tests leave it false.
    scheduler: _resolve(
      scheduler,
      buildDefaultScheduler,
      () => kIsWeb
          ? NoopReminderScheduler()
          : FlutterLocalNotificationsScheduler(settingsStore: settings),
    ),
  );
}

/// Resolves one optional service: an explicit [override] always wins,
/// otherwise [build] runs only when [enabled] says its inputs are present.
T? _resolve<T>(T? override, bool enabled, T Function() build) =>
    override ?? (enabled ? build() : null);

// ---------------------------------------------------------------------------
// Issue #418 (AC2): lifecycle-coordinator construction sites.
//
// Every concrete lifecycle coordinator/publisher the roots own is constructed
// here — `lib/app.dart` and `lib/app_lifecycle.dart` only consume the
// returned instances (and start/dispose them). Each builder is pure
// construction: no `start()`/`dispose()` inside, so the roots keep owning
// the lifecycle while composition owns the `new` expression.

/// The drift settings store for [db] (AC2: `lib/app_lifecycle.dart` must not
/// construct `DriftSettingsStore` itself).
SettingsStore buildCompositionSettingsStore(LunarLogDatabase db) =>
    DriftSettingsStore(db.storage);

/// The per-profile reminder configuration store backing the coordinator.
ReminderConfigService buildReminderConfigService(SettingsStore settings) =>
    ReminderConfigService(settings);

/// Constructs the reminder action executor (Issue #136). Gate callbacks are
/// plain closures so this module never names `GateController` (which lives
/// in `lib/app_lifecycle.dart`).
ReminderActionExecutor buildReminderActionExecutor({
  required DayEntriesRepository dayEntries,
  required ObservationsRepository observations,
  required ReminderConfigService configService,
  required bool Function()? isUnlocked,
  required void Function(void Function() callback)? addUnlockListener,
  required void Function(void Function() callback)? removeUnlockListener,
}) =>
    ReminderActionExecutor(
      dayEntries: dayEntries,
      observations: observations,
      configService: configService,
      isUnlocked: isUnlocked,
      addUnlockListener: addUnlockListener,
      removeUnlockListener: removeUnlockListener,
    );

/// Constructs the reminder coordinator. The caller owns the deferred
/// `start()` (post-frame, inside the gate's system-UI window).
ReminderCoordinator buildReminderCoordinator({
  required ReminderScheduler scheduler,
  required NotificationAvailabilitySink permissionState,
  required Stream<List<Profile>> activeProfiles,
  required Stream<CyclePrediction> Function(String profileId) predictionFor,
  required ReminderConfigService localSettings,
  required Stream<BirthControlState?> Function(String profileId)?
      birthControlStateFor,
}) =>
    ReminderCoordinator(
      scheduler: scheduler,
      permissionState: permissionState,
      activeProfiles: activeProfiles,
      predictionFor: predictionFor,
      localSettings: localSettings,
      birthControlStateFor: birthControlStateFor,
    );

/// Constructs the reminder-window publisher, or null when either
/// collaborator is absent (the R17 zero-conditional gating posture).
ReminderWindowPublisher? buildReminderWindowPublisher({
  required NotificationPreferencesService? notificationPreferencesService,
  required ReminderWindowRemote? reminderWindowUpsert,
  required Stream<List<Profile>> activeProfiles,
  required Stream<CyclePrediction> Function(String profileId) predictionFor,
  required bool Function() isSignedIn,
}) {
  if (notificationPreferencesService == null || reminderWindowUpsert == null) {
    return null;
  }
  return ReminderWindowPublisher(
    activeProfiles: activeProfiles,
    predictionFor: predictionFor,
    upsert: reminderWindowUpsert,
    isSignedIn: isSignedIn,
  );
}

/// Constructs the prediction-projection publisher, or null when no
/// prediction-connection service is configured (Issue #151/#373: the only
/// gate — deliberately not the push gate).
PredictionProjectionPublisher? buildPredictionProjectionPublisher({
  required PredictionConnectionService? service,
  required Stream<List<Profile>> activeProfiles,
  required Stream<CyclePrediction> Function(String profileId) predictionFor,
  required bool Function() isSignedIn,
}) {
  if (service == null) return null;
  return LocalPredictionProjectionPublisher(
    activeProfiles: activeProfiles,
    predictionFor: predictionFor,
    service: service,
    isSignedIn: isSignedIn,
  );
}

/// Constructs the health-flow write coordinator, or null when the feature
/// is gated off (Issue #193: `AppConfig.hasHealthSync`, iOS-only until
/// #202; widget-test harnesses and web never construct it).
HealthFlowWriteCoordinator? buildHealthFlowWriteCoordinator({
  required SettingsStore settings,
  required ProfilesRepository profiles,
  required DayEntriesRepository dayEntries,
  required ObservationsRepository observations,
  required Future<List<ProfileGuardian>> Function(String profileId)
      guardiansForProfile,
  required String? Function() signedInUserId,
  required bool minorBindingAllowed,
}) {
  if (!AppConfig.hasHealthSync) return null;
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
  final binding = HealthSyncBinding(settings);
  final platform = createHealthPlatform(
    defaultTargetPlatform,
    binding: binding,
    minorBindingAllowed: minorBindingAllowed,
  );
  final service = LocalHealthFlowWriteService(
    platform: platform,
    binding: binding,
    minorBindingAllowed: minorBindingAllowed,
    profiles: profiles,
    dayEntries: dayEntries,
    observations: observations,
    settings: settings,
    guardiansForProfile: guardiansForProfile,
    signedInUserId: signedInUserId,
  );
  return LocalHealthFlowWriteCoordinator(
    binding: binding,
    dayEntries: dayEntries,
    service: service,
  );
}

/// Constructs the realtime sync coordinator (AC2: `lib/app_lifecycle.dart`
/// must not construct it itself). The caller owns `start()`/`dispose()`.
RealtimeSyncCoordinator buildRealtimeSyncCoordinator({
  required SupabaseClient client,
  required SyncEngine syncEngine,
  required LunarLogStorage storage,
  required AuthService auth,
}) =>
    RealtimeSyncCoordinator(
      client: client,
      syncEngine: syncEngine,
      storage: storage,
      auth: auth,
    );

/// Constructs the push-registration coordinator (AC2). The caller resolves
/// [deviceId] (via [buildCompositionSettingsStore] +
/// `resolvePushDeviceId`) and owns `start()`/`dispose()`.
PushRegistrationCoordinator buildPushRegistrationCoordinator({
  required SupabaseClient client,
  required String deviceId,
  required String platform,
  required Stream<AuthSessionState> authStates,
  required AuthSessionState Function() currentAuthState,
  required void Function(String profileId)? onTap,
}) =>
    PushRegistrationCoordinator(
      tokenSource: FirebasePushTokenSource(),
      registry: SupabasePushDeviceRegistry(client: client),
      deviceId: deviceId,
      platform: platform,
      authStates: authStates,
      currentAuthState: currentAuthState,
      onTap: onTap,
    );
