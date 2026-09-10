/// Composition-module tests: the unconfigured-build posture (R14) and the
/// constructor-injected scheduler (R9).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/composition/app_dependencies.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';

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

  test('R9: a platform scheduler is rebuilt with its settings store injected',
      () {
    final original = FlutterLocalNotificationsScheduler();
    expect(original.settingsStore, isNull);

    final deps = buildAppDependencies(db: db, scheduler: original);
    final resolved = deps.scheduler;

    expect(resolved, isA<FlutterLocalNotificationsScheduler>());
    expect(identical(resolved, original), isFalse);
    expect(
      (resolved! as FlutterLocalNotificationsScheduler).settingsStore,
      isNotNull,
    );
  });
}
