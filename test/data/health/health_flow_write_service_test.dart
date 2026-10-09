/// `LocalHealthFlowWriteService`'s whole policy, pinned: guard-first (zero port
/// calls on any deny), opt-in (authorization requested exactly once,
/// cursor stamped at the grant instant), forward-only (pre-cursor rows are
/// never written; a clean pass advances the cursor to the newest processed
/// row; a failing pass advances nothing), cycle-start metadata from
/// episodes.dart, the A3-4 spotting branch at the service level, and the
/// one-way rule (health-store-sourced rows are never echoed back).
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_flow_mapping.dart';
import 'package:lunarlog/data/health/health_flow_write_service.dart';
import 'package:lunarlog/data/health/health_record_ids.dart';
import 'package:lunarlog/data/health/health_written_types.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/health/health_export_ledger.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/health/health_write_pass_state.dart';
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
  @override
  bool writesCycleStart = true;

  HealthPlatformResult bindResult = const HealthPlatformAllowed();
  HealthPlatformResult authResult = const HealthPlatformAllowed();

  /// Outcomes consumed by successive write calls; the last one repeats.
  List<HealthPlatformResult> writeResults = [];
  final List<HealthMenstrualFlowWrite> flowWrites = [];
  final List<HealthIntermenstrualBleedingWrite> markerWrites = [];
  final List<HealthMenstrualPeriodWrite> periodWrites = [];
  final List<List<String>> deleteCalls = [];

  /// The delete calls that name a period record. Since Issue #1589 a
  /// pass also deletes the records of a day that is gone, so a test
  /// about what happens to the period record looks at these.
  List<List<String>> get periodDeleteCalls => [
        for (final call in deleteCalls)
          if (call.any((id) => id.startsWith('period-'))) call,
      ];
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

  Set<String> grantedTypes = const {};
  int grantedWriteTypesCalls = 0;
  Object? grantedWriteTypesError;

  @override
  Future<Set<String>> grantedWriteTypes() async {
    grantedWriteTypesCalls++;
    if (grantedWriteTypesError != null) {
      throw grantedWriteTypesError!;
    }
    return grantedTypes;
  }

  /// Issue #1590: the ask for a type no sheet has asked about belongs to
  /// the Health sync screen, never to a pass. The stubs throw, so a pass
  /// that ever reached one fails loudly in a test rather than raising a
  /// sheet mid-day-logging.
  @override
  Future<Set<String>> neverAskedWriteTypes() =>
      throw StateError('a write pass must never ask what was never asked');

  @override
  Future<HealthPlatformResult> requestWriteAuthorizationForTypes(
    HealthGuardFacts facts,
    Set<String> types,
  ) =>
      throw StateError('a write pass must never raise the ask for a new type');

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

  /// Run when the pass mirrors the binding, which it does once, before
  /// any write or delete: a test's moment to change something behind
  /// the running pass.
  void Function()? onBind;

  /// Run on each flow write, after the pass has checked it may write.
  void Function()? onFlowWrite;

  @override
  Future<HealthPlatformResult> bindProfile(HealthGuardFacts facts) async {
    bindCalls++;
    onBind?.call();
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
    onFlowWrite?.call();
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

/// A [_FakePlatform] whose flow write does not answer until [release] is
/// called, to hold a pass open (Issue #1581).
class _GatedPlatform extends _FakePlatform {
  final Completer<void> _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<HealthPlatformResult> writeMenstrualFlow(
    HealthMenstrualFlowWrite write,
  ) async {
    flowWrites.add(write);
    await _gate.future;
    return const HealthPlatformResult.allowed();
  }
}

/// A [_FakePlatform] that refuses a delete naming any id in [refused] and
/// allows every other (Issue #1581).
class _SelectiveDeletePlatform extends _FakePlatform {
  Set<String> refused = {};

  @override
  Future<HealthPlatformResult> deleteRecords(
    HealthGuardFacts facts,
    List<String> recordIds,
  ) async {
    deleteCalls.add(List.of(recordIds));
    return recordIds.any(refused.contains)
        ? const HealthPlatformResult.failed('no')
        : const HealthPlatformResult.allowed();
  }
}

/// A [_FakePlatform] that tracks flow and marker records in the store,
/// removing on delete and inserting on write (Issue #1641).
class _SimulatedStorePlatform extends _FakePlatform {
  final Set<String> store = {};

  @override
  Future<HealthPlatformResult> writeMenstrualFlow(
    HealthMenstrualFlowWrite write,
  ) async {
    store.add('flow:${write.recordId}');
    return super.writeMenstrualFlow(write);
  }

  @override
  Future<HealthPlatformResult> writeIntermenstrualBleeding(
    HealthIntermenstrualBleedingWrite write,
  ) async {
    store.add('marker:${write.recordId}');
    return super.writeIntermenstrualBleeding(write);
  }

  @override
  Future<HealthPlatformResult> deleteRecords(
    HealthGuardFacts facts,
    List<String> recordIds,
  ) async {
    for (final id in recordIds) {
      store.remove('flow:$id');
      store.remove('marker:$id');
    }
    return super.deleteRecords(facts, recordIds);
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

  /// Thrown by the next [listForProfile], once.
  Object? failNextList;
  // Issue #548: a per-test fake with no close() call — the test process is
  // short-lived and nothing in this file ever emits on it, so there is no
  // real leak to guard against.
  // ignore: close_sinks
  final _changes = StreamController<List<DayEntry>>.broadcast();

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async {
    final failure = failNextList;
    if (failure != null) {
      failNextList = null;
      throw failure;
    }
    return entries;
  }

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

  /// [guardians] is read afresh on every authority check, so a test can
  /// move the profile's ownership while a pass is running.
  LocalHealthFlowWriteService buildService({
    List<ProfileGuardian> Function()? guardians,
  }) =>
      LocalHealthFlowWriteService(
        platform: platform,
        binding: HealthSyncBinding(settings),
        minorBindingAllowed: false,
        profiles: profiles,
        dayEntries: dayEntries,
        observations: observations,
        settings: settings,
        ledger: ledger,
        guardiansForProfile: (_) async => guardians?.call() ?? [_ownerRow()],
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

    test('the floor stays where the grant put it; a row is sent once, and '
        'again when it is edited', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      final entryUpdatedAt = grant.add(const Duration(hours: 2));
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, entryUpdatedAt),
      ];
      final service = buildService();

      await service.syncNow();
      // Issue #1581: nothing moves the floor. What was sent is remembered
      // record by record, with the version of the row it was sent at.
      expect(await settings.get(_cursorKey),
          '${grant.millisecondsSinceEpoch}');
      final remembered = ledger.rows
          .singleWhere((row) => row.recordId == 'entry-2026-06-02');
      expect(remembered.exportedAt, entryUpdatedAt);
      expect(remembered.kind, HealthExportLedgerKind.entry);

      await service.syncNow();
      expect(platform.flowWrites, hasLength(1));

      // A later edit is sent.
      clock = grant.add(const Duration(hours: 3));
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 3))),
      ];
      final report = await service.syncNow();
      expect(report.samplesWritten, 1);
      expect(platform.flowWrites.last.flow, HealthFlowValue.heavy);
      expect(await settings.get(_cursorKey),
          '${grant.millisecondsSinceEpoch}');
    });

    // Issue #1577. A row's `updatedAt` carries microseconds, and the cursor
    // was stored in whole milliseconds: the newest row a pass wrote was
    // still after it, by its microseconds, and went to the health store
    // again on every pass. Every other time in this file is a whole second,
    // which is why none of them noticed. Since Issue #1581 a row is not
    // sent twice because the ledger holds it at its exact version, and
    // the stored floor's precision matters only for rows saved in the
    // grant's own millisecond.
    group('the cursor keeps the microseconds a row carries (#1577)', () {
      const usKey = SettingsKeys.healthSyncWrittenThroughUs;
      final grant = DateTime.utc(2026, 6, 1, 12);
      final savedAt = grant.add(const Duration(hours: 2, microseconds: 455));

      test('a pass with nothing changed writes nothing', () async {
        await seedGranted(grant);
        dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, savedAt)];
        final service = buildService();

        expect((await service.syncNow()).blocked, isNull);
        expect(platform.flowWrites, hasLength(1));
        final periodWrites = platform.periodWrites.length;
        expect(
          ledger.rows
              .singleWhere((row) => row.recordId == 'entry-2026-06-02')
              .exportedAt,
          savedAt,
          reason: 'remembered to the microsecond',
        );

        // The same service, and then a new one, as after a restart.
        for (final again in [service, buildService()]) {
          final report = await again.syncNow();
          expect(report.blocked, isNull);
          expect(report.samplesWritten, 0);
          expect(platform.flowWrites, hasLength(1));
          expect(platform.periodWrites, hasLength(periodWrites));
        }
      });

      test('nor is a spotting entry or a temperature, when one of them is '
          'the newest row', () async {
        await seedGranted(grant);
        final earlier = grant.add(const Duration(hours: 1));
        dayEntries.entries = [
          _entry('2026-06-20', FlowLevel.none, earlier),
          _entry('2026-06-21', FlowLevel.none, earlier),
        ];
        observations.observations = [
          _spotting('2026-06-20', savedAt),
          _bbt('2026-06-21', 36.6, savedAt.add(const Duration(microseconds: 7))),
        ];
        final recorder = _BbtRecordingPlatform();
        platform = recorder;
        final service = buildService();

        expect((await service.syncNow()).blocked, isNull);
        expect(recorder.markerWrites, hasLength(1));
        expect(recorder.bbtWrites, hasLength(1));

        for (final again in [service, buildService()]) {
          expect((await again.syncNow()).blocked, isNull);
          expect(recorder.markerWrites, hasLength(1));
          expect(recorder.bbtWrites, hasLength(1));
        }
      });

      // Deciding in whole milliseconds would also have stopped the repeat,
      // and would have lost this row: the app itself saves a day and the
      // entry on it a fraction of a millisecond apart.
      test('a row saved later in the same millisecond is still written',
          () async {
        await seedGranted(grant);
        dayEntries.entries = [_entry('2026-06-20', FlowLevel.none, savedAt)];
        final service = buildService();
        expect((await service.syncNow()).blocked, isNull);
        expect(platform.markerWrites, isEmpty);

        observations.observations = [
          _spotting(
            '2026-06-20',
            savedAt.add(const Duration(microseconds: 300)),
          ),
        ];
        expect((await service.syncNow()).blocked, isNull);
        expect(platform.markerWrites, hasLength(1));
      });

      // An install that upgrades from the moving cursor. Its floor is where
      // the cursor stood, in milliseconds alone, which is a little before
      // the newest row that build wrote. A row after the floor is how one
      // that build still owed looks, so it is sent once more, as it was on
      // every pass before #1577, and then no more.
      test('a cursor an earlier build stored, in milliseconds alone, sends '
          'the newest row once more and then no more', () async {
        await settings.set(_bindingKey, _profileId);
        await settings.set(_cursorKey, '${savedAt.millisecondsSinceEpoch}');
        dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, savedAt)];
        await ledger.record([
          HealthExportLedgerEntry(
            recordId: 'entry-2026-06-02',
            profileId: _profileId,
            sourceRowId: 'entry-2026-06-02',
            kind: HealthExportLedgerKind.entry,
            localDate: '2026-06-02',
            exportedAt: savedAt.add(const Duration(seconds: 1)),
          ),
        ]);

        expect((await buildService().syncNow()).blocked, isNull);
        expect(platform.flowWrites, hasLength(1));

        expect((await buildService().syncNow()).blocked, isNull);
        expect(platform.flowWrites, hasLength(1));
      });

      test('and a row that build had not written is sent once', () async {
        await settings.set(_bindingKey, _profileId);
        await settings.set(_cursorKey, '${savedAt.millisecondsSinceEpoch}');
        dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, savedAt)];

        expect((await buildService().syncNow()).blocked, isNull);
        expect(platform.flowWrites, hasLength(1));

        expect((await buildService().syncNow()).blocked, isNull);
        expect(platform.flowWrites, hasLength(1));
      });

      test('the millisecond value decides when the two disagree, so a row '
          'can be sent and is never skipped', () async {
        // The microsecond value names a later second than the millisecond
        // one. If it decided, the floor would be past this row.
        await seedGranted(grant);
        await settings.set(
          usKey,
          '${grant.add(const Duration(seconds: 5)).microsecondsSinceEpoch}',
        );
        final first =
            _entry('2026-06-02', FlowLevel.medium,
                grant.add(const Duration(seconds: 1)));
        dayEntries.entries = [first];
        expect((await buildService().syncNow()).blocked, isNull);
        expect(platform.flowWrites, hasLength(1));

        // And a value that is not a number is ignored the same way.
        await settings.set(usKey, 'not a number');
        dayEntries.entries = [
          first,
          _entry('2026-06-20', FlowLevel.medium,
              grant.add(const Duration(seconds: 2))),
        ];
        expect((await buildService().syncNow()).blocked, isNull);
        expect(platform.flowWrites, hasLength(2));
      });

      // On main the grant pass left a row saved a moment before the grant
      // alone, and every later pass read the cursor back as the start of
      // its millisecond and wrote it: a backfill of something logged
      // before write access was given.
      test('a row saved in the grant\'s millisecond, before the grant, is '
          'never written', () async {
        await settings.set(_bindingKey, _profileId);
        clock = grant.add(const Duration(microseconds: 500));
        dayEntries.entries = [
          _entry('2026-06-02', FlowLevel.medium,
              grant.add(const Duration(microseconds: 200))),
        ];

        expect((await buildService().syncNow()).blocked, isNull);
        expect(await settings.get(usKey), '${clock.microsecondsSinceEpoch}');
        expect(platform.flowWrites, isEmpty);

        expect((await buildService().syncNow()).blocked, isNull);
        expect(platform.flowWrites, isEmpty);
      });

      test('unbinding clears both forms', () async {
        await seedGranted(grant);
        dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, savedAt)];
        final service = buildService();
        await service.syncNow();
        await service.onUnbound();
        expect(await settings.get(_cursorKey), '');
        expect(await settings.get(usKey), '');
      });
    });

    test('a failed write is not remembered, so the failing day (and only '
        'it) is sent again', () async {
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

      // A later-logged day fails. It is not remembered as written, so it
      // is sent again on the next pass; the first day is remembered, and
      // is not.
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
      expect(
        ledger.rows.map((row) => row.recordId),
        isNot(contains('entry-2026-06-03')),
      );

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

    test('none and notBleeding produce no sample, and each is asked to be '
        'deleted once, in case an earlier binding wrote it', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.none,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-03', FlowLevel.notBleeding,
            grant.add(const Duration(hours: 2))),
      ];
      final service = buildService();

      final report = await service.syncNow();

      expect(report.samplesWritten, 0);
      expect(report.daysWithoutSample, 2);
      expect(platform.flowWrites, isEmpty);
      expect(platform.markerWrites, isEmpty);
      // Issue #1581: nothing says these were ever in the store, so they do
      // not count as taken out of it, and nothing is remembered. The delete
      // is sent blind, once, as it always was (issue #619, LLA-024).
      expect(report.samplesReconciled, 0);
      expect(platform.deleteCalls, [
        ['entry-2026-06-02', 'entry-2026-06-03'],
      ]);
      expect(ledger.rows, isEmpty);

      // Not on every pass: before #1581 it was sent again whenever the day
      // was saved, and after it a pass looks at these days every time.
      await service.syncNow();
      await buildService().syncNow();
      expect(platform.deleteCalls, hasLength(1));
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
        'issue #619, LLA-024: a refused reconciliation delete is reported, '
        'and sent again on the next pass', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
      ];
      final service = buildService();
      await service.syncNow();

      platform.deleteResult =
          const HealthPlatformResult.failed('store unavailable');
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.none,
            grant.add(const Duration(hours: 3))),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isA<HealthPlatformFailed>());
      expect(report.samplesReconciled, 0);
      expect(
        ledger.rows.map((row) => row.recordId),
        contains('entry-2026-06-02'),
        reason: 'a delete the store refused is not forgotten',
      );

      platform.deleteResult = const HealthPlatformAllowed();
      platform.deleteCalls.clear();
      final retried = await service.syncNow();
      expect(retried.blocked, isNull);
      expect(platform.deleteCalls.first, ['entry-2026-06-02']);
      expect(ledger.rows, isEmpty);
    });

    test(
        'a partial reconciliation delete with flow skipped is reported, '
        'and asked again on the next pass (issue #1583)',
        () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      platform.deleteResult =
          const HealthPlatformResult.partial({'menstrualFlow'});
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.none,
            grant.add(const Duration(hours: 1))),
      ];

      final service = buildService();
      final report = await service.syncNow();

      expect(report.blocked, isA<HealthPlatformPartial>());

      // Issue #1581: nothing was let go, so the day is asked for again.
      platform.deleteResult = const HealthPlatformAllowed();
      expect((await service.syncNow()).blocked, isNull);
      expect(platform.deleteCalls, [
        ['entry-2026-06-02'],
        ['entry-2026-06-02'],
      ]);
      await service.syncNow();
      expect(platform.deleteCalls, hasLength(2));
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

      final service = buildService();
      final report = await service.syncNow();

      expect(report.blocked, isA<HealthPlatformPermissionDenied>());
      expect(platform.periodWrites, hasLength(1));

      // The period is still owed, and the day that was written is not
      // sent again.
      platform.writeResults = [];
      final next = await service.syncNow();
      expect(next.blocked, isNull);
      expect(next.periodRecordsWritten, 1);
      expect(platform.periodWrites, hasLength(2));
      expect(platform.flowWrites, hasLength(1));
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
      // The day's own record goes with the day (Issue #1589), then the
      // period that was made of it.
      expect(platform.deleteCalls, [
        ['entry-2026-06-02'],
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
      expect(platform.deleteCalls, [
        ['entry-2026-06-04'],
      ], reason: 'the deleted day\'s own record goes (Issue #1589)');
      expect(platform.periodDeleteCalls, isEmpty,
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
      // Each pass asks for the deleted day's own record (Issue #1589) and
      // then for the period: refused, then allowed.
      expect(platform.deleteCalls, [
        ['entry-2026-06-02'],
        ['period-$_profileId-2026-06-02'],
        ['entry-2026-06-02'],
        ['period-$_profileId-2026-06-02'],
      ]);
      expect(periodRow('period-$_profileId-2026-06-02'), isNull);
    });

    test('a partial delete with menstrualFlow skipped keeps the period record '
        'remembered and is retried (issue #1583)', () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
      ];
      await service.syncNow();

      dayEntries.entries = [];
      platform.deleteResult =
          const HealthPlatformResult.partial({'menstrualFlow'});
      final partial = await service.syncNow();
      expect(partial.blocked, isA<HealthPlatformPartial>());
      expect(periodRow('period-$_profileId-2026-06-02'), isNotNull);

      platform.deleteResult = const HealthPlatformAllowed();
      final retried = await service.syncNow();
      expect(retried.blocked, isNull);
      // The deleted day's own record is a flow record too (Issue #1589),
      // so it was passed over with the period and is asked for again.
      expect(platform.deleteCalls, [
        ['entry-2026-06-02'],
        ['period-$_profileId-2026-06-02'],
        ['entry-2026-06-02'],
        ['period-$_profileId-2026-06-02'],
      ]);
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
      expect(platform.periodDeleteCalls, isEmpty,
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
        ['entry-2026-06-02'],
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
      platform.deleteCalls.clear();

      // Re-bound, already granted, the remaining day now gone too: its
      // records were written under the earlier binding, so they are left
      // in place — what the screen says turning sync off does. None of
      // them: not the period, and not the day's own.
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
        'no period record, and moves the cycle-start flag off the old first '
        'day (#1591)', () async {
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
      // The flag follows the episode, and the episode the flag derives
      // from includes imported days (episodes.dart, the same derivation
      // the spotting rule uses) — so the imported 06-02 is now the
      // episode's first day, and the hand-logged 06-03 sample stops
      // saying it is one. Since #1591 a change made through *other* rows
      // is sent: 06-03 is re-written with the flag false, at a raised
      // version, and 06-04 — whose own summary is unchanged — is not.
      expect(platform.flowWrites, hasLength(flowWrites + 1));
      final rewrite = platform.flowWrites.last;
      expect(rewrite.date.iso, '2026-06-03');
      expect(rewrite.cycleStart, isFalse);
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
    test('a period whose zone cannot be resolved is left alone: its record '
        'is neither deleted nor written again, and the pass does not fail',
        () async {
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
      expect(platform.periodDeleteCalls, isEmpty,
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
      // The day that was written before the transfer is remembered, and
      // the one that was not is still owed: nothing is remembered as
      // written that was cancelled.
      expect(ledger.rows.map((row) => row.recordId), ['entry-2026-06-02']);
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
      expect(ledger.rows.map((row) => row.recordId), ['entry-2026-06-02']);
    });

    // Issue #1605. The two deletes a pass can send are checked like its
    // writes, and nothing tested it: the drift tests above cover writes.
    test('ownership transferred away before a cleared day\'s record is asked '
        'to be deleted: the delete is not sent, and is asked for on the next '
        'pass', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      // A day saved with no flow: the ledger knows of no record for it, so
      // the pass asks the store to delete one, once.
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.none,
            grant.add(const Duration(hours: 1))),
      ];
      var transferred = false;
      platform.onBind = () => transferred = true;
      final service = buildService(
        guardians: () => [transferred ? _transferredRow() : _ownerRow()],
      );

      final report = await service.syncNow();

      expect(platform.deleteCalls, isEmpty);
      expect((report.blocked! as HealthPlatformRefused).check,
          HealthSyncCheck.notOwner);

      // Ownership is hers again. The delete was not counted as asked.
      platform.onBind = null;
      transferred = false;
      final next = await service.syncNow();
      expect(next.blocked, isNull);
      expect(platform.deleteCalls, [
        ['entry-2026-06-02'],
      ]);
    });

    test('ownership transferred away after a day is written and before a '
        'record it no longer has is deleted: the delete is not sent, and the '
        'record stays remembered', () async {
      final grant = DateTime.utc(2026, 6, 1, 12);
      await seedGranted(grant);
      const symptom = 'symptom-entry-2026-06-02-abdominalCramps';
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1)),
            tags: const ['cramps']),
      ];
      var transferred = false;
      final service = buildService(
        guardians: () => [transferred ? _transferredRow() : _ownerRow()],
      );
      await service.syncNow();
      expect(ledger.rows.map((row) => row.recordId), contains(symptom));

      // She unticks the symptom. The day is written again, and the
      // transfer lands between that write and the delete.
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 3))),
      ];
      platform.onFlowWrite = () => transferred = true;
      final report = await service.syncNow();

      expect(platform.flowWrites, hasLength(2));
      expect(platform.deleteCalls, isEmpty);
      expect((report.blocked! as HealthPlatformRefused).check,
          HealthSyncCheck.notOwner);
      expect(ledger.rows.map((row) => row.recordId), contains(symptom));

      platform.onFlowWrite = null;
      transferred = false;
      final next = await service.syncNow();
      expect(next.blocked, isNull);
      expect(platform.deleteCalls, [
        [symptom],
      ]);
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
      // issued, and the record stays remembered for when it can be.
      signedInUserId = 'someone-else';
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 3)),
            tags: const ['headache']),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isA<HealthPlatformRefused>());
      expect(platform.deleteCalls, isEmpty,
          reason: 'the same guard that gates the write gates the delete');
      expect(
        ledger.rows.map((row) => row.recordId),
        contains(healthSymptomRecordId('entry-2026-06-02', 'abdominalCramps')),
      );
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

      platform.deleteResult = const HealthPlatformPermissionDenied();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 3)),
            tags: const ['headache']),
      ];
      final blocked = await service.syncNow();
      expect(blocked.blocked, isA<HealthPlatformPermissionDenied>());
      expect(platform.deleteCalls, hasLength(1));
      expect(platform.flowWrites, hasLength(2),
          reason: 'the edited day itself was written');

      platform.deleteResult = const HealthPlatformAllowed();
      final retried = await service.syncNow();
      expect(retried.blocked, isNull);
      expect(platform.deleteCalls, hasLength(2),
          reason: 'the same removal is retried, not silently acknowledged');
    });

    test('a partial delete with the removed type skipped leaves the record in '
        'the ledger and retries next pass (issue #1583)', () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1)),
            tags: const ['cramps']),
      ];
      await service.syncNow();

      platform.deleteResult =
          const HealthPlatformResult.partial({'symptoms'});
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 3)),
            tags: const []),
      ];
      final blocked = await service.syncNow();
      expect(blocked.blocked, isA<HealthPlatformPartial>());
      expect(platform.deleteCalls, hasLength(1));
      expect(
        ledger.rows.map((row) => row.recordId),
        contains(healthSymptomRecordId('entry-2026-06-02', 'abdominalCramps')),
        reason: 'a record the store passed over is not forgotten',
      );

      platform.deleteResult = const HealthPlatformAllowed();
      final retried = await service.syncNow();
      expect(retried.blocked, isNull);
      expect(platform.deleteCalls, hasLength(2),
          reason: 'the same removal is retried, not silently acknowledged');
    });

    // What an iPhone answers with one symptom type off (acne here): that
    // type, and 'symptoms' beside it. The cramps record is of another type
    // and was deleted. Read as "every symptom was passed over", the answer
    // kept it remembered, and the delete was sent again on every pass.
    test('a partial delete that passed over another symptom type lets the '
        'removed one go: it is not asked for again', () async {
      await seedGranted(grant);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1)),
            tags: const ['cramps']),
      ];
      await service.syncNow();

      platform.deleteResult =
          const HealthPlatformResult.partial({'acne', 'symptoms'});
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 3)),
            tags: const []),
      ];
      await service.syncNow();
      expect(platform.deleteCalls.single,
          ['symptom-entry-2026-06-02-abdominalCramps']);

      final next = await service.syncNow();
      expect(next.blocked, isNull);
      expect(platform.deleteCalls, hasLength(1),
          reason: 'the record is gone, so there is nothing left to ask for');
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

  group('partial write permissions (issue #1555)', () {
    final grant = DateTime.utc(2026, 6, 1, 12);

    test('writingSome does not block the sync pass and queries grantedWriteTypes',
        () async {
      await seedGranted(grant);
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'menstrualFlow'};
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            grant.add(const Duration(hours: 1))),
      ];

      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      expect(report.samplesWritten, 1);
      expect(platform.grantedWriteTypesCalls, 1);
      expect(platform.flowWrites, hasLength(1));
    });

    // Issue #1581. Forward-only holds for each type: what was logged
    // while a type was off stays out when the type is switched on, as it
    // did when a cursor moved past it. What changed is the other case,
    // further down: a correction to a record already in the store.
    test('when menstrualFlow is off, a day logged meanwhile is not sent when '
        'it is switched on; a day logged after that is', () async {
      await seedGranted(grant);
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'spotting'};
      final t1 = grant.add(const Duration(hours: 1));
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy, t1),
      ];
      clock = t1.add(const Duration(minutes: 1));
      final service = buildService();

      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(report.samplesWritten, 0);
      expect(report.periodRecordsWritten, 0);
      expect(platform.flowWrites, isEmpty);
      expect(platform.periodWrites, isEmpty);
      expect(ledger.rows, isEmpty,
          reason: 'nothing is remembered as written that was not');

      // Switched on. The day was logged while it was off.
      platform.permission = HealthPermissionStatus.granted;
      clock = t1.add(const Duration(minutes: 2));
      final after = await service.syncNow();
      expect(after.samplesWritten, 0);
      expect(after.periodRecordsWritten, 0,
          reason: 'nor does that period get a record');
      expect(platform.flowWrites, isEmpty);
      expect(platform.periodWrites, isEmpty);

      // A day logged from here on is written, with its own period.
      dayEntries.entries = [
        ...dayEntries.entries,
        _entry('2026-06-20', FlowLevel.medium,
            t1.add(const Duration(minutes: 3))),
      ];
      clock = t1.add(const Duration(minutes: 4));
      final later = await service.syncNow();
      expect(later.samplesWritten, 1);
      expect(platform.flowWrites.single.recordId, 'entry-2026-06-20');
      expect(platform.periodWrites.single.start, LocalDate.fromIso('2026-06-20'));
    });

    test('an edit made while its type is off is sent when the type is back '
        'on: the store already has the record, and it is out of date',
        () async {
      await seedGranted(grant);
      final t1 = grant.add(const Duration(hours: 1));
      dayEntries.entries = [_entry('2026-06-02', FlowLevel.heavy, t1)];
      clock = t1.add(const Duration(minutes: 1));
      final service = buildService();
      await service.syncNow();
      expect(platform.flowWrites.single.flow, HealthFlowValue.heavy);

      // Menstruation is switched off, and she corrects the day to light.
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'spotting'};
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.light,
            t1.add(const Duration(minutes: 2))),
      ];
      clock = t1.add(const Duration(minutes: 3));
      await service.syncNow();
      await service.syncNow();
      expect(platform.flowWrites, hasLength(1));

      // Back on: the store is brought up to what she logged.
      platform.permission = HealthPermissionStatus.granted;
      clock = t1.add(const Duration(minutes: 4));
      final after = await service.syncNow();
      expect(after.samplesWritten, 1);
      expect(platform.flowWrites.last.flow, HealthFlowValue.light);
      expect(
        platform.flowWrites.last.recordVersionMs,
        greaterThan(platform.flowWrites.first.recordVersionMs),
      );
    });

    test('when spotting is off, a spotting entry logged meanwhile is not '
        'sent when it is switched on, while flow is written throughout',
        () async {
      await seedGranted(grant);
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'menstrualFlow'};
      final t1 = grant.add(const Duration(hours: 1));
      final t2 = grant.add(const Duration(hours: 2));
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, t1),
      ];
      observations.observations = [
        _spotting('2026-06-03', t2),
      ];
      clock = t2.add(const Duration(minutes: 1));
      final service = buildService();

      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(report.samplesWritten, 1);
      expect(platform.flowWrites, hasLength(1));
      expect(platform.markerWrites, isEmpty);

      platform.grantedTypes = {'menstrualFlow', 'spotting'};
      clock = t2.add(const Duration(minutes: 2));
      final after = await service.syncNow();
      expect(after.samplesWritten, 0);
      expect(platform.markerWrites, isEmpty);

      observations.observations = [
        ...observations.observations,
        _spotting('2026-06-10', t2.add(const Duration(minutes: 3))),
      ];
      clock = t2.add(const Duration(minutes: 4));
      final later = await service.syncNow();
      expect(later.samplesWritten, 1);
      expect(platform.markerWrites.single.recordId, 'spot-2026-06-10');
      expect(platform.flowWrites, hasLength(1),
          reason: 'the day that was written is not sent again');
    });

    test('when BBT, cervical mucus, and ovulation are off, what was logged '
        'meanwhile is not sent when they are switched on; a later save of '
        'the day is', () async {
      await seedGranted(grant);
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'menstrualFlow'};
      final t1 = grant.add(const Duration(hours: 1));
      final t2 = grant.add(const Duration(hours: 2));
      const tags = ['egg_white', 'ovulation_positive'];
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, t1, tags: tags),
      ];
      observations.observations = [
        _bbt('2026-06-03', 36.6, t2),
      ];
      clock = t2.add(const Duration(minutes: 1));
      final service = buildService();

      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(report.samplesWritten, 1);
      expect(report.cervicalMucusSamplesWritten, 0);
      expect(report.ovulationTestSamplesWritten, 0);
      expect(report.basalBodyTemperatureSamplesWritten, 0);

      platform.permission = HealthPermissionStatus.granted;
      clock = t2.add(const Duration(minutes: 2));
      final after = await service.syncNow();
      expect(after.samplesWritten, 0);
      expect(after.cervicalMucusSamplesWritten, 0);
      expect(after.ovulationTestSamplesWritten, 0);
      expect(after.basalBodyTemperatureSamplesWritten, 0);

      // She saves the day and the reading again, with the types on.
      final t3 = t2.add(const Duration(minutes: 3));
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, t3, tags: tags),
      ];
      observations.observations = [_bbt('2026-06-03', 36.7, t3)];
      clock = t3.add(const Duration(minutes: 1));
      final later = await service.syncNow();
      expect(later.cervicalMucusSamplesWritten, 1);
      expect(later.ovulationTestSamplesWritten, 1);
      expect(later.basalBodyTemperatureSamplesWritten, 1);
    });

    // Second review of #1595. With every type off the pass ends before it
    // reads which types are on, and it moved no floor: a month logged with
    // write access removed was sent when one type came back.
    test('when write access is removed altogether, a day logged meanwhile '
        'is not sent when a type is switched on; a day logged after that is',
        () async {
      await seedGranted(grant);
      final t1 = grant.add(const Duration(hours: 1));
      dayEntries.entries = [_entry('2026-06-02', FlowLevel.heavy, t1)];
      clock = t1.add(const Duration(minutes: 1));
      final service = buildService();
      await service.syncNow();
      expect(platform.flowWrites, hasLength(1));

      // Every write permission is switched off, and she logs a day.
      platform.permission = HealthPermissionStatus.denied;
      final t2 = t1.add(const Duration(minutes: 2));
      dayEntries.entries = [
        ...dayEntries.entries,
        _entry('2026-06-20', FlowLevel.medium, t2),
      ];
      clock = t2.add(const Duration(minutes: 1));
      final off = await service.syncNow();
      expect(off.blocked, isA<HealthPlatformPermissionDenied>());
      final floors = HealthWritePassState.decode(
        await settings.get(SettingsKeys.healthSyncWriteState),
      )!.typeFloors;
      expect(floors.keys.toSet(), healthWriteTypesOff(const <String>{}),
          reason: 'every write type, not flow alone');
      expect(floors.values.toSet(), {clock});

      // Menstruation comes back.
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'menstrualFlow'};
      clock = t2.add(const Duration(minutes: 2));
      final back = await service.syncNow();
      expect(back.blocked, isNull);
      expect(back.samplesWritten, 0);
      expect(platform.flowWrites, hasLength(1));

      // A day logged from here on is written.
      dayEntries.entries = [
        ...dayEntries.entries,
        _entry('2026-07-15', FlowLevel.light,
            t2.add(const Duration(minutes: 3))),
      ];
      clock = t2.add(const Duration(minutes: 4));
      final later = await service.syncNow();
      expect(later.samplesWritten, 1);
      expect(platform.flowWrites.last.recordId, 'entry-2026-07-15');
    });

    // Never granted, so there is no floor yet. The grant stamps one, and
    // it covers everything logged before it.
    test('a binding that was never granted write access stores nothing '
        'when it finds it refused', () async {
      await settings.set(_bindingKey, _profileId);
      platform.permission = HealthPermissionStatus.denied;

      final report = await buildService().syncNow();

      expect(report.blocked, isA<HealthPlatformPermissionDenied>());
      expect(await settings.get(SettingsKeys.healthSyncWriteState), isNull);
    });

    // Second review of #1595. A period has a record when the store holds
    // the flow of one of its days. Any record of the day's row used to
    // count, a discharge among them.
    test('with menstrualFlow off, a period day whose discharge was written '
        'gets no period record when flow is switched on', () async {
      await seedGranted(grant);
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'cervicalMucus'};
      final t1 = grant.add(const Duration(hours: 1));
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy, t1, tags: const ['egg_white']),
      ];
      clock = t1.add(const Duration(minutes: 1));
      final service = buildService();

      final off = await service.syncNow();
      expect(off.cervicalMucusSamplesWritten, 1);
      expect(platform.flowWrites, isEmpty);

      platform.grantedTypes = {'cervicalMucus', 'menstrualFlow'};
      clock = t1.add(const Duration(minutes: 2));
      final back = await service.syncNow();
      expect(back.blocked, isNull);
      expect(back.samplesWritten, 0);
      expect(back.periodRecordsWritten, 0);
      expect(platform.periodWrites, isEmpty);
    });
  });

  // Issue #1604. A type's floor moved only on a pass that found it off, so
  // a row that arrived between the last such pass and the one that found
  // the type on again was sent when the type came back. One test per kind
  // of row the review named, and one for the row saved after the pass that
  // finds the type on.
  group('issue #1604: what arrived while a type was off stays out when it '
      'is switched back on', () {
    final grant = DateTime.utc(2026, 6, 1, 12);
    DateTime at(int minutes) => grant.add(Duration(minutes: minutes));

    /// A first pass that finds spotting off, so its floor and the
    /// remembered off-set are stored.
    Future<LocalHealthFlowWriteService> passThatFindsSpottingOff() async {
      await seedGranted(grant);
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'menstrualFlow'};
      dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, at(60))];
      clock = at(61);
      final service = buildService();
      final off = await service.syncNow();
      expect(off.blocked, isNull);
      expect(platform.flowWrites, hasLength(1));
      return service;
    }

    test('a row from another device that synced in while the app was '
        'closed', () async {
      final service = await passThatFindsSpottingOff();

      // While this app was closed, another device's spotting entry synced
      // in: its time is after the pass that saw spotting off.
      observations.observations = [_spotting('2026-06-03', at(70))];

      // She returns and switches spotting on.
      platform.grantedTypes = {'menstrualFlow', 'spotting'};
      clock = at(71);
      final back = await service.syncNow();
      expect(back.samplesWritten, 0);
      expect(platform.markerWrites, isEmpty,
          reason: 'it arrived while spotting was off; the pass that finds '
              'the type on moves its floor over it');

      // Saved from here on, it is written.
      observations.observations = [_spotting('2026-06-10', at(72))];
      clock = at(73);
      final later = await service.syncNow();
      expect(later.samplesWritten, 1);
      expect(platform.markerWrites.single.recordId, 'spot-2026-06-10');
    });

    test('a day saved in the moment before the app was left', () async {
      final service = await passThatFindsSpottingOff();

      // Saved just before she left for the store's settings screen — the
      // write pass is debounced, so no pass saw it while spotting was off.
      observations.observations = [_spotting('2026-06-03', at(62))];

      platform.grantedTypes = {'menstrualFlow', 'spotting'};
      clock = at(63);
      final back = await service.syncNow();
      expect(back.samplesWritten, 0);
      expect(platform.markerWrites, isEmpty);

      observations.observations = [_spotting('2026-06-10', at(64))];
      clock = at(65);
      final later = await service.syncNow();
      expect(later.samplesWritten, 1);
    });

    test('a row saved around a pass that ended before it reached the '
        'floors', () async {
      final service = await passThatFindsSpottingOff();

      // The next pass cannot read which types are on (#1584) and ends
      // before the floors; the row arrives meanwhile.
      platform.grantedWriteTypesError = StateError('the store would not say');
      clock = at(62);
      final failed = await service.syncNow();
      expect(failed.blocked, isNotNull);
      platform.grantedWriteTypesError = null;
      observations.observations = [_spotting('2026-06-03', at(63))];

      platform.grantedTypes = {'menstrualFlow', 'spotting'};
      clock = at(64);
      final back = await service.syncNow();
      expect(back.samplesWritten, 0);
      expect(platform.markerWrites, isEmpty);

      observations.observations = [_spotting('2026-06-10', at(65))];
      clock = at(66);
      final later = await service.syncNow();
      expect(later.samplesWritten, 1);
    });

    // The review's sequencing, confirmed: an in-app grant is observed by
    // the pass that asked for it (the request is awaited inside the pass,
    // and the post-request status is what the same pass resolves types
    // from), so no save of hers can land between the grant and the pass
    // that records it.
    test('the pass that asks for write access observes the grant itself',
        () async {
      await settings.set(_bindingKey, _profileId);
      platform.permission = HealthPermissionStatus.notAsked;
      platform.permissionAfterAuth = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'menstrualFlow'};
      clock = at(10);
      final service = buildService();

      final grantPass = await service.syncNow();
      expect(grantPass.authorizationRequested, isTrue);
      expect(platform.authCalls, 1);

      // The grant pass saw spotting off; a spotting entry saved while it is
      // off stays out when the type comes back.
      observations.observations = [_spotting('2026-06-03', at(11))];
      platform.grantedTypes = {'menstrualFlow', 'spotting'};
      clock = at(12);
      final back = await service.syncNow();
      expect(back.samplesWritten, 0);
      expect(platform.markerWrites, isEmpty);

      observations.observations = [_spotting('2026-06-10', at(13))];
      clock = at(14);
      final later = await service.syncNow();
      expect(later.samplesWritten, 1);
      expect(platform.markerWrites.single.recordId, 'spot-2026-06-10');
    });
  });

  // Issue #1581. The pass used to send whatever was newer than a cursor
  // that moved to the newest row it wrote. A row that turns up with an
  // older time was never sent. Each test here is one such row.
  group('issue #1581: what is sent is decided from what was written', () {
    final grant = DateTime.utc(2026, 6, 1, 12);
    DateTime at(int minutes) => grant.add(Duration(minutes: minutes));

    test('a row that arrives late from another device, older than rows '
        'already written, is sent', () async {
      await seedGranted(grant);
      final written = _entry('2026-06-10', FlowLevel.medium, at(60));
      dayEntries.entries = [written];
      final service = buildService();
      await service.syncNow();
      expect(platform.flowWrites, hasLength(1));

      // Saved on another device half an hour before that row, and synced
      // to this phone only now.
      dayEntries.entries = [
        written,
        _entry('2026-06-20', FlowLevel.light, at(30)),
      ];
      final report = await service.syncNow();

      expect(report.samplesWritten, 1);
      expect(platform.flowWrites.last.date, LocalDate.fromIso('2026-06-20'));
    });

    test('but never one saved before write access was granted, whenever it '
        'arrives', () async {
      await seedGranted(grant);
      final written = _entry('2026-06-10', FlowLevel.medium, at(60));
      dayEntries.entries = [written];
      final service = buildService();
      await service.syncNow();

      dayEntries.entries = [
        written,
        _entry('2026-05-20', FlowLevel.light, at(-30)),
      ];
      final report = await service.syncNow();

      expect(report.samplesWritten, 0);
      expect(platform.flowWrites, hasLength(1));
    });

    // The day sheet stamped an entry with the device's clock and the
    // storage layer stamped the day with its own, a little ahead.
    test('a row stamped by a slower clock than the one a pass has already '
        'seen is sent', () async {
      await seedGranted(grant);
      dayEntries.entries = [_entry('2026-06-10', FlowLevel.none, at(60))];
      final service = buildService();
      await service.syncNow();

      observations.observations = [_bbt('2026-06-10', 36.6, at(59))];
      final report = await service.syncNow();

      expect(report.basalBodyTemperatureSamplesWritten, 1);
    });

    test('the floor is stamped by the clock rows are stamped with, not the '
        'device\'s own', () async {
      await settings.set(_bindingKey, _profileId);
      // The phone runs five minutes ahead of the server, so the storage
      // layer stamps rows five minutes behind the device's clock.
      const ahead = Duration(minutes: 5);
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
        signedInUserId: () => _ownerId,
        now: () => clock,
        rowClock: () => clock.subtract(ahead),
      );

      await service.syncNow();
      expect(
        await settings.get(_cursorKey),
        '${clock.subtract(ahead).millisecondsSinceEpoch}',
      );

      // A day saved a minute after access was granted.
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium,
            clock.add(const Duration(minutes: 1)).subtract(ahead)),
      ];
      expect((await service.syncNow()).samplesWritten, 1);
    });

    test('spotting on a bleed day is sent when the flow is cleared, though '
        'nothing touched the spotting entry', () async {
      await seedGranted(grant);
      dayEntries.entries = [_entry('2026-06-10', FlowLevel.medium, at(10))];
      observations.observations = [_spotting('2026-06-10', at(10))];
      final service = buildService();
      final first = await service.syncNow();
      expect(platform.markerWrites, isEmpty);
      expect(first.daysWithoutSample, 1);

      dayEntries.entries = [_entry('2026-06-10', FlowLevel.none, at(20))];
      await service.syncNow();

      expect(platform.markerWrites.single.recordId, 'spot-2026-06-10');
      expect(platform.deleteCalls, [
        ['entry-2026-06-10'],
        ['period-$_profileId-2026-06-10'],
      ]);
    });

    test('a spotting marker is taken out when its day is given a flow, and '
        'written again when the flow goes', () async {
      await seedGranted(grant);
      dayEntries.entries = [_entry('2026-06-10', FlowLevel.none, at(10))];
      observations.observations = [_spotting('2026-06-10', at(10))];
      final service = buildService();
      await service.syncNow();
      expect(platform.markerWrites, hasLength(1));

      platform.deleteCalls.clear();

      dayEntries.entries = [_entry('2026-06-10', FlowLevel.medium, at(20))];
      final report = await service.syncNow();
      expect(platform.flowWrites.single.recordId, 'entry-2026-06-10');
      expect(platform.deleteCalls, [
        ['spot-2026-06-10'],
      ]);
      expect(report.samplesReconciled, 1);
      expect(platform.markerWrites, hasLength(1));

      dayEntries.entries = [_entry('2026-06-10', FlowLevel.none, at(30))];
      await service.syncNow();
      expect(platform.markerWrites, hasLength(2));
      // The store has held this record and let it go, and the spotting
      // row itself has not changed. It is given a later version than
      // before, the day's, so the store cannot take it for one it has
      // already seen.
      expect(
        platform.markerWrites.last.recordVersionMs,
        at(30).millisecondsSinceEpoch,
      );
      expect(
        platform.markerWrites.first.recordVersionMs,
        at(10).millisecondsSinceEpoch,
      );
    });

    test('a row that maps to no sample is counted on every pass', () async {
      await seedGranted(grant);
      dayEntries.entries = [_entry('2026-06-10', FlowLevel.none, at(10))];
      final service = buildService();

      expect((await service.syncNow()).daysWithoutSample, 1);
      expect((await service.syncNow()).daysWithoutSample, 1);
      expect(platform.deleteCalls, hasLength(1),
          reason: 'asked to be deleted once, not on every pass');
    });

    test('a record waiting for its type does not send the row\'s other '
        'records again', () async {
      await seedGranted(grant);
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'menstrualFlow'};
      dayEntries.entries = [
        _entry('2026-06-10', FlowLevel.medium, at(10),
            tags: const ['egg_white']),
      ];
      final service = buildService();

      final first = await service.syncNow();
      expect(first.samplesWritten, 1);
      expect(first.cervicalMucusSamplesWritten, 0);

      for (final again in [service, buildService()]) {
        final report = await again.syncNow();
        expect(report.samplesWritten, 0);
        expect(platform.flowWrites, hasLength(1));
      }
    });

    test('a record whose type is off is not asked to be deleted, and stays '
        'remembered until the type is back on', () async {
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-10', FlowLevel.medium, at(10),
            tags: const ['egg_white']),
      ];
      final service = buildService();
      final first = await service.syncNow();
      expect(first.cervicalMucusSamplesWritten, 1);

      // Cervical mucus is switched off, and she removes the tag.
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'menstrualFlow'};
      dayEntries.entries = [_entry('2026-06-10', FlowLevel.medium, at(20))];
      final off = await service.syncNow();

      expect(off.blocked, isNull);
      expect(off.samplesReconciled, 0);
      expect(platform.deleteCalls, isEmpty);
      expect(
        ledger.rows.map((row) => row.recordId),
        contains(healthCervicalMucusRecordId('entry-2026-06-10')),
      );

      platform.permission = HealthPermissionStatus.granted;
      final on = await service.syncNow();
      expect(platform.deleteCalls, [
        [healthCervicalMucusRecordId('entry-2026-06-10')],
      ]);
      expect(on.samplesReconciled, 1);
    });

    test('a spotting record is removed only with both flow and spotting '
        'on', () async {
      await seedGranted(grant);
      dayEntries.entries = [_entry('2026-06-10', FlowLevel.none, at(10))];
      observations.observations = [_spotting('2026-06-10', at(10))];
      final service = buildService();
      await service.syncNow();
      expect(platform.markerWrites, hasLength(1));
      platform.deleteCalls.clear();

      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'menstrualFlow'};
      dayEntries.entries = [_entry('2026-06-10', FlowLevel.medium, at(20))];
      await service.syncNow();
      expect(platform.flowWrites, hasLength(1));
      expect(platform.deleteCalls, isEmpty);

      platform.grantedTypes = {'menstrualFlow', 'spotting'};
      await service.syncNow();
      expect(platform.deleteCalls, [
        ['spot-2026-06-10'],
      ]);
    });

    test('a store that is not there ends the step at the first answer, and '
        'nothing is remembered as written', () async {
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-10', FlowLevel.medium, at(10)),
        _entry('2026-06-20', FlowLevel.medium, at(11)),
        _entry('2026-06-30', FlowLevel.medium, at(12)),
      ];
      platform.writeResults = [const HealthPlatformUnavailable()];
      final service = buildService();

      final report = await service.syncNow();

      expect(report.blocked, isA<HealthPlatformUnavailable>());
      expect(platform.flowWrites, hasLength(1));
      expect(ledger.rows, isEmpty);

      platform.writeResults = [];
      final after = await service.syncNow();
      expect(after.blocked, isNull);
      expect(after.samplesWritten, 3);
      expect(after.periodRecordsWritten, 3);
    });

    // Builds before this one filed every id a day could produce under the
    // day, written or not, and stamped the row with the time of the pass.
    test('a ledger from an earlier build: what it wrote is not sent again, '
        'and a flow record it only named is cleared once', () async {
      await settings.set(_bindingKey, _profileId);
      // Where that build's cursor stood: at the row it wrote last.
      await settings.set(_cursorKey, '${at(10).millisecondsSinceEpoch}');
      dayEntries.entries = [
        _entry('2026-06-10', FlowLevel.none, at(10), tags: const ['cramps']),
      ];
      final symptomId =
          healthSymptomRecordId('entry-2026-06-10', 'abdominalCramps');
      await ledger.record([
        for (final recordId in ['entry-2026-06-10', symptomId])
          HealthExportLedgerEntry(
            recordId: recordId,
            profileId: _profileId,
            sourceRowId: 'entry-2026-06-10',
            kind: HealthExportLedgerKind.entry,
            localDate: '2026-06-10',
            exportedAt: at(11),
          ),
      ]);

      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      expect(report.symptomSamplesWritten, 0);
      expect(platform.flowWrites, isEmpty);
      // That build asked for the day's flow record to be deleted when it
      // looked at the day, so there is nothing to ask the store: the name
      // is dropped from the ledger.
      expect(platform.deleteCalls, isEmpty);
      expect(ledger.rows.map((row) => row.recordId), [symptomId]);
      expect(ledger.rows.single.exportedAt, at(10),
          reason: 're-stamped with the row\'s own time');

      await buildService().syncNow();
      expect(platform.deleteCalls, isEmpty);

      // And an edit to that day, later, is sent.
      dayEntries.entries = [
        _entry('2026-06-10', FlowLevel.light, at(40), tags: const ['cramps']),
      ];
      final edited = await buildService().syncNow();
      expect(edited.samplesWritten, 1);
      expect(edited.symptomSamplesWritten, 1);
    });

    // Third read of #1595. No binding has a stored state when this build
    // first runs for it, so the one found with write access removed then
    // is everyone who had removed it before updating. Its ledger is read
    // as that build's on that pass: a state stored without doing so would
    // tell the first real pass there was nothing left to read.
    test('a ledger from an earlier build, found with write access removed: '
        'it is read as one on that pass, and what she logs meanwhile is not '
        'sent when write access comes back', () async {
      await settings.set(_bindingKey, _profileId);
      await settings.set(_cursorKey, '${at(10).millisecondsSinceEpoch}');
      dayEntries.entries = [
        _entry('2026-06-10', FlowLevel.medium, at(10)),
      ];
      await ledger.record([
        HealthExportLedgerEntry(
          recordId: 'entry-2026-06-10',
          profileId: _profileId,
          sourceRowId: 'entry-2026-06-10',
          kind: HealthExportLedgerKind.entry,
          localDate: '2026-06-10',
          exportedAt: at(11),
        ),
      ]);
      platform.permission = HealthPermissionStatus.denied;
      clock = at(20);
      final service = buildService();

      final off = await service.syncNow();
      expect(off.blocked, isA<HealthPlatformPermissionDenied>());
      expect(ledger.rows.single.exportedAt, at(10),
          reason: 're-stamped with the row\'s own time');
      final state = HealthWritePassState.decode(
        await settings.get(SettingsKeys.healthSyncWriteState),
      )!;
      expect(state.clearedThrough, at(10));
      expect(state.typeFloors['menstrualFlow'], at(20));

      // She logs a day with write access still removed.
      dayEntries.entries = [
        ...dayEntries.entries,
        _entry('2026-06-25', FlowLevel.light, at(30)),
      ];
      clock = at(31);
      await service.syncNow();

      // Write access comes back.
      platform.permission = HealthPermissionStatus.granted;
      clock = at(32);
      final back = await service.syncNow();
      expect(back.blocked, isNull);
      // The 06-10 day was written by the earlier build, which recorded
      // nothing about what its record said; issue #1591 reads that as
      // unknown and sends it once, with its cycle-start flag. The 06-25
      // day logged with write access removed is a different matter: it
      // was never written, and its type's floor keeps it out.
      expect(back.samplesWritten, 1);
      expect(platform.flowWrites.single.recordId, 'entry-2026-06-10');
      expect(
        ledger.rows
            .singleWhere((row) => row.recordId == 'entry-2026-06-10')
            .payloadSummary,
        'flow:medium:1',
        reason: 'the re-send stamps what it said',
      );
      clock = at(33);
      await service.syncNow();
      expect(platform.flowWrites, hasLength(1),
          reason: 'the #1591 re-send is once, not on every pass');

      dayEntries.entries = [
        ...dayEntries.entries,
        _entry('2026-07-20', FlowLevel.medium, at(40)),
      ];
      clock = at(41);
      final later = await service.syncNow();
      expect(later.samplesWritten, 1);
      expect(platform.flowWrites.last.recordId, 'entry-2026-07-20');
    });

    // The same install: every day of the period is at or below its floor,
    // so only the ledger says those days are in the store. Without that,
    // the period no longer counts as written and its record is deleted.
    test('a ledger from an earlier build: a period whose days it wrote '
        'keeps its record', () async {
      await settings.set(_bindingKey, _profileId);
      await settings.set(_cursorKey, '${at(11).millisecondsSinceEpoch}');
      dayEntries.entries = [
        _entry('2026-06-10', FlowLevel.medium, at(10)),
        _entry('2026-06-11', FlowLevel.medium, at(11)),
      ];
      await ledger.record([
        for (final day in ['2026-06-10', '2026-06-11'])
          HealthExportLedgerEntry(
            recordId: 'entry-$day',
            profileId: _profileId,
            sourceRowId: 'entry-$day',
            kind: HealthExportLedgerKind.entry,
            localDate: day,
            exportedAt: at(12),
          ),
        HealthExportLedgerEntry(
          recordId: 'period-$_profileId-2026-06-10',
          profileId: _profileId,
          sourceRowId: '2026-06-10/2026-06-11',
          kind: HealthExportLedgerKind.period,
          localDate: '2026-06-10',
          exportedAt: at(12),
        ),
      ]);

      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      expect(platform.deleteCalls, isEmpty);
      expect(platform.periodWrites, isEmpty,
          reason: 'the remembered interval is the episode there is');
      // The days were written by a build that recorded nothing about what
      // its records said (#1591): both are sent once — 06-10 as the
      // episode's first day, 06-11 not — and the summary each re-send
      // stamps keeps them quiet after that.
      expect(platform.flowWrites, hasLength(2));
      final flags = {
        for (final write in platform.flowWrites) write.date.iso: write.cycleStart,
      };
      expect(flags['2026-06-10'], isTrue);
      expect(flags['2026-06-11'], isFalse);
      await buildService().syncNow();
      expect(platform.flowWrites, hasLength(2));
    });

    // That build filed a row's records whether or not the write went
    // through, and held its cursor when one did not. So a row after the
    // floor was still owed.
    test('a ledger from an earlier build: a row that build still owed is '
        'sent, whatever its ledger says', () async {
      await settings.set(_bindingKey, _profileId);
      await settings.set(_cursorKey, '${at(10).millisecondsSinceEpoch}');
      dayEntries.entries = [
        _entry('2026-06-10', FlowLevel.medium, at(10)),
        _entry('2026-06-20', FlowLevel.medium, at(20)),
      ];
      await ledger.record([
        for (final day in ['2026-06-10', '2026-06-20'])
          HealthExportLedgerEntry(
            recordId: 'entry-$day',
            profileId: _profileId,
            sourceRowId: 'entry-$day',
            kind: HealthExportLedgerKind.entry,
            localDate: day,
            exportedAt: at(21),
          ),
      ]);

      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      // 06-20 was still owed and is sent; 06-10 was written by the
      // earlier build, which recorded nothing about what its record said,
      // so #1591 sends it once as well (as the episode's first day).
      expect(report.samplesWritten, 2);
      expect(
        platform.flowWrites.map((write) => write.recordId),
        contains('entry-2026-06-20'),
      );
      expect(
        ledger.rows
            .singleWhere((row) => row.recordId == 'entry-2026-06-20')
            .exportedAt,
        at(20),
      );
    });

    // The earlier build stamped the ledger with the device's clock at the
    // time of the pass. On a phone whose clock trails the server that is
    // before the time the storage layer gave the row.
    test('a ledger from an earlier build: a stamp older than the row sends '
        'the written row once (#1591), then no more', () async {
      await settings.set(_bindingKey, _profileId);
      await settings.set(_cursorKey, '${at(10).millisecondsSinceEpoch}');
      dayEntries.entries = [_entry('2026-06-10', FlowLevel.medium, at(10))];
      await ledger.record([
        HealthExportLedgerEntry(
          recordId: 'entry-2026-06-10',
          profileId: _profileId,
          sourceRowId: 'entry-2026-06-10',
          kind: HealthExportLedgerKind.entry,
          localDate: '2026-06-10',
          exportedAt: at(9),
        ),
      ]);

      await buildService().syncNow();
      // What the record said is unknown (#1591): sent once, with its
      // cycle-start flag, and the summary the re-send stamps keeps it
      // quiet from then on.
      expect(platform.flowWrites, hasLength(1));
      expect(platform.flowWrites.single.cycleStart, isTrue);
      await buildService().syncNow();
      await buildService().syncNow();

      expect(platform.flowWrites, hasLength(1));
    });

    test('a ledger from an earlier build: a no-flow day saved after the '
        'floor has its flow record asked for once more', () async {
      await settings.set(_bindingKey, _profileId);
      await settings.set(_cursorKey, '${at(10).millisecondsSinceEpoch}');
      // Written as a period day, then cleared; the earlier build's pass for
      // the cleared day had not gone through.
      dayEntries.entries = [_entry('2026-06-20', FlowLevel.none, at(20))];
      await ledger.record([
        HealthExportLedgerEntry(
          recordId: 'entry-2026-06-20',
          profileId: _profileId,
          sourceRowId: 'entry-2026-06-20',
          kind: HealthExportLedgerKind.entry,
          localDate: '2026-06-20',
          exportedAt: at(15),
        ),
      ]);

      await buildService().syncNow();

      expect(platform.deleteCalls, [
        ['entry-2026-06-20'],
      ]);
      expect(ledger.rows, isEmpty);
      await buildService().syncNow();
      expect(platform.deleteCalls, hasLength(1));
    });

    // A row at or before the floor that this device wrote stays looked
    // after. Its record can stop being wanted without the row changing.
    test('a spotting entry an earlier build wrote, from before the floor, is '
        'taken out when its day is given a flow', () async {
      await settings.set(_bindingKey, _profileId);
      await settings.set(_cursorKey, '${at(10).millisecondsSinceEpoch}');
      dayEntries.entries = [_entry('2026-06-08', FlowLevel.none, at(5))];
      observations.observations = [_spotting('2026-06-08', at(5))];
      await ledger.record([
        HealthExportLedgerEntry(
          recordId: 'spot-2026-06-08',
          profileId: _profileId,
          sourceRowId: 'spot-2026-06-08',
          kind: HealthExportLedgerKind.spotting,
          localDate: '2026-06-08',
          exportedAt: at(6),
        ),
      ]);
      final service = buildService();
      await service.syncNow();
      // What that build's record said is unknown (#1591, #1641): the old-type
      // record is cleared first in case it was written as the other type,
      // then the entry is sent as the marker it is now (no bleed day near it),
      // and the summary stamped keeps it quiet after.
      expect(platform.markerWrites, hasLength(1));
      expect(platform.deleteCalls, [
        ['spot-2026-06-08'],
      ]);

      dayEntries.entries = [_entry('2026-06-08', FlowLevel.medium, at(20))];
      clock = at(21);
      await service.syncNow();

      expect(platform.flowWrites.single.recordId, 'entry-2026-06-08');
      expect(platform.deleteCalls, [
        ['spot-2026-06-08'],
        ['spot-2026-06-08'],
      ]);
    });

    test('a spotting entry saved again while spotting is off waits, and is '
        'sent when spotting is back on', () async {
      await seedGranted(grant);
      dayEntries.entries = [_entry('2026-06-10', FlowLevel.none, at(10))];
      observations.observations = [_spotting('2026-06-10', at(10))];
      clock = at(11);
      final service = buildService();
      await service.syncNow();
      expect(platform.markerWrites, hasLength(1));

      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'menstrualFlow'};
      observations.observations = [_spotting('2026-06-10', at(20))];
      clock = at(21);
      expect((await service.syncNow()).blocked, isNull);
      expect(platform.markerWrites, hasLength(1));

      platform.grantedTypes = {'menstrualFlow', 'spotting'};
      clock = at(22);
      await service.syncNow();
      expect(platform.markerWrites, hasLength(2));
      expect(
        platform.markerWrites.last.recordVersionMs,
        at(20).millisecondsSinceEpoch,
      );
    });

    // A type's floor is compared with the times rows carry, so it is
    // stamped by the clock that stamps rows.
    test('a type\'s floor is stamped by the clock rows are stamped with',
        () async {
      await seedGranted(grant);
      // The phone runs five minutes ahead of the server.
      const ahead = Duration(minutes: 5);
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
        signedInUserId: () => _ownerId,
        now: () => clock,
        rowClock: () => clock.subtract(ahead),
      );
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'spotting'};
      clock = at(60);
      await service.syncNow();

      // Flow is switched on. The pass that finds it on runs before she can
      // save anything — the review's sequencing (issue #1604) — and stamps
      // flow's floor with the row clock, five minutes behind the device's.
      platform.permission = HealthPermissionStatus.granted;
      clock = at(61);
      await service.syncNow();

      // A day saved from here on is sent, although its row time trails the
      // device clock the observing pass ran on. Had the floor used the
      // device clock, the row would be under it and never sent.
      dayEntries.entries = [
        _entry('2026-06-10', FlowLevel.medium, at(62).subtract(ahead)),
      ];
      clock = at(63);

      expect((await service.syncNow()).samplesWritten, 1);
    });

    test('the earlier ledger is re-stamped once: the pass leaves a note that '
        'it has been, and unbinding clears it', () async {
      await seedGranted(grant);
      expect(await settings.get(SettingsKeys.healthSyncWriteState), isNull);
      final service = buildService();

      await service.syncNow();

      final stored = await settings.get(SettingsKeys.healthSyncWriteState);
      expect(HealthWritePassState.decode(stored), isNotNull);
      expect(HealthWritePassState.decode(stored)!.clearedThrough, grant);

      await service.onUnbound();
      expect(await settings.get(SettingsKeys.healthSyncWriteState), '');
    });

    // The ledger says what this binding wrote. A record written under an
    // earlier binding is in the store and in no ledger.
    group('a no-flow day the ledger knows nothing of', () {
      Future<LocalHealthFlowWriteService> boundAgainAfterWriting() async {
        await seedGranted(grant);
        dayEntries.entries = [_entry('2026-06-10', FlowLevel.medium, at(10))];
        clock = at(11);
        final service = buildService();
        await service.syncNow();
        expect(platform.flowWrites, hasLength(1));
        await service.onUnbound();
        expect(ledger.rows, isEmpty);
        await seedGranted(at(20));
        platform.deleteCalls.clear();
        return service;
      }

      test('cleared after binding again, it is asked to be deleted once',
          () async {
        final service = await boundAgainAfterWriting();
        dayEntries.entries = [_entry('2026-06-10', FlowLevel.none, at(30))];
        clock = at(31);

        final report = await service.syncNow();

        expect(report.blocked, isNull);
        expect(platform.deleteCalls, [
          ['entry-2026-06-10'],
        ]);
        await service.syncNow();
        await buildService().syncNow();
        expect(platform.deleteCalls, hasLength(1));
      });

      test('not while flow is switched off, and then once it is back on',
          () async {
        final service = await boundAgainAfterWriting();
        platform.permission = HealthPermissionStatus.writingSome;
        platform.grantedTypes = {'spotting'};
        dayEntries.entries = [_entry('2026-06-10', FlowLevel.none, at(30))];
        clock = at(31);

        expect((await service.syncNow()).blocked, isNull);
        expect(platform.deleteCalls, isEmpty);

        platform.permission = HealthPermissionStatus.granted;
        clock = at(32);
        await service.syncNow();
        expect(platform.deleteCalls, [
          ['entry-2026-06-10'],
        ]);
      });

      // The mark is one time for every no-flow day. A day whose known
      // record was deleted in the same pass must not carry it past a day
      // whose blind delete was refused.
      test('a refused delete is asked again even when a later day was '
          'cleared in the same pass', () async {
        await seedGranted(grant);
        final selective = _SelectiveDeletePlatform();
        platform = selective;
        dayEntries.entries = [_entry('2026-06-10', FlowLevel.medium, at(10))];
        clock = at(11);
        final service = buildService();
        await service.syncNow();

        // The written day is cleared, later than a second no-flow day the
        // ledger knows nothing of, whose delete the store refuses.
        selective.refused = {'entry-2026-06-12'};
        dayEntries.entries = [
          _entry('2026-06-10', FlowLevel.none, at(30)),
          _entry('2026-06-12', FlowLevel.none, at(20)),
        ];
        clock = at(31);
        final report = await service.syncNow();
        expect(report.blocked, isA<HealthPlatformFailed>());
        expect(report.samplesReconciled, 1);

        selective.refused = {};
        selective.deleteCalls.clear();
        expect((await service.syncNow()).blocked, isNull);
        // The first day rides along once more, which removes nothing:
        // the one mark could not move past the day that was refused.
        expect(selective.deleteCalls.single, contains('entry-2026-06-12'));
        await service.syncNow();
        expect(selective.deleteCalls, hasLength(1));
      });

      test('a delete the store refused is asked again', () async {
        final service = await boundAgainAfterWriting();
        dayEntries.entries = [_entry('2026-06-10', FlowLevel.none, at(30))];
        clock = at(31);
        platform.deleteResult = const HealthPlatformResult.failed('no');

        expect((await service.syncNow()).blocked, isA<HealthPlatformFailed>());

        platform.deleteResult = const HealthPlatformAllowed();
        expect((await service.syncNow()).blocked, isNull);
        expect(platform.deleteCalls, hasLength(2));
        await service.syncNow();
        expect(platform.deleteCalls, hasLength(2));
      });
    });

    test('a temperature whose type is off is not asked to be deleted, and '
        'is once the type is back on', () async {
      await seedGranted(grant);
      dayEntries.entries = [_entry('2026-06-10', FlowLevel.medium, at(10))];
      observations.observations = [_bbt('2026-06-10', 36.6, at(10))];
      clock = at(11);
      final service = buildService();
      expect((await service.syncNow()).basalBodyTemperatureSamplesWritten, 1);

      // The type is switched off, and she clears the reading.
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'menstrualFlow', 'spotting'};
      observations.observations = [];
      clock = at(21);
      expect((await service.syncNow()).blocked, isNull);
      expect(platform.deleteCalls, isEmpty);

      platform.permission = HealthPermissionStatus.granted;
      clock = at(22);
      await service.syncNow();
      expect(platform.deleteCalls, [
        [healthBbtRecordId('obs-bbt-2026-06-10')],
      ]);
    });

    // Issue #1583: the store says which types it passed over, and it says
    // so for any type that is off, whichever records were asked for.
    group('a delete the store answers "partial" to', () {
      test('with another type passed over, the record is gone: forgotten, '
          'counted, and nothing is reported', () async {
        await seedGranted(grant);
        dayEntries.entries = [_entry('2026-06-10', FlowLevel.medium, at(10))];
        clock = at(11);
        final service = buildService();
        await service.syncNow();

        // Temperature is switched off for lunarlog. She clears the day.
        platform.deleteResult =
            const HealthPlatformResult.partial({'basalBodyTemperature'});
        dayEntries.entries = [_entry('2026-06-10', FlowLevel.none, at(20))];
        clock = at(21);
        final report = await service.syncNow();

        expect(report.blocked, isNull);
        expect(report.samplesReconciled, 1);
        expect(ledger.rows, isEmpty,
            reason: 'the flow record and the period record are both gone');
        final asked = platform.deleteCalls.length;
        await service.syncNow();
        expect(platform.deleteCalls, hasLength(asked));
      });

      test('a no-flow day the ledger knows nothing of is cleared all the '
          'same when only another type was passed over', () async {
        await seedGranted(grant);
        platform.deleteResult =
            const HealthPlatformResult.partial({'cervicalMucus'});
        dayEntries.entries = [_entry('2026-06-10', FlowLevel.none, at(10))];
        clock = at(11);
        final service = buildService();

        expect((await service.syncNow()).blocked, isNull);
        await service.syncNow();
        expect(platform.deleteCalls, hasLength(1));
      });

      // When a spotting record's ledger row has no summary (written by an
      // earlier build before Issue #1591), what type was written is unknown,
      // so either type being passed over keeps it remembered.
      test('a spotting entry\'s record with no summary stays remembered '
          'when either of its two types was passed over', () async {
        for (final skipped in ['menstrualFlow', 'spotting']) {
          ledger = FakeHealthExportLedger();
          settings = FakeSettingsStore();
          platform = _FakePlatform();
          await seedGranted(grant);
          await ledger.record([
            HealthExportLedgerEntry(
              profileId: _profileId,
              recordId: 'spot-obs-1',
              sourceRowId: 'obs-1',
              kind: HealthExportLedgerKind.spotting,
              localDate: '2026-06-10',
              exportedAt: at(10),
              payloadSummary: null,
            ),
          ]);
          // The observation is gone, so the spotting record is an orphan.
          observations.observations = [];
          dayEntries.entries = [];
          platform.deleteResult = HealthPlatformResult.partial({skipped});
          clock = at(21);
          final service = buildService();
          final report = await service.syncNow();

          expect(report.blocked, isA<HealthPlatformPartial>(),
              reason: skipped);
          expect(
            ledger.rows.map((row) => row.recordId),
            contains('spot-obs-1'),
            reason: skipped,
          );
        }
      });

      // Issue #1644: with a known payload summary, only a skip of the type
      // actually written counts as passed over; skipping the other type lets
      // the delete through and forgets the record.
      test('a spotting marker with menstrualFlow skipped is deleted and '
          'forgotten, but stays remembered when spotting was skipped (issue #1644)',
          () async {
        // 1. menstrualFlow skipped: delete succeeds and record is forgotten.
        ledger = FakeHealthExportLedger();
        settings = FakeSettingsStore();
        platform = _FakePlatform();
        await seedGranted(grant);
        observations.observations = [_spotting('2026-06-10', at(10))];
        clock = at(11);
        var service = buildService();
        await service.syncNow();
        expect(platform.markerWrites, hasLength(1));
        expect(ledger.rows.single.payloadSummary, 'marker');

        platform.deleteResult =
            const HealthPlatformResult.partial({'menstrualFlow'});
        observations.observations = [];
        clock = at(21);
        var report = await service.syncNow();

        expect(report.blocked, isNull);
        expect(report.samplesReconciled, 1);
        expect(ledger.rows, isEmpty);
        expect(platform.deleteCalls, hasLength(1));

        // Subsequent pass sends nothing.
        await service.syncNow();
        expect(platform.deleteCalls, hasLength(1));

        // 2. spotting skipped: record stays remembered and failure is reported.
        ledger = FakeHealthExportLedger();
        settings = FakeSettingsStore();
        platform = _FakePlatform();
        await seedGranted(grant);
        observations.observations = [_spotting('2026-06-10', at(10))];
        clock = at(11);
        service = buildService();
        await service.syncNow();
        expect(platform.markerWrites, hasLength(1));

        platform.deleteResult =
            const HealthPlatformResult.partial({'spotting'});
        observations.observations = [];
        clock = at(21);
        report = await service.syncNow();

        expect(report.blocked, isA<HealthPlatformPartial>());
        expect(
          ledger.rows.map((row) => row.recordId),
          contains('spot-2026-06-10'),
        );
      });

      test('a spotting flow sample with spotting skipped is deleted and '
          'forgotten, but stays remembered when menstrualFlow was skipped',
          () async {
        // 1. spotting skipped: flow sample delete succeeds and is forgotten.
        ledger = FakeHealthExportLedger();
        settings = FakeSettingsStore();
        platform = _FakePlatform();
        await seedGranted(grant);
        dayEntries.entries = [
          _entry('2026-06-09', FlowLevel.medium, at(10)),
          _entry('2026-06-11', FlowLevel.medium, at(10)),
        ];
        observations.observations = [_spotting('2026-06-10', at(10))];
        clock = at(11);
        var service = buildService();
        await service.syncNow();
        expect(
          ledger.rows
              .firstWhere((r) => r.recordId == 'spot-2026-06-10')
              .payloadSummary,
          startsWith('flow:'),
        );

        platform.deleteResult =
            const HealthPlatformResult.partial({'spotting'});
        observations.observations = [];
        clock = at(21);
        var report = await service.syncNow();

        expect(report.blocked, isNull);
        expect(
          ledger.rows.map((r) => r.recordId),
          isNot(contains('spot-2026-06-10')),
        );

        // 2. menstrualFlow skipped: flow sample stays remembered.
        ledger = FakeHealthExportLedger();
        settings = FakeSettingsStore();
        platform = _FakePlatform();
        await seedGranted(grant);
        dayEntries.entries = [
          _entry('2026-06-09', FlowLevel.medium, at(10)),
          _entry('2026-06-11', FlowLevel.medium, at(10)),
        ];
        observations.observations = [_spotting('2026-06-10', at(10))];
        clock = at(11);
        service = buildService();
        await service.syncNow();

        platform.deleteResult =
            const HealthPlatformResult.partial({'menstrualFlow'});
        observations.observations = [];
        clock = at(21);
        report = await service.syncNow();

        expect(report.blocked, isA<HealthPlatformPartial>());
        expect(
          ledger.rows.map((r) => r.recordId),
          contains('spot-2026-06-10'),
        );
      });
    });

    // Never written back, whatever the ledger says: a row lunarlog wrote
    // and the import later took over has a health store as its source.
    test('a row that came from the health store is left alone even when the '
        'ledger knows it', () async {
      await seedGranted(grant);
      dayEntries.entries = [_entry('2026-06-10', FlowLevel.medium, at(10))];
      clock = at(11);
      final service = buildService();
      await service.syncNow();
      expect(platform.flowWrites, hasLength(1));
      final periodWrites = platform.periodWrites.length;

      dayEntries.entries = [
        _entry('2026-06-10', FlowLevel.none, at(20),
            source: DayEntrySource.healthConnect),
      ];
      clock = at(21);
      await service.syncNow();

      expect(platform.flowWrites, hasLength(1));
      expect(platform.periodWrites, hasLength(periodWrites));
      expect(
        platform.deleteCalls.expand((ids) => ids),
        isNot(contains('entry-2026-06-10')),
      );
      expect(
        ledger.rows.map((row) => row.recordId),
        contains('entry-2026-06-10'),
      );
    });

    // Issue #1589. The tombstone path deletes a deleted row's records
    // while the deleted row is still on the phone, and keeps in the ledger
    // those whose type was off. A deleted row is swept two days after it
    // syncs. With the type switched back on after that, nothing looked at
    // the ledger row again, and the record stayed in the store for good.
    group('issue #1589: the records of a row that is gone', () {
      const mucus = 'cervical-mucus-entry-2026-06-10';
      const everyTypeButMucus = {
        'menstrualFlow',
        'spotting',
        'ovulationTest',
        'basalBodyTemperature',
      };

      test('a day deleted while one of its records\' types is off: that '
          'record stays remembered, and is deleted once the type is back on',
          () async {
        await seedGranted(grant);
        dayEntries.entries = [
          _entry('2026-06-10', FlowLevel.medium, at(60),
              tags: const ['egg_white']),
        ];
        final service = buildService();
        await service.syncNow();
        expect(ledger.rows.map((row) => row.recordId), contains(mucus));

        // Cervical mucus is switched off, and she deletes the day.
        platform
          ..permission = HealthPermissionStatus.writingSome
          ..grantedTypes = everyTypeButMucus;
        dayEntries.entries = [];
        await service.syncNow();

        expect(
          platform.deleteCalls.expand((call) => call),
          isNot(contains(mucus)),
          reason: 'a delete sent now would pass the record over and read '
              'as done',
        );
        expect(platform.deleteCalls.expand((call) => call),
            contains('entry-2026-06-10'));
        expect(ledger.rows.map((row) => row.recordId), [mucus]);

        // Days later, with the deleted row long swept, the type is back.
        platform.permission = HealthPermissionStatus.granted;
        platform.deleteCalls.clear();
        final back = await service.syncNow();

        expect(back.blocked, isNull);
        expect(platform.deleteCalls, [
          [mucus],
        ]);
        expect(ledger.rows, isEmpty);

        // And that is the end of it.
        await service.syncNow();
        expect(platform.deleteCalls, hasLength(1));
      });

      test('a spotting entry that is gone has its record deleted', () async {
        await seedGranted(grant);
        observations.observations = [_spotting('2026-06-12', at(60))];
        final service = buildService();
        await service.syncNow();
        expect(platform.markerWrites.single.recordId, 'spot-2026-06-12');

        observations.observations = [];
        final report = await service.syncNow();

        expect(report.blocked, isNull);
        expect(platform.deleteCalls, [
          ['spot-2026-06-12'],
        ]);
        expect(ledger.rows, isEmpty);
      });

      test('the records of a day that is still there are left alone when '
          'another day goes', () async {
        await seedGranted(grant);
        dayEntries.entries = [
          _entry('2026-06-10', FlowLevel.medium, at(60),
              tags: const ['egg_white']),
          _entry('2026-06-11', FlowLevel.light, at(61)),
        ];
        final service = buildService();
        await service.syncNow();

        // One day goes. Nothing about the other changed, and its records
        // must not be taken for a gone row's.
        dayEntries.entries = [dayEntries.entries.first];
        await service.syncNow();

        expect(platform.deleteCalls.expand((call) => call),
            isNot(contains('entry-2026-06-10')));
        expect(platform.deleteCalls.expand((call) => call),
            isNot(contains(mucus)));
        expect(platform.deleteCalls.expand((call) => call),
            contains('entry-2026-06-11'));
      });

      test('a delete the store refuses leaves the record remembered, and it '
          'is asked for again', () async {
        await seedGranted(grant);
        dayEntries.entries = [_entry('2026-06-10', FlowLevel.none, at(60),
            tags: const ['egg_white'])];
        final service = buildService();
        await service.syncNow();
        expect(ledger.rows.map((row) => row.recordId), [mucus]);

        dayEntries.entries = [];
        platform.deleteResult = const HealthPlatformPermissionDenied();
        final refused = await service.syncNow();
        expect(refused.blocked, isA<HealthPlatformPermissionDenied>());
        expect(ledger.rows.map((row) => row.recordId), [mucus]);

        platform.deleteResult = const HealthPlatformAllowed();
        final retried = await service.syncNow();
        expect(retried.blocked, isNull);
        expect(ledger.rows, isEmpty);
      });

      // Undo saves the same row back: the same id, a later time.
      test('a day deleted, undone and deleted again: its record goes, is '
          'written again, and goes again', () async {
        const flow = 'entry-2026-06-10';
        await seedGranted(grant);
        dayEntries.entries = [_entry('2026-06-10', FlowLevel.medium, at(60))];
        final service = buildService();
        await service.syncNow();
        expect(platform.flowWrites.map((write) => write.recordId), [flow]);

        dayEntries.entries = [];
        await service.syncNow();
        expect(platform.deleteCalls.expand((call) => call), contains(flow));
        expect(ledger.rows, isEmpty);

        dayEntries.entries = [_entry('2026-06-10', FlowLevel.medium, at(70))];
        await service.syncNow();
        expect(
          platform.flowWrites.map((write) => write.recordId),
          [flow, flow],
        );
        expect(ledger.rows.map((row) => row.recordId), contains(flow));

        // The tombstone path relays a row's deletion once a session. The
        // second time, this is what removes the record.
        platform.deleteCalls.clear();
        dayEntries.entries = [];
        await service.syncNow();
        expect(platform.deleteCalls.expand((call) => call), contains(flow));
        expect(ledger.rows, isEmpty);
      });

      // A spotting entry's record is one of two types. A row written by
      // this build says which it was (#1591) and only that type's switch
      // holds its removal back; a row written before the summary existed
      // says nothing, so with either type off a delete may pass it over
      // and it waits.
      for (final off in const ['spotting', 'menstrualFlow']) {
        test('a pre-#1591 spotting entry that is gone while $off is off '
            'keeps its record remembered until the type is back', () async {
          const marker = 'spot-2026-06-12';
          await seedGranted(grant);
          observations.observations = [_spotting('2026-06-12', at(60))];
          await buildService().syncNow();
          expect(ledger.rows.map((row) => row.recordId), [marker]);
          // Wind the ledger row back to what a build before #1591 wrote:
          // no summary of which type the record was. A fresh service
          // reads it, the way a relaunched process would.
          await ledger.record([
            HealthExportLedgerEntry(
              recordId: marker,
              profileId: _profileId,
              sourceRowId: marker,
              kind: HealthExportLedgerKind.spotting,
              localDate: '2026-06-12',
              exportedAt: at(60),
            ),
          ]);

          platform
            ..permission = HealthPermissionStatus.writingSome
            ..grantedTypes = {...everyTypeButMucus, 'cervicalMucus'}
              .difference({off});
          observations.observations = [];
          await buildService().syncNow();
          expect(
            platform.deleteCalls.expand((call) => call),
            isNot(contains(marker)),
          );
          expect(ledger.rows.map((row) => row.recordId), [marker]);

          platform.permission = HealthPermissionStatus.granted;
          final back = await buildService().syncNow();
          expect(back.blocked, isNull);
          expect(platform.deleteCalls.expand((call) => call), [marker]);
          expect(ledger.rows, isEmpty);
        });
      }

      // The summary says which type the record was written as, so the
      // other type's switch no longer holds its removal back (#1591).
      test('a spotting entry written as a marker whose row is gone is '
          'deleted with spotting on, even while menstrualFlow is off',
          () async {
        const marker = 'spot-2026-06-12';
        await seedGranted(grant);
        observations.observations = [_spotting('2026-06-12', at(60))];
        final service = buildService();
        await service.syncNow();
        expect(ledger.rows.single.payloadSummary, 'marker');

        platform
          ..permission = HealthPermissionStatus.writingSome
          ..grantedTypes = {...everyTypeButMucus, 'cervicalMucus'}
            .difference({'menstrualFlow'});
        observations.observations = [];
        final report = await service.syncNow();

        expect(report.blocked, isNull);
        expect(platform.deleteCalls.expand((call) => call), [marker]);
        expect(ledger.rows, isEmpty);
      });

      // Another device's row for the date wins a merge: this phone's row
      // is gone, and a row with another id is live for the same day.
      test('a day whose row another device\'s replaced: the new row\'s '
          'record is written and the old row\'s deleted', () async {
        await seedGranted(grant);
        dayEntries.entries = [_entry('2026-06-10', FlowLevel.medium, at(60))];
        final service = buildService();
        await service.syncNow();

        dayEntries.entries = [
          DayEntry(
            id: 'entry-from-her-tablet',
            profileId: _profileId,
            localDate: LocalDate.fromIso('2026-06-10'),
            tz: _tz,
            flow: FlowLevel.heavy,
            updatedAt: at(70),
          ),
        ];
        final report = await service.syncNow();

        expect(report.blocked, isNull);
        expect(platform.flowWrites.last.recordId, 'entry-from-her-tablet');
        expect(
          platform.deleteCalls.expand((call) => call),
          contains('entry-2026-06-10'),
        );
        expect(
          [
            for (final row in ledger.rows)
              if (row.kind == HealthExportLedgerKind.entry) row.recordId,
          ],
          ['entry-from-her-tablet'],
        );
      });
    });

    // Issue #1605. A pass runs on every save and every return to the
    // app. Storing a state that has not changed would be a settings write,
    // and a notification to whatever watches the key, each time.
    test('a pass that leaves the state as it was does not store it again',
        () async {
      await seedGranted(grant);
      dayEntries.entries = [_entry('2026-06-10', FlowLevel.medium, at(60))];
      final stored = <String?>[];
      final watching = settings
          .watch(SettingsKeys.healthSyncWriteState)
          .listen(stored.add);
      addTearDown(watching.cancel);
      final service = buildService();

      await service.syncNow();
      await service.syncNow();
      await service.syncNow();
      await pumpEventQueue();

      // What was there to begin with (nothing), then the first pass's.
      expect(stored, hasLength(2));
      expect(stored.first, isNull);
      expect(HealthWritePassState.decode(stored.last), isNotNull);
    });

    // Two passes side by side would each decide from the ledger before the
    // other had written to it.
    group('one pass at a time', () {
      late _GatedPlatform gated;

      setUp(() async {
        await seedGranted(grant);
        gated = _GatedPlatform();
        platform = gated;
        dayEntries.entries = [_entry('2026-06-10', FlowLevel.medium, at(10))];
      });

      test('requests that arrive during a pass share the next one, and '
          'nothing is sent twice', () async {
        final service = buildService();

        final first = service.syncNow();
        final second = service.syncNow();
        final third = service.syncNow();
        expect(identical(second, third), isTrue);
        expect(identical(first, second), isFalse);
        await pumpEventQueue();
        expect(gated.flowWrites, hasLength(1), reason: 'only one has begun');

        gated.release();
        expect((await first).samplesWritten, 1);
        expect((await second).samplesWritten, 0);
        expect(gated.flowWrites, hasLength(1));
      });

      test('the next pass sees what was saved while the first ran', () async {
        final service = buildService();
        final first = service.syncNow();
        await pumpEventQueue();

        dayEntries.entries = [
          ...dayEntries.entries,
          _entry('2026-06-20', FlowLevel.light, at(20)),
        ];
        final second = service.syncNow();
        gated.release();

        expect((await first).samplesWritten, 1);
        expect((await second).samplesWritten, 1);
        expect(gated.flowWrites.last.recordId, 'entry-2026-06-20');

        // And with nothing running, a request starts its own pass.
        final third = service.syncNow();
        expect(identical(third, second), isFalse);
        expect((await third).samplesWritten, 0);
      });

      test('a pass that throws does not hold up the one behind it', () async {
        final service = buildService();
        dayEntries.failNextList = StateError('storage');

        final first = service.syncNow();
        final second = service.syncNow();
        gated.release();

        await expectLater(first, throwsStateError);
        expect((await second).samplesWritten, 1);
        expect((await service.syncNow()).samplesWritten, 0);
      });
    });

    test(
        'with menstrualFlow off, a pass leaves no ledger row for the day, and turning it on later writes no period record for that episode (issue #1585)',
        () async {
      await seedGranted(grant);
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'spotting'};
      final t1 = grant.add(const Duration(hours: 1));
      final t5 = grant.add(const Duration(hours: 5));
      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.medium, t1),
        _entry('2026-06-02', FlowLevel.heavy, grant.add(const Duration(hours: 2))),
        _entry('2026-06-03', FlowLevel.heavy, grant.add(const Duration(hours: 3))),
        _entry('2026-06-04', FlowLevel.medium, grant.add(const Duration(hours: 4))),
        _entry('2026-06-05', FlowLevel.light, t5),
      ];
      clock = t5.add(const Duration(minutes: 1));

      final report1 = await buildService().syncNow();

      expect(report1.blocked, isNull);
      expect(report1.samplesWritten, 0);
      expect(report1.periodRecordsWritten, 0);
      expect(platform.flowWrites, isEmpty);
      expect(platform.periodWrites, isEmpty);
      expect(await ledger.readForProfile(_profileId), isEmpty);
      // Since #1581 the floor does not move. What keeps these days out is
      // menstrualFlow's own floor, which that pass moved past them.
      expect(await settings.get(_cursorKey),
          '${grant.millisecondsSinceEpoch}');
      final flowFloor = HealthWritePassState.decode(
        await settings.get(SettingsKeys.healthSyncWriteState),
      )!.typeFloors['menstrualFlow'];
      expect(flowFloor, clock);

      // Turn menstrualFlow on. The days are behind its floor, and neither
      // memory nor ledger recorded them as exported.
      platform.grantedTypes = {'menstrualFlow', 'spotting'};
      clock = t5.add(const Duration(minutes: 2));
      final report2 = await buildService().syncNow();

      expect(report2.blocked, isNull);
      expect(report2.samplesWritten, 0);
      expect(report2.periodRecordsWritten, 0);
      expect(platform.periodWrites, isEmpty);

      // Verify a fresh relaunch also sees no ledger rows and writes no period.
      final report3 = await buildService().syncNow();
      expect(report3.periodRecordsWritten, 0);
      expect(platform.periodWrites, isEmpty);
    });

    test(
        'when BBT is off, no ledger row is saved for BBT observations (issue #1585)',
        () async {
      await seedGranted(grant);
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'menstrualFlow'};
      final t1 = grant.add(const Duration(hours: 1));
      observations.observations = [
        _bbt('2026-06-03', 36.6, t1),
      ];

      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      expect(report.basalBodyTemperatureSamplesWritten, 0);
      final rows = await ledger.readForProfile(_profileId);
      expect(rows.where((r) => r.kind == HealthExportLedgerKind.bbt), isEmpty);

      // Clearing the observation does not attempt to delete the unexported record.
      observations.observations = [];
      await buildService().syncNow();
      expect(platform.deleteCalls, isEmpty);
    });

    test(
        'when day has flow and symptoms, but flow is off, only symptom is saved to ledger and turning flow on writes no period (issue #1585)',
        () async {
      await seedGranted(grant);
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'symptoms'};
      final t1 = grant.add(const Duration(hours: 1));
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, t1, tags: const ['cramps']),
      ];
      clock = t1.add(const Duration(minutes: 1));

      final report1 = await buildService().syncNow();

      expect(report1.blocked, isNull);
      expect(report1.samplesWritten, 0);
      expect(report1.symptomSamplesWritten, 1);
      expect(report1.periodRecordsWritten, 0);
      final rows = await ledger.readForProfile(_profileId);
      expect(rows, hasLength(1));
      expect(rows.single.recordId, startsWith('symptom-'));

      // Turning flow on does not generate a period record for the day whose flow was never exported.
      platform.grantedTypes = {'menstrualFlow', 'symptoms'};
      final report2 = await buildService().syncNow();
      expect(report2.periodRecordsWritten, 0);
      expect(platform.periodWrites, isEmpty);
    });

    // Issue #1584, and since #1581 the reason it matters most: a failed
    // query for which types are on says nothing about them. Read as "none
    // are on", it would move every type's floor to the present, and the
    // day below would never be sent. So each of these checks what the
    // next pass does, with the query working again. (They used to check
    // that a cursor had not moved, which it no longer can.)
    for (final (what, error, answer) in <(String, Object, Type)>[
      (
        'an error',
        Exception('health connect failure'),
        HealthPlatformFailed,
      ),
      (
        'a store that is not there',
        PlatformException(
          code: 'unavailable',
          message: 'Health Connect unavailable',
        ),
        HealthPlatformUnavailable,
      ),
      (
        'no native half',
        MissingPluginException(),
        HealthPlatformUnavailable,
      ),
    ]) {
      test('a query for which types are on that ends in $what stops the '
          'pass, moves no floor, and the next pass sends the day (issue '
          '#1584)', () async {
        await seedGranted(grant);
        platform.permission = HealthPermissionStatus.writingSome;
        platform.grantedWriteTypesError = error;
        final t1 = grant.add(const Duration(hours: 1));
        dayEntries.entries = [
          _entry('2026-06-02', FlowLevel.medium, t1),
        ];
        // The pass runs after the day was saved, as it always does. A
        // floor moved by this pass would stand after the day.
        clock = t1.add(const Duration(minutes: 1));
        final service = buildService();

        final report = await service.syncNow();

        expect(report.blocked.runtimeType, answer);
        expect(report.samplesWritten, 0);
        expect(platform.flowWrites, isEmpty);
        expect(await settings.get(SettingsKeys.healthSyncWriteState), isNull);

        platform
          ..grantedWriteTypesError = null
          ..grantedTypes = {'menstrualFlow'};
        clock = t1.add(const Duration(minutes: 2));
        final next = await service.syncNow();
        expect(next.blocked, isNull);
        expect(next.samplesWritten, 1);
        expect(platform.flowWrites.single.recordId, 'entry-2026-06-02');
      });
    }
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

  // Issue #1591: what a record says is decided partly by *other* days —
  // the cycle-start flag by which day starts the period, a spotting
  // record's type by whether its day falls inside one — so the ledger
  // remembers a summary of what each written record said, and a record
  // whose summary differs from what its row now produces is sent again
  // at a raised version, without its own row ever changing.
  group('issue #1591: another day changing what a record should say', () {
    final grant = DateTime.utc(2026, 6, 1, 12);
    DateTime at(int minutes) => grant.add(Duration(minutes: minutes));

    test('logging the day before a written period day moves the '
        'cycle-start flag to it, and the old first day is corrected',
        () async {
      await seedGranted(grant);
      // She logs Tuesday.
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
      ];
      final service = buildService();
      await service.syncNow();
      expect(platform.flowWrites.single.cycleStart, isTrue);
      final tuesdayFirstWrite = platform.flowWrites.single;
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'entry-2026-06-02')
            .payloadSummary,
        'flow:heavy:1',
      );

      // The next day she adds Monday, which she forgot. Monday is the
      // period's first day now, and Tuesday's own row has not changed.
      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.light,
            grant.add(const Duration(hours: 2))),
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(report.samplesWritten, 2);
      final monday =
          platform.flowWrites.singleWhere((w) => w.date.iso == '2026-06-01');
      final tuesday = platform.flowWrites
          .where((w) => w.date.iso == '2026-06-02')
          .last;
      expect(monday.cycleStart, isTrue);
      expect(tuesday.cycleStart, isFalse);
      // The correction carries a version above the one the store already
      // holds for Tuesday, or it would keep the old copy.
      expect(tuesday.recordVersionMs,
          greaterThan(tuesdayFirstWrite.recordVersionMs));
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'entry-2026-06-02')
            .payloadSummary,
        'flow:heavy:0',
      );

      // And that is the end of it: the third pass sends nothing.
      await service.syncNow();
      expect(platform.flowWrites, hasLength(3));
    });

    test('deleting the day before moves the cycle-start flag back, and '
        'its record goes with the day', () async {
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.light,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 2))),
      ];
      final service = buildService();
      await service.syncNow();
      expect(
        platform.flowWrites.singleWhere((w) => w.date.iso == '2026-06-01')
            .cycleStart,
        isTrue,
      );
      final writesBefore = platform.flowWrites.length;

      // She deletes Monday. Tuesday's row has not changed, and it is the
      // period's first day again.
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 2))),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      final tuesday = platform.flowWrites.last;
      expect(tuesday.date.iso, '2026-06-02');
      expect(tuesday.cycleStart, isTrue);
      expect(tuesday.recordVersionMs,
          greaterThan(platform.flowWrites.first.recordVersionMs));
      expect(
        platform.deleteCalls.expand((call) => call),
        contains('entry-2026-06-01'),
        reason: 'the deleted day\'s record is taken out',
      );
      final entryRows = ledger.rows
          .where((row) => row.kind == HealthExportLedgerKind.entry)
          .toList();
      expect(entryRows.map((row) => row.recordId), ['entry-2026-06-02']);
      expect(entryRows.single.payloadSummary, 'flow:heavy:1');

      await service.syncNow();
      expect(platform.flowWrites, hasLength(writesBefore + 1));
    });

    test('a spotting entry whose day moves into a period is re-sent as a '
        'light flow sample, and the marker is taken out first', () async {
      await seedGranted(grant);
      // Spotting outside any period: an intermenstrual marker.
      observations.observations = [_spotting('2026-06-10', at(5))];
      final service = buildService();
      await service.syncNow();
      expect(platform.markerWrites.single.recordId, 'spot-2026-06-10');
      final markerWrite = platform.markerWrites.single;
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        'marker',
      );

      // Bleed days appear around it; the spotting day is inside the
      // period now. Its own row has not changed.
      dayEntries.entries = [
        _entry('2026-06-09', FlowLevel.heavy, at(6)),
        _entry('2026-06-11', FlowLevel.medium, at(7)),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(platform.markerWrites, hasLength(1),
          reason: 'no second marker is written');
      // Both types share the one record id, so the old one goes before
      // the new one is written — a delete after the write would take the
      // new record out with the old.
      expect(platform.deleteCalls, [
        ['spot-2026-06-10'],
      ]);
      final inside = platform.flowWrites.last;
      expect(inside.recordId, 'spot-2026-06-10');
      expect(inside.flow, HealthFlowValue.light);
      expect(inside.cycleStart, isFalse);
      expect(inside.recordVersionMs,
          greaterThan(markerWrite.recordVersionMs));
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        'flow:light:0',
      );

      final writesAfterSwap = platform.flowWrites.length;
      await service.syncNow();
      expect(platform.flowWrites, hasLength(writesAfterSwap));
      expect(platform.deleteCalls, hasLength(1));
    });

    test('a spotting entry whose day stops being in a period is re-sent '
        'as a marker, and the light flow sample is taken out first',
        () async {
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-09', FlowLevel.heavy, at(5)),
        _entry('2026-06-11', FlowLevel.medium, at(6)),
      ];
      observations.observations = [_spotting('2026-06-10', at(7))];
      final service = buildService();
      await service.syncNow();
      final inside = platform.flowWrites
          .singleWhere((write) => write.recordId == 'spot-2026-06-10');
      expect(inside.flow, HealthFlowValue.light);
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        'flow:light:0',
      );

      // The period's first day goes. The spotting day is outside any
      // period now; its own row has not changed.
      dayEntries.entries = [
        _entry('2026-06-11', FlowLevel.medium, at(6)),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      // The swap-delete is the pass's first delete; taking the removed
      // day's and the old episode's records out follows it.
      expect(platform.deleteCalls.first, ['spot-2026-06-10']);
      final marker = platform.markerWrites.single;
      expect(marker.recordId, 'spot-2026-06-10');
      expect(marker.recordVersionMs, greaterThan(inside.recordVersionMs));
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        'marker',
      );

      final deletesAfterSwap = platform.deleteCalls.length;
      await service.syncNow();
      expect(platform.markerWrites, hasLength(1));
      expect(platform.deleteCalls, hasLength(deletesAfterSwap));
    });

    test('a summary-only re-send waits when the replaced type is switched '
        'off, and goes once it is back', () async {
      await seedGranted(grant);
      observations.observations = [_spotting('2026-06-10', at(5))];
      final service = buildService();
      await service.syncNow();
      expect(platform.markerWrites, hasLength(1));

      // Spotting is switched off when the spotting day moves into a
      // period. The marker cannot be taken out while its type is off —
      // the delete would be passed over and the old record would stay
      // beside the new one for good — so the swap waits.
      platform
        ..permission = HealthPermissionStatus.writingSome
        ..grantedTypes = {'menstrualFlow'};
      dayEntries.entries = [
        _entry('2026-06-09', FlowLevel.heavy, at(6)),
        _entry('2026-06-11', FlowLevel.medium, at(7)),
      ];
      clock = at(8);
      final waiting = await service.syncNow();
      expect(waiting.blocked, isNull);
      expect(platform.markerWrites, hasLength(1));
      expect(
        platform.flowWrites.map((write) => write.recordId),
        ['entry-2026-06-09', 'entry-2026-06-11'],
        reason: 'the two bleed days go out; the spotting swap waits',
      );
      expect(platform.deleteCalls, isEmpty);
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        'marker',
        reason: 'still what the store holds',
      );

      // Spotting is back on: the marker goes out first, then the light
      // flow sample is written.
      platform
        ..permission = HealthPermissionStatus.granted
        ..grantedTypes = const {};
      clock = at(9);
      final swapped = await service.syncNow();
      expect(swapped.blocked, isNull);
      expect(platform.deleteCalls, [
        ['spot-2026-06-10'],
      ]);
      expect(platform.flowWrites.last.recordId, 'spot-2026-06-10');
      expect(platform.flowWrites.last.flow, HealthFlowValue.light);
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        'flow:light:0',
      );
    });

    test('a failed write after a successful swap-delete is retried '
        'on the next pass', () async {
      await seedGranted(grant);
      observations.observations = [_spotting('2026-06-10', at(5))];
      final service = buildService();
      await service.syncNow();
      expect(platform.markerWrites, hasLength(1));

      dayEntries.entries = [
        _entry('2026-06-09', FlowLevel.heavy, at(6)),
        _entry('2026-06-11', FlowLevel.medium, at(7)),
      ];
      // The swap-delete goes through; the light sample's write is
      // refused. The deleted marker is forgotten from the ledger
      // (issue #1642), so the next pass sees it as unwritten and writes
      // the light sample without needing a redundant delete.
      platform.writeResults = [
        const HealthPlatformAllowed(), // 06-09 heavy
        const HealthPlatformAllowed(), // 06-11 medium
        const HealthPlatformResult.failed('no'),
      ];
      final refused = await service.syncNow();
      expect(refused.blocked, isA<HealthPlatformFailed>());
      expect(refused.samplesReconciled, 1);
      expect(platform.deleteCalls, [
        ['spot-2026-06-10'],
      ]);
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        flowPayloadSummaryGone,
      );

      platform.writeResults = [];
      final retried = await service.syncNow();
      expect(retried.blocked, isNull);
      expect(platform.deleteCalls, hasLength(1));
      expect(platform.flowWrites.last.recordId, 'spot-2026-06-10');
      expect(platform.flowWrites.last.flow, HealthFlowValue.light);
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        'flow:light:0',
      );
    });

    test('a spotting type swap whose delete succeeds and write fails writes '
        'the marker if the day reverts before the retry (issue #1642)',
        () async {
      await seedGranted(grant);
      observations.observations = [_spotting('2026-06-10', at(5))];
      final service = buildService();
      await service.syncNow();
      expect(platform.markerWrites, hasLength(1));

      dayEntries.entries = [
        _entry('2026-06-09', FlowLevel.heavy, at(6)),
        _entry('2026-06-11', FlowLevel.medium, at(7)),
      ];
      // The swap-delete goes through; the light sample's write fails.
      platform.writeResults = [
        const HealthPlatformAllowed(), // 06-09 heavy
        const HealthPlatformAllowed(), // 06-11 medium
        const HealthPlatformResult.failed('transient'), // 06-10 swap write
      ];
      final refused = await service.syncNow();
      expect(refused.blocked, isA<HealthPlatformFailed>());
      expect(refused.samplesReconciled, 1);
      expect(platform.deleteCalls, [
        ['spot-2026-06-10'],
      ]);
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        flowPayloadSummaryGone,
        reason: 'the deleted marker was marked gone so a reverted plan is due',
      );

      // Before the retry, she removes the surrounding flow days.
      // The plan reverts to an intermenstrual marker.
      dayEntries.entries = [];
      platform.writeResults = [];
      final retried = await service.syncNow();
      expect(retried.blocked, isNull);
      expect(platform.markerWrites, hasLength(2));
      expect(platform.markerWrites.last.recordId, 'spot-2026-06-10');
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        'marker',
      );
    });

    test('a spotting type swap whose write fails keeps an entry saved '
        'before the floor in scope and writes the new type on retry '
        '(issue #1670)', () async {
      await seedGranted(grant);
      // Floor stands at at(10); spotting entry is from before the floor (at(5)).
      await settings.set(_cursorKey, '${at(10).millisecondsSinceEpoch}');
      observations.observations = [_spotting('2026-06-10', at(5))];
      await ledger.record([
        HealthExportLedgerEntry(
          recordId: 'spot-2026-06-10',
          profileId: _profileId,
          sourceRowId: 'spot-2026-06-10',
          kind: HealthExportLedgerKind.spotting,
          localDate: '2026-06-10',
          exportedAt: at(5),
          payloadSummary: 'marker',
        ),
      ]);
      final service = buildService();

      dayEntries.entries = [
        _entry('2026-06-09', FlowLevel.heavy, at(11)),
        _entry('2026-06-11', FlowLevel.medium, at(11)),
      ];
      // The swap-delete goes through; the light sample's write is refused.
      platform.writeResults = [
        const HealthPlatformAllowed(), // 06-09 heavy
        const HealthPlatformAllowed(), // 06-11 medium
        const HealthPlatformResult.failed('no'), // 06-10 swap write
      ];
      final refused = await service.syncNow();
      expect(refused.blocked, isA<HealthPlatformFailed>());
      expect(platform.deleteCalls, [
        ['spot-2026-06-10'],
      ]);
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        flowPayloadSummaryGone,
      );

      // On retry, the entry is still in scope because the ledger knows the row,
      // despite its updatedAt being before the floor.
      platform.writeResults = [];
      final retried = await service.syncNow();
      expect(retried.blocked, isNull);
      expect(platform.deleteCalls, hasLength(1));
      expect(platform.flowWrites.last.recordId, 'spot-2026-06-10');
      expect(platform.flowWrites.last.flow, HealthFlowValue.light);
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        'flow:light:0',
      );
    });

    test('a spotting type swap whose write fails keeps an entry saved '
        'before the floor in scope and writes the marker if the day '
        'reverts before retry (issue #1670)', () async {
      await seedGranted(grant);
      await settings.set(_cursorKey, '${at(10).millisecondsSinceEpoch}');
      observations.observations = [_spotting('2026-06-10', at(5))];
      await ledger.record([
        HealthExportLedgerEntry(
          recordId: 'spot-2026-06-10',
          profileId: _profileId,
          sourceRowId: 'spot-2026-06-10',
          kind: HealthExportLedgerKind.spotting,
          localDate: '2026-06-10',
          exportedAt: at(5),
          payloadSummary: 'marker',
        ),
      ]);
      final service = buildService();

      dayEntries.entries = [
        _entry('2026-06-09', FlowLevel.heavy, at(11)),
        _entry('2026-06-11', FlowLevel.medium, at(11)),
      ];
      platform.writeResults = [
        const HealthPlatformAllowed(),
        const HealthPlatformAllowed(),
        const HealthPlatformResult.failed('transient'),
      ];
      final refused = await service.syncNow();
      expect(refused.blocked, isA<HealthPlatformFailed>());
      expect(platform.deleteCalls, [
        ['spot-2026-06-10'],
      ]);
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        flowPayloadSummaryGone,
      );

      // Surrounding flow days removed; plan reverts to marker.
      dayEntries.entries = [];
      platform.writeResults = [];
      final retried = await service.syncNow();
      expect(retried.blocked, isNull);
      expect(platform.markerWrites, hasLength(1));
      expect(platform.markerWrites.last.recordId, 'spot-2026-06-10');
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        'marker',
      );
    });

    test('a spotting type swap whose write fails writes on retry even '
        'when the new type\'s floor is set after the entry (issue #1670)',
        () async {
      await seedGranted(grant);
      observations.observations = [_spotting('2026-06-10', at(5))];
      await ledger.record([
        HealthExportLedgerEntry(
          recordId: 'spot-2026-06-10',
          profileId: _profileId,
          sourceRowId: 'spot-2026-06-10',
          kind: HealthExportLedgerKind.spotting,
          localDate: '2026-06-10',
          exportedAt: at(5),
          payloadSummary: 'marker',
        ),
      ]);
      // Menstrual flow type floor stands at at(8), after the entry's at(5).
      final passState = HealthWritePassState(
        typeFloors: {HealthWriteTypes.menstrualFlow: at(8)},
      );
      await settings.set(
        SettingsKeys.healthSyncWriteState,
        passState.encode(),
      );
      final service = buildService();

      dayEntries.entries = [
        _entry('2026-06-09', FlowLevel.heavy, at(9)),
        _entry('2026-06-11', FlowLevel.medium, at(10)),
      ];
      // The swap-delete goes through; the light sample's write is refused.
      platform.writeResults = [
        const HealthPlatformAllowed(), // 06-09 heavy
        const HealthPlatformAllowed(), // 06-11 medium
        const HealthPlatformResult.failed('no'), // 06-10 swap write
      ];
      final refused = await service.syncNow();
      expect(refused.blocked, isA<HealthPlatformFailed>());
      expect(platform.deleteCalls, [
        ['spot-2026-06-10'],
      ]);
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        flowPayloadSummaryGone,
      );

      // On retry, admitsNew is not consulted because the record is remembered
      // in the ledger (not a brand new record). The light flow sample is written.
      platform.writeResults = [];
      final retried = await service.syncNow();
      expect(retried.blocked, isNull);
      expect(platform.flowWrites.last.recordId, 'spot-2026-06-10');
      expect(platform.flowWrites.last.flow, HealthFlowValue.light);
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'spot-2026-06-10')
            .payloadSummary,
        'flow:light:0',
      );
    });

    test('a record a build before this one wrote is sent once more, and '
        'the summary it stamps keeps it quiet after', () async {
      await seedGranted(grant);
      // The wrong cycle start is already out there: Tuesday was written
      // as the first day by a build that recorded no summary, and Monday
      // has since been added.
      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.light,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 2))),
      ];
      await ledger.record([
        HealthExportLedgerEntry(
          recordId: 'entry-2026-06-02',
          profileId: _profileId,
          sourceRowId: 'entry-2026-06-02',
          kind: HealthExportLedgerKind.entry,
          localDate: '2026-06-02',
          exportedAt: grant.add(const Duration(hours: 2)),
        ),
      ]);
      final service = buildService();

      final report = await service.syncNow();

      expect(report.blocked, isNull);
      final tuesday =
          platform.flowWrites.singleWhere((w) => w.date.iso == '2026-06-02');
      expect(tuesday.cycleStart, isFalse,
          reason: 'the correction: Monday is the first day now');
      expect(tuesday.recordVersionMs,
          greaterThan(grant.add(const Duration(hours: 2)).millisecondsSinceEpoch),
          reason: 'the store holds the record at the old version');
      // Monday was never written, so it is sent as it stands.
      expect(
        platform.flowWrites.singleWhere((w) => w.date.iso == '2026-06-01')
            .cycleStart,
        isTrue,
      );
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'entry-2026-06-02')
            .payloadSummary,
        'flow:heavy:0',
      );

      await service.syncNow();
      expect(platform.flowWrites, hasLength(2));
    });

    test('a seeded ledger row with no summary for a spotting entry whose day '
        'is now inside a period ends with one record in the store (issue #1641)',
        () async {
      final simulated = _SimulatedStorePlatform();
      platform = simulated;
      // Pre-seed the store with an intermenstrual marker from an earlier build.
      simulated.store.add('marker:spot-2026-06-10');

      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-09', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-11', FlowLevel.medium,
            grant.add(const Duration(hours: 2))),
      ];
      observations.observations = [
        _spotting('2026-06-10', grant.add(const Duration(hours: 3))),
      ];
      // An earlier build wrote the spotting entry without a payload summary.
      await ledger.record([
        HealthExportLedgerEntry(
          recordId: 'spot-2026-06-10',
          profileId: _profileId,
          sourceRowId: 'spot-2026-06-10',
          kind: HealthExportLedgerKind.spotting,
          localDate: '2026-06-10',
          exportedAt: grant.add(const Duration(hours: 3)),
        ),
      ]);
      final service = buildService();

      final report = await service.syncNow();

      expect(report.blocked, isNull);
      // The old marker was deleted first, and the new light flow was written.
      expect(simulated.deleteCalls.first, ['spot-2026-06-10']);
      final spotWrite = simulated.flowWrites
          .singleWhere((w) => w.recordId == 'spot-2026-06-10');
      expect(spotWrite.flow, HealthFlowValue.light);
      // For the spotting record, the store ends with exactly one record:
      // the new light flow sample (the old marker was removed).
      expect(
        simulated.store.where((r) => r.endsWith(':spot-2026-06-10')),
        {'flow:spot-2026-06-10'},
      );
      expect(
        ledger.rows
            .singleWhere((r) => r.recordId == 'spot-2026-06-10')
            .payloadSummary,
        'flow:light:0',
      );

      final writesAfter = simulated.flowWrites.length;
      final deletesAfter = simulated.deleteCalls.length;
      await service.syncNow();
      expect(simulated.flowWrites, hasLength(writesAfter));
      expect(simulated.deleteCalls, hasLength(deletesAfter));
      expect(
        simulated.store.where((r) => r.endsWith(':spot-2026-06-10')),
        {'flow:spot-2026-06-10'},
      );
    });

    test('an unknown spotting record waits when either type is switched off, '
        'and deletes then writes once both are back (issue #1641)', () async {
      await seedGranted(grant);
      dayEntries.entries = [
        _entry('2026-06-09', FlowLevel.heavy, at(1)),
        _entry('2026-06-11', FlowLevel.medium, at(2)),
      ];
      observations.observations = [_spotting('2026-06-10', at(3))];
      await ledger.record([
        HealthExportLedgerEntry(
          recordId: 'spot-2026-06-10',
          profileId: _profileId,
          sourceRowId: 'spot-2026-06-10',
          kind: HealthExportLedgerKind.spotting,
          localDate: '2026-06-10',
          exportedAt: at(3),
        ),
      ]);
      final service = buildService();

      // Only menstrualFlow is granted; spotting is off. An unknown spotting
      // record needs both types granted to safely clear the replaced type.
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'menstrualFlow'};
      final waiting = await service.syncNow();
      expect(waiting.blocked, isNull);
      expect(platform.deleteCalls, isEmpty);
      expect(
        platform.flowWrites.where((w) => w.recordId == 'spot-2026-06-10'),
        isEmpty,
      );

      // Both types granted: swap delete goes through, followed by the write.
      platform.permission = HealthPermissionStatus.granted;
      platform.grantedTypes = {'menstrualFlow', 'spotting'};
      final completed = await service.syncNow();
      expect(completed.blocked, isNull);
      expect(platform.deleteCalls, [
        ['spot-2026-06-10'],
      ]);
      expect(
        platform.flowWrites
            .singleWhere((w) => w.recordId == 'spot-2026-06-10')
            .flow,
        HealthFlowValue.light,
      );
      expect(
        ledger.rows
            .singleWhere((r) => r.recordId == 'spot-2026-06-10')
            .payloadSummary,
        'flow:light:0',
      );
    });

    test('a ledger from an earlier build: payloadSummary is preserved when '
        'adoptEarlierLedger runs again (issue #1641)', () async {
      await settings.set(_bindingKey, _profileId);
      await settings.set(_cursorKey, '${at(10).millisecondsSinceEpoch}');
      dayEntries.entries = [
        _entry('2026-06-09', FlowLevel.medium, at(10)),
        _entry('2026-06-10', FlowLevel.none, at(10)),
      ];
      observations.observations = [
        _spotting('2026-06-10', at(10)),
      ];
      await ledger.record([
        HealthExportLedgerEntry(
          recordId: 'entry-2026-06-09',
          profileId: _profileId,
          sourceRowId: 'entry-2026-06-09',
          kind: HealthExportLedgerKind.entry,
          localDate: '2026-06-09',
          exportedAt: at(10),
          payloadSummary: 'flow:medium:1',
        ),
        HealthExportLedgerEntry(
          recordId: 'spot-2026-06-10',
          profileId: _profileId,
          sourceRowId: 'spot-2026-06-10',
          kind: HealthExportLedgerKind.spotting,
          localDate: '2026-06-10',
          exportedAt: at(10),
          payloadSummary: 'marker',
        ),
      ]);
      // Write state is cleared so adoptEarlierLedger runs on next pass.
      await settings.set(SettingsKeys.healthSyncWriteState, '');
      final service = buildService();
      await service.syncNow();

      expect(
        ledger.rows
            .singleWhere((r) => r.recordId == 'entry-2026-06-09')
            .payloadSummary,
        'flow:medium:1',
      );
      expect(
        ledger.rows
            .singleWhere((r) => r.recordId == 'spot-2026-06-10')
            .payloadSummary,
        'marker',
      );
    });

    test('on Android (writesCycleStart = false), logging the day before a '
        'written period day does not re-send the second day (issue #1645)', () async {
      await seedGranted(grant);
      platform.writesCycleStart = false;
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
      ];
      final service = buildService();
      await service.syncNow();
      expect(platform.flowWrites, hasLength(1));
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'entry-2026-06-02')
            .payloadSummary,
        'flow:heavy',
        reason: 'Android flow summary leaves out the cycle-start flag',
      );

      // The next day she adds Monday. Monday is the period's first day now,
      // and Tuesday's own row has not changed.
      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.light,
            grant.add(const Duration(hours: 2))),
        _entry('2026-06-02', FlowLevel.heavy,
            grant.add(const Duration(hours: 1))),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      // Only Monday is written: Tuesday's record in Health Connect is
      // already identical to what this pass would write.
      expect(report.samplesWritten, 1);
      expect(platform.flowWrites, hasLength(2));
      expect(platform.flowWrites.last.date.iso, '2026-06-01');
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'entry-2026-06-01')
            .payloadSummary,
        'flow:light',
      );
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'entry-2026-06-02')
            .payloadSummary,
        'flow:heavy',
      );

      // Third pass sends nothing.
      await service.syncNow();
      expect(platform.flowWrites, hasLength(2));
    });

    test('on Android (writesCycleStart = false), a pre-#1640 flow record '
        'with no summary is not re-sent and is quietly stamped (issue #1645)', () async {
      await seedGranted(grant);
      platform.writesCycleStart = false;
      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.light,
            grant.add(const Duration(hours: 1))),
        _entry('2026-06-02', FlowLevel.heavy,
            grant.subtract(const Duration(hours: 1))),
      ];
      // Tuesday was written by a pre-#1640 build without a payload summary.
      await ledger.record([
        HealthExportLedgerEntry(
          recordId: 'entry-2026-06-02',
          profileId: _profileId,
          sourceRowId: 'entry-2026-06-02',
          kind: HealthExportLedgerKind.entry,
          localDate: '2026-06-02',
          exportedAt: grant.subtract(const Duration(hours: 1)),
        ),
      ]);
      final service = buildService();

      final report = await service.syncNow();

      expect(report.blocked, isNull);
      // Tuesday was already written to Health Connect at its current version
      // and Health Connect has no cycle-start flag, so only Monday is sent.
      expect(report.samplesWritten, 1);
      expect(platform.flowWrites, hasLength(1));
      expect(platform.flowWrites.single.date.iso, '2026-06-01');

      // Tuesday's ledger row is quietly stamped with its summary.
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'entry-2026-06-02')
            .payloadSummary,
        'flow:heavy',
      );
      expect(
        ledger.rows.singleWhere((row) => row.recordId == 'entry-2026-06-01')
            .payloadSummary,
        'flow:light',
      );

      // Subsequent pass sends nothing.
      await service.syncNow();
      expect(platform.flowWrites, hasLength(1));
    });
  });

  // Issue #1643: a correction re-send writes the store at a raised version
  // but the row's updatedAt did not change. The ledger must remember the
  // written version sent to the store, so a later offline edit stamped
  // between the row's original updatedAt and the correction's store version
  // is not dropped by the health store.
  group('issue #1643: written store version is remembered in export ledger', () {
    final grant = DateTime.utc(2026, 6, 1, 12);
    DateTime at(int minutes) => grant.add(Duration(minutes: minutes));

    test('an offline edit stamped earlier than a previous correction re-send '
        'is written with a store version above the correction', () async {
      await seedGranted(grant);
      // Tuesday logged at +1h.
      final tuesdayT1 = at(60);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy, tuesdayT1),
      ];
      final service = buildService();
      await service.syncNow();
      final tuesdayFirstWrite = platform.flowWrites.single;
      expect(tuesdayFirstWrite.cycleStart, isTrue);
      expect(tuesdayFirstWrite.recordVersionMs,
          tuesdayT1.millisecondsSinceEpoch);

      // Tuesday's ledger remembers both exportedAt and writtenVersion.
      var tuesdayRow = ledger.rows
          .singleWhere((r) => r.recordId == 'entry-2026-06-02');
      expect(tuesdayRow.exportedAt, tuesdayT1);
      expect(tuesdayRow.storeVersion, tuesdayT1);

      // Monday is added at +2h; Tuesday's row is untouched.
      final mondayT2 = at(120);
      clock = mondayT2;
      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.light, mondayT2),
        _entry('2026-06-02', FlowLevel.heavy, tuesdayT1),
      ];
      final report = await service.syncNow();
      expect(report.samplesWritten, 2);

      final tuesdayCorrectionWrite = platform.flowWrites
          .where((w) => w.date.iso == '2026-06-02')
          .last;
      expect(tuesdayCorrectionWrite.cycleStart, isFalse);
      expect(tuesdayCorrectionWrite.recordVersionMs,
          mondayT2.millisecondsSinceEpoch);

      tuesdayRow = ledger.rows
          .singleWhere((r) => r.recordId == 'entry-2026-06-02');
      expect(tuesdayRow.exportedAt, tuesdayT1,
          reason: 'row updatedAt is still T1');
      expect(tuesdayRow.writtenVersion, mondayT2,
          reason: 'store was written at T2');
      expect(tuesdayRow.storeVersion, mondayT2);

      // Tuesday is edited offline at +90m (between T1 and T2).
      final tuesdayT3 = at(90);
      clock = at(180);
      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.light, mondayT2),
        _entry('2026-06-02', FlowLevel.light, tuesdayT3),
      ];
      final editReport = await service.syncNow();
      expect(editReport.samplesWritten, 1);

      final tuesdayEditWrite = platform.flowWrites
          .where((w) => w.date.iso == '2026-06-02')
          .last;
      expect(tuesdayEditWrite.flow, HealthFlowValue.light);
      expect(tuesdayEditWrite.recordVersionMs,
          greaterThan(tuesdayCorrectionWrite.recordVersionMs),
          reason: 'must write above T2 so HealthKit/Health Connect accepts it');

      tuesdayRow = ledger.rows
          .singleWhere((r) => r.recordId == 'entry-2026-06-02');
      expect(tuesdayRow.exportedAt, tuesdayT3);
      expect(
        tuesdayRow.storeVersion,
        DateTime.fromMillisecondsSinceEpoch(
            tuesdayEditWrite.recordVersionMs,
            isUtc: true),
      );
    });

    test('a second correction after clock is moved backwards writes '
        'above the previously written store version', () async {
      await seedGranted(grant);
      final tuesdayT1 = at(60);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy, tuesdayT1),
      ];
      final service = buildService();
      await service.syncNow();

      // Monday is added at +2h; Tuesday is corrected.
      final mondayT2 = at(120);
      clock = mondayT2;
      dayEntries.entries = [
        _entry('2026-06-01', FlowLevel.light, mondayT2),
        _entry('2026-06-02', FlowLevel.heavy, tuesdayT1),
      ];
      await service.syncNow();
      final tuesdayCorrection1 = platform.flowWrites
          .where((w) => w.date.iso == '2026-06-02')
          .last;
      expect(tuesdayCorrection1.recordVersionMs,
          mondayT2.millisecondsSinceEpoch);

      // Now clock moves backward (e.g. at(30)) and Monday is deleted.
      // Tuesday becomes cycleStart: true again.
      clock = at(30);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy, tuesdayT1),
      ];
      final report = await service.syncNow();
      expect(report.samplesWritten, 1);

      final tuesdayCorrection2 = platform.flowWrites
          .where((w) => w.date.iso == '2026-06-02')
          .last;
      expect(tuesdayCorrection2.cycleStart, isTrue);
      expect(tuesdayCorrection2.recordVersionMs,
          greaterThan(tuesdayCorrection1.recordVersionMs),
          reason:
              'clock move backward cannot write lower than previous store version');
    });
  });
}
