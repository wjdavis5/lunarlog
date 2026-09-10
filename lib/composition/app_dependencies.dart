/// The single place every concrete data-layer implementation is constructed.
///
/// Both composition roots (`lib/main.dart`/`lib/app_lifecycle.dart` and
/// `lib/app.dart`) delegate here: `LunarLogRoot` builds an [AppDependencies]
/// once the database is open and passes it to `LunarLogApp`; `LunarLogApp`
/// falls back to building one from its own (test-injectable) collaborators
/// when none is supplied. `lib/ui` never sees this type — it reads the
/// individual domain contracts from the provider tree.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'package:lunarlog/data/account/supabase_account_deletion_service.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/diagnostics/device_diagnostics_collector.dart'
    as data;
import 'package:lunarlog/data/export/account_export_writer.dart' as data;
import 'package:lunarlog/data/export/fhir_bundle_writer.dart' as data;
import 'package:lunarlog/data/export/supabase_account_export_remote_source.dart';
import 'package:lunarlog/data/feedback/image_picker_attachment_source.dart';
import 'package:lunarlog/data/feedback/supabase_feedback_service.dart';
import 'package:lunarlog/data/import/account_importer.dart' as data;
import 'package:lunarlog/data/import/import_file_picker.dart' as data;
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/data/notifications/supabase_notification_preferences_service.dart';
import 'package:lunarlog/data/notifications/supabase_reminder_window_remote.dart';
import 'package:lunarlog/data/repositories/activity_feed_repository.dart'
    as data;
import 'package:lunarlog/data/repositories/drift_care_content_repository.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_onboarding_cycle_answers_recorder.dart';
import 'package:lunarlog/data/repositories/drift_profile_modes_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart'
    as data;
import 'package:lunarlog/data/sharing/supabase_ownership_transfer_service.dart';
import 'package:lunarlog/data/sharing/supabase_prediction_connection_service.dart';
import 'package:lunarlog/data/sharing/supabase_sharing_service.dart';
import 'package:lunarlog/domain/account/account_deletion_service.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/export/account_export_remote_source.dart';
import 'package:lunarlog/domain/feedback/device_diagnostics_collector.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/domain/export/account_export_writer.dart';
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
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
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
  final profileGuardians = data.ProfileGuardiansRepository(storage);

  final builtAccountExportRemoteSource = _resolve(
    accountExportRemoteSource,
    client != null,
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
    activityFeed: data.ActivityFeedRepository(storage),
    onboardingCycleAnswers: DriftOnboardingCycleAnswersRecorder(storage),
    deviceDiagnostics: data.DeviceDiagnosticsCollector(),
    accountExportWriter: data.AccountExportWriter(
      remoteSource: builtAccountExportRemoteSource,
    ),
    fhirBundleWriter: const data.FhirBundleWriter(),
    attachmentSource: ImagePickerAttachmentSource(),
    importFileReader: const data.PickImportFileReader(),
    accountImportCoordinator: data.AccountImportCoordinator(
      profilesRepository: profiles,
      dayEntriesRepository: dayEntries,
      observationsRepository: observations,
      storage: storage,
      guardiansForProfile: profileGuardians.getForProfile,
      currentUserIdProvider: currentUserIdProvider,
    ),
    prediction: CyclePredictionService(dayEntries,
        settings: settings, profiles: profiles),
    cycleHistory: CycleHistoryService(dayEntries, settings: settings),
    cycleExclusions: CycleExclusionList(settings),
    authService: authService,
    syncEngine: syncEngine,
    sharingService: _resolve(
      sharingService,
      client != null && syncEngine != null,
      () => SupabaseSharingService(client: client!, syncEngine: syncEngine!),
    ),
    feedbackService: _resolve(
      feedbackService,
      client != null,
      () => SupabaseFeedbackService(client: client!),
    ),
    accountDeletionService: _resolve(
      accountDeletionService,
      client != null,
      () => SupabaseAccountDeletionService(client: client!),
    ),
    ownershipTransferService: _resolve(
      ownershipTransferService,
      client != null && syncEngine != null,
      () => SupabaseOwnershipTransferService(
          client: client!, syncEngine: syncEngine!),
    ),
    predictionConnectionService: _resolve(
      predictionConnectionService,
      client != null,
      () => SupabasePredictionConnectionService(client: client!),
    ),
    notificationPreferencesService: _resolve(
      notificationPreferencesService,
      client != null && pushEnabled,
      () => SupabaseNotificationPreferencesService(client: client!),
    ),
    accountExportRemoteSource: builtAccountExportRemoteSource,
    reminderWindowUpsert: _resolve(
      reminderWindowUpsert,
      client != null && pushEnabled,
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
