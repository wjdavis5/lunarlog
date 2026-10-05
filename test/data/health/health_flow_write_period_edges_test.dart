/// Edge cases of the period-record rule (Issue #1478), from the independent
/// review of its fix: which failures leave the store and the export ledger
/// in a state the next pass can finish from, and what keeps the rule
/// forward-only.
///
/// The rule under test (`LocalHealthFlowWriteService._collectPeriods`): an
/// episode has a period record exactly when this device has exported one of
/// its days. The pass writes what is missing or changed, then deletes what
/// no longer qualifies, in that order.
library;


import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_flow_write_service.dart';
import 'package:lunarlog/domain/health/health_export_ledger.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
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

const _profileId = 'profile-1';
const _ownerId = 'owner-user';
const _tz = 'Europe/Berlin';
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
  String tz = _tz,
  List<String> tags = const [],
}) =>
    DayEntry(
      id: 'entry-$isoDay',
      profileId: _profileId,
      localDate: LocalDate.fromIso(isoDay),
      tz: tz,
      flow: flow,
      tags: tags,
      updatedAt: updatedAt,
      source: source,
    );

class _Settings implements SettingsStore {
  final Map<String, String> values = {};
  @override
  Future<String?> get(String key) async => values[key];
  @override
  Future<void> set(String key, String value) async => values[key] = value;
  @override
  Stream<String?> watch(String key) => const Stream.empty();
}

class _Ledger implements HealthExportLedger {
  final Map<String, HealthExportLedgerEntry> rows = {};
  @override
  Future<List<HealthExportLedgerEntry>> readForProfile(String profileId) async =>
      [for (final r in rows.values) if (r.profileId == profileId) r];
  @override
  Future<void> record(Iterable<HealthExportLedgerEntry> entries) async {
    for (final e in entries) {
      rows[e.recordId] = e;
    }
  }

  @override
  Future<void> removeRecordIds(Iterable<String> recordIds) async {
    recordIds.forEach(rows.remove);
  }

  @override
  Future<void> clearProfile(String profileId) async =>
      rows.removeWhere((_, r) => r.profileId == profileId);
  @override
  Future<void> clearAll() async => rows.clear();

  List<String> get periods => [
        for (final r in rows.values)
          if (r.kind == HealthExportLedgerKind.period)
            '${r.recordId} ${r.sourceRowId}',
      ]..sort();
}

class _Profiles implements ProfilesRepository {
  @override
  Future<Profile?> findById(String id) async => _profile();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _DayEntries implements DayEntriesRepository {
  List<DayEntry> entries = const [];
  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => entries;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Observations implements ObservationsRepository {
  @override
  Future<List<Observation>> listForProfile(String profileId) async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Recording port. One ordered log of the calls that touch the store.
class _Platform implements HealthPlatformStore {
  HealthPermissionStatus permission = HealthPermissionStatus.granted;
  HealthPermissionStatus permissionAfterAuth = HealthPermissionStatus.granted;
  final List<HealthMenstrualFlowWrite> flowWrites = [];
  final List<HealthMenstrualPeriodWrite> periodWrites = [];
  final List<List<String>> deleteCalls = [];
  final List<String> log = [];
  int authCalls = 0;

  /// Results for successive period writes / deletes; empty = allowed.
  List<HealthPlatformResult> periodResults = [];
  List<HealthPlatformResult> deleteResults = [];

  HealthPlatformResult _next(List<HealthPlatformResult> queue) =>
      queue.isEmpty ? const HealthPlatformAllowed() : queue.removeAt(0);

  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<HealthPermissionStatus> permissionStatus() async => permission;
  @override
  Future<void> openPermissionSettings() async {}
  @override
  Future<HealthPlatformResult> bindProfile(HealthGuardFacts facts) async =>
      const HealthPlatformAllowed();
  @override
  Future<void> unbindProfile() async {}
  @override
  Future<HealthPlatformResult> requestWriteAuthorization(
      HealthGuardFacts facts) async {
    authCalls++;
    permission = permissionAfterAuth;
    return const HealthPlatformAllowed();
  }

  @override
  Future<HealthPlatformResult> writeMenstrualFlow(
      HealthMenstrualFlowWrite write) async {
    flowWrites.add(write);
    return const HealthPlatformAllowed();
  }

  @override
  Future<HealthPlatformResult> writeMenstrualPeriod(
      HealthMenstrualPeriodWrite write) async {
    final result = _next(periodResults);
    periodWrites.add(write);
    log.add('period-write ${write.recordId} ${write.start.iso}..${write.end.iso}'
        ' -> ${result.runtimeType}');
    return result;
  }

  @override
  Future<HealthPlatformResult> deleteRecords(
      HealthGuardFacts facts, List<String> recordIds) async {
    deleteCalls.add(List.of(recordIds));
    if (recordIds.any((id) => id.startsWith('period-'))) {
      final result = _next(deleteResults);
      log.add('delete $recordIds -> ${result.runtimeType}');
      return result;
    }
    return const HealthPlatformAllowed();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<HealthPlatformResult>.value(const HealthPlatformAllowed());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Settings settings;
  late _Ledger ledger;
  late _DayEntries dayEntries;
  late DateTime clock;
  final grant = DateTime.utc(2026, 6, 1, 12);

  LocalHealthFlowWriteService build(HealthPlatformStore platform) =>
      LocalHealthFlowWriteService(
        platform: platform,
        binding: HealthSyncBinding(settings),
        minorBindingAllowed: false,
        profiles: _Profiles(),
        dayEntries: dayEntries,
        observations: _Observations(),
        settings: settings,
        ledger: ledger,
        guardiansForProfile: (_) async => [_ownerRow()],
        signedInUserId: () => _ownerId,
        now: () => clock,
      );

  Future<void> seedGranted(DateTime at) async {
    await settings.set(_bindingKey, _profileId);
    await settings.set(_cursorKey, '${at.millisecondsSinceEpoch}');
  }

  DateTime h(int hours, [int minutes = 0]) =>
      grant.add(Duration(hours: hours, minutes: minutes));

  setUp(() {
    settings = _Settings();
    ledger = _Ledger();
    dayEntries = _DayEntries();
    clock = h(6);
  });

  test('deleting the only exported day of a period that began before sync '
      'removes its record: the earlier days no longer qualify', () async {
    await seedGranted(grant);
    final platform = _Platform();
    final service = build(platform);
    final pre1 = _entry('2026-05-30', FlowLevel.heavy, grant.subtract(const Duration(days: 2)));
    final pre2 = _entry('2026-05-31', FlowLevel.medium, grant.subtract(const Duration(days: 1)));
    dayEntries.entries = [pre1, pre2, _entry('2026-06-01', FlowLevel.light, h(1))];
    await service.syncNow();
    expect(ledger.periods, ['period-$_profileId-2026-05-30 2026-05-30/2026-06-01']);
    platform.log.clear();
    // 06-01 is tombstoned (gone from the live list). NB the write service's
    // in-memory "exported" map still names entry-2026-06-01, but that entry
    // is no longer among the days.
    dayEntries.entries = [pre1, pre2];
    final report = await service.syncNow();
    expect(report.blocked, isNull);
    expect(ledger.periods, isEmpty);
    expect(platform.log.single, startsWith('delete [period-$_profileId-2026-05-30]'));
  });

  test('after a relaunch the ledger alone makes the surviving days '
      'qualify', () async {
    await seedGranted(grant);
    final platform = _Platform();
    final d2 = _entry('2026-06-02', FlowLevel.heavy, h(1));
    final d3 = _entry('2026-06-03', FlowLevel.medium, h(2));
    final d4 = _entry('2026-06-04', FlowLevel.light, h(3));
    dayEntries.entries = [d2, d3, d4];
    await build(platform).syncNow();
    // New process. 06-02 was deleted while the app was closed.
    dayEntries.entries = [d3, d4];
    final report = await build(platform).syncNow();
    expect(report.blocked, isNull);
    expect(ledger.periods, ['period-$_profileId-2026-06-03 2026-06-03/2026-06-04']);
  });

  test('first day moves and the new record is refused: the old one '
      'is not deleted; the retry finishes the job', () async {
    await seedGranted(grant);
    final platform = _Platform();
    final service = build(platform);
    final d5 = _entry('2026-06-05', FlowLevel.medium, h(1));
    dayEntries.entries = [d5];
    await service.syncNow();
    platform.log.clear();
    dayEntries.entries = [_entry('2026-06-04', FlowLevel.light, h(2)), d5];
    platform.periodResults = [const HealthPlatformResult.failed('store busy')];
    final failed = await service.syncNow();
    expect(failed.blocked, isA<HealthPlatformFailed>());
    expect(platform.log.where((l) => l.startsWith('delete')), isEmpty);
    expect(ledger.periods, ['period-$_profileId-2026-06-05 2026-06-05/2026-06-05']);
    final retried = await service.syncNow();
    expect(retried.blocked, isNull);
    expect(ledger.periods, ['period-$_profileId-2026-06-04 2026-06-04/2026-06-05']);
  });

  test('first day moves and the old record cannot be deleted: both are '
      'remembered, the next pass removes the old one and rewrites nothing',
      () async {
    await seedGranted(grant);
    final platform = _Platform();
    final service = build(platform);
    final d5 = _entry('2026-06-05', FlowLevel.medium, h(1));
    dayEntries.entries = [d5];
    await service.syncNow();
    dayEntries.entries = [_entry('2026-06-04', FlowLevel.light, h(2)), d5];
    platform.deleteResults = [const HealthPlatformPermissionDenied()];
    final failed = await service.syncNow();
    expect(failed.blocked, isA<HealthPlatformPermissionDenied>());
    expect(ledger.periods, [
      'period-$_profileId-2026-06-04 2026-06-04/2026-06-05',
      'period-$_profileId-2026-06-05 2026-06-05/2026-06-05',
    ]);
    final writesBefore = platform.periodWrites.length;
    final retried = await service.syncNow();
    expect(retried.blocked, isNull);
    expect(platform.periodWrites, hasLength(writesBefore));
    expect(ledger.periods, ['period-$_profileId-2026-06-04 2026-06-04/2026-06-05']);
  });
}
