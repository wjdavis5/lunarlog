/// Issue #238: `LocalHealthFlowWriteService`'s symptom half. Proves the
/// write service resolves a day entry's tags + graded pain into HealthKit
/// symptom samples, respects the guard/forward-only/one-way policies the
/// flow path already pins, reports the count, and treats a platform with no
/// symptom types (Health Connect) as a graceful skip rather than a
/// pass-blocking failure.
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
  FlowLevel flow = FlowLevel.none,
  List<String> tags = const [],
  DateTime? updatedAt,
  DayEntrySource source = DayEntrySource.manual,
}) => DayEntry(
  id: 'entry-$isoDay',
  profileId: _profileId,
  localDate: LocalDate.fromIso(isoDay),
  tz: _tz,
  flow: flow,
  tags: tags,
  updatedAt: updatedAt ?? DateTime.utc(2026, 6, 2),
  source: source,
);

Observation _pain(String day, String code, int intensity) => Observation(
  id: 'pain-$day-$code',
  dayEntryId: 'entry-$day',
  profileId: _profileId,
  localDate: LocalDate.fromIso(day),
  tz: _tz,
  category: ObservationCategory.pain,
  code: code,
  intensity: intensity,
  updatedAt: DateTime.utc(2026, 6, 2),
);

class _FakePlatform implements HealthPlatformStore {
  final List<HealthSymptomSamplesWrite> symptomWrites = [];
  HealthPlatformResult symptomResult = const HealthPlatformAllowed();
  HealthPlatformResult flowResult = const HealthPlatformAllowed();
  final List<HealthMenstrualFlowWrite> flowWrites = [];

  @override
  Future<bool> isAvailable() async => true;

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
  ) async {
    flowWrites.add(write);
    return flowResult;
  }

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
  ) async {
    symptomWrites.add(write);
    return symptomResult;
  }

  // Issue #228: this fake predates the fertility/measurement port methods;
  // the symptom tests never emit those, so they succeed trivially.
  @override
  Future<HealthPlatformResult> writeCervicalMucus(
    HealthCervicalMucusWrite write,
  ) async => const HealthPlatformAllowed();

  @override
  Future<HealthPlatformResult> writeOvulationTest(
    HealthOvulationTestWrite write,
  ) async => const HealthPlatformAllowed();

  @override
  Future<HealthPlatformResult> writeBasalBodyTemperature(
    HealthBasalBodyTemperatureWrite write,
  ) async => const HealthPlatformAllowed();

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

  test('a day with mapped tags writes one sample per symptom type, with the '
      'tag\'s graded severity and a stable record id', () async {
    await seedGranted();
    dayEntries.entries = [
      _entry(
        '2026-06-02',
        tags: const ['cramps', 'headache', 'running'],
        updatedAt: grant.add(const Duration(hours: 1)),
      ),
    ];
    observations.observations = [
      _pain('2026-06-02', 'cramps', 5),
      _pain('2026-06-02', 'headache', 2),
    ];

    final report = await buildService().syncNow();

    expect(report.symptomSamplesWritten, 2);
    expect(report.blocked, isNull);
    final write = platform.symptomWrites.single;
    expect(write.date, LocalDate.fromIso('2026-06-02'));
    final byType = {
      for (final sample in write.samples)
        sample.healthKitTypeIdentifier: sample,
    };
    expect(byType['abdominalCramps']!.severity, HealthSymptomSeverity.severe);
    expect(byType['headache']!.severity, HealthSymptomSeverity.moderate);
    expect(
      byType['abdominalCramps']!.recordId,
      'symptom-entry-2026-06-02-abdominalCramps',
    );
    expect(byType['headache']!.recordId, 'symptom-entry-2026-06-02-headache');
    // The unexported `running` tag contributes no sample.
    expect(byType.containsKey('running'), isFalse);
  });

  test('mood tags dedupe to one moodChanges sample', () async {
    await seedGranted();
    dayEntries.entries = [
      _entry(
        '2026-06-02',
        tags: const ['sad', 'anxious'],
        updatedAt: grant.add(const Duration(hours: 1)),
      ),
    ];

    final report = await buildService().syncNow();

    expect(report.symptomSamplesWritten, 1);
    final write = platform.symptomWrites.single;
    expect(write.samples.single.healthKitTypeIdentifier, 'moodChanges');
    expect(write.samples.single.severity, HealthSymptomSeverity.unspecified);
  });

  test(
    'a day whose tags are all unmapped writes no symptom samples at all',
    () async {
      await seedGranted();
      dayEntries.entries = [
        _entry(
          '2026-06-02',
          flow: FlowLevel.heavy,
          tags: const ['running', 'pad', 'calm'],
          updatedAt: grant.add(const Duration(hours: 1)),
        ),
      ];

      final report = await buildService().syncNow();

      expect(report.symptomSamplesWritten, 0);
      expect(platform.symptomWrites, isEmpty);
      // The flow write still happens for the same day.
      expect(report.samplesWritten, 1);
    },
  );

  test(
    'forward-only: symptom tags on a pre-grant day are never written',
    () async {
      await seedGranted();
      dayEntries.entries = [
        _entry(
          '2026-05-30',
          tags: const ['cramps'],
          updatedAt: grant.subtract(const Duration(hours: 1)),
        ),
      ];

      final report = await buildService().syncNow();

      expect(report.symptomSamplesWritten, 0);
      expect(platform.symptomWrites, isEmpty);
    },
  );

  test('one-way: health-store-sourced entries are never echoed back as '
      'symptoms', () async {
    await seedGranted();
    dayEntries.entries = [
      _entry(
        '2026-06-02',
        tags: const ['cramps'],
        updatedAt: grant.add(const Duration(hours: 1)),
        source: DayEntrySource.healthkit,
      ),
    ];

    final report = await buildService().syncNow();

    expect(report.symptomSamplesWritten, 0);
    expect(platform.symptomWrites, isEmpty);
  });

  test('a platform without symptom types skips them gracefully (Health '
      'Connect) and does not block the pass', () async {
    await seedGranted();
    platform.symptomResult = const HealthPlatformUnavailable();
    dayEntries.entries = [
      _entry(
        '2026-06-02',
        flow: FlowLevel.heavy,
        tags: const ['cramps'],
        updatedAt: grant.add(const Duration(hours: 1)),
      ),
    ];

    final report = await buildService().syncNow();

    expect(report.symptomSamplesWritten, 0);
    expect(report.samplesWritten, 1);
    expect(
      report.blocked,
      isNull,
      reason: 'unavailable symptom support must not block the pass',
    );
  });

  test(
    'a failing symptom write blocks the pass and leaves the cursor',
    () async {
      await seedGranted();
      platform.symptomResult = const HealthPlatformPermissionDenied();
      dayEntries.entries = [
        _entry(
          '2026-06-02',
          tags: const ['cramps'],
          updatedAt: grant.add(const Duration(hours: 1)),
        ),
      ];

      final report = await buildService().syncNow();

      expect(report.blocked, isA<HealthPlatformPermissionDenied>());
      expect(
        await settings.get(_cursorKey),
        '${grant.millisecondsSinceEpoch}',
        reason: 'a failed symptom write must not advance the cursor',
      );
    },
  );

  test(
    'symptom severity is calculated per day entry, not across the profile '
    'lifetime (Issue #934)',
    () async {
      await seedGranted();
      dayEntries.entries = [
        _entry(
          '2026-06-02',
          tags: const ['cramps'],
          updatedAt: grant.add(const Duration(hours: 1)),
        ),
        _entry(
          '2026-06-03',
          tags: const ['cramps'],
          updatedAt: grant.add(const Duration(hours: 2)),
        ),
      ];
      observations.observations = [
        _pain('2026-06-02', 'cramps', 4),
      ];

      final report = await buildService().syncNow();

      expect(report.symptomSamplesWritten, 2);
      expect(platform.symptomWrites, hasLength(2));
      final writesByDate = {
        for (final write in platform.symptomWrites) write.date: write,
      };
      final day1Cramps = writesByDate[LocalDate.fromIso('2026-06-02')]!
          .samples
          .singleWhere((s) => s.healthKitTypeIdentifier == 'abdominalCramps');
      final day2Cramps = writesByDate[LocalDate.fromIso('2026-06-03')]!
          .samples
          .singleWhere((s) => s.healthKitTypeIdentifier == 'abdominalCramps');

      expect(day1Cramps.severity, HealthSymptomSeverity.severe);
      expect(day2Cramps.severity, HealthSymptomSeverity.unspecified);
    },
  );
}

