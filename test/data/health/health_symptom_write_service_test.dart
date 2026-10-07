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
  bool writesCycleStart = true;

  @override
  Future<bool> isAvailable() async => true;

  /// Issue #1555: HealthKit grants symptom types one by one. Granted in
  /// full unless a test says otherwise.
  HealthPermissionStatus permission = HealthPermissionStatus.granted;
  Set<String> grantedTypes = const {};

  @override
  Future<HealthPermissionStatus> permissionStatus() async => permission;

  @override
  Future<Set<String>> grantedWriteTypes() async => grantedTypes;

  // Issue #1491: the read-side probe is the background import's alone. A
  // write pass that read it would be gating writes on a read permission.
  @override
  Future<HealthPermissionStatus> importPermissionStatus() =>
      throw StateError('a write pass must never read the import probe');

  // Issue #1515: what the store discloses about reads is the status line's
  // question, and the import's request is the import's. A write pass that
  // touched either would be deciding a write on the read side.
  @override
  bool get readAccessDisclosed =>
      throw StateError('a write pass must never ask about read access');

  @override
  Future<bool> importReachesPastData() =>
      throw StateError('a write pass must never ask about read access');

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
  Future<HealthPlatformResult> requestImportAuthorization(
    HealthGuardFacts facts,
  ) =>
      throw StateError('a write pass must never raise the import\'s request');

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

  // A new one for each test (Issue #1581): what the ledger holds now
  // decides what is sent, so one shared by the whole file made a later
  // test's day read as already written.
  late FakeHealthExportLedger ledger;
  late DateTime clock;

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
    now: () => clock,
  );

  final grant = DateTime.utc(2026, 6, 1, 12);

  Future<void> seedGranted() async {
    await settings.set(_bindingKey, _profileId);
    await settings.set(_cursorKey, '${grant.millisecondsSinceEpoch}');
  }

  setUp(() {
    clock = DateTime.utc(2026, 6, 1, 12);
    ledger = FakeHealthExportLedger();
    platform = _FakePlatform();
    settings = FakeSettingsStore();
    dayEntries = _FakeDayEntries();
    observations = _FakeObservations();
  });

  tearDown(() => settings.close());

  // Issue #1581: what was written is remembered sample by sample, so a
  // pass with nothing changed sends nothing, and one new tag does not make
  // the pass forget the others were written.
  test('a pass with nothing changed sends no symptom again, in this session '
      'or the next', () async {
    await seedGranted();
    dayEntries.entries = [
      _entry(
        '2026-06-02',
        tags: const ['cramps', 'headache'],
        updatedAt: grant.add(const Duration(hours: 1)),
      ),
    ];
    final service = buildService();
    expect((await service.syncNow()).symptomSamplesWritten, 2);

    for (final again in [service, buildService()]) {
      final report = await again.syncNow();
      expect(report.blocked, isNull);
      expect(report.symptomSamplesWritten, 0);
      expect(platform.symptomWrites, hasLength(1));
    }
  });

  test('a failed symptom write is sent again on the next pass', () async {
    await seedGranted();
    dayEntries.entries = [
      _entry(
        '2026-06-02',
        tags: const ['cramps'],
        updatedAt: grant.add(const Duration(hours: 1)),
      ),
    ];
    platform.symptomResult = const HealthPlatformResult.failed('boom');
    final service = buildService();
    expect((await service.syncNow()).blocked, isA<HealthPlatformFailed>());

    platform.symptomResult = const HealthPlatformResult.allowed();
    final report = await service.syncNow();
    expect(report.blocked, isNull);
    expect(report.symptomSamplesWritten, 1);
    expect(platform.symptomWrites, hasLength(2));
  });

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
    'a failing symptom write is reported, and its samples are not '
    'remembered as written',
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
      expect(report.symptomSamplesWritten, 0);
      expect(
        ledger.rows.map((row) => row.recordId),
        isNot(contains('symptom-entry-2026-06-02-abdominalCramps')),
      );
    },
  );

  // Issue #1581, with #1555: HealthKit grants symptom types one by one.
  test(
    'with one symptom type off, only the samples sent are remembered, and '
    'the other is not sent when its type is switched on later',
    () async {
      await seedGranted();
      platform.permission = HealthPermissionStatus.writingSome;
      platform.grantedTypes = {'menstrualFlow', 'headache'};
      final saved = grant.add(const Duration(hours: 1));
      dayEntries.entries = [
        _entry(
          '2026-06-02',
          tags: const ['cramps', 'headache'],
          updatedAt: saved,
        ),
      ];
      clock = saved.add(const Duration(minutes: 1));
      final service = buildService();

      final report = await service.syncNow();

      expect(report.symptomSamplesWritten, 1);
      expect(
        platform.symptomWrites.single.samples
            .map((sample) => sample.healthKitTypeIdentifier),
        ['headache'],
      );
      final remembered = ledger.rows.map((row) => row.recordId);
      expect(remembered, contains('symptom-entry-2026-06-02-headache'));
      expect(
        remembered,
        isNot(contains('symptom-entry-2026-06-02-abdominalCramps')),
      );

      // Cramps was logged while its type was off: it stays out.
      platform.permission = HealthPermissionStatus.granted;
      clock = saved.add(const Duration(minutes: 2));
      final after = await service.syncNow();
      expect(after.symptomSamplesWritten, 0);
      expect(platform.symptomWrites, hasLength(1));

      // Saved again with the type on, both go: one is new, one is newer.
      dayEntries.entries = [
        _entry(
          '2026-06-02',
          tags: const ['cramps', 'headache'],
          updatedAt: saved.add(const Duration(minutes: 3)),
        ),
      ];
      clock = saved.add(const Duration(minutes: 4));
      final later = await service.syncNow();
      expect(later.symptomSamplesWritten, 2);
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

