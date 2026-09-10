/// The single place every concrete data-layer implementation is constructed.
///
/// Both composition roots (`lib/main.dart`/`lib/app_lifecycle.dart` and
/// `lib/app.dart`) delegate here: `LunarLogRoot` builds an [AppDependencies]
/// once the database is open and passes it to `LunarLogApp`; `LunarLogApp`
/// falls back to building one from its own (test-injectable) collaborators
/// when none is supplied. `lib/ui` never sees this type — it reads the
/// individual domain contracts from the provider tree.
library;

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
import 'package:lunarlog/data/notifications/reminder_window_publisher.dart'
    show ReminderWindowUpsert;
import 'package:lunarlog/data/notifications/supabase_notification_preferences_service.dart';
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
import 'package:lunarlog/data/sync/sync_transport.dart';
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
  final ReminderWindowUpsert? reminderWindowUpsert;

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
  SyncTransport? syncTransport,
  SyncEngine? syncEngine,
  SharingService? sharingService,
  FeedbackService? feedbackService,
  AccountDeletionService? accountDeletionService,
  OwnershipTransferService? ownershipTransferService,
  PredictionConnectionService? predictionConnectionService,
  NotificationPreferencesService? notificationPreferencesService,
  AccountExportRemoteSource? accountExportRemoteSource,
  ReminderWindowUpsert? reminderWindowUpsert,
  ReminderScheduler? scheduler,
  String? Function()? currentUserIdProvider,
  bool pushEnabled = false,
}) {
  final storage = db.storage;
  final profiles = DriftProfilesRepository(storage);
  final dayEntries = DriftDayEntriesRepository(storage);
  final observations = DriftObservationsRepository(storage);
  final settings = DriftSettingsStore(storage);
  final profileGuardians = data.ProfileGuardiansRepository(storage);

  final builtAccountExportRemoteSource =
      _resolveAccountExportRemoteSource(accountExportRemoteSource, client);

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
    sharingService: _resolveSharingService(sharingService, client, syncEngine),
    feedbackService: _resolveFeedbackService(feedbackService, client),
    accountDeletionService:
        _resolveAccountDeletionService(accountDeletionService, client),
    ownershipTransferService:
        _resolveOwnershipTransferService(ownershipTransferService, client,
            syncEngine),
    predictionConnectionService:
        _resolvePredictionConnectionService(predictionConnectionService, client),
    notificationPreferencesService: _resolveNotificationPreferencesService(
        notificationPreferencesService, client, pushEnabled),
    accountExportRemoteSource: builtAccountExportRemoteSource,
    reminderWindowUpsert:
        _resolveReminderWindowUpsert(reminderWindowUpsert, client, pushEnabled),
    scheduler: _resolveScheduler(scheduler, settings),
  );
}

/// R9: the scheduler's settings store is constructor-injected. `main.dart`
/// builds the platform scheduler before the database (and so the settings
/// store) exists; rebuild it here with the store attached so no
/// post-construction mutation is needed. A fake injected by a test passes
/// through untouched.
ReminderScheduler? _resolveScheduler(
  ReminderScheduler? scheduler,
  SettingsStore settings,
) {
  if (scheduler is FlutterLocalNotificationsScheduler &&
      scheduler.settingsStore == null) {
    return FlutterLocalNotificationsScheduler(settingsStore: settings);
  }
  return scheduler;
}

AccountExportRemoteSource? _resolveAccountExportRemoteSource(
  AccountExportRemoteSource? override,
  SupabaseClient? client,
) {
  if (override != null) return override;
  if (client == null) return null;
  return SupabaseAccountExportRemoteSource(client: client);
}

SharingService? _resolveSharingService(
  SharingService? override,
  SupabaseClient? client,
  SyncEngine? syncEngine,
) {
  if (override != null) return override;
  if (client == null || syncEngine == null) return null;
  return SupabaseSharingService(client: client, syncEngine: syncEngine);
}

OwnershipTransferService? _resolveOwnershipTransferService(
  OwnershipTransferService? override,
  SupabaseClient? client,
  SyncEngine? syncEngine,
) {
  if (override != null) return override;
  if (client == null || syncEngine == null) return null;
  return SupabaseOwnershipTransferService(client: client, syncEngine: syncEngine);
}

FeedbackService? _resolveFeedbackService(
  FeedbackService? override,
  SupabaseClient? client,
) {
  if (override != null) return override;
  if (client == null) return null;
  return SupabaseFeedbackService(client: client);
}

AccountDeletionService? _resolveAccountDeletionService(
  AccountDeletionService? override,
  SupabaseClient? client,
) {
  if (override != null) return override;
  if (client == null) return null;
  return SupabaseAccountDeletionService(client: client);
}

PredictionConnectionService? _resolvePredictionConnectionService(
  PredictionConnectionService? override,
  SupabaseClient? client,
) {
  if (override != null) return override;
  if (client == null) return null;
  return SupabasePredictionConnectionService(client: client);
}

NotificationPreferencesService? _resolveNotificationPreferencesService(
  NotificationPreferencesService? override,
  SupabaseClient? client,
  bool pushEnabled,
) {
  if (override != null) return override;
  if (client == null || !pushEnabled) return null;
  return SupabaseNotificationPreferencesService(client: client);
}

ReminderWindowUpsert? _resolveReminderWindowUpsert(
  ReminderWindowUpsert? override,
  SupabaseClient? client,
  bool pushEnabled,
) {
  if (override != null) return override;
  if (client == null || !pushEnabled) return null;
  return _supabaseReminderWindowUpsert(client);
}

/// The `upsert_reminder_window` RPC (Issue #5, U6): one narrow write, no
/// content.
ReminderWindowUpsert _supabaseReminderWindowUpsert(SupabaseClient client) =>
    (profileId, estimatedNextStartIso, episodeOpen) async {
      await client.rpc<dynamic>('upsert_reminder_window', params: {
        'p_profile_id': profileId,
        'p_estimated_next_start': estimatedNextStartIso,
        'p_episode_open': episodeOpen,
      });
    };
