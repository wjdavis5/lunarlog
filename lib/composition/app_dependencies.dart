/// The single place every concrete data-layer implementation is constructed.
///
/// Both composition roots (`lib/main.dart`/`lib/app_lifecycle.dart` and
/// `lib/app.dart`) delegate here: `LunarLogRoot` builds an [AppDependencies]
/// once the database is open and passes it to `LunarLogApp`; `LunarLogApp`
/// falls back to building one from its own (test-injectable) collaborators
/// when none is supplied. `lib/ui` never sees this type — it reads the
/// individual domain contracts from the provider tree.
library;

import 'dart:async' show unawaited;

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
import 'package:lunarlog/data/export/clinical_pdf_writer.dart';
import 'package:lunarlog/data/export/fhir_bundle_writer.dart';
import 'package:lunarlog/data/export/supabase_account_export_remote_source.dart';
import 'package:lunarlog/data/feedback/image_picker_attachment_source.dart';
import 'package:lunarlog/data/feedback/supabase_feedback_service.dart';
import 'package:lunarlog/data/health/health_channel.dart';
import 'package:lunarlog/data/health/health_flow_write_coordinator.dart';
import 'package:lunarlog/data/health/health_flow_write_service.dart';
import 'package:lunarlog/data/health/health_import_service.dart';
import 'package:lunarlog/data/health/health_sync_deletion_service.dart';
import 'package:lunarlog/data/health/health_sync_tombstone_coordinator.dart';
import 'package:lunarlog/data/import/account_importer.dart';
import 'package:lunarlog/data/import/clue_importer.dart';
import 'package:lunarlog/data/import/import_file_picker.dart';
import 'package:lunarlog/data/notifications/firebase_push_token_source.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/data/notifications/push_presentation.dart';
import 'package:lunarlog/data/notifications/push_registration_coordinator.dart';
import 'package:lunarlog/data/notifications/reminder_action_executor.dart';
import 'package:lunarlog/data/notifications/reminder_coordinator.dart';
import 'package:lunarlog/data/notifications/reminder_window_publisher.dart';
import 'package:lunarlog/data/notifications/supabase_notification_preferences_service.dart';
import 'package:lunarlog/data/notifications/supabase_push_device_registry.dart';
import 'package:lunarlog/data/notifications/supabase_reminder_window_remote.dart';
import 'package:lunarlog/data/profiles/supabase_profile_erasure_service.dart';
import 'package:lunarlog/data/repositories/drift_account_export_snapshot_repository.dart';
import 'package:lunarlog/data/repositories/drift_activity_feed_repository.dart';
import 'package:lunarlog/data/repositories/drift_care_content_repository.dart';
import 'package:lunarlog/data/repositories/drift_guardian_notes_repository.dart';
import 'package:lunarlog/data/repositories/drift_cycle_overrides_repository.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_health_export_ledger.dart';
import 'package:lunarlog/data/repositories/drift_health_sync_state_repository.dart';
import 'package:lunarlog/data/repositories/drift_health_sync_tombstone_source.dart';
import 'package:lunarlog/data/repositories/drift_imported_data_purge_repository.dart';
import 'package:lunarlog/data/repositories/drift_onboarding_cycle_answers_recorder.dart';
import 'package:lunarlog/data/repositories/drift_profile_modes_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/repositories/drift_profile_guardians_repository.dart';
import 'package:lunarlog/data/repositories/drift_tag_registry_repository.dart';
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
import 'package:lunarlog/domain/export/clinical_pdf_writer.dart';
import 'package:lunarlog/domain/export/fhir_bundle_writer.dart';
import 'package:lunarlog/domain/import/account_import_coordinator.dart';
import 'package:lunarlog/domain/import/clue/clue_import_run.dart'
    show ClueImportRunner;
import 'package:lunarlog/domain/import/import_file_reader.dart';
import 'package:lunarlog/domain/notifications/notification_preferences_service.dart';
import 'package:lunarlog/domain/notifications/reminder_scheduler.dart';
import 'package:lunarlog/domain/notifications/reminder_window_remote.dart';
import 'package:lunarlog/domain/onboarding/onboarding_cycle_answers.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/profiles/profile_erasure_service.dart';
import 'package:lunarlog/domain/repositories/account_export_snapshot_repository.dart';
import 'package:lunarlog/domain/repositories/activity_feed_repository.dart';
import 'package:lunarlog/domain/repositories/care_content_repository.dart';
import 'package:lunarlog/domain/repositories/guardian_notes_repository.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/domain/repositories/tag_registry_repository.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/health/health_flow_write_coordinator.dart';
import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_export_ledger.dart';
import 'package:lunarlog/domain/health/health_sync_state_repository.dart';
import 'package:lunarlog/domain/health/health_sync_tombstone_source.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
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
    required this.guardianNotes,
    required this.tagRegistry,
    required this.settings,
    required this.profileModes,
    required this.profileGuardians,
    required this.activityFeed,
    required this.onboardingCycleAnswers,
    required this.deviceDiagnostics,
    required this.healthSyncAnchors,
    required this.healthSyncTombstoneSource,
    required this.healthExportLedger,
    required this.accountExportWriter,
    required this.fhirBundleWriter,
    required this.csvExportWriter,
    required this.clinicalPdfWriter,
    required this.attachmentSource,
    required this.exportSnapshot,
    required this.importFileReader,
    required this.accountImportCoordinator,
    required this.clueImportRunner,
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
    this.profileErasureService,
    this.notificationPreferencesService,
    this.accountExportRemoteSource,
    this.reminderWindowUpsert,
    this.scheduler,
  });

  final ProfilesRepository profiles;
  final DayEntriesRepository dayEntries;
  final ObservationsRepository observations;
  final CareContentRepository careContent;

  /// Issue #801: per-guardian dated notes — the date-bound AND
  /// author-scoped sibling of [careContent].
  final GuardianNotesRepository guardianNotes;

  /// Issue #257: the per-profile custom-tag registry (create/rename/
  /// retire) the day sheet's tag picker drives.
  final TagRegistryRepository tagRegistry;

  final SettingsStore settings;
  final ProfileModesRepository profileModes;
  final ProfileGuardiansRepository profileGuardians;
  final ActivityFeedRepository activityFeed;
  final OnboardingCycleAnswersRecorder onboardingCycleAnswers;
  final DeviceDiagnosticsCollector deviceDiagnostics;

  /// Device-local health-store sync anchors (Issue #186) — never synced to
  /// the server; the drift `health_sync_state` table's domain contract.
  final HealthSyncStateRepository healthSyncAnchors;

  /// Full-fidelity (tombstones-included) day-entry/observation reads for
  /// [HealthSyncTombstoneCoordinator] (Issue #619, LLA-018/LLA-020) — never
  /// [dayEntries]/[observations], whose UI-facing streams filter tombstones
  /// out.
  final HealthSyncTombstoneSource healthSyncTombstoneSource;

  /// The device-local health-store export ledger (Issue #936) — never
  /// synced to the server; the drift `health_export_ledger` table's domain
  /// contract. Seeds both health-store deletion paths across app restarts.
  final HealthExportLedger healthExportLedger;

  final AccountExportWriter accountExportWriter;
  final FhirBundleWriter fhirBundleWriter;
  final CsvExportWriter csvExportWriter;
  final ClinicalPdfWriter clinicalPdfWriter;
  final AttachmentSource attachmentSource;

  /// Issue #140 review, LLA-084/LLA-094: the coherent point-in-time export
  /// read — see `AccountExportSnapshotRepository`'s own doc comment.
  final AccountExportSnapshotRepository exportSnapshot;
  final ImportFileReader importFileReader;
  final AccountImportCoordinator accountImportCoordinator;

  /// Issue #452: the effectful Clue-export write path the import screen
  /// drives, typed as the domain [ClueImportRunner] so `lib/ui` never names
  /// `ClueImporter` or the raw storage object.
  final ClueImportRunner clueImportRunner;
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

  /// Issue #472: the `delete_profile_data` RPC seam — "Delete profile
  /// permanently" and "Purge imported data". Null on the unconfigured-build
  /// posture (R26), same gate as [predictionConnectionService].
  final ProfileErasureService? profileErasureService;

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
  ProfileErasureService? profileErasureService,
  NotificationPreferencesService? notificationPreferencesService,
  AccountExportRemoteSource? accountExportRemoteSource,
  ReminderWindowRemote? reminderWindowUpsert,
  ReminderScheduler? scheduler,
  String? Function()? currentUserIdProvider,
  bool pushEnabled = false,
  bool buildDefaultScheduler = false,
  // Issue LLA-070: null (the default here, and LunarLogRoot's own default
  // too) keeps CyclePredictionService's own timer-free default (tick
  // once, never again) -- the right choice for both
  // LunarLogApp.withCollaborators (`@visibleForTesting`, still this same
  // factory) and every test that constructs LunarLogRoot directly. Only
  // `main.dart` -- the real app's actual entry point, whose widget tree
  // is guaranteed to be disposed through real app lifecycle rather than a
  // test that may never unmount it -- passes `dateRolloverTicker`
  // explicitly, threaded through LunarLogRoot.dateTicker.
  Stream<void> Function()? dateTicker,
}) {
  final storage = db.storage;
  final profiles = DriftProfilesRepository(storage);
  final dayEntries = DriftDayEntriesRepository(storage);
  final observations = DriftObservationsRepository(storage);
  final settings = DriftSettingsStore(storage);
  final profileModes = DriftProfileModesRepository(storage);
  final profileGuardians = DriftProfileGuardiansRepository(storage);
  final accountImporter = DriftAccountImporter(storage);
  // Issue #568 (b): the synced source of truth cycle-history omissions read
  // and write through now, instead of the device-local settings list.
  final cycleOverrides = DriftCycleOverridesRepository(storage);
  final tagRegistry = DriftTagRegistryRepository(storage);
  final guardianNotes = DriftGuardianNotesRepository(storage);
  // One-time carry-over of any pre-existing device-local omissions into
  // cycle_overrides rows (see migrateOmittedCyclesToCycleOverrides's own
  // doc comment for its idempotency). Fired and forgotten:
  // buildAppDependencies itself is synchronous and nothing downstream needs
  // this to have finished — the migration's own settings flag makes every
  // later launch's call an immediate no-op regardless of how this one
  // resolves. Errors are swallowed rather than left unhandled: the database
  // can legitimately close (a short-lived test harness, a fast app
  // shutdown) before this finishes, and a background best-effort migration
  // must never surface as an unhandled Future error or crash-report noise
  // for something the next launch's call will simply retry.
  unawaited(
    profiles
        .list()
        .then(
          (allProfiles) => migrateOmittedCyclesToCycleOverrides(
            settings: settings,
            overrides: cycleOverrides,
            profileIds: [for (final profile in allProfiles) profile.id],
          ),
        )
        .catchError((_) {}),
  );

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
    guardianNotes: guardianNotes,
    tagRegistry: tagRegistry,
    settings: settings,
    profileModes: profileModes,
    profileGuardians: profileGuardians,
    activityFeed: DriftActivityFeedRepository(storage),
    onboardingCycleAnswers: DriftOnboardingCycleAnswersRecorder(storage),
    deviceDiagnostics: PlatformDeviceDiagnosticsCollector(),
    healthSyncAnchors: DriftHealthSyncStateRepository(storage),
    healthSyncTombstoneSource: DriftHealthSyncTombstoneSource(storage),
    healthExportLedger: DriftHealthExportLedger(storage),
    accountExportWriter: PlatformAccountExportWriter(
      remoteSource: builtAccountExportRemoteSource,
    ),
    fhirBundleWriter: const PlatformFhirBundleWriter(),
    csvExportWriter: const PlatformCsvExportWriter(),
    clinicalPdfWriter: const PlatformClinicalPdfWriter(),
    attachmentSource: ImagePickerAttachmentSource(),
    exportSnapshot: DriftAccountExportSnapshotRepository(
      storage: storage,
      entriesRepository: dayEntries,
      observationsRepository: observations,
      profileModesRepository: profileModes,
      cycleOverridesRepository: cycleOverrides,
      tagRegistryRepository: tagRegistry,
      guardianNotesRepository: guardianNotes,
    ),
    importFileReader: PickImportFileReader(),
    accountImportCoordinator: DriftAccountImportCoordinator(
      profilesRepository: profiles,
      dayEntriesRepository: dayEntries,
      observationsRepository: observations,
      storage: storage,
      cycleOverridesRepository: cycleOverrides,
      tagRegistryRepository: tagRegistry,
      guardianNotesRepository: guardianNotes,
      guardiansForProfile: profileGuardians.getForProfile,
      currentUserIdProvider: currentUserIdProvider,
      importer: accountImporter,
    ),
    clueImportRunner: ClueImporter(storage),
    // Issue #233: the profile_modes birth-control watcher feeds the
    // predictor's branch (withdrawal-bleed -> pack schedule, continuous ->
    // suppressed). Issue #551: goes through ProfileModesRepository.watch
    // plus the one shared birthControlStateFromProfileMode mapper, rather
    // than a hand-copy of `lib/app.dart`'s reminder-coordinator wiring
    // reaching past this repository into LunarLogStorage directly.
    //
    // Issue #528: the same profile_modes row's `mode` column feeds the
    // life-stage suppression branch (pregnancy/postpartum/perimenopause ->
    // suppressed), via a second `.map` over the identical
    // ProfileModesRepository.watch stream rather than a second
    // subscription.
    prediction: CyclePredictionService(
      dayEntries,
      settings: settings,
      cycleOverrides: cycleOverrides,
      profiles: profiles,
      birthControlStateFor: (profileId) =>
          profileModes.watch(profileId).map(birthControlStateFromProfileMode),
      lifecycleModeFor: (profileId) => profileModes
          .watch(profileId)
          .map((row) => row?.mode ?? LifecycleMode.tracking),
      dateTicker: dateTicker,
    ),
    cycleHistory: CycleHistoryService(
      dayEntries,
      settings: settings,
      cycleOverrides: cycleOverrides,
    ),
    cycleExclusions: CycleExclusionList(settings, overrides: cycleOverrides),
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
        client: client!,
        syncEngine: syncEngine!,
      ),
    ),
    predictionConnectionService: _resolve(
      predictionConnectionService,
      cloudEnabled,
      () => SupabasePredictionConnectionService(client: client!),
    ),
    profileErasureService: _resolve(
      profileErasureService,
      cloudEnabled,
      () => SupabaseProfileErasureService(
        client: client!,
        profiles: profiles,
        importedDataPurge: DriftImportedDataPurgeRepository(storage),
        syncEngine: syncEngine,
      ),
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
}) => ReminderActionExecutor(
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
  LocalTimeZoneProvider? localTimeZoneProvider,
}) => ReminderCoordinator(
  scheduler: scheduler,
  permissionState: permissionState,
  activeProfiles: activeProfiles,
  predictionFor: predictionFor,
  localSettings: localSettings,
  birthControlStateFor: birthControlStateFor,
  localTimeZoneProvider: localTimeZoneProvider,
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

/// The platforms the *write* direction is wired on. Writes stay iOS-only
/// (Issue #193/#202's device checklist owns opening Android); Issue #458
/// wired only the read/import direction there, so the Settings screen's
/// write-specific copy is conditioned on this.
const Set<TargetPlatform> _healthWritePlatforms = {TargetPlatform.iOS};

/// The import platform each wired OS store maps to (Issue #458).
const Map<TargetPlatform, HealthImportPlatform> _healthImportPlatforms = {
  TargetPlatform.iOS: HealthImportPlatform.appleHealth,
  TargetPlatform.android: HealthImportPlatform.healthConnect,
};

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
  required HealthExportLedger ledger,
}) {
  if (!AppConfig.hasHealthSync) return null;
  if (kIsWeb || !_healthWritePlatforms.contains(defaultTargetPlatform)) {
    return null;
  }
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
    ledger: ledger,
  );
  return LocalHealthFlowWriteCoordinator(
    binding: binding,
    dayEntries: dayEntries,
    service: service,
  );
}

/// Constructs the user-initiated OS health-store import runner (Issues #217
/// and #458), or null when the feature is gated off — the same
/// `AppConfig.hasHealthSync` plus wired-store gate, but the only health
/// capability wired on Android. Unlike the write coordinator there is
/// nothing to start: the runner is a stateless-ish service the Settings
/// screen calls once per explicit import action.
///
/// It is handed the read port (`createHealthImportSource`) and the write
/// port (`createHealthPlatform`) from one platform, so `bindProfile` (the
/// native guard mirror) and `requestWriteAuthorization` (which now also
/// requests the read types) are the same calls the write path makes.
HealthImportRunner? buildHealthImportRunner({
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
  final importPlatform = _healthImportPlatforms[defaultTargetPlatform];
  if (kIsWeb || importPlatform == null) return null;
  final binding = HealthSyncBinding(settings);
  return LocalHealthImportService(
    importPlatform: importPlatform,
    platform: createHealthPlatform(
      defaultTargetPlatform,
      binding: binding,
      minorBindingAllowed: minorBindingAllowed,
    ),
    source: createHealthImportSource(
      defaultTargetPlatform,
      binding: binding,
      minorBindingAllowed: minorBindingAllowed,
    ),
    binding: binding,
    minorBindingAllowed: minorBindingAllowed,
    profiles: profiles,
    dayEntries: dayEntries,
    observations: observations,
    guardiansForProfile: guardiansForProfile,
    signedInUserId: signedInUserId,
  );
}

/// Constructs the health-store tombstone-propagation coordinator (Issue
/// #186, AC6), or null when the feature is gated off (same gate as the write
/// coordinator: `AppConfig.hasHealthSync`, iOS-only; widget-test harnesses
/// and web never construct it). A tombstoned bound-profile entry hands its
/// ULID (the recorded health-store external id) to the platform's
/// `deleteRecords`.
HealthSyncTombstoneCoordinator? buildHealthSyncTombstoneCoordinator({
  required SettingsStore settings,
  required ProfilesRepository profiles,
  required HealthSyncTombstoneSource tombstoneSource,
  required Future<List<ProfileGuardian>> Function(String profileId)
  guardiansForProfile,
  required String? Function() signedInUserId,
  required HealthExportLedger ledger,
}) {
  if (!AppConfig.hasHealthSync) return null;
  if (kIsWeb || !_healthWritePlatforms.contains(defaultTargetPlatform)) {
    return null;
  }
  final binding = HealthSyncBinding(settings);
  final platform = createHealthPlatform(
    defaultTargetPlatform,
    binding: binding,
    minorBindingAllowed: AppConfig.healthSyncMinorBindingAllowed,
  );
  final deletionService = LocalHealthSyncDeletionService(
    platform: platform,
    binding: binding,
    profiles: profiles,
    guardiansForProfile: guardiansForProfile,
    signedInUserId: signedInUserId,
  );
  return HealthSyncTombstoneCoordinator(
    binding: binding,
    source: tombstoneSource,
    deletionService: deletionService,
    ledger: ledger,
  );
}

/// Constructs the realtime sync coordinator (AC2: `lib/app_lifecycle.dart`
/// must not construct it itself). The caller owns `start()`/`dispose()`.
RealtimeSyncCoordinator buildRealtimeSyncCoordinator({
  required SupabaseClient client,
  required SyncEngine syncEngine,
  required LunarLogStorage storage,
  required AuthService auth,
}) => RealtimeSyncCoordinator(
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
}) => PushRegistrationCoordinator(
  tokenSource: FirebasePushTokenSource(),
  registry: SupabasePushDeviceRegistry(client: client),
  deviceId: deviceId,
  platform: platform,
  authStates: authStates,
  currentAuthState: currentAuthState,
  onTap: onTap,
);

/// Constructs the foreground push presenter (Issue #174). The caller starts
/// it next to the push-registration coordinator (the same
/// `AppConfig.hasPush && !isWeb` gate in `lib/app_root.dart`) and disposes
/// it with the coordinator — foreground caregiver alerts are presented only
/// for a device that is registered to receive them at all.
PushForegroundPresenter buildPushForegroundPresenter() =>
    PushForegroundPresenter();
