/// `LocalHealthFlowWriteService`'s whole policy, pinned: guard-first (zero port
/// calls on any deny), opt-in (authorization requested exactly once,
/// cursor stamped at the grant instant), forward-only (pre-cursor rows are
/// never written; a clean pass advances the cursor to the newest processed
/// row; a failing pass advances nothing), cycle-start metadata from
/// episodes.dart, the A3-4 spotting branch at the service level, and the
/// one-way rule (health-store-sourced rows are never echoed back).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_flow_write_service.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import '../../support/fake_settings_store.dart';

const _profileId = 'profile-1';
const _ownerId = 'owner-user';
const _tz = 'America/New_York';
const _bindingKey = SettingsKeys.healthStoreProfileId;
const _cursorKey = SettingsKeys.healthSyncWrittenThroughMs;

Profile _profile() => Profile(
      id: _profileId,
      displayName: 'Ada',
      isMinor: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

ProfileGuardian _ownerRow() => ProfileGuardian(
      id: 'g1',
      profileId: _profileId,
      userId: _ownerId,
      role: GuardianRole.primaryGuardian,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

DayEntry _entry(
  String isoDay,
  FlowLevel flow,
  DateTime updatedAt, {
  DayEntrySource source = DayEntrySource.manual,
}) =>
    DayEntry(
      id: 'entry-$isoDay',
      profileId: _profileId,
      localDate: LocalDate.fromIso(isoDay),
      tz: _tz,
      flow: flow,
      updatedAt: updatedAt,
      source: source,
    );

Observation _spotting(
  String isoDay,
  DateTime updatedAt, {
  ObservationSource source = ObservationSource.manual,
}) =>
    Observation(
      id: 'spot-$isoDay',
      dayEntryId: 'entry-$isoDay',
      profileId: _profileId,
      localDate: LocalDate.fromIso(isoDay),
      tz: _tz,
      category: 'spotting',
      code: 'spotting',
      updatedAt: updatedAt,
      source: source,
    );

/// Records every port call; each guarded call's outcome is programmable.
class _FakePlatform implements HealthPlatformStore {
  HealthPlatformResult bindResult = const HealthPlatformAllowed();
  HealthPlatformResult authResult = const HealthPlatformAllowed();

  /// Outcomes consumed by successive write calls; the last one repeats.
  List<HealthPlatformResult> writeResults = [];
  final List<HealthMenstrualFlowWrite> flowWrites = [];
  final List<HealthIntermenstrualBleedingWrite> markerWrites = [];
  final List<HealthMenstrualPeriodWrite> periodWrites = [];
  int bindCalls = 0;
  int authCalls = 0;
  int unbindCalls = 0;

  HealthPlatformResult _nextWriteResult() => writeResults.isEmpty
      ? const HealthPlatformAllowed()
      : writeResults.length == 1
          ? writeResults.first
          : writeResults.removeAt(0);

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<HealthPlatformResult> bindProfile(HealthGuardFacts facts) async {
    bindCalls++;
    return bindResult;
  }

  @override
  Future<void> unbindProfile() async {
    unbindCalls++;
  }

  @override
  Future<HealthPlatformResult> requestWriteAuthorization(
    HealthGuardFacts facts,
  ) async {
    authCalls++;
    return authResult;
  }

  @override
  Future<HealthPlatformResult> writeMenstrualFlow(
    HealthMenstrualFlowWrite write,
  ) async {
    flowWrites.add(write);
    return _nextWriteResult();
  }

  @override
  Future<HealthPlatformResult> writeIntermenstrualBleeding(
    HealthIntermenstrualBleedingWrite write,
  ) async {
    markerWrites.add(write);
    return _nextWriteResult();
  }

  @override
  Future<HealthPlatformResult> writeMenstrualPeriod(
    HealthMenstrualPeriodWrite write,
  ) async {
    periodWrites.add(write);
    return _nextWriteResult();
  }

  @override
  Future<HealthPlatformResult> deleteRecords(
    HealthGuardFacts facts,
    List<String> recordIds,
  ) async =>
      const HealthPlatformAllowed();
}

class _FakeProfiles implements ProfilesRepository {
  Profile? profile = _profile();

  @override
  Future<Profile?> findById(String id) async => profile;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeDayEntries implements DayEntriesRepository {
  List<DayEntry> entries = const [];
  final _changes = StreamController<List<DayEntry>>.broadcast();

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => entries;

  @override
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) =>
      _changes.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeObservations implements ObservationsRepository {
  List<Observation> observations = const [];

  @override
  Future<List<Observation>> listForProfile(String profileId) async =>
      observations;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _FakePlatform platform;
  late FakeSettingsStore settings;
  late _FakeProfiles profiles;
  late _FakeDayEntries dayEntries;
  late _FakeObservations observations;
  late DateTime clock;

  LocalHealthFlowWriteService buildService() => LocalHealthFlowWriteService(
        platform: platform,
        binding: HealthSyncBinding(settings),
        minorBindingAllowed: false,
        profiles: profiles,
        dayEntries: dayEntries,
        observations: observations,
        settings: settings,
        guardiansForProfile: (_) async => [_ownerRow()],
        signedInUserId: () => _ownerId,
        now: () => clock,
      );

  /// Binds the profile and stamps the cursor as if sync was already
  /// granted at [grantedAt].
  Future<void> seedGranted(DateTime grantedAt) async {
    await settings.set(_bindingKey, _profileId);
    await settings.set(_cursorKey, '${grantedAt.millisecondsSinceEpoch}');
  }

  setUp(() {
    platform = _FakePlatform();
    settings = FakeSettingsStore();
    profiles = _FakeProfiles();
    dayEntries = _FakeDayEntries();
    observations = _FakeObservations();
    clock = DateTime.utc(2026, 6, 1, 12);
  });

  tearDown(() => settings.close());

  group('opt-in and guard', () {
    test('no binding: nothing is synced and no port call is made', () async {
      final report = await buildService().syncNow();

      expect(report.bound, isFalse);
      expect(platform.bindCalls, 0);
      expect(platform.authCalls, 0);
      expect(platform.flowWrites, isEmpty);
      expect(platform.markerWrites, isEmpty);
    });

    test('bound profile deleted from storage: treated as unbound',
        () async {
      await settings.set(_bindingKey, _profileId);
      profiles.profile = null;

      final report = await buildService().syncNow();

      expect(report.bound, isFalse);
      expect(platform.bindCalls, 0);
    });

    test('guard deny (non-owner): refused with zero port calls', () async {
      await settings.set(_bindingKey, _profileId);
      final service = LocalHealthFlowWriteService(
        platform: platform,
        binding: HealthSyncBinding(settings),
        minorBindingAllowed: false,
        profiles: profiles,
        dayEntries: dayEntries,
        observations: observations,
        settings: settings,
        guardiansForProfile: (_) async => [_ownerRow()],
        signedInUserId: () => 'someone-else',
        now: () => clock,
      );

      final report = await service.syncNow();

      expect(report.bound, isTrue);
      expect(report.blocked, isA<HealthPlatformRefused>());
      expect(
        (report.blocked! as HealthPlatformRefused).check,
        HealthSyncCheck.notOwner,
      );
      expect(platform.bindCalls, 0);
      expect(platform.authCalls, 0);
      expect(platform.flowWrites, isEmpty);
      expect(platform.markerWrites, isEmpty);
    });
  });

  group('forward-only grant', () {
    test('first pass requests authorization once and stamps the grant '
        'instant as the cursor', () async {
      await settings.set(_bindingKey, _profileId);
      final before = clock;

      final report = await buildService().syncNow();

      expect(report.authorizationRequested, isTrue);
      expect(platform.authCalls, 1);
      final cursor = await settings.get(_cursorKey);
      expect(cursor, '${before.millisecondsSinceEpoch}');
    });

    test('a second pass does not re-request authorization', () async {
      await settings.set(_bindingKey, _profileId);
      final service = buildService();
      await service.syncNow();
      await service.syncNow();

      expect(platform.authCalls, 1);
    });

    test('pre-grant entries are never backfilled; post-grant entries are',
        () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-05-30', FlowLevel.heavy,
            grant.subtract(const Duration(hours: 1))),
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
      ];

      final report = await buildService().syncNow();

      expect(report.samplesWritten, 1);
      expect(platform.flowWrites.single.date,
          LocalDate.fromIso('2026-06-02'));
    });

    test('a fully successful pass advances the cursor to the newest '
        'processed row; edits after it sync on a later pass', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      final entryUpdatedAt = grant.add(const Duration(hours: 2));
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, entryUpdatedAt),
      ];
      final service = buildService();

      await service.syncNow();
      expect(await settings.get(_cursorKey),
          '${entryUpdatedAt.millisecondsSinceEpoch}');

      // A later edit re-syncs the same day under the advanced cursor.
      clock = grant.add(const Duration(hours: 3));
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 3))),
      ];
      final report = await service.syncNow();
      expect(report.samplesWritten, 1);
      expect(platform.flowWrites.last.flow, HealthFlowValue.heavy);
    });

    test('a failed write leaves the cursor (and the failing day) to retry',
        () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      final updatedAt = grant.add(const Duration(hours: 2));
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy, updatedAt),
      ];
      platform.writeResults = [const HealthPlatformAllowed()];

      final first = await buildService().syncNow();
      expect(first.samplesWritten, 1);
      expect(first.blocked, isNull);
      expect(await settings.get(_cursorKey),
          '${updatedAt.millisecondsSinceEpoch}');

      // A later-logged day fails: the cursor stays put, so the failing day
      // (and only it — the first day's updatedAt is not after the cursor
      // any more) retries on the next pass.
      platform.writeResults = [
        const HealthPlatformPermissionDenied(),
      ];
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy, updatedAt),
        _entry('2026-06-03', FlowLevel.light,
            grant.add(const Duration(hours: 4))),
      ];
      final second = await buildService().syncNow();
      expect(second.blocked, isA<HealthPlatformPermissionDenied>());
      expect(second.samplesWritten, 0);
      expect(await settings.get(_cursorKey),
          '${updatedAt.millisecondsSinceEpoch}');

      platform.writeResults = [const HealthPlatformAllowed()];
      final third = await buildService().syncNow();
      expect(third.blocked, isNull);
      expect(third.samplesWritten, 1);
      expect(platform.markerWrites, isEmpty);
      expect(
        platform.flowWrites.last.date,
        LocalDate.fromIso('2026-06-03'),
      );
    });

    test('authorization denial does not stamp the cursor; the next pass '
        'asks again', () async {
      await settings.set(_bindingKey, _profileId);
      platform.authResult = const HealthPlatformPermissionDenied();
      final service = buildService();

      final first = await service.syncNow();
      expect(first.authorizationRequested, isTrue);
      expect(first.blocked, isA<HealthPlatformPermissionDenied>());
      expect(await settings.get(_cursorKey), isNull);

      platform.authResult = const HealthPlatformAllowed();
      final second = await service.syncNow();
      expect(second.authorizationRequested, isTrue);
      expect(platform.authCalls, 2);
      expect(await settings.get(_cursorKey), isNotNull);
    });

    test('an unavailable health store stamps the cursor (never re-prompts) '
        'and reports blocked', () async {
      await settings.set(_bindingKey, _profileId);
      platform.authResult = const HealthPlatformUnavailable();
      final service = buildService();

      final first = await service.syncNow();
      expect(first.blocked, isA<HealthPlatformUnavailable>());
      expect(await settings.get(_cursorKey), isNotNull);

      await service.syncNow();
      expect(platform.authCalls, 1);
    });
  });

  group('cycle-start metadata and mapping at the service level', () {
    test('first day of an episode gets cycleStart true; later days false',
        () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-05-30', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
        _entry('2026-05-31', FlowLevel.medium,
            grant.add(const Duration(hours: 2))),
        _entry('2026-06-02', FlowLevel.light,
            grant.add(const Duration(hours: 3))),
      ];

      final report = await buildService().syncNow();

      expect(report.samplesWritten, 3);
      final byDay = {
        for (final write in platform.flowWrites)
          write.date.iso: write.cycleStart,
      };
      // 05-30 starts the episode; 05-31 continues it; 06-02 (one-day gap)
      // is still the same merged episode per deriveEpisodes.
      expect(byDay['2026-05-30'], isTrue);
      expect(byDay['2026-05-31'], isFalse);
      expect(byDay['2026-06-02'], isFalse);
    });

    test('each write carries the entry\'s own civil date and zone', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
      ];

      await buildService().syncNow();

      final write = platform.flowWrites.single;
      expect(write.date, LocalDate.fromIso('2026-06-02'));
      expect(write.tzName, _tz);
      expect(write.flow, HealthFlowValue.heavy);
    });

    test('none and notBleeding produce no sample', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.none,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-03', FlowLevel.notBleeding,
            grant.add(const Duration(hours: 2))),
      ];

      final report = await buildService().syncNow();

      expect(report.samplesWritten, 0);
      expect(report.daysWithoutSample, 2);
      expect(platform.flowWrites, isEmpty);
      expect(platform.markerWrites, isEmpty);
    });

    test('superHeavy is written as heavy (the documented collapse)',
        () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.superHeavy,
            grant.add(const Duration(hours: 1))),
      ];

      await buildService().syncNow();

      expect(platform.flowWrites.single.flow, HealthFlowValue.heavy);
    });
  });

  group('the A3-4 spotting rule at the service level', () {
    final grant = DateTime.utc(2026, 6, 1, 12);

    test('spotting inside a period episode is a menstrual light sample '
        'carrying cycle-start metadata; outside one it is intermenstrual',
        () async {
      await seedGranted(grant);
      // Episode 05-30..06-01 (a one-day gap merges 05-30 and 06-01).
      dayEntries.entries = [
        _entry('2026-05-30', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-01', FlowLevel.heavy,
            grant.add(const Duration(hours: 2))),
      ];
      observations.observations = [
        // Inside the episode (between the two bleed days).
        _spotting('2026-05-31', grant.add(const Duration(hours: 3))),
        // Outside any episode.
        _spotting('2026-06-10', grant.add(const Duration(hours: 4))),
      ];

      final report = await buildService().syncNow();

      // Two heavy bleed samples + the in-episode spotting light sample +
      // the out-of-episode intermenstrual marker.
      expect(report.samplesWritten, 4);
      expect(platform.flowWrites, hasLength(3));
      final inside = platform.flowWrites
          .singleWhere((w) => w.date.iso == '2026-05-31');
      expect(inside.flow, HealthFlowValue.light);
      expect(inside.cycleStart, isFalse);
      expect(
        platform.markerWrites.single.date,
        LocalDate.fromIso('2026-06-10'),
      );
    });

    test('spotting on a day whose own flow already carries the intensity '
        'is skipped (no second sample for the same day)', () async {
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
      ];
      observations.observations = [
        _spotting('2026-06-02', grant.add(const Duration(hours: 2))),
      ];

      final report = await buildService().syncNow();

      expect(report.samplesWritten, 1);
      expect(report.daysWithoutSample, 1);
      expect(platform.flowWrites.single.flow, HealthFlowValue.heavy);
      expect(platform.markerWrites, isEmpty);
    });

    test('spotting that starts a merged-episode day is never the cycle '
        'start — only a bleed day can be', () async {
      await seedGranted(grant);
      // A standalone spotting observation forms no episode of its own.
      observations.observations = [
        _spotting('2026-06-10', grant.add(const Duration(hours: 1))),
      ];

      final report = await buildService().syncNow();

      expect(report.samplesWritten, 1);
      expect(platform.markerWrites, hasLength(1));
      expect(platform.flowWrites, isEmpty);
    });
  });

  group('one-way: health-store-sourced rows are never echoed back',
      () {
    final grant = DateTime.utc(2026, 6, 1, 12);

    test('healthkit/health_connect day entries are skipped', () async {
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 1)),
            source: DayEntrySource.healthkit),
        _entry('2026-06-03', FlowLevel.medium,
            grant.add(const Duration(hours: 2)),
            source: DayEntrySource.healthConnect),
        _entry('2026-06-04', FlowLevel.heavy,
            grant.add(const Duration(hours: 3))),
      ];

      final report = await buildService().syncNow();

      expect(report.samplesWritten, 1);
      expect(platform.flowWrites.single.date,
          LocalDate.fromIso('2026-06-04'));
    });

    test('health-store-sourced spotting observations are skipped', () async {
      await seedGranted(grant);
      observations.observations = [
        _spotting('2026-06-10', grant.add(const Duration(hours: 1)),
            source: ObservationSource.appleHealth),
        _spotting('2026-06-11', grant.add(const Duration(hours: 2)),
            source: ObservationSource.healthConnect),
      ];

      final report = await buildService().syncNow();

      expect(report.samplesWritten, 0);
      expect(platform.flowWrites, isEmpty);
      expect(platform.markerWrites, isEmpty);
    });
  });

  group('unbind', () {
    test('onUnbound clears the cursor and the native binding mirror',
        () async {
      await seedGranted(DateTime.utc(2026, 6, 1, 12));

      await buildService().onUnbound();

      expect(await settings.get(_cursorKey), '');
      expect(platform.unbindCalls, 1);
    });

    test('after unbind and rebind, the first pass re-requests '
        'authorization (fresh forward-only grant)', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      final service = buildService();
      await service.syncNow();
      expect(platform.authCalls, 0); // Cursor already stamped.

      await service.onUnbound();
      await settings.set(_bindingKey, _profileId);

      final report = await service.syncNow();
      expect(report.authorizationRequested, isTrue);
      expect(platform.authCalls, 1);
      expect(platform.unbindCalls, 1);
    });
  });

  group('episode derivation integration', () {
    test('a spotting-only run never forms an episode (episodes.dart rule)',
        () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      // A spotting day adjacent to a bleed day does not join the episode:
      // spotting is never part of a period, so it stays intermenstrual
      // only if it is outside — here it IS adjacent to the episode start.
      // Per episodes.dart, spotting days are not bleed days, so the
      // episode is exactly 06-01..06-02 and 05-31 sits outside it.
      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-02', FlowLevel.light,
            grant.add(const Duration(hours: 2))),
      ];
      observations.observations = [
        _spotting('2026-05-31', grant.add(const Duration(hours: 3))),
      ];

      await buildService().syncNow();

      // 05-31 is outside the episode → intermenstrual, never menstrual.
      expect(platform.markerWrites, hasLength(1));
      expect(platform.flowWrites, hasLength(2));
    });
  });

  group('period-episode interval writes (#202 AC3/AC7)', () {
    test('a still-open episode is updated (not duplicated) as new days are '
        'logged, and its final write is the finalized closed record',
        () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      final service = buildService();

      // Pass 1: an in-progress episode 06-01..06-02.
      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 2))),
      ];
      final first = await service.syncNow();
      expect(first.periodRecordsWritten, 1);
      final firstWrite = platform.periodWrites.single;
      expect(firstWrite.start, LocalDate.fromIso('2026-06-01'));
      expect(firstWrite.end, LocalDate.fromIso('2026-06-02'));
      expect(firstWrite.recordId, 'period-$_profileId-2026-06-01');
      final firstVersion = firstWrite.recordVersionMs;

      // Pass 2: the episode extends to 06-03 — the SAME clientRecordId (an
      // update, never a duplicate), a later end, a higher version.
      dayEntries.entries = [
        ...dayEntries.entries,
        _entry('2026-06-03', FlowLevel.light,
            grant.add(const Duration(hours: 3))),
      ];
      final second = await service.syncNow();
      expect(second.periodRecordsWritten, 1);
      final secondWrite = platform.periodWrites.last;
      expect(secondWrite.recordId, 'period-$_profileId-2026-06-01',
          reason: 'the same episode must reuse the same clientRecordId');
      expect(secondWrite.end, LocalDate.fromIso('2026-06-03'));
      expect(secondWrite.recordVersionMs, greaterThan(firstVersion),
          reason: 'an extending episode carries a higher clientRecordVersion');

      // Pass 3: no new days — the now-closed episode is not re-written, so
      // its last write (pass 2) is the finalized record.
      final third = await service.syncNow();
      expect(third.periodRecordsWritten, 0);
      expect(platform.periodWrites, hasLength(2));
    });

    test('a closed episode that receives no new days is not re-written; a '
        'later new episode gets its own separate record', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      final service = buildService();

      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 2))),
      ];
      await service.syncNow();
      expect(platform.periodWrites.single.recordId,
          'period-$_profileId-2026-06-01');

      // A distinct episode (gap > 1 day) starts 06-10.
      dayEntries.entries = [
        ...dayEntries.entries,
        _entry('2026-06-10', FlowLevel.heavy,
            grant.add(const Duration(hours: 4))),
      ];
      final second = await service.syncNow();
      expect(second.periodRecordsWritten, 1);
      expect(platform.periodWrites.last.recordId,
          'period-$_profileId-2026-06-10',
          reason: 'a distinct episode must get its own clientRecordId');
      expect(platform.periodWrites.last.start, LocalDate.fromIso('2026-06-10'));
    });

    test('an episode entirely before the grant cursor is never written '
        '(forward-only applies to period records too)', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-05-30', FlowLevel.heavy,
            grant.subtract(const Duration(hours: 1))),
        _entry('2026-05-31', FlowLevel.medium,
            grant.subtract(const Duration(minutes: 30))),
      ];

      final report = await buildService().syncNow();

      expect(report.periodRecordsWritten, 0);
      expect(platform.periodWrites, isEmpty);
    });

    test('the interval record derives its instants from the entry\'s own '
        'zone, carried through the write (#180)', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 2))),
      ];

      await buildService().syncNow();

      final write = platform.periodWrites.single;
      expect(write.tzName, _tz);
      expect(write.start, LocalDate.fromIso('2026-06-01'));
      expect(write.end, LocalDate.fromIso('2026-06-02'));
      expect(write.recordVersionMs, isPositive);
    });

    test('a platform that answers unavailable for the period record is '
        'skipped gracefully, not a pass-blocking failure (HealthKit has no '
        'period-record type, #193)', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
      ];
      // Flow writes succeed; the period record is unavailable.
      platform.writeResults = [
        const HealthPlatformAllowed(),
        const HealthPlatformUnavailable(),
      ];

      final report = await buildService().syncNow();

      expect(report.samplesWritten, 1);
      expect(report.periodRecordsWritten, 0);
      expect(report.blocked, isNull,
          reason: 'unavailable period-record support must not block the pass');
    });

    test('a failing period write blocks the pass like any failing write',
        () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
      ];
      platform.writeResults = [
        const HealthPlatformAllowed(), // flow write
        const HealthPlatformPermissionDenied(), // period write
      ];

      final report = await buildService().syncNow();

      expect(report.blocked, isA<HealthPlatformPermissionDenied>());
      // The cursor does not advance (blocked), so the next pass retries.
      expect(await settings.get(_cursorKey),
          '${grant.millisecondsSinceEpoch}');
    });
  });

  // Sanity pin on the bleed-day set the service derives from: keeps the
  // episode-membership facts above honest against episodes.dart itself.
  test('bleedDatesOf excludes spotting and none, includes superHeavy',
      () {
    final entries = [
      _entry('2026-06-01', FlowLevel.superHeavy, DateTime.utc(2026, 6, 1)),
      _entry('2026-06-02', FlowLevel.none, DateTime.utc(2026, 6, 2)),
    ];
    expect(bleedDatesOf(entries).map((d) => d.iso).toList(),
        ['2026-06-01']);
  });
}
