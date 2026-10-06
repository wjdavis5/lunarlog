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
import 'package:lunarlog/data/health/health_record_ids.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/health/health_export_ledger.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';

import '../../support/fake_health_export_ledger.dart';
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

/// The accepted `primary_guardian` row after an ownership transfer away
/// from [_ownerId] — used by the mid-pass authority-drift regression
/// (Issue #620, LLA-023) to simulate a transfer completing between two of
/// the same pass's writes.
ProfileGuardian _transferredRow() => ProfileGuardian(
      id: 'g2',
      profileId: _profileId,
      userId: 'new-owner',
      role: GuardianRole.primaryGuardian,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

DayEntry _entry(
  String isoDay,
  FlowLevel flow,
  DateTime updatedAt, {
  DayEntrySource source = DayEntrySource.manual,
  List<String> tags = const [],
}) =>
    DayEntry(
      id: 'entry-$isoDay',
      profileId: _profileId,
      localDate: LocalDate.fromIso(isoDay),
      tz: _tz,
      flow: flow,
      tags: tags,
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
      category: ObservationCategory.spotting,
      code: 'spotting',
      updatedAt: updatedAt,
      source: source,
    );

/// A graded pain row (issue #238's severity input) for [isoDay]'s [code].
Observation _pain(
  String isoDay,
  String code,
  int intensity,
  DateTime updatedAt,
) =>
    Observation(
      id: 'pain-$isoDay-$code',
      dayEntryId: 'entry-$isoDay',
      profileId: _profileId,
      localDate: LocalDate.fromIso(isoDay),
      tz: _tz,
      category: ObservationCategory.pain,
      code: code,
      intensity: intensity,
      updatedAt: updatedAt,
    );

/// A manually tracked BBT row for [isoDay] (issue #228's numeric signal).
Observation _bbt(
  String isoDay,
  double celsius,
  DateTime updatedAt, {
  bool excluded = false,
}) =>
    Observation(
      id: 'obs-bbt-$isoDay',
      dayEntryId: 'entry-$isoDay',
      profileId: _profileId,
      localDate: LocalDate.fromIso(isoDay),
      tz: _tz,
      category: ObservationCategory.bbt,
      valueNum: celsius,
      unit: 'celsius',
      excluded: excluded,
      updatedAt: updatedAt,
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
  final List<List<String>> deleteCalls = [];
  int bindCalls = 0;
  int authCalls = 0;
  int unbindCalls = 0;
  HealthPlatformResult deleteResult = const HealthPlatformAllowed();

  HealthPlatformResult _nextWriteResult() => writeResults.isEmpty
      ? const HealthPlatformAllowed()
      : writeResults.length == 1
          ? writeResults.first
          : writeResults.removeAt(0);

  @override
  Future<bool> isAvailable() async => true;

  /// Issue #959: the OS write-permission state the sync pass re-checks each
  /// pass. Granted by default so every pre-#959 test keeps passing; a test
  /// sets this to [HealthPermissionStatus.denied] to prove a revoked
  /// permission stops the pass. Since Issue #1478 a granted permission
  /// means the pass has nothing to ask, so the tests about the request
  /// itself set [HealthPermissionStatus.notAsked], the state a real first
  /// pass meets.
  HealthPermissionStatus permission = HealthPermissionStatus.granted;
  int permissionStatusCalls = 0;

  /// What [permission] becomes once [requestWriteAuthorization] has
  /// answered allowed: the state the permission sheet left behind. Granted
  /// by default (the person allowed the writes); a test sets
  /// [HealthPermissionStatus.denied] for a sheet that was answered without
  /// them — Android's request still answers allowed if any permission, a
  /// read for instance, was granted (Issue #1478).
  HealthPermissionStatus permissionAfterAuth = HealthPermissionStatus.granted;

  @override
  Future<HealthPermissionStatus> permissionStatus() async {
    permissionStatusCalls++;
    return permission;
  }

  /// Issue #1491: the read-side probe gates the background import and
  /// nothing else. Programmable and counted so a test can prove a write
  /// pass is neither stopped by it nor reads it.
  HealthPermissionStatus importPermission = HealthPermissionStatus.granted;
  int importPermissionStatusCalls = 0;

  @override
  Future<HealthPermissionStatus> importPermissionStatus() async {
    importPermissionStatusCalls++;
    return importPermission;
  }

  /// Issue #1515: whether the store discloses read access is the status
  /// line's question and never a write pass's. Counted so a test can prove
  /// the pass does not read it.
  int readAccessDisclosedReads = 0;

  @override
  bool get readAccessDisclosed {
    readAccessDisclosedReads++;
    return true;
  }

  /// Issue #1549: a read-side question, like the two above. Counted with
  /// them, so the same assertions prove a write pass never asks it.
  @override
  Future<bool> importReachesPastData() async {
    readAccessDisclosedReads++;
    return true;
  }

  /// Issue #1515: the import's own request. The write pass has its own
  /// ([requestWriteAuthorization]); counted so a test can prove it never
  /// raises this one instead.
  int importAuthCalls = 0;

  @override
  Future<HealthPlatformResult> requestImportAuthorization(
    HealthGuardFacts facts,
  ) async {
    importAuthCalls++;
    return const HealthPlatformAllowed();
  }

  @override
  Future<void> openPermissionSettings() async {}

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
    if (authResult is HealthPlatformAllowed) permission = permissionAfterAuth;
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
  Future<HealthPlatformResult> writeSymptomSamples(
    HealthSymptomSamplesWrite write,
  ) async =>
      const HealthPlatformResult.allowed();

  // Issue #228: this fake predates the fertility/measurement port methods.
  // The tests here exercise the flow path; the new types get their own
  // service tests, so these simply succeed.
  @override
  Future<HealthPlatformResult> writeCervicalMucus(
    HealthCervicalMucusWrite write,
  ) async =>
      const HealthPlatformResult.allowed();

  @override
  Future<HealthPlatformResult> writeOvulationTest(
    HealthOvulationTestWrite write,
  ) async =>
      const HealthPlatformResult.allowed();

  @override
  Future<HealthPlatformResult> writeBasalBodyTemperature(
    HealthBasalBodyTemperatureWrite write,
  ) async =>
      const HealthPlatformResult.allowed();

  @override
  Future<HealthPlatformResult> deleteRecords(
    HealthGuardFacts facts,
    List<String> recordIds,
  ) async {
    deleteCalls.add(List.of(recordIds));
    return deleteResult;
  }
}

/// A [_FakePlatform] that also keeps the BBT writes it is handed (Issue
/// #1478's future-time rule needs the instant the service chose).
class _BbtRecordingPlatform extends _FakePlatform {
  final List<HealthBasalBodyTemperatureWrite> bbtWrites = [];

  @override
  Future<HealthPlatformResult> writeBasalBodyTemperature(
    HealthBasalBodyTemperatureWrite write,
  ) async {
    bbtWrites.add(write);
    return const HealthPlatformResult.allowed();
  }
}

class _FakeProfiles implements ProfilesRepository {
  Profile? profile = _profile();

  @override
  Future<Profile?> findById(String id) async => profile;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A [ProfilesRepository] whose [findById] answer is driven by a callback
/// invoked on every call — for the mid-pass authority-drift regression
/// (Issue #620, LLA-023) that needs the profile lookup to change its
/// answer partway through a single sync pass.
class _FlakyProfiles implements ProfilesRepository {
  _FlakyProfiles({required this.onFind});

  final Profile? Function() onFind;

  @override
  Future<Profile?> findById(String id) async => onFind();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeDayEntries implements DayEntriesRepository {
  List<DayEntry> entries = const [];
  // Issue #548: a per-test fake with no close() call — the test process is
  // short-lived and nothing in this file ever emits on it, so there is no
  // real leak to guard against.
  // ignore: close_sinks
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
  late FakeHealthExportLedger ledger;
  late DateTime clock;

  LocalHealthFlowWriteService buildService() => LocalHealthFlowWriteService(
        platform: platform,
        binding: HealthSyncBinding(settings),
        minorBindingAllowed: false,
        profiles: profiles,
        dayEntries: dayEntries,
        observations: observations,
        settings: settings,
        ledger: ledger,
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
    ledger = FakeHealthExportLedger();
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
        ledger: ledger,
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

    // Issue #959: the OS write permission is re-checked on every pass, not
    // only on the first write, so a revocation in OS settings stops the very
    // next pass — before the native bind mirror, before any write, and with
    // no health content or exception text in the report.
    test('a revoked OS write permission stops the pass before any port call',
        () async {
      await seedGranted(clock.subtract(const Duration(hours: 1)));
      platform.permission = HealthPermissionStatus.denied;

      final report = await buildService().syncNow();

      expect(report.bound, isTrue);
      expect(report.blocked, isA<HealthPlatformPermissionDenied>());
      expect(platform.permissionStatusCalls, 1);
      expect(platform.bindCalls, 0,
          reason: 'the permission re-check precedes the native bind mirror');
      expect(platform.authCalls, 0);
      expect(platform.flowWrites, isEmpty);
      expect(platform.markerWrites, isEmpty);
      expect(platform.deleteCalls, isEmpty);
    });

    // Issue #1491: the background import moved to a read-side probe of its
    // own. The write pass is still decided by the write permissions alone:
    // reads that are off must not stop a write, and the write pass must not
    // read that probe at all.
    test('the read-side probe is not the write pass\'s: reads off and '
        'writes on still writes, and the probe is never read', () async {
      final grant = clock.subtract(const Duration(hours: 1));
      await seedGranted(grant);
      platform.importPermission = HealthPermissionStatus.denied;
      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.medium, clock),
      ];

      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      expect(report.samplesWritten, 1);
      expect(platform.flowWrites.single.date, LocalDate.fromIso('2026-06-01'));
      expect(platform.permissionStatusCalls, 1);
      expect(platform.importPermissionStatusCalls, 0);
    });

    test('a not-yet-asked permission does not block — the grant stage asks',
        () async {
      await settings.set(_bindingKey, _profileId);
      platform.permission = HealthPermissionStatus.notAsked;

      await buildService().syncNow();

      // Once before the pass, and once more after the request: an allowed
      // request says the sheet was answered, not that the writes were
      // granted (Issue #1478's review).
      expect(platform.permissionStatusCalls, 2);
      expect(platform.authCalls, 1,
          reason: 'notAsked is the first-pass grant moment, not a revocation');
    });

    test('an unavailable permission surface does not block the pass',
        () async {
      await seedGranted(clock.subtract(const Duration(hours: 1)));
      platform.permission = HealthPermissionStatus.unavailable;

      final report = await buildService().syncNow();

      expect(report.blocked, isNull,
          reason: 'unavailable is a platform state, not a revocation');
    });
  });

  group('forward-only grant', () {
    // The state a first pass meets: the OS has not been asked yet (Issue
    // #1478 — an already-granted permission is not asked for again).
    setUp(() => platform.permission = HealthPermissionStatus.notAsked);

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

    // Issue #1577. A row's `updatedAt` carries microseconds and the cursor
    // is stored in milliseconds. Compared exactly, the newest row a pass
    // wrote was still after the cursor by its microseconds, and was sent
    // to the health store again on every pass. Every other time in this
    // file is a whole second, which is why none of them noticed.
    test('a pass with nothing changed writes nothing, although the newest '
        'row was saved between two milliseconds', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      final savedAt = grant.add(const Duration(hours: 2, microseconds: 455));
      final spottedAt = grant.add(const Duration(hours: 1, microseconds: 217));
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, savedAt),
        _entry('2026-06-20', FlowLevel.none, spottedAt),
      ];
      observations.observations = [_spotting('2026-06-20', spottedAt)];
      final service = buildService();

      final first = await service.syncNow();
      expect(first.blocked, isNull);
      expect(platform.flowWrites, hasLength(1));
      expect(platform.markerWrites, hasLength(1));
      expect(await settings.get(_cursorKey),
          '${savedAt.millisecondsSinceEpoch}');

      // The same service, and then a new one, as after a restart.
      for (final again in [service, buildService()]) {
        final report = await again.syncNow();
        expect(report.blocked, isNull);
        expect(report.samplesWritten, 0);
        expect(platform.flowWrites, hasLength(1));
        expect(platform.markerWrites, hasLength(1));
      }

      // An edit one millisecond later is after the cursor, and is written.
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy,
            savedAt.add(const Duration(milliseconds: 1))),
        _entry('2026-06-20', FlowLevel.none, spottedAt),
      ];
      await service.syncNow();
      expect(platform.flowWrites, hasLength(2));
      expect(platform.flowWrites.last.flow, HealthFlowValue.heavy);
      expect(platform.markerWrites, hasLength(1));
    });

    // The other side of deciding in whole milliseconds, stated so that it
    // is a choice and not an accident: a row stamped inside the cursor's
    // own millisecond is not after it.
    test('a row stamped within the cursor\'s own millisecond is not after '
        'it', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(microseconds: 900))),
      ];
      final report = await buildService().syncNow();
      expect(report.samplesWritten, 0);
      expect(platform.flowWrites, isEmpty);
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

    test('none and notBleeding produce no sample, and each issues a '
        'reconciliation delete for its own recordId (issue #619, LLA-024)',
        () async {
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
      // A day that was never exported has no matching store sample, so
      // this delete is a documented no-op — issued unconditionally rather
      // than only when a prior export is known to have happened (see
      // _resolveNoWriteOutcome's doc comment).
      expect(report.samplesReconciled, 2);
      expect(platform.deleteCalls, [
        ['entry-2026-06-02'],
        ['entry-2026-06-03'],
      ]);
    });

    test(
        'issue #619, LLA-024: a day exported as bleeding then edited to '
        'notBleeding reconciles away the prior sample by its own recordId',
        () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      // First pass: an exportable day is actually written to the store.
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
      ];
      final service = buildService();
      final firstReport = await service.syncNow();
      expect(firstReport.samplesWritten, 1);
      expect(platform.flowWrites.single.recordId, 'entry-2026-06-02');

      // Second pass: the SAME entry is edited to notBleeding after the
      // first pass's cursor — pre-#619 fix, the writer silently skipped
      // this instead of reconciling the now-stale sample it had written.
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.notBleeding,
            grant.add(const Duration(hours: 3))),
      ];
      final secondReport = await service.syncNow();

      expect(secondReport.samplesWritten, 0);
      expect(secondReport.samplesReconciled, 1);
      // The day's own sample, then (Issue #1478) the one-day period record
      // the first pass wrote for it — that day was the whole episode.
      expect(platform.deleteCalls, [
        ['entry-2026-06-02'],
        ['period-$_profileId-2026-06-02'],
      ]);
    });

    test(
        'issue #619, LLA-024: a refused reconciliation delete blocks the '
        'pass and leaves the cursor for a retry, like any other failure',
        () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      platform.deleteResult =
          const HealthPlatformResult.failed('store unavailable');
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.none,
            grant.add(const Duration(hours: 1))),
      ];

      final report = await buildService().syncNow();

      expect(report.blocked, isA<HealthPlatformFailed>());
      expect(
        await settings.get(_cursorKey),
        '${grant.millisecondsSinceEpoch}',
        reason: 'a failed reconciliation must not advance the cursor',
      );
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
      // A re-bind on a device where the OS has yet to be asked (Issue
      // #1478: with the permission already granted there is nothing to ask,
      // and the fresh cursor is stamped without a request).
      platform.permission = HealthPermissionStatus.notAsked;

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

  // Issue #1478: the interval record is the one export no single day entry
  // owns, so the write path reconciles it itself. Before, the only thing
  // that ever touched a period record was "an eligible bleed day re-writes
  // its episode's record" — and on an Android emulator that left Health
  // Connect holding a period for a day whose flow had been cleared, and two
  // overlapping periods after an earlier day was logged.
  group('issue #1478: period records follow the episode they describe', () {
    final grant = DateTime.utc(2026, 6, 1, 12);

    HealthExportLedgerEntry? periodRow(String recordId) {
      for (final row in ledger.rows) {
        if (row.recordId == recordId) return row;
      }
      return null;
    }

    test('clearing the only bleed day deletes the period record too',
        () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
      ];
      await service.syncNow();
      expect(platform.periodWrites.single.recordId,
          'period-$_profileId-2026-06-02');
      expect(periodRow('period-$_profileId-2026-06-02')?.kind,
          HealthExportLedgerKind.period);

      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.none,
            grant.add(const Duration(hours: 2))),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(platform.deleteCalls,
          contains(equals(['period-$_profileId-2026-06-02'])));
      expect(platform.periodWrites, hasLength(1),
          reason: 'a period that no longer exists is not written again');
      expect(periodRow('period-$_profileId-2026-06-02'), isNull,
          reason: 'the ledger row leaves with the store record');
    });

    test('a deleted (tombstoned) only bleed day deletes the period record',
        () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
      ];
      await service.syncNow();

      // The repository lists live rows only, so a deleted day is simply
      // absent — there is no eligible row at all on this pass.
      dayEntries.entries = [];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(platform.deleteCalls, [
        ['period-$_profileId-2026-06-02'],
      ]);
    });

    test('logging an earlier day replaces the record rather than adding a '
        'second, overlapping one', () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-05', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
      ];
      await service.syncNow();
      expect(platform.periodWrites.single.recordId,
          'period-$_profileId-2026-06-05');

      // The day before is logged: the episode now starts on 06-04, and the
      // record id is derived from the first day.
      dayEntries.entries = [
        ...dayEntries.entries,
        _entry('2026-06-04', FlowLevel.light,
            grant.add(const Duration(hours: 2))),
      ];
      await service.syncNow();

      expect(platform.periodWrites.last.recordId,
          'period-$_profileId-2026-06-04');
      expect(platform.periodWrites.last.end, LocalDate.fromIso('2026-06-05'));
      expect(platform.deleteCalls,
          contains(equals(['period-$_profileId-2026-06-05'])),
          reason: 'the record keyed on the old first day must not survive');
      expect(periodRow('period-$_profileId-2026-06-05'), isNull);
      expect(periodRow('period-$_profileId-2026-06-04')?.sourceRowId,
          '2026-06-04/2026-06-05');
    });

    test('removing the last day shortens the record: the shorter interval '
        'is written over it at a higher version, although no bleed day in it '
        'is newly edited — and only for a period this device exported',
        () async {
      await seedGranted(grant);
      final service = buildService();
      // An older period, logged before sync was turned on: never exported
      // (forward-only), so never this pass's to correct.
      final before = [
        _entry('2026-05-20', FlowLevel.heavy,
            grant.subtract(const Duration(hours: 3))),
        _entry('2026-05-21', FlowLevel.medium,
            grant.subtract(const Duration(hours: 2))),
      ];
      final after = [
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-03', FlowLevel.medium,
            grant.add(const Duration(hours: 2))),
        _entry('2026-06-04', FlowLevel.light,
            grant.add(const Duration(hours: 3))),
      ];
      dayEntries.entries = [...before, ...after];
      await service.syncNow();
      final firstWrite = platform.periodWrites.single;
      expect(firstWrite.end, LocalDate.fromIso('2026-06-04'));

      // The last day of each period is removed.
      clock = grant.add(const Duration(hours: 5));
      dayEntries.entries = [before.first, ...after.sublist(0, 2)];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(platform.deleteCalls, isEmpty,
          reason: 'the same record is written again, not removed; and the '
              'older period, which this device never wrote, is not touched');
      final rewrite = platform.periodWrites.last;
      expect(platform.periodWrites, hasLength(2));
      expect(rewrite.recordId, 'period-$_profileId-2026-06-02');
      expect(rewrite.start, LocalDate.fromIso('2026-06-02'));
      expect(rewrite.end, LocalDate.fromIso('2026-06-03'));
      expect(rewrite.tzName, _tz);
      expect(rewrite.recordVersionMs, clock.millisecondsSinceEpoch);
      expect(rewrite.recordVersionMs, greaterThan(firstWrite.recordVersionMs));
      expect(periodRow('period-$_profileId-2026-06-02')?.sourceRowId,
          '2026-06-02/2026-06-03');
      expect(periodRow('period-$_profileId-2026-05-20'), isNull);

      // Nothing changed since: the corrected record is left alone.
      await service.syncNow();
      expect(platform.periodWrites, hasLength(2));
    });

    test('a refused period delete blocks the pass, keeps the record '
        'remembered, and is retried', () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
      ];
      await service.syncNow();

      dayEntries.entries = [];
      platform.deleteResult = const HealthPlatformPermissionDenied();
      final refused = await service.syncNow();
      expect(refused.blocked, isA<HealthPlatformPermissionDenied>());
      expect(periodRow('period-$_profileId-2026-06-02'), isNotNull);

      platform.deleteResult = const HealthPlatformAllowed();
      final retried = await service.syncNow();
      expect(retried.blocked, isNull);
      expect(platform.deleteCalls, hasLength(2));
      expect(periodRow('period-$_profileId-2026-06-02'), isNull);
    });

    test('a shorter interval whose write fails stays owed, with the record '
        'it replaces still in place: the next pass writes it', () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-03', FlowLevel.medium,
            grant.add(const Duration(hours: 2))),
      ];
      await service.syncNow();

      dayEntries.entries = dayEntries.entries.sublist(0, 1);
      platform.writeResults = [const HealthPlatformResult.failed('store busy')];
      final failed = await service.syncNow();
      expect(failed.blocked, isA<HealthPlatformFailed>());
      expect(platform.deleteCalls, isEmpty,
          reason: 'nothing is removed while its replacement is still owed');
      expect(periodRow('period-$_profileId-2026-06-02')?.sourceRowId,
          '2026-06-02/2026-06-03',
          reason: 'still remembered with the interval the store last took');

      platform.writeResults = [const HealthPlatformAllowed()];
      final retried = await service.syncNow();
      expect(retried.blocked, isNull);
      expect(platform.periodWrites.last.end, LocalDate.fromIso('2026-06-02'));
      expect(periodRow('period-$_profileId-2026-06-02')?.sourceRowId,
          '2026-06-02/2026-06-02');
    });

    test('the record is still reconciled after a relaunch (the ledger is '
        'what remembers it)', () async {
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
      ];
      await buildService().syncNow();

      // A fresh service: nothing in memory, only the persisted ledger.
      dayEntries.entries = [];
      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      expect(platform.deleteCalls, [
        ['period-$_profileId-2026-06-02'],
      ]);
    });

    test('a mid-pass loss of authority stops the period correction with no '
        'store call', () async {
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
      ];
      await buildService().syncNow();

      dayEntries.entries = [];
      // Authority is intact when the pass starts and gone by the time the
      // correction is reached: the pass's first session lookup answers the
      // owner, every later one somebody else.
      var lookups = 0;
      final drifting = LocalHealthFlowWriteService(
        platform: platform,
        binding: HealthSyncBinding(settings),
        minorBindingAllowed: false,
        profiles: profiles,
        dayEntries: dayEntries,
        observations: observations,
        settings: settings,
        ledger: ledger,
        guardiansForProfile: (_) async => [_ownerRow()],
        signedInUserId: () => lookups++ == 0 ? _ownerId : 'someone-else',
        now: () => clock,
      );
      final report = await drifting.syncNow();

      expect(report.blocked, isA<HealthPlatformRefused>());
      expect(platform.deleteCalls, isEmpty,
          reason: 'the #153 guard is re-checked before the correction');
      expect(periodRow('period-$_profileId-2026-06-02'), isNotNull);
    });

    test('an episode longer than Health Connect accepts writes its daily '
        'flow but no interval record', () async {
      await seedGranted(grant);
      final first = LocalDate.fromIso('2026-06-02');
      dayEntries.entries = [
        for (var day = 0; day <= kHealthPeriodRecordMaxDays; day++)
          _entry(first.addDays(day).iso, FlowLevel.light,
              grant.add(Duration(hours: 1, minutes: day))),
      ];

      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      expect(report.samplesWritten, kHealthPeriodRecordMaxDays + 1);
      expect(platform.periodWrites, isEmpty);
    });

    test('an exported period that grows past the limit is removed rather '
        'than left describing a shorter period', () async {
      await seedGranted(grant);
      final first = LocalDate.fromIso('2026-06-02');
      final service = buildService();
      dayEntries.entries = [
        for (var day = 0; day < kHealthPeriodRecordMaxDays; day++)
          _entry(first.addDays(day).iso, FlowLevel.light,
              grant.add(Duration(hours: 1, minutes: day))),
      ];
      await service.syncNow();
      expect(platform.periodWrites.single.end,
          first.addDays(kHealthPeriodRecordMaxDays - 1));

      dayEntries.entries = [
        ...dayEntries.entries,
        _entry(first.addDays(kHealthPeriodRecordMaxDays).iso, FlowLevel.light,
            grant.add(const Duration(hours: 4))),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(platform.periodWrites, hasLength(1));
      expect(platform.deleteCalls,
          contains(equals(['period-$_profileId-${first.iso}'])));
    });

    test('the correction belongs to one binding: it happens while bound, '
        'and unbinding forgets the exported periods with the rest of the '
        'ledger', () async {
      await seedGranted(grant);
      final service = buildService();
      final days = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-03', FlowLevel.medium,
            grant.add(const Duration(hours: 2))),
      ];
      dayEntries.entries = days;
      await service.syncNow();

      // While bound, a removed day is corrected in the store.
      dayEntries.entries = [days.first];
      await service.syncNow();
      expect(platform.periodWrites, hasLength(2));
      expect(platform.periodWrites.last.end, LocalDate.fromIso('2026-06-02'));

      await service.onUnbound();
      expect(ledger.rows, isEmpty);

      // Re-bound, already granted, the remaining day now gone too: that
      // record was written under the earlier binding, so it is left in
      // place — what the screen says turning sync off does.
      await seedGranted(grant.add(const Duration(hours: 4)));
      dayEntries.entries = [];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(platform.deleteCalls, isEmpty);
      expect(platform.periodWrites, hasLength(2));
    });
  });

  group('issue #1478: the write pass asks only when it has not asked', () {
    test('a permission that is already granted stamps the cursor and asks '
        'nothing', () async {
      await settings.set(_bindingKey, _profileId);
      platform.permission = HealthPermissionStatus.granted;

      final report = await buildService().syncNow();

      expect(platform.authCalls, 0,
          reason: 'on Android the request carries the read permissions too, '
              'so asking here could raise the sheet again for one the person '
              'had just declined');
      expect(report.authorizationRequested, isFalse);
      expect(report.blocked, isNull);
      expect(await settings.get(_cursorKey),
          '${clock.millisecondsSinceEpoch}');
    });

    test('a day logged after that stamp is written', () async {
      await settings.set(_bindingKey, _profileId);
      platform.permission = HealthPermissionStatus.granted;
      final service = buildService();
      await service.syncNow();

      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.medium,
            clock.add(const Duration(minutes: 5))),
      ];
      final report = await service.syncNow();

      expect(report.samplesWritten, 1);
      expect(platform.authCalls, 0);
    });
  });

  // Issue #1515. The import asks through a request of its own now, for the
  // reads alone. Nothing about the write pass moved: it asks where it
  // always did, through its own request, in the not-yet-asked state — and
  // on Android that is the state someone who has only ever tapped Import is
  // in for the writes, because being asked for the reads is not being asked
  // for the writes.
  group('issue #1515: the write pass still asks through its own request', () {
    test('a first pass raises the write path\'s request, never the '
        'import\'s, and does not ask what the store discloses', () async {
      await settings.set(_bindingKey, _profileId);
      platform.permission = HealthPermissionStatus.notAsked;

      final report = await buildService().syncNow();

      expect(platform.authCalls, 1);
      expect(platform.importAuthCalls, 0);
      expect(platform.readAccessDisclosedReads, 0);
      expect(report.authorizationRequested, isTrue);
    });

    test('reads on and the writes not yet asked: the pass asks for the '
        'writes, whatever the read side says', () async {
      await settings.set(_bindingKey, _profileId);
      // The reads are already allowed (she tapped Import and said yes); the
      // write sheet has never been shown.
      platform.importPermission = HealthPermissionStatus.granted;
      platform.permission = HealthPermissionStatus.notAsked;
      // She declines the writes on the sheet the pass raises.
      platform.permissionAfterAuth = HealthPermissionStatus.denied;

      final report = await buildService().syncNow();

      expect(platform.authCalls, 1,
          reason: 'never having been shown the writes must not stop the '
              'write path from asking');
      expect(platform.importAuthCalls, 0);
      expect(platform.importPermissionStatusCalls, 0);
      expect(report.blocked, isA<HealthPlatformPermissionDenied>());
      expect(await settings.get(_cursorKey), isNull,
          reason: 'no write access, so nothing is dated from this moment');
    });

    test('writes declined: the pass stops before either request', () async {
      await settings.set(_bindingKey, _profileId);
      platform.importPermission = HealthPermissionStatus.granted;
      platform.permission = HealthPermissionStatus.denied;

      final report = await buildService().syncNow();

      expect(report.blocked, isA<HealthPlatformPermissionDenied>());
      expect(platform.authCalls, 0);
      expect(platform.importAuthCalls, 0);
    });
  });

  group('issue #1478: a waking temperature is never dated in the future', () {
    // 2026-06-01 is in daylight time in America/New_York (UTC-4), so the
    // 07:00 default for that day is 11:00 UTC.
    final sevenLocal = DateTime.utc(2026, 6, 1, 11);

    test('entered before 07:00, with no recorded time: written at the '
        'present moment, not at a 07:00 that has not happened; from 07:00 on '
        'the default stands', () async {
      final grant = DateTime.utc(2026, 6, 1, 8);
      await seedGranted(grant);
      clock = DateTime.utc(2026, 6, 1, 9, 30); // 05:30 local
      expect(clock.isBefore(sevenLocal), isTrue);
      final reading =
          _bbt('2026-06-01', 36.6, grant.add(const Duration(minutes: 30)));
      observations.observations = [reading];
      final recorder = _BbtRecordingPlatform();
      platform = recorder;
      final service = buildService();

      await service.syncNow();

      expect(recorder.bbtWrites.single.observedAt, clock,
          reason: 'Health Connect refuses a record dated in the future');

      // The same reading, edited later that morning: the default is in the
      // past now, so it is left to the port (null = 07:00 local).
      clock = sevenLocal.add(const Duration(hours: 1));
      observations.observations = [
        _bbt('2026-06-01', 36.7, clock.subtract(const Duration(minutes: 1))),
      ];
      await service.syncNow();

      expect(recorder.bbtWrites, hasLength(2));
      expect(recorder.bbtWrites.last.observedAt, isNull);
    });
  });

  // The review of the first #1478 commit (reproductions R1 to R7). Each
  // test below states the behaviour wanted; R4 and R5 pin behaviour that
  // already held.
  group('issue #1478 review: which period record an episode gets', () {
    final grant = DateTime.utc(2026, 6, 1, 12);

    List<String> periodRows() => [
          for (final row in ledger.rows)
            if (row.kind == HealthExportLedgerKind.period)
              '${row.recordId} ${row.sourceRowId}',
        ]..sort();

    DayEntry imported(String isoDay, DateTime updatedAt) => DayEntry(
          id: 'entry-$isoDay',
          profileId: _profileId,
          localDate: LocalDate.fromIso(isoDay),
          // What the Health Connect import stamps on a row: the record's
          // raw offset, not an IANA name.
          tz: 'UTC+02:00',
          flow: FlowLevel.medium,
          updatedAt: updatedAt,
          source: DayEntrySource.healthConnect,
        );

    // R1 / decision A.
    test('a period record is made of hand-logged days only: an imported '
        'first day neither starts it nor lends it its zone', () async {
      await seedGranted(grant);
      final service = buildService();
      final d2 = _entry('2026-06-02', FlowLevel.medium,
          grant.add(const Duration(hours: 1)));
      final d3 = _entry('2026-06-03', FlowLevel.light,
          grant.add(const Duration(hours: 2)));
      dayEntries.entries = [imported('2026-06-01', grant), d2, d3];

      final first = await service.syncNow();
      expect(first.blocked, isNull);
      expect(first.periodRecordsWritten, 1);
      expect(platform.periodWrites.single.start, LocalDate.fromIso('2026-06-02'));
      expect(platform.periodWrites.single.end, LocalDate.fromIso('2026-06-03'));
      expect(platform.periodWrites.single.tzName, _tz,
          reason: 'never the import\'s fixed-offset zone, which the day '
              'boundary maths cannot resolve');
      expect(periodRows(),
          ['period-$_profileId-2026-06-02 2026-06-02/2026-06-03']);

      // The last hand-logged day is deleted: the record is corrected, still
      // in a hand-logged day's zone.
      dayEntries.entries = [imported('2026-06-01', grant), d2];
      final second = await service.syncNow();
      expect(second.blocked, isNull);
      expect(platform.periodWrites.last.start, LocalDate.fromIso('2026-06-02'));
      expect(platform.periodWrites.last.end, LocalDate.fromIso('2026-06-02'));
      expect(platform.periodWrites.last.tzName, _tz);
    });

    // Decision A: an import can never start, extend or reshape a period.
    test('an import that adds bleed days around an exported period changes '
        'nothing in the store', () async {
      await seedGranted(grant);
      final service = buildService();
      final own = [
        _entry('2026-06-03', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-04', FlowLevel.light,
            grant.add(const Duration(hours: 2))),
      ];
      dayEntries.entries = own;
      await service.syncNow();
      final flowWrites = platform.flowWrites.length;
      final periodWrites = platform.periodWrites.length;

      // A (background) import lands a day before and a day after it.
      final later = grant.add(const Duration(hours: 5));
      dayEntries.entries = [
        imported('2026-06-02', later),
        ...own,
        imported('2026-06-05', later),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(platform.flowWrites, hasLength(flowWrites));
      expect(platform.periodWrites, hasLength(periodWrites),
          reason: 'the written period still says 06-03..06-04');
      expect(platform.deleteCalls, isEmpty);
      expect(periodRows(),
          ['period-$_profileId-2026-06-03 2026-06-03/2026-06-04']);
    });

    test('one imported day between hand-logged days is a one-day gap in the '
        'same period; two imported days in a row split it', () async {
      await seedGranted(grant);
      final service = buildService();
      DayEntry own(String day, int hour) =>
          _entry(day, FlowLevel.medium, grant.add(Duration(hours: hour)));
      dayEntries.entries = [
        own('2026-06-02', 1),
        imported('2026-06-03', grant),
        own('2026-06-04', 2),
      ];
      await service.syncNow();
      expect(periodRows(),
          ['period-$_profileId-2026-06-02 2026-06-02/2026-06-04']);

      dayEntries.entries = [
        own('2026-06-02', 1),
        imported('2026-06-03', grant),
        imported('2026-06-04', grant),
        own('2026-06-05', 3),
      ];
      final report = await service.syncNow();
      expect(report.blocked, isNull);
      expect(periodRows(), [
        'period-$_profileId-2026-06-02 2026-06-02/2026-06-02',
        'period-$_profileId-2026-06-05 2026-06-05/2026-06-05',
      ]);
    });

    // R2 / decision B.
    test('removing the first day of an exported period writes a record for '
        'the days that remain', () async {
      await seedGranted(grant);
      final service = buildService();
      final days = [
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-03', FlowLevel.medium,
            grant.add(const Duration(hours: 2))),
        _entry('2026-06-04', FlowLevel.light,
            grant.add(const Duration(hours: 3))),
      ];
      dayEntries.entries = days;
      await service.syncNow();
      expect(platform.periodWrites.single.recordId,
          'period-$_profileId-2026-06-02');

      // The first day is set back to "no flow" by hand.
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.none,
            grant.add(const Duration(hours: 4))),
        days[1],
        days[2],
      ];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(platform.deleteCalls,
          contains(equals(['period-$_profileId-2026-06-02'])));
      expect(platform.periodWrites.last.recordId,
          'period-$_profileId-2026-06-03');
      expect(platform.periodWrites.last.start, LocalDate.fromIso('2026-06-03'));
      expect(platform.periodWrites.last.end, LocalDate.fromIso('2026-06-04'));
      expect(periodRows(),
          ['period-$_profileId-2026-06-03 2026-06-03/2026-06-04']);
    });

    // R3 / decision B.
    test('splitting an exported period leaves two records, one per half',
        () async {
      await seedGranted(grant);
      final service = buildService();
      final days = [
        for (var day = 2; day <= 7; day++)
          _entry('2026-06-0$day', FlowLevel.medium,
              grant.add(Duration(hours: 1, minutes: day))),
      ];
      dayEntries.entries = days;
      await service.syncNow();
      expect(periodRows(),
          ['period-$_profileId-2026-06-02 2026-06-02/2026-06-07']);

      // 06-04 and 06-05 are deleted: 06-02..06-03 and 06-06..06-07.
      dayEntries.entries = [days[0], days[1], days[4], days[5]];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(periodRows(), [
        'period-$_profileId-2026-06-02 2026-06-02/2026-06-03',
        'period-$_profileId-2026-06-06 2026-06-06/2026-06-07',
      ]);
      final secondHalf = platform.periodWrites
          .lastWhere((write) => write.recordId.endsWith('2026-06-06'));
      expect(secondHalf.start, LocalDate.fromIso('2026-06-06'));
      expect(secondHalf.end, LocalDate.fromIso('2026-06-07'));
    });

    // Decision B: over thirty days and back.
    test('a period that grew past the limit gets its record back when it '
        'shrinks to thirty days again', () async {
      await seedGranted(grant);
      final first = LocalDate.fromIso('2026-06-02');
      final service = buildService();
      final days = [
        for (var day = 0; day <= kHealthPeriodRecordMaxDays; day++)
          _entry(first.addDays(day).iso, FlowLevel.light,
              grant.add(Duration(hours: 1, minutes: day))),
      ];
      dayEntries.entries = days;
      await service.syncNow();
      expect(platform.periodWrites, isEmpty);

      dayEntries.entries = days.sublist(0, kHealthPeriodRecordMaxDays);
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(platform.periodWrites.single.start, first);
      expect(platform.periodWrites.single.end,
          first.addDays(kHealthPeriodRecordMaxDays - 1));
    });

    // R4 / decision G: kept, and now said in the Health Connect copy.
    test('a period that began before sync was on is written with its true '
        'first day, though only the later day gets a flow record', () async {
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-05-30', FlowLevel.heavy,
            grant.subtract(const Duration(days: 2))),
        _entry('2026-05-31', FlowLevel.medium,
            grant.subtract(const Duration(days: 1))),
        _entry('2026-06-01', FlowLevel.light,
            grant.add(const Duration(hours: 1))),
      ];

      await buildService().syncNow();

      expect(platform.flowWrites.map((write) => write.date.iso),
          ['2026-06-01']);
      expect(platform.periodWrites.single.start, LocalDate.fromIso('2026-05-30'));
      expect(platform.periodWrites.single.end, LocalDate.fromIso('2026-06-01'));
    });

    test('a store with no period record type (iOS) is asked once in a pass, '
        'not once per period, and the pass is not blocked', () async {
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-10', FlowLevel.medium,
            grant.add(const Duration(hours: 2))),
        _entry('2026-06-20', FlowLevel.medium,
            grant.add(const Duration(hours: 3))),
      ];
      platform.writeResults = [
        const HealthPlatformAllowed(), // flow 06-02
        const HealthPlatformAllowed(), // flow 06-10
        const HealthPlatformAllowed(), // flow 06-20
        const HealthPlatformUnavailable(), // the first period record
      ];

      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      expect(report.samplesWritten, 3);
      expect(report.periodRecordsWritten, 0);
      expect(platform.periodWrites, hasLength(1));
      expect(periodRows(), isEmpty);
    });

    // R6 / decision E.
    test('every write of a period record carries a higher version than the '
        'one before it, whatever the days\' own timestamps say', () async {
      await seedGranted(grant);
      final service = buildService();
      final d2 = _entry('2026-06-02', FlowLevel.heavy,
          grant.add(const Duration(hours: 1)));
      final d3 = _entry('2026-06-03', FlowLevel.medium,
          grant.add(const Duration(hours: 2)));
      final d4 = _entry('2026-06-04', FlowLevel.light,
          grant.add(const Duration(hours: 3)));
      clock = grant.add(const Duration(hours: 3, minutes: 30));
      dayEntries.entries = [d2, d3, d4];
      await service.syncNow();

      // 06-04 is deleted on this phone; the correction runs at +10h.
      clock = grant.add(const Duration(hours: 10));
      dayEntries.entries = [d2, d3];
      await service.syncNow();
      final correction = platform.periodWrites.last;
      expect(correction.end, LocalDate.fromIso('2026-06-03'));

      // A row saved on ANOTHER device at +5h (after this phone's cursor,
      // +3h, but before the correction) arrives by account sync at +11h.
      clock = grant.add(const Duration(hours: 11));
      dayEntries.entries = [
        d2,
        d3,
        _entry('2026-06-04', FlowLevel.medium,
            grant.add(const Duration(hours: 5))),
      ];
      final report = await service.syncNow();
      final later = platform.periodWrites.last;

      expect(report.blocked, isNull);
      expect(later.recordId, correction.recordId);
      expect(later.end, LocalDate.fromIso('2026-06-04'));
      expect(later.recordVersionMs, greaterThan(correction.recordVersionMs),
          reason: 'Health Connect keeps the copy with the higher version: '
              'a lower one is ignored while the ledger records it as written');

      // And if this phone's clock has gone backwards, still higher.
      clock = grant.add(const Duration(hours: 4));
      dayEntries.entries = [d2, d3];
      await service.syncNow();
      expect(platform.periodWrites.last.end, LocalDate.fromIso('2026-06-03'));
      expect(platform.periodWrites.last.recordVersionMs,
          greaterThan(later.recordVersionMs));
    });

    // Decision C.
    test('a period whose zone cannot be resolved is left alone: no delete, '
        'no write, no failed pass', () async {
      await seedGranted(grant);
      final service = buildService();
      final d2 = _entry('2026-06-02', FlowLevel.medium,
          grant.add(const Duration(hours: 1)));
      final d3 = _entry('2026-06-03', FlowLevel.light,
          grant.add(const Duration(hours: 2)));
      dayEntries.entries = [d2, d3];
      await service.syncNow();
      expect(periodRows(),
          ['period-$_profileId-2026-06-02 2026-06-02/2026-06-03']);

      // 06-03 goes, and the remaining day now carries a zone name the day
      // boundary maths cannot resolve (a restored row, say).
      dayEntries.entries = [
        DayEntry(
          id: d2.id,
          profileId: _profileId,
          localDate: d2.localDate,
          tz: 'Mars/Olympus',
          flow: d2.flow,
          updatedAt: d2.updatedAt,
        ),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(platform.periodWrites, hasLength(1));
      expect(platform.deleteCalls, isEmpty,
          reason: 'nothing can replace the record, so it is not removed');
      expect(periodRows(),
          ['period-$_profileId-2026-06-02 2026-06-02/2026-06-03']);
    });

    test('a zone that cannot be resolved on the first day is taken from the '
        'next hand-logged day of the same period', () async {
      await seedGranted(grant);
      final service = buildService();
      // A restored row can carry a fixed-offset zone without being a
      // health-store import.
      final restored = DayEntry(
        id: 'entry-2026-06-02',
        profileId: _profileId,
        localDate: LocalDate.fromIso('2026-06-02'),
        tz: 'UTC+02:00',
        flow: FlowLevel.medium,
        updatedAt: grant.subtract(const Duration(hours: 1)),
        source: DayEntrySource.fileImport,
      );
      final d3 = _entry('2026-06-03', FlowLevel.light,
          grant.add(const Duration(hours: 2)));
      final d4 = _entry('2026-06-04', FlowLevel.light,
          grant.add(const Duration(hours: 3)));
      dayEntries.entries = [restored, d3, d4];
      await service.syncNow();
      expect(platform.periodWrites.single.start, LocalDate.fromIso('2026-06-02'));
      expect(platform.periodWrites.single.tzName, _tz);

      // The last day goes: the correction has no newly edited day behind
      // it, and must still not reach for the first day's zone.
      dayEntries.entries = [restored, d3];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(platform.periodWrites.last.end, LocalDate.fromIso('2026-06-03'));
      expect(platform.periodWrites.last.tzName, _tz);
    });
  });

  group('issue #1478 review: the cursor is stamped when writes are granted',
      () {
    // R7 / decision D.
    test('a sheet answered with something other than the write permissions '
        'stamps nothing; days logged while writes were off stay unwritten '
        'when writes are turned on later', () async {
      await settings.set(_bindingKey, _profileId);
      platform.permission = HealthPermissionStatus.notAsked;
      // Android answers the request "allowed" when ANY permission was
      // granted; here only the reads were, so the status that follows is
      // "denied".
      platform.permissionAfterAuth = HealthPermissionStatus.denied;
      final service = buildService();
      final grant = clock;

      final first = await service.syncNow();
      expect(platform.authCalls, 1);
      expect(first.authorizationRequested, isTrue);
      expect(first.blocked, isA<HealthPlatformPermissionDenied>());
      expect(await settings.get(_cursorKey), isNull,
          reason: 'no write access, no "access was granted" moment');

      // A day is logged while writes are still off.
      clock = grant.add(const Duration(days: 9));
      dayEntries.entries = [
        _entry('2026-06-10', FlowLevel.medium, clock),
      ];
      final blocked = await service.syncNow();
      expect(blocked.blocked, isA<HealthPlatformPermissionDenied>());
      expect(platform.flowWrites, isEmpty);

      // Three weeks later the person turns the write permissions on.
      platform.permission = HealthPermissionStatus.granted;
      clock = grant.add(const Duration(days: 21));
      final enabled = await service.syncNow();
      expect(enabled.blocked, isNull);
      expect(platform.authCalls, 1, reason: 'nothing left to ask');
      expect(platform.flowWrites, isEmpty,
          reason: 'logged before write access was granted');
      expect(await settings.get(_cursorKey),
          '${clock.millisecondsSinceEpoch}');

      // A day logged from then on is written.
      dayEntries.entries = [
        ...dayEntries.entries,
        _entry('2026-06-23', FlowLevel.light,
            clock.add(const Duration(hours: 1))),
      ];
      final after = await service.syncNow();
      expect(after.samplesWritten, 1);
      expect(platform.flowWrites.single.date, LocalDate.fromIso('2026-06-23'));
    });

    test('a sheet that grants the writes stamps at once (the status is read '
        'again after the request)', () async {
      await settings.set(_bindingKey, _profileId);
      platform.permission = HealthPermissionStatus.notAsked;

      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      expect(platform.permissionStatusCalls, 2);
      expect(await settings.get(_cursorKey),
          '${clock.millisecondsSinceEpoch}');
    });

    test('a permission surface that cannot answer after the request stamps '
        'nothing either, and is reported as unavailable, not as a denial',
        () async {
      await settings.set(_bindingKey, _profileId);
      platform.permission = HealthPermissionStatus.notAsked;
      platform.permissionAfterAuth = HealthPermissionStatus.unavailable;

      final report = await buildService().syncNow();

      expect(report.blocked, isA<HealthPlatformUnavailable>());
      expect(await settings.get(_cursorKey), isNull);
    });

    // R5 / decision H: held before, pinned now.
    test('the already-granted path stamps now and writes nothing logged '
        'before the stamp, not even a moment before', () async {
      await settings.set(_bindingKey, _profileId);
      platform.permission = HealthPermissionStatus.granted;
      dayEntries.entries = [
        _entry('2026-05-31', FlowLevel.medium,
            clock.subtract(const Duration(seconds: 1))),
        _entry('2026-06-01', FlowLevel.medium, clock),
      ];

      final report = await buildService().syncNow();

      expect(platform.authCalls, 0);
      expect(report.samplesWritten, 0);
      expect(platform.flowWrites, isEmpty);
      expect(platform.periodWrites, isEmpty);
      expect(await settings.get(_cursorKey),
          '${clock.millisecondsSinceEpoch}');
    });
  });

  group('mid-pass authority drift (issue #620, LLA-023)', () {
    test(
        'ownership transferred away between two writes cancels the rest of '
        'the pass instead of writing the second day under the stale owner',
        () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-03', FlowLevel.heavy,
            grant.add(const Duration(hours: 2))),
      ];

      // `guardiansForProfile` is consulted once to resolve the pass's
      // starting facts, then again before each write's fresh recheck
      // (Issue #620, LLA-023). The first two calls (pass start, first
      // write's recheck) still see the original owner; from the third
      // call on — the SECOND write's recheck — ownership has moved to a
      // different account, simulating a transfer that completed while
      // the pass was suspended between platform calls.
      var guardianCalls = 0;
      final service = LocalHealthFlowWriteService(
        platform: platform,
        binding: HealthSyncBinding(settings),
        minorBindingAllowed: false,
        profiles: profiles,
        dayEntries: dayEntries,
        observations: observations,
        settings: settings,
        ledger: ledger,
        guardiansForProfile: (_) async {
          guardianCalls++;
          return guardianCalls <= 2 ? [_ownerRow()] : [_transferredRow()];
        },
        signedInUserId: () => _ownerId,
        now: () => clock,
      );

      final report = await service.syncNow();

      expect(platform.flowWrites, hasLength(1),
          reason: 'the second write must be cancelled once the recheck '
              'observes the ownership change, not sent under stale facts');
      expect(
          platform.flowWrites.single.date, LocalDate.fromIso('2026-06-02'));
      expect(report.blocked, isA<HealthPlatformRefused>());
      expect((report.blocked! as HealthPlatformRefused).check,
          HealthSyncCheck.notOwner);
      // A blocked pass never advances the cursor: the whole batch,
      // including the day that DID get written before the drift was
      // observed, is retried by the next pass under fresh facts.
      expect(await settings.get(_cursorKey),
          '${grant.millisecondsSinceEpoch}');
    });

    test(
        'the bound profile being deleted mid-pass cancels the rest of the '
        'pass', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-03', FlowLevel.heavy,
            grant.add(const Duration(hours: 2))),
      ];

      var findCalls = 0;
      final flakyProfiles = _FlakyProfiles(
        onFind: () {
          findCalls++;
          // Call 1 is the pass's own `_resolveBound`; call 2 is the first
          // write's recheck — both still resolve. From call 3 on (the
          // second write's recheck) the profile row is gone.
          return findCalls <= 2 ? _profile() : null;
        },
      );
      final service = LocalHealthFlowWriteService(
        platform: platform,
        binding: HealthSyncBinding(settings),
        minorBindingAllowed: false,
        profiles: flakyProfiles,
        dayEntries: dayEntries,
        observations: observations,
        settings: settings,
        ledger: ledger,
        guardiansForProfile: (_) async => [_ownerRow()],
        signedInUserId: () => _ownerId,
        now: () => clock,
      );

      final report = await service.syncNow();

      expect(platform.flowWrites, hasLength(1));
      expect(report.blocked, isA<HealthPlatformFailed>());
      expect(await settings.get(_cursorKey),
          '${grant.millisecondsSinceEpoch}');
    });
  });

  group('issue #930: reconciling records an edit removed from a kept day',
      () {
    final grant = DateTime.utc(2026, 6, 1, 12);

    test('unticking a symptom on a live day deletes exactly that symptom '
        'record id and nothing else', () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1)),
            tags: const ['cramps', 'headache']),
      ];
      await service.syncNow();
      expect(platform.deleteCalls, isEmpty);

      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 3)),
            tags: const ['headache']),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(platform.deleteCalls, [
        [healthSymptomRecordId('entry-2026-06-02', 'abdominalCramps')],
      ], reason: 'only the removed symptom is addressed; the still-present '
          'headache and the unchanged flow id are not');
    });

    test("changing a symptom's graded intensity rewrites the same record id "
        'and deletes nothing', () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1)),
            tags: const ['cramps']),
      ];
      observations.observations = [
        _pain('2026-06-02', 'cramps', 2, grant.add(const Duration(hours: 1))),
      ];
      await service.syncNow();

      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 3)),
            tags: const ['cramps']),
      ];
      observations.observations = [
        _pain('2026-06-02', 'cramps', 4, grant.add(const Duration(hours: 3))),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(platform.deleteCalls, isEmpty,
          reason: 'a severity change is an update of the SAME '
              'symptom-<entry>-abdominalCramps id, never a removal');
    });

    test('clearing a BBT reading from a day that still exists deletes its '
        'bbt record', () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
      ];
      observations.observations = [
        _bbt('2026-06-02', 36.5, grant.add(const Duration(hours: 1))),
      ];
      final first = await service.syncNow();
      expect(first.basalBodyTemperatureSamplesWritten, 1);
      expect(platform.deleteCalls, isEmpty);

      // The operator clears the field: the observation row is tombstoned
      // (so the live list no longer carries it), while the day entry — and
      // its flow sample — remain.
      observations.observations = const [];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(platform.deleteCalls, [
        [healthBbtRecordId('obs-bbt-2026-06-02')],
      ]);
    });

    test('changing flow rewrites the same record id and deletes nothing',
        () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
      ];
      await service.syncNow();

      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 3))),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(platform.deleteCalls, isEmpty,
          reason: 'a flow change is an update of the same day-entry id');
      expect(platform.flowWrites.last.flow, HealthFlowValue.heavy);
    });

    test('a denied binding blocks the removal delete with no new bypass',
        () async {
      await seedGranted(grant);
      var signedInUserId = _ownerId;
      final service = LocalHealthFlowWriteService(
        platform: platform,
        binding: HealthSyncBinding(settings),
        minorBindingAllowed: false,
        profiles: profiles,
        dayEntries: dayEntries,
        observations: observations,
        settings: settings,
        ledger: ledger,
        guardiansForProfile: (_) async => [_ownerRow()],
        signedInUserId: () => signedInUserId,
        now: () => clock,
      );
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1)),
            tags: const ['cramps', 'headache']),
      ];
      await service.syncNow();

      // The signed-in account no longer owns the bound profile: the pass is
      // refused before any health-API touch, so the pending removal is not
      // issued and the cursor does not advance.
      signedInUserId = 'someone-else';
      final exportedCursor = grant.add(const Duration(hours: 1));
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 3)),
            tags: const ['headache']),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isA<HealthPlatformRefused>());
      expect(platform.deleteCalls, isEmpty,
          reason: 'the same guard that gates the write gates the delete');
      expect(await settings.get(_cursorKey),
          '${exportedCursor.millisecondsSinceEpoch}');
    });

    test('a refused removal delete blocks the pass and is retried by the '
        'next change rather than acknowledged', () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1)),
            tags: const ['cramps', 'headache']),
      ];
      await service.syncNow();
      final exportedCursor = await settings.get(_cursorKey);

      platform.deleteResult = const HealthPlatformPermissionDenied();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 3)),
            tags: const ['headache']),
      ];
      final blocked = await service.syncNow();
      expect(blocked.blocked, isA<HealthPlatformPermissionDenied>());
      expect(platform.deleteCalls, hasLength(1));
      expect(await settings.get(_cursorKey), exportedCursor,
          reason: 'a failed removal must not advance the cursor');

      platform.deleteResult = const HealthPlatformAllowed();
      final retried = await service.syncNow();
      expect(retried.blocked, isNull);
      expect(platform.deleteCalls, hasLength(2),
          reason: 'the same removal is retried, not silently acknowledged');
    });

    test('the remembered set advances with the write, so a repeated '
        'cramp-free save deletes nothing a second time', () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1)),
            tags: const ['cramps', 'headache']),
      ];
      await service.syncNow();

      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 3)),
            tags: const ['headache']),
      ];
      await service.syncNow();
      expect(platform.deleteCalls, hasLength(1));

      // The same cramp-free day is saved again: the remembered set moved to
      // the post-removal state, so there is no difference to delete.
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 4)),
            tags: const ['headache']),
      ];
      await service.syncNow();
      expect(platform.deleteCalls, hasLength(1),
          reason: 'a repeated save of the same state must not re-delete');
    });
  });

  group('issue #936: the ledger survives a relaunch', () {
    final grant = DateTime.utc(2026, 6, 1, 12);

    test('a symptom removed by an edit made in a later session is deleted '
        'after the service is rebuilt from scratch', () async {
      await seedGranted(grant);
      final first = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1)),
            tags: const ['cramps', 'headache']),
      ];
      await first.syncNow();
      expect(platform.deleteCalls, isEmpty);

      // A relaunch: a brand new service, same persisted ledger. Before
      // #936 the remembered set started empty here, so `removed` was empty
      // and the cramp sample was never deleted.
      final relaunched = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 3)),
            tags: const ['headache']),
      ];
      final report = await relaunched.syncNow();

      expect(report.blocked, isNull);
      expect(platform.deleteCalls, [
        [healthSymptomRecordId('entry-2026-06-02', 'abdominalCramps')],
      ]);
    });

    test('a BBT reading cleared in a later session is deleted after a '
        'relaunch', () async {
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
      ];
      observations.observations = [
        _bbt('2026-06-02', 36.5, grant.add(const Duration(hours: 1))),
      ];
      final first = buildService();
      expect((await first.syncNow()).basalBodyTemperatureSamplesWritten, 1);
      expect(platform.deleteCalls, isEmpty);

      // Relaunch, then the operator clears the reading: the observation is
      // gone while the day (and its flow sample) remain.
      final relaunched = buildService();
      observations.observations = const [];
      final report = await relaunched.syncNow();

      expect(report.blocked, isNull);
      expect(platform.deleteCalls, [
        [healthBbtRecordId('obs-bbt-2026-06-02')],
      ]);
    });

    test('ledger rows advance with the write and are dropped once their '
        'record is deleted from the store', () async {
      await seedGranted(grant);
      final first = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1)),
            tags: const ['cramps', 'headache']),
      ];
      await first.syncNow();

      final entryRows = [
        for (final row in ledger.rows)
          if (row.kind == HealthExportLedgerKind.entry) row.recordId,
      ];
      expect(
        entryRows,
        containsAll([
          'entry-2026-06-02',
          healthSymptomRecordId('entry-2026-06-02', 'abdominalCramps'),
          healthSymptomRecordId('entry-2026-06-02', 'headache'),
        ]),
      );

      // The edit removes the cramp: its ledger row is dropped once the
      // store deletion succeeds, and the remaining set stays.
      final relaunched = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 3)),
            tags: const ['headache']),
      ];
      await relaunched.syncNow();

      final remaining = {
        for (final row in ledger.rows)
          if (row.kind == HealthExportLedgerKind.entry) row.recordId,
      };
      expect(
        remaining,
        isNot(contains(
          healthSymptomRecordId('entry-2026-06-02', 'abdominalCramps'),
        )),
      );
      expect(
        remaining,
        contains(healthSymptomRecordId('entry-2026-06-02', 'headache')),
      );
    });

    test('onUnbound clears the persisted ledger with the cursor', () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1)),
            tags: const ['cramps']),
      ];
      await service.syncNow();
      expect(ledger.rows, isNotEmpty);

      await service.onUnbound();

      expect(ledger.rows, isEmpty);
      expect(await settings.get(_cursorKey), '');
    });

    test('in-session reconcile is unchanged by the persisted ledger '
        '(same repeated-save behaviour, no extra deletes)', () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1)),
            tags: const ['cramps', 'headache']),
      ];
      await service.syncNow();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 3)),
            tags: const ['headache']),
      ];
      await service.syncNow();
      expect(platform.deleteCalls, hasLength(1));

      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 4)),
            tags: const ['headache']),
      ];
      await service.syncNow();
      expect(platform.deleteCalls, hasLength(1),
          reason: 'the ledger seeds the same state the in-memory set held, '
              'so a repeated save is still a no-op');
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
