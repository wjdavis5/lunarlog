/// Regression coverage for the opus-review fix to issue #151: the
/// prediction-projection publisher must start whenever
/// [LunarLogApp.predictionConnectionService] is present, independent of
/// the push-notification gate.
///
/// Before this fix, [LunarLogApp._startPredictionProjectionPublisher] was
/// only ever called from inside `_initReminderWindowPublisher`, which
/// early-returns whenever `notificationPreferencesService` or
/// `reminderWindowUpsert` is null - exactly the case on web/no-push
/// builds (`AppConfig.hasPush && !isWeb` gates both in app_lifecycle.dart,
/// while `predictionConnectionService` is provided whenever a Supabase
/// client is present, unconditionally). That left the entire #151
/// prediction-connection UI reachable with its only data-publishing path
/// dead. This test pumps [LunarLogApp] the same way: a
/// [PredictionConnectionService] present, no scheduler, and both
/// `notificationPreferencesService`/`reminderWindowUpsert` left null (the
/// default) - the web/no-push shape - and asserts the publisher still
/// gets built and provided to the tree.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/domain/sharing/prediction_projection.dart';
import 'package:lunarlog/data/sharing/prediction_projection_publisher.dart';
import 'package:provider/provider.dart';

/// Bare-bones fake - this test never expects a real call to land on it,
/// it only needs to exist so [LunarLogApp.predictionConnectionService] is
/// non-null.
class _FakePredictionConnectionService implements PredictionConnectionService {
  @override
  Future<Set<String>> outgoingConnectedProfileIds() async => const {};

  @override
  Future<void> publishProjection({
    required String profileId,
    required PredictionProjection projection,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
      'the prediction projection publisher starts on a web/no-push shaped '
      'build (predictionConnectionService present, no scheduler, '
      'notificationPreferencesService and reminderWindowUpsert both null)',
      (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final profile = await DriftProfilesRepository(db.storage)
        .create(displayName: 'Alice', isMinor: false);
    await DriftSettingsStore(db.storage)
        .set(SettingsKeys.lastActiveProfile, profile.id);
    final connectionService = _FakePredictionConnectionService();

    await tester.pumpWidget(LunarLogApp(
      db: db,
      // No `scheduler`: mirrors a widget-test/web harness where
      // `_buildReminderCoordinator` never runs, so
      // `notificationPreferencesService`/`reminderWindowUpsert` stay at
      // their default null - the exact web/no-push AppConfig gate shape
      // in app_lifecycle.dart that left the publisher dead before this
      // fix.
      predictionConnectionService: connectionService,
    ));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(MaterialApp));
    final publisher =
        Provider.of<PredictionProjectionPublisher?>(context, listen: false);

    expect(publisher, isNotNull,
        reason: 'the publisher must start whenever predictionConnectionService '
            'is present, regardless of the push-notification gate');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  });

  testWidgets(
      'no predictionConnectionService means no publisher is provided',
      (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final profile = await DriftProfilesRepository(db.storage)
        .create(displayName: 'Alice', isMinor: false);
    await DriftSettingsStore(db.storage)
        .set(SettingsKeys.lastActiveProfile, profile.id);

    await tester.pumpWidget(LunarLogApp(db: db));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(MaterialApp));
    final publisher =
        Provider.of<PredictionProjectionPublisher?>(context, listen: false);

    expect(publisher, isNull,
        reason: 'the publisher\'s own guard must still no-op cleanly when '
            'predictionConnectionService itself is null');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  });
}
