/// Composition-module tests: the unconfigured-build posture (R14) and the
/// constructor-injected scheduler (R9).
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/composition/app_dependencies.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/export/account_export.dart';
import 'package:lunarlog/domain/import/account_import.dart';

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
}
