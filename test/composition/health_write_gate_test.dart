/// The health write gate (Issue #1478): one answer to "does this platform
/// write to its OS health store", read by both places that used to decide
/// it for themselves.
///
/// Before #1478 the composition root kept its own platform set
/// (`_healthWritePlatforms = {TargetPlatform.iOS}`) and the Settings screen
/// its own comparison (`defaultTargetPlatform == TargetPlatform.iOS`). On
/// Android the app asked Health Connect for five write permissions and then
/// never built the coordinator that writes — and nothing tied the screen's
/// description of the feature to whether that coordinator existed.
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/composition/app_dependencies.dart';
import 'package:lunarlog/config.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/domain/health/health_flow_write_service.dart'
    show HealthWritePassQueue;

/// Runs the queued action at once. The gate test only checks whether the
/// coordinators are built, not how they queue (Issue #1614).
class _UnusedPassQueue implements HealthWritePassQueue {
  const _UnusedPassQueue();

  @override
  Future<T> runInPassQueue<T>(Future<T> Function() action) => action();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late AppDependencies deps;
  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    deps = buildAppDependencies(db: db);
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await db.close();
  });

  Object? writeCoordinatorOn(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    final built = buildHealthFlowWriteService(
      settings: deps.settings,
      profiles: deps.profiles,
      dayEntries: deps.dayEntries,
      observations: deps.observations,
      guardiansForProfile: deps.profileGuardians.getForProfile,
      signedInUserId: () => null,
      minorBindingAllowed: AppConfig.healthSyncMinorBindingAllowed,
      ledger: deps.healthExportLedger,
    );
    if (built == null) return null;
    return buildHealthFlowWriteCoordinator(
      service: built.service,
      binding: built.binding,
      dayEntries: deps.dayEntries,
    );
  }

  Object? tombstoneCoordinatorOn(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    return buildHealthSyncTombstoneCoordinator(
      settings: deps.settings,
      profiles: deps.profiles,
      tombstoneSource: deps.healthSyncTombstoneSource,
      guardiansForProfile: deps.profileGuardians.getForProfile,
      signedInUserId: () => null,
      ledger: deps.healthExportLedger,
      // The gate test does not exercise the queue; the write path's own
      // builder test and the coordinator's tests cover it (Issue #1614).
      passQueue: const _UnusedPassQueue(),
    );
  }

  group('AppConfig.healthSyncWritesOn', () {
    test('Android writes to Health Connect, as iOS writes to Apple Health, '
        'and no platform without a health store writes', () {
      expect(AppConfig.healthSyncWritesOn(TargetPlatform.android), isTrue);
      expect(AppConfig.healthSyncWritesOn(TargetPlatform.iOS), isTrue);
      for (final platform in [
        TargetPlatform.fuchsia,
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        expect(AppConfig.healthSyncWritesOn(platform), isFalse,
            reason: '$platform');
      }
      expect(AppConfig.healthSyncWritePlatforms, {
        TargetPlatform.iOS,
        TargetPlatform.android,
      });
    });
  });

  group('the composition root builds the write path from that answer', () {
    test('Android gets a write coordinator and a tombstone coordinator, and '
        'every platform gets them exactly where AppConfig says writes are on',
        () {
      expect(writeCoordinatorOn(TargetPlatform.android), isNotNull);
      expect(tombstoneCoordinatorOn(TargetPlatform.android), isNotNull);
      for (final platform in TargetPlatform.values) {
        final expected = AppConfig.healthSyncWritesOn(platform);
        expect(writeCoordinatorOn(platform) != null, expected,
            reason: 'write coordinator on $platform');
        expect(tombstoneCoordinatorOn(platform) != null, expected,
            reason: 'tombstone coordinator on $platform');
      }
    });
  });

  group('one source of truth', () {
    String source(String path) => File(path).readAsStringSync();

    test('the composition root keeps no platform list of its own for writes',
        () {
      final composition = source('lib/composition/app_dependencies.dart');
      expect(composition, isNot(contains('_healthWritePlatforms')));
      expect(
        'AppConfig.healthSyncWritesOn('.allMatches(composition),
        hasLength(1),
        reason: 'one helper asks; both write-side builders use the helper',
      );
      expect(
        '_healthWritesOnThisPlatform()'.allMatches(composition),
        hasLength(3),
        reason: 'the helper, the write service builder, the tombstone '
            'coordinator',
      );
    });

    test('the Settings screen asks AppConfig rather than comparing the '
        'platform itself', () {
      final settings = source('lib/ui/settings/settings_screen.dart');
      expect(
        settings,
        contains(
          'writeEnabled: AppConfig.healthSyncWritesOn(defaultTargetPlatform)',
        ),
      );
      expect(
        settings,
        isNot(contains('writeEnabled: defaultTargetPlatform ==')),
      );
    });
  });

  // Issue #1581. The write pass stamps its forward-only floor when access
  // is granted and compares rows with it. Rows are stamped by the storage
  // clock (the device's, plus what sync has learned of the server's), so
  // the floor has to be stamped by the same one.
  group('the write pass is handed the clock rows are stamped with', () {
    test('the composition root\'s clock follows the offset the storage '
        'layer has learned', () {
      const offset = Duration(minutes: 5);
      final before = DateTime.now().toUtc();
      expect(
        deps.localWriteClock().difference(before).abs(),
        lessThan(const Duration(minutes: 1)),
      );

      db.storage.setClockOffset(offset);
      final stamped = deps.localWriteClock();

      expect(stamped.isUtc, isTrue);
      expect(
        stamped.difference(before.add(offset)).abs(),
        lessThan(const Duration(minutes: 1)),
      );
    });

    test('and the app and the builder pass it through to the service', () {
      String source(String path) => File(path).readAsStringSync();
      expect(
        source('lib/app.dart'),
        contains('rowClock: _deps.localWriteClock,'),
      );
      expect(
        source('lib/composition/app_dependencies.dart'),
        contains('    rowClock: rowClock,'),
      );
    });
  });
}
