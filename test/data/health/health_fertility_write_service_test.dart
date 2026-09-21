/// Issue #228: `LocalHealthFlowWriteService`'s fertility-signal and BBT
/// half. Proves the service resolves a day's discharge/ovulation tags and a
/// manual `bbt` observation into platform writes, keeps a platform- or
/// wearable-sourced BBT value out entirely, respects forward-only/one-way
/// policy, reports counts, and treats a platform `unavailable` as a
/// graceful skip rather than a pass-blocking failure.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_flow_write_service.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
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

DayEntry _entry(
  String isoDay, {
  List<String> tags = const [],
  DateTime? updatedAt,
  DayEntrySource source = DayEntrySource.manual,
}) => DayEntry(
  id: 'entry-$isoDay',
  profileId: _profileId,
  localDate: LocalDate.fromIso(isoDay),
  tz: _tz,
  flow: FlowLevel.none,
  tags: tags,
  updatedAt: updatedAt ?? DateTime.utc(2026, 6, 2),
  source: source,
);

Observation _bbt(
  String day, {
  double? value = 36.6,
  String? unit = 'celsius',
  bool excluded = false,
  ObservationSource source = ObservationSource.manual,
  DateTime? updatedAt,
  DateTime? observedAt,
}) => Observation(
  id: 'bbt-$day',
  dayEntryId: 'entry-$day',
  profileId: _profileId,
  localDate: LocalDate.fromIso(day),
  tz: _tz,
  category: ObservationCategory.bbt,
  valueNum: value,
  unit: unit,
  excluded: excluded,
  source: source,
  updatedAt: updatedAt ?? DateTime.utc(2026, 6, 2),
  observedAt: observedAt,
);

class _FakePlatform implements HealthPlatformStore {
  final List<HealthCervicalMucusWrite> cervicalWrites = [];
  final List<HealthOvulationTestWrite> ovulationWrites = [];
  final List<HealthBasalBodyTemperatureWrite> bbtWrites = [];
  HealthPlatformResult fertilityResult = const HealthPlatformAllowed();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<HealthPermissionStatus> permissionStatus() async =>
      HealthPermissionStatus.granted;

  @override
  Future<void> openPermissionSettings() async {}

  @override
  Future<HealthPlatformResult> bindProfile(HealthGuardFacts facts) async =>
      const HealthPlatformAllowed();

  @override
  Future<void> unbindProfile() async {}

  @override
  Future<HealthPlatformResult> requestWriteAuthorization(
    HealthGuardFacts facts,
  ) async => const HealthPlatformAllowed();

  @override
  Future<HealthPlatformResult> writeMenstrualFlow(
    HealthMenstrualFlowWrite write,
  ) async => const HealthPlatformAllowed();

  @override
  Future<HealthPlatformResult> writeIntermenstrualBleeding(
    HealthIntermenstrualBleedingWrite write,
  ) async => const HealthPlatformAllowed();

  @override
  Future<HealthPlatformResult> writeMenstrualPeriod(
    HealthMenstrualPeriodWrite write,
  ) async => const HealthPlatformUnavailable();

  @override
  Future<HealthPlatformResult> writeSymptomSamples(
    HealthSymptomSamplesWrite write,
  ) async => const HealthPlatformUnavailable();

  @override
  Future<HealthPlatformResult> writeCervicalMucus(
    HealthCervicalMucusWrite write,
  ) async {
    cervicalWrites.add(write);
    return fertilityResult;
  }

  @override
  Future<HealthPlatformResult> writeOvulationTest(
    HealthOvulationTestWrite write,
  ) async {
    ovulationWrites.add(write);
    return fertilityResult;
  }

  @override
  Future<HealthPlatformResult> writeBasalBodyTemperature(
    HealthBasalBodyTemperatureWrite write,
  ) async {
    bbtWrites.add(write);
    return fertilityResult;
  }

  @override
  Future<HealthPlatformResult> deleteRecords(
    HealthGuardFacts facts,
    List<String> recordIds,
  ) async => const HealthPlatformAllowed();
}

class _FakeProfiles implements ProfilesRepository {
  @override
  Future<Profile?> findById(String id) async => _profile();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeDayEntries implements DayEntriesRepository {
  List<DayEntry> entries = const [];

  // Issue #548: short-lived per-test fake with no close() call.
  // ignore: close_sinks
  final _changes = StreamController<List<DayEntry>>.broadcast();

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => entries;

  @override
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) => _changes.stream;

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
  late _FakeDayEntries dayEntries;
  late _FakeObservations observations;

  final ledger = FakeHealthExportLedger();

  LocalHealthFlowWriteService buildService() => LocalHealthFlowWriteService(
    platform: platform,
    binding: HealthSyncBinding(settings),
    minorBindingAllowed: false,
    profiles: _FakeProfiles(),
    dayEntries: dayEntries,
    observations: observations,
    settings: settings,
    guardiansForProfile: (_) async => [_ownerRow()],
    signedInUserId: () => _ownerId,
    ledger: ledger,
    now: () => DateTime.utc(2026, 6, 1, 12),
  );

  final grant = DateTime.utc(2026, 6, 1, 12);

  Future<void> seedGranted() async {
    await settings.set(_bindingKey, _profileId);
    await settings.set(_cursorKey, '${grant.millisecondsSinceEpoch}');
  }

  setUp(() {
    platform = _FakePlatform();
    settings = FakeSettingsStore();
    dayEntries = _FakeDayEntries();
    observations = _FakeObservations();
  });

  tearDown(() => settings.close());

  test('a day with discharge + ovulation tags writes both, with stable ids',
      () async {
    await seedGranted();
    dayEntries.entries = [
      _entry(
        '2026-06-02',
        tags: const ['creamy', 'ovulation_positive'],
        updatedAt: grant.add(const Duration(hours: 1)),
      ),
    ];

    final report = await buildService().syncNow();

    expect(report.cervicalMucusSamplesWritten, 1);
    expect(report.ovulationTestSamplesWritten, 1);
    expect(report.blocked, isNull);

    final cervical = platform.cervicalWrites.single;
    expect(cervical.date, LocalDate.fromIso('2026-06-02'));
    expect(cervical.healthKitValue, 'creamy');
    expect(cervical.healthConnectAppearance, 'APPEARANCE_CREAMY');
    expect(cervical.recordId, 'cervical-mucus-entry-2026-06-02');

    final ovulation = platform.ovulationWrites.single;
    expect(ovulation.healthKitResult, 'luteinizingHormoneSurge');
    expect(ovulation.healthConnectResult, 'RESULT_POSITIVE');
    expect(
      ovulation.recordId,
      'ovulation-entry-2026-06-02-luteinizingHormoneSurge',
    );
  });

  test('positive and peak on one day write one ovulation sample', () async {
    await seedGranted();
    dayEntries.entries = [
      _entry(
        '2026-06-02',
        tags: const ['ovulation_positive', 'ovulation_peak'],
        updatedAt: grant.add(const Duration(hours: 1)),
      ),
    ];

    final report = await buildService().syncNow();

    expect(report.ovulationTestSamplesWritten, 1);
    expect(platform.ovulationWrites, hasLength(1));
  });

  test('atypical/none discharge and pregnancy tests write nothing', () async {
    await seedGranted();
    dayEntries.entries = [
      _entry(
        '2026-06-02',
        tags: const ['atypical', 'pregnancy_positive', 'none'],
        updatedAt: grant.add(const Duration(hours: 1)),
      ),
    ];

    final report = await buildService().syncNow();

    expect(report.cervicalMucusSamplesWritten, 0);
    expect(report.ovulationTestSamplesWritten, 0);
    expect(platform.cervicalWrites, isEmpty);
    expect(platform.ovulationWrites, isEmpty);
  });

  test('a manual BBT observation writes its Celsius value', () async {
    await seedGranted();
    observations.observations = [
      _bbt('2026-06-02', value: 36.7, updatedAt: grant.add(const Duration(hours: 1))),
    ];

    final report = await buildService().syncNow();

    expect(report.basalBodyTemperatureSamplesWritten, 1);
    final write = platform.bbtWrites.single;
    expect(write.celsius, closeTo(36.7, 1e-9));
    expect(write.healthConnectMeasurementLocation, 'MEASUREMENT_LOCATION_UNKNOWN');
    expect(write.recordId, 'bbt-bbt-2026-06-02');
    expect(write.observedAt, isNull);
  });

  test('a manual BBT observation forwards observedAt to the write payload',
      () async {
    await seedGranted();
    final observed = DateTime.utc(2026, 6, 2, 6, 45);
    observations.observations = [
      _bbt(
        '2026-06-02',
        value: 36.7,
        observedAt: observed,
        updatedAt: grant.add(const Duration(hours: 1)),
      ),
    ];

    final report = await buildService().syncNow();

    expect(report.basalBodyTemperatureSamplesWritten, 1);
    final write = platform.bbtWrites.single;
    expect(write.observedAt, observed);
  });

  test('a Fahrenheit manual BBT observation is converted to Celsius',
      () async {
    await seedGranted();
    observations.observations = [
      _bbt(
        '2026-06-02',
        value: 98.6,
        unit: 'fahrenheit',
        updatedAt: grant.add(const Duration(hours: 1)),
      ),
    ];

    await buildService().syncNow();

    expect(platform.bbtWrites.single.celsius, closeTo(37.0, 1e-9));
  });

  test('a platform- or wearable-sourced BBT never overwrites a manual one',
      () async {
    await seedGranted();
    observations.observations = [
      _bbt('2026-06-02',
          source: ObservationSource.wearable,
          updatedAt: grant.add(const Duration(hours: 1))),
      _bbt('2026-06-03',
          source: ObservationSource.appleHealth,
          updatedAt: grant.add(const Duration(hours: 1))),
      _bbt('2026-06-04',
          source: ObservationSource.healthConnect,
          updatedAt: grant.add(const Duration(hours: 1))),
    ];

    final report = await buildService().syncNow();

    expect(report.basalBodyTemperatureSamplesWritten, 0);
    expect(platform.bbtWrites, isEmpty);
  });

  test('forward-only: pre-grant fertility/BBT is never written', () async {
    await seedGranted();
    dayEntries.entries = [
      _entry(
        '2026-05-30',
        tags: const ['creamy', 'ovulation_negative'],
        updatedAt: grant.subtract(const Duration(hours: 1)),
      ),
    ];
    observations.observations = [
      _bbt('2026-05-30',
          updatedAt: grant.subtract(const Duration(hours: 1))),
    ];

    final report = await buildService().syncNow();

    expect(report.cervicalMucusSamplesWritten, 0);
    expect(report.ovulationTestSamplesWritten, 0);
    expect(report.basalBodyTemperatureSamplesWritten, 0);
    expect(platform.cervicalWrites, isEmpty);
    expect(platform.ovulationWrites, isEmpty);
    expect(platform.bbtWrites, isEmpty);
  });

  test('one-way: health-store-sourced entries are never echoed back',
      () async {
    await seedGranted();
    dayEntries.entries = [
      _entry(
        '2026-06-02',
        tags: const ['creamy', 'ovulation_positive'],
        updatedAt: grant.add(const Duration(hours: 1)),
        source: DayEntrySource.healthkit,
      ),
    ];

    final report = await buildService().syncNow();

    expect(report.cervicalMucusSamplesWritten, 0);
    expect(platform.cervicalWrites, isEmpty);
  });

  test('an unavailable platform skips fertility/BBT without blocking',
      () async {
    await seedGranted();
    platform.fertilityResult = const HealthPlatformUnavailable();
    dayEntries.entries = [
      _entry(
        '2026-06-02',
        tags: const ['creamy', 'ovulation_positive'],
        updatedAt: grant.add(const Duration(hours: 1)),
      ),
    ];
    observations.observations = [
      _bbt('2026-06-02', updatedAt: grant.add(const Duration(hours: 1))),
    ];

    final report = await buildService().syncNow();

    expect(report.cervicalMucusSamplesWritten, 0);
    expect(report.ovulationTestSamplesWritten, 0);
    expect(report.basalBodyTemperatureSamplesWritten, 0);
    expect(
      report.blocked,
      isNull,
      reason: 'unavailable support must not block the pass',
    );
  });

  test('a failing fertility write blocks the pass and leaves the cursor',
      () async {
    await seedGranted();
    platform.fertilityResult = const HealthPlatformPermissionDenied();
    dayEntries.entries = [
      _entry(
        '2026-06-02',
        tags: const ['creamy'],
        updatedAt: grant.add(const Duration(hours: 1)),
      ),
    ];

    final report = await buildService().syncNow();

    expect(report.blocked, isA<HealthPlatformPermissionDenied>());
    expect(
      await settings.get(_cursorKey),
      '${grant.millisecondsSinceEpoch}',
      reason: 'a failed fertility write must not advance the cursor',
    );
  });
}
