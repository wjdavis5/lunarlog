/// Composition-module tests: the unconfigured-build posture (R14) and the
/// constructor-injected scheduler (R9).
///
/// Issue #418 (AC6): the production-tree smoke test — every contract the
/// tree provides resolves (no null for a contract the bundle claims).
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/composition/app_dependencies.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/account/account_deletion_service.dart';
import 'package:lunarlog/domain/export/account_export.dart';
import 'package:lunarlog/domain/export/account_export_remote_source.dart';
import 'package:lunarlog/domain/export/account_export_writer.dart';
import 'package:lunarlog/domain/export/fhir_bundle_writer.dart';
import 'package:lunarlog/domain/feedback/device_diagnostics_collector.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/domain/import/account_import.dart';
import 'package:lunarlog/domain/import/account_import_coordinator.dart';
import 'package:lunarlog/domain/import/import_file_reader.dart';
import 'package:lunarlog/domain/notifications/notification_preferences_service.dart';
import 'package:lunarlog/domain/notifications/reminder_config_store.dart';
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
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/profiles/profile_home_gate.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_feedback_service.dart';
import '../support/fake_notification_preferences_service.dart';
import '../support/fake_reminder_scheduler.dart';
import '../support/fake_sync_engine.dart';

/// A fully controllable stub for a cloud contract with no dedicated fake:
/// every member answers via `noSuchMethod`, so the tree can provide it and
/// the smoke test can assert identity without implementing the surface.
class _StubSharingService implements SharingService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubAccountDeletionService implements AccountDeletionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubOwnershipTransferService implements OwnershipTransferService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubPredictionConnectionService
    implements PredictionConnectionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubAccountExportRemoteSource implements AccountExportRemoteSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubReminderWindowRemote implements ReminderWindowRemote {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('unconfigured build has local contracts and null cloud services', () {
    final deps = buildAppDependencies(db: db);

    expect(deps.profiles, isNotNull);
    expect(deps.dayEntries, isNotNull);
    expect(deps.observations, isNotNull);
    expect(deps.profileGuardians, isNotNull);
    expect(deps.activityFeed, isNotNull);
    expect(deps.accountImportCoordinator, isNotNull);
    expect(deps.prediction, isNotNull);

    expect(deps.authService, isNull);
    expect(deps.syncEngine, isNull);
    expect(deps.sharingService, isNull);
    expect(deps.feedbackService, isNull);
    expect(deps.accountDeletionService, isNull);
    expect(deps.ownershipTransferService, isNull);
    expect(deps.predictionConnectionService, isNull);
    expect(deps.notificationPreferencesService, isNull);
    expect(deps.accountExportRemoteSource, isNull);
    expect(deps.reminderWindowUpsert, isNull);
    expect(deps.scheduler, isNull);
  });

  test('R9: buildDefaultScheduler builds the platform scheduler with its '
      'settings store injected', () {
    final deps = buildAppDependencies(db: db, buildDefaultScheduler: true);
    final resolved = deps.scheduler;

    expect(resolved, isA<FlutterLocalNotificationsScheduler>());
    expect(
      (resolved! as FlutterLocalNotificationsScheduler).settingsStore,
      isNotNull,
    );
  });

  test('R9: an explicitly injected scheduler passes through untouched', () {
    final original = FlutterLocalNotificationsScheduler();
    expect(original.settingsStore, isNull);

    final deps = buildAppDependencies(db: db, scheduler: original);

    expect(identical(deps.scheduler, original), isTrue);
  });

  test('R16: buildAppDependencies wires currentUserIdProvider into the import '
      'coordinator, so a viewer membership blocks the plan', () async {
    final deps = buildAppDependencies(
      db: db,
      currentUserIdProvider: () => 'viewer-user',
    );

    final profile =
        await deps.profiles.create(displayName: 'Shared', isMinor: false);
    await LunarLogStorage(db).applyRemoteRows([
      RemoteProfileGuardianRow(
        id: 'g1',
        profileId: profile.id,
        userId: 'viewer-user',
        role: 'viewer',
        status: 'accepted',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ]);

    final parsed = parseAccountImport(utf8.encode(jsonEncode({
      'schemaVersion': kAccountExportSchemaVersion,
      'exportedAt': '2026-01-03T00:00:00.000Z',
      'app': {'name': 'lunarlog', 'version': '1.0.0+1'},
      'profiles': [
        {
          'id': profile.id,
          'displayName': 'Shared',
          'isMinor': false,
          'mode': 'standard',
          'sortOrder': 0,
          'archivedAt': null,
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
          'dayEntries': const <Object?>[],
          'observations': const <Object?>[],
        },
      ],
    })));
    expect(parsed, isA<AccountImportParsed>());
    final document = (parsed as AccountImportParsed).document;

    final plan = await deps.accountImportCoordinator.buildPlan(document);

    expect(plan.profiles.single.outcome, ProfileImportOutcome.skipped,
        reason: 'the provider-supplied id must gate the viewer membership '
            'even though the coordinator captured no currentUserId');
  });

  testWidgets('AC6: the production tree provides every contract the full '
      'bundle claims', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final auth = FakeAuthService();
    addTearDown(auth.dispose);
    final engine = FakeSyncEngine();
    addTearDown(engine.dispose);
    final sharing = _StubSharingService();
    final feedback = FakeFeedbackService();
    final deletion = _StubAccountDeletionService();
    final transfer = _StubOwnershipTransferService();
    final predictionConnection = _StubPredictionConnectionService();
    final preferences = FakeNotificationPreferencesService();
    final remoteSource = _StubAccountExportRemoteSource();
    final reminderUpsert = _StubReminderWindowRemote();
    final scheduler = FakeReminderScheduler();

    final deps = buildAppDependencies(
      db: db,
      authService: auth,
      syncEngine: engine,
      sharingService: sharing,
      feedbackService: feedback,
      accountDeletionService: deletion,
      ownershipTransferService: transfer,
      predictionConnectionService: predictionConnection,
      notificationPreferencesService: preferences,
      accountExportRemoteSource: remoteSource,
      reminderWindowUpsert: reminderUpsert,
      scheduler: scheduler,
    );

    await tester.pumpWidget(LunarLogApp(db: db, dependencies: deps));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(ProfileHomeGate));

    // Local contracts: always provided, identical to the bundle.
    expect(context.read<ProfilesRepository>(), same(deps.profiles));
    expect(context.read<DayEntriesRepository>(), same(deps.dayEntries));
    expect(context.read<ObservationsRepository>(), same(deps.observations));
    expect(context.read<CareContentRepository>(), same(deps.careContent));
    expect(context.read<SettingsStore>(), same(deps.settings));
    expect(context.read<ProfileModesRepository>(), same(deps.profileModes));
    expect(
        context.read<ProfileGuardiansRepository>(),
        same(deps.profileGuardians));
    expect(context.read<ActivityFeedRepository>(), same(deps.activityFeed));
    expect(context.read<OnboardingCycleAnswersRecorder>(),
        same(deps.onboardingCycleAnswers));
    expect(context.read<DeviceDiagnosticsCollector>(),
        same(deps.deviceDiagnostics));
    expect(
        context.read<AccountExportWriter>(), same(deps.accountExportWriter));
    expect(context.read<FhirBundleWriter>(), same(deps.fhirBundleWriter));
    expect(context.read<AttachmentSource>(), isNotNull);
    expect(context.read<ImportFileReader>(),
        same(deps.importFileReader));
    expect(context.read<AccountImportCoordinator>(),
        same(deps.accountImportCoordinator));
    expect(context.read<CyclePredictionService>(), same(deps.prediction));
    expect(context.read<CycleHistoryService>(), same(deps.cycleHistory));
    expect(context.read<CycleExclusionList>(), same(deps.cycleExclusions));

    // Cloud contracts: provided because the full bundle claims each one.
    expect(context.read<AuthController>(), isNotNull);
    expect(context.read<SharingService>(), same(sharing));
    expect(context.read<FeedbackService>(), same(feedback));
    expect(
        context.read<AccountDeletionService>(), same(deletion));
    expect(context.read<OwnershipTransferService>(), same(transfer));
    expect(context.read<PredictionConnectionService>(),
        same(predictionConnection));
    expect(context.read<NotificationPreferencesService>(),
        same(preferences));
    expect(context.read<AccountExportRemoteSource>(), same(remoteSource));
    // Reminder machinery: a scheduler in the bundle means the coordinator,
    // its config store, and the permission callback are all provided.
    expect(context.read<ReminderConfigService>(), isNotNull);
    expect(context.read<RequestNotificationPermissionCallback>(), isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
