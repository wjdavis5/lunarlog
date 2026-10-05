/// The write service driven through the real channel adapter (Issue #1478's
/// review, reproduction R1): the period-record paths that only fail once
/// the day-boundary maths actually runs.
///
/// `health_flow_write_service_test.dart` uses a recording fake port, which
/// accepts any zone name. A Health Connect import stamps its rows with a
/// fixed-offset zone such as `UTC+02:00`, and `day_boundary.dart` resolves
/// IANA names only — so a period record that took its zone from an imported
/// first day was deleted, could not be rewritten, and failed every pass
/// after that with nothing on screen. That is only visible with the real
/// `MethodChannelHealthPlatform` building the channel arguments.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_channel.dart';
import 'package:lunarlog/data/health/health_flow_write_service.dart';
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

import '../../support/fake_health_export_ledger.dart';
import '../../support/fake_settings_store.dart';

const _profileId = 'profile-1';
const _ownerId = 'owner-user';
const _tz = 'Europe/Berlin';

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

DayEntry _logged(String isoDay, DateTime updatedAt) => DayEntry(
      id: 'entry-$isoDay',
      profileId: _profileId,
      localDate: LocalDate.fromIso(isoDay),
      tz: _tz,
      flow: FlowLevel.medium,
      updatedAt: updatedAt,
    );

/// A row as the Health Connect import writes it: its source, and the
/// record's raw offset as the zone name.
DayEntry _imported(String isoDay, DateTime updatedAt) => DayEntry(
      id: 'entry-$isoDay',
      profileId: _profileId,
      localDate: LocalDate.fromIso(isoDay),
      tz: 'UTC+02:00',
      flow: FlowLevel.medium,
      updatedAt: updatedAt,
      source: DayEntrySource.healthConnect,
    );

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kHealthChannelName);
  final grant = DateTime.utc(2026, 6, 1, 12);
  late List<MethodCall> calls;
  late FakeSettingsStore settings;
  late FakeHealthExportLedger ledger;
  late _DayEntries dayEntries;
  late LocalHealthFlowWriteService service;

  /// Every call that reached the native side, by method name.
  List<String> methods() => [for (final call in calls) call.method];

  /// The calls that touch the health store's data: everything but the
  /// status probe and the binding mirror, which every pass makes.
  List<String> storeCalls() => [
        for (final method in methods())
          if (method != 'permissionStatus' && method != 'bind') method,
      ];

  Map<Object?, Object?> lastPeriodArgs() => calls
      .lastWhere((call) => call.method == 'writeMenstrualPeriod')
      .arguments as Map<Object?, Object?>;

  setUp(() async {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'permissionStatus' ? 'granted' : 'allowed';
    });
    settings = FakeSettingsStore();
    ledger = FakeHealthExportLedger();
    dayEntries = _DayEntries();
    await settings.set(SettingsKeys.healthStoreProfileId, _profileId);
    await settings.set(
      SettingsKeys.healthSyncWrittenThroughMs,
      '${grant.millisecondsSinceEpoch}',
    );
    final binding = HealthSyncBinding(settings);
    service = LocalHealthFlowWriteService(
      platform: MethodChannelHealthPlatform(
        channel: channel,
        binding: binding,
        minorBindingAllowed: false,
        readAccessDisclosed: true,
      ),
      binding: binding,
      minorBindingAllowed: false,
      profiles: _Profiles(),
      dayEntries: dayEntries,
      observations: _Observations(),
      settings: settings,
      ledger: ledger,
      guardiansForProfile: (_) async => [_ownerRow()],
      signedInUserId: () => _ownerId,
      now: () => grant.add(const Duration(hours: 6)),
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await settings.close();
  });

  test('a period whose first day was imported from Health Connect is '
      'written, corrected and corrected again without a failed pass',
      () async {
    final imported = _imported('2026-06-01', grant);
    final d2 = _logged('2026-06-02', grant.add(const Duration(hours: 1)));
    final d3 = _logged('2026-06-03', grant.add(const Duration(hours: 2)));
    dayEntries.entries = [imported, d2, d3];

    final first = await service.syncNow();
    expect(first.blocked, isNull);
    expect(first.periodRecordsWritten, 1);
    // 06-02 00:00 in Berlin (UTC+2 in June) to 06-03 23:59:59: the
    // hand-logged days only, in a hand-logged day's zone.
    expect(lastPeriodArgs()['startMs'],
        DateTime.utc(2026, 6, 1, 22).millisecondsSinceEpoch);
    expect(lastPeriodArgs()['endMs'],
        DateTime.utc(2026, 6, 3, 21, 59, 59).millisecondsSinceEpoch);

    // 06-03 is deleted (a tombstone: gone from the live list).
    calls.clear();
    dayEntries.entries = [imported, d2];
    final second = await service.syncNow();
    expect(second.blocked, isNull,
        reason: 'the correction used to delete the record and then fail to '
            'build its replacement, on this pass and every one after');
    expect(methods(), contains('writeMenstrualPeriod'));
    expect(lastPeriodArgs()['endMs'],
        DateTime.utc(2026, 6, 2, 21, 59, 59).millisecondsSinceEpoch);

    // Nothing left to do: the next pass is quiet and still not blocked.
    calls.clear();
    final third = await service.syncNow();
    expect(third.blocked, isNull);
    expect(storeCalls(), isEmpty);
  });

  // PRIVACY section 4: a background import pass never writes anything to
  // the health store, and the site says lunarlog never writes its imports
  // back. A period record is derived data, so that has to hold for it too.
  test('an import that lands bleed days beside an exported period makes no '
      'call that touches the store', () async {
    final own = [
      _logged('2026-06-03', grant.add(const Duration(hours: 1))),
      _logged('2026-06-04', grant.add(const Duration(hours: 2))),
    ];
    dayEntries.entries = own;
    await service.syncNow();
    expect(methods(), contains('writeMenstrualPeriod'));

    calls.clear();
    final imported = grant.add(const Duration(hours: 5));
    dayEntries.entries = [
      _imported('2026-06-01', imported),
      _imported('2026-06-02', imported),
      ...own,
      _imported('2026-06-05', imported),
    ];
    final report = await service.syncNow();

    expect(report.blocked, isNull);
    expect(storeCalls(), isEmpty,
        reason: 'no write and no delete: the period still says '
            '06-03..06-04');
    expect(methods(), everyElement(anyOf('permissionStatus', 'bind')));
  });
}
