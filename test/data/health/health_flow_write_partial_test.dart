/// Issue #1555: a write type that is off is skipped, never a reason to stop.
///
/// Health Connect shows five write permissions as five switches and Apple
/// Health seventeen, and the person may decline any of them. Before #1555
/// one switch off read as "denied", and the write pass stopped before
/// writing anything: someone who declined Basal body temperature, or Acne,
/// had none of her periods written.
///
/// These tests run `LocalHealthFlowWriteService` against a store with a
/// switch per type ([_SwitchedStore]), which answers each write and each
/// delete the way the two native halves do: for the record's own type.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_flow_write_service.dart';
import 'package:lunarlog/data/health/health_record_ids.dart';
import 'package:lunarlog/domain/health/health_export_ledger.dart';
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

const _profileId = 'profile1';
const _ownerId = 'owner-user';
const _tz = 'America/New_York';
const _bindingKey = SettingsKeys.healthStoreProfileId;
const _cursorKey = SettingsKeys.healthSyncWrittenThroughMs;

// Health Connect's five write switches, by the record types each governs.
// The period record needs the permission the flow record needs.
const _menstruation = {'MenstruationFlowRecord', 'MenstruationPeriodRecord'};
const _basalBodyTemperature = {'BasalBodyTemperatureRecord'};

// Three of Apple Health's seventeen.
const _flow = {'menstrualFlow'};
const _cramps = {'abdominalCramps'};
const _acne = {'acne'};

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

/// The id of the day entry for [isoDay]. No dash, as a real id (a ULID)
/// has none: that is how a day's own record id is told from the others.
String _entryId(String isoDay) => 'day${isoDay.replaceAll('-', '')}';

String _bbtObservationId(String isoDay) => 'obs${isoDay.replaceAll('-', '')}';

String _periodId(String firstIsoDay) =>
    healthPeriodRecordId(_profileId, LocalDate.fromIso(firstIsoDay));

DayEntry _entry(
  String isoDay,
  FlowLevel flow,
  DateTime updatedAt, {
  List<String> tags = const [],
}) =>
    DayEntry(
      id: _entryId(isoDay),
      profileId: _profileId,
      localDate: LocalDate.fromIso(isoDay),
      tz: _tz,
      flow: flow,
      tags: tags,
      updatedAt: updatedAt,
    );

Observation _bbt(String isoDay, DateTime updatedAt) => Observation(
      id: _bbtObservationId(isoDay),
      dayEntryId: _entryId(isoDay),
      profileId: _profileId,
      localDate: LocalDate.fromIso(isoDay),
      tz: _tz,
      category: ObservationCategory.bbt,
      valueNum: 36.6,
      unit: 'celsius',
      updatedAt: updatedAt,
      // A reading with its own time, so the write never depends on the
      // 07:00 default being in the past.
      observedAt: updatedAt,
    );

Observation _spotting(String isoDay, DateTime updatedAt) => Observation(
      id: 'spot${isoDay.replaceAll('-', '')}',
      dayEntryId: _entryId(isoDay),
      profileId: _profileId,
      localDate: LocalDate.fromIso(isoDay),
      tz: _tz,
      category: ObservationCategory.spotting,
      code: 'spotting',
      updatedAt: updatedAt,
    );

/// A health store with a switch for each type, as both real stores have.
///
/// It answers the way the two native halves do after Issue #1555. A write
/// looks at its own type: off answers "this type is off" and nothing is
/// written. A delete removes the records whose type is on, and answers
/// "this type is off" when a type its ids can be in is off, those types
/// being the ones the channel names with the call
/// ([healthStoreTypesForRecordIds]), or every type when it names none.
class _SwitchedStore implements HealthPlatformStore {
  _SwitchedStore.android() : _android = true;
  _SwitchedStore.iphone() : _android = false;

  final bool _android;

  /// The types whose switch is off: Health Connect record class names on
  /// Android, HealthKit case names on an iPhone.
  final Set<String> off = {};

  /// What the store holds: record id to the type it was written as.
  final Map<String, String> held = {};

  /// The ids of everything the store holds.
  Set<String> get heldIds => held.keys.toSet();

  final List<List<String>> deleteCalls = [];
  int authCalls = 0;
  int writeCalls = 0;

  /// When set, the status the store reports whatever its switches say (for
  /// "not yet asked"). Cleared by an answered request.
  HealthPermissionStatus? status;

  /// When set, every delete answers this (a failure that is not about a
  /// type being off).
  HealthPlatformResult? deleteAnswer;

  void switchOff(Set<String> types) => off.addAll(types);

  void switchOn(Set<String> types) => off.removeAll(types);

  @override
  Future<HealthPermissionStatus> permissionStatus() async =>
      status ??
      (off.isEmpty
          ? HealthPermissionStatus.granted
          : HealthPermissionStatus.partial);

  HealthPlatformResult _write(String type, String recordId) {
    writeCalls++;
    if (off.contains(type)) return const HealthPlatformResult.typeOff();
    held[recordId] = type;
    return const HealthPlatformResult.allowed();
  }

  @override
  Future<HealthPlatformResult> writeMenstrualFlow(
    HealthMenstrualFlowWrite write,
  ) async =>
      _write(_android ? 'MenstruationFlowRecord' : 'menstrualFlow',
          write.recordId);

  @override
  Future<HealthPlatformResult> writeIntermenstrualBleeding(
    HealthIntermenstrualBleedingWrite write,
  ) async =>
      _write(
        _android ? 'IntermenstrualBleedingRecord' : 'intermenstrualBleeding',
        write.recordId,
      );

  /// HealthKit has no period record.
  @override
  Future<HealthPlatformResult> writeMenstrualPeriod(
    HealthMenstrualPeriodWrite write,
  ) async =>
      _android
          ? _write('MenstruationPeriodRecord', write.recordId)
          : const HealthPlatformResult.unavailable();

  /// Health Connect has no symptom types. On an iPhone one call carries
  /// every symptom type of the day: the ones that are on are written, and
  /// the answer is "this type is off" only when none was.
  @override
  Future<HealthPlatformResult> writeSymptomSamples(
    HealthSymptomSamplesWrite write,
  ) async {
    if (_android) return const HealthPlatformResult.unavailable();
    writeCalls++;
    var written = 0;
    for (final sample in write.samples) {
      if (off.contains(sample.healthKitTypeIdentifier)) continue;
      held[sample.recordId] = sample.healthKitTypeIdentifier;
      written++;
    }
    return written == 0
        ? const HealthPlatformResult.typeOff()
        : const HealthPlatformResult.allowed();
  }

  @override
  Future<HealthPlatformResult> writeCervicalMucus(
    HealthCervicalMucusWrite write,
  ) async =>
      _write(_android ? 'CervicalMucusRecord' : 'cervicalMucusQuality',
          write.recordId);

  @override
  Future<HealthPlatformResult> writeOvulationTest(
    HealthOvulationTestWrite write,
  ) async =>
      _write(_android ? 'OvulationTestRecord' : 'ovulationTestResult',
          write.recordId);

  @override
  Future<HealthPlatformResult> writeBasalBodyTemperature(
    HealthBasalBodyTemperatureWrite write,
  ) async =>
      _write(
        _android ? 'BasalBodyTemperatureRecord' : 'basalBodyTemperature',
        write.recordId,
      );

  @override
  Future<HealthPlatformResult> deleteRecords(
    HealthGuardFacts facts,
    List<String> recordIds,
  ) async {
    deleteCalls.add(List.of(recordIds));
    final failure = deleteAnswer;
    if (failure != null) return failure;
    for (final recordId in recordIds) {
      if (!off.contains(held[recordId])) held.remove(recordId);
    }
    final types = healthStoreTypesForRecordIds(recordIds);
    final toCover = types == null
        ? null
        : (_android ? types.healthConnect : types.healthKit);
    final uncovered =
        toCover == null ? off.isNotEmpty : toCover.any(off.contains);
    return uncovered
        ? const HealthPlatformResult.typeOff()
        : const HealthPlatformResult.allowed();
  }

  @override
  Future<HealthPlatformResult> requestWriteAuthorization(
    HealthGuardFacts facts,
  ) async {
    authCalls++;
    status = null;
    return const HealthPlatformResult.allowed();
  }

  @override
  Future<HealthPlatformResult> bindProfile(HealthGuardFacts facts) async =>
      const HealthPlatformResult.allowed();

  @override
  Future<void> unbindProfile() async {}

  @override
  Future<bool> isAvailable() async => true;

  // A write pass asks nothing about reading.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
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

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => entries;

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
  final grant = DateTime.utc(2026, 6, 1, 12);
  final first = grant.add(const Duration(hours: 1));
  final second = grant.add(const Duration(hours: 3));
  final third = grant.add(const Duration(hours: 5));

  late _SwitchedStore store;
  late FakeSettingsStore settings;
  late _FakeDayEntries dayEntries;
  late _FakeObservations observations;
  late FakeHealthExportLedger ledger;

  /// A service over the same store, settings and ledger: building a second
  /// one is a relaunch, with nothing left in memory.
  LocalHealthFlowWriteService buildService() => LocalHealthFlowWriteService(
        platform: store,
        binding: HealthSyncBinding(settings),
        minorBindingAllowed: false,
        profiles: _FakeProfiles(),
        dayEntries: dayEntries,
        observations: observations,
        settings: settings,
        ledger: ledger,
        guardiansForProfile: (_) async => [_ownerRow()],
        signedInUserId: () => _ownerId,
        now: () => DateTime.utc(2026, 6, 2, 12),
      );

  Future<void> bind() => settings.set(_bindingKey, _profileId);

  /// Binds the profile with sync already granted at [grant].
  Future<void> seedGranted() async {
    await bind();
    await settings.set(_cursorKey, '${grant.millisecondsSinceEpoch}');
  }

  Future<String?> cursor() => settings.get(_cursorKey);

  String cursorAt(DateTime instant) => '${instant.millisecondsSinceEpoch}';

  /// The ledger's rows as `<kind> <record id>`.
  Set<String> ledgerRows() => {
        for (final row in ledger.rows) '${row.kind.name} ${row.recordId}',
      };

  void useStore(_SwitchedStore value) => store = value;

  setUp(() {
    store = _SwitchedStore.android();
    settings = FakeSettingsStore();
    dayEntries = _FakeDayEntries();
    observations = _FakeObservations();
    ledger = FakeHealthExportLedger();
  });

  tearDown(() => settings.close());

  group('Android: one of the five write permissions is off', () {
    // The case in the issue, as seen on an emulator: four of five writes
    // on, Basal body temperature off, flow logged, nothing written.
    test('Basal body temperature off: her period is written, the pass does '
        'not fail, and the cursor moves on', () async {
      await seedGranted();
      store.switchOff(_basalBodyTemperature);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, first, tags: const ['creamy']),
      ];
      observations.observations = [_bbt('2026-06-02', second)];

      final report = await buildService().syncNow();

      expect(report.blocked, isNull, reason: 'a type that is off is skipped');
      expect(report.samplesWritten, 1);
      expect(report.cervicalMucusSamplesWritten, 1);
      expect(report.periodRecordsWritten, 1);
      expect(report.basalBodyTemperatureSamplesWritten, 0,
          reason: 'a skipped record is not counted as written');
      expect(store.heldIds, {
        _entryId('2026-06-02'),
        healthCervicalMucusRecordId(_entryId('2026-06-02')),
        _periodId('2026-06-02'),
      });
      // The cursor moves past the skipped row too.
      expect(await cursor(), cursorAt(second));
      // Nothing is remembered for a record that was not written.
      expect(
        ledgerRows(),
        isNot(contains(
          'bbt ${healthBbtRecordId(_bbtObservationId('2026-06-02'))}',
        )),
      );
      expect(store.authCalls, 0, reason: 'this change asks for nothing');
    });

    // Every one of the five in turn: a day with flow, discharge, an
    // ovulation test and a temperature, and spotting on a later day.
    final entryId = _entryId('2026-06-02');
    final recordsBySwitch = <String, Set<String>>{
      'Menstruation': {entryId, _periodId('2026-06-02')},
      'Spotting': {'spot20260610'},
      'Cervical mucus': {healthCervicalMucusRecordId(entryId)},
      'Ovulation test': {
        healthOvulationRecordId(entryId, 'luteinizingHormoneSurge'),
      },
      'Basal body temperature': {
        healthBbtRecordId(_bbtObservationId('2026-06-02')),
      },
    };
    const typesBySwitch = <String, Set<String>>{
      'Menstruation': _menstruation,
      'Spotting': {'IntermenstrualBleedingRecord'},
      'Cervical mucus': {'CervicalMucusRecord'},
      'Ovulation test': {'OvulationTestRecord'},
      'Basal body temperature': _basalBodyTemperature,
    };
    for (final off in typesBySwitch.keys) {
      test('$off off on its own: its records are left out and not '
          'remembered, and every other type is written', () async {
        await seedGranted();
        store.switchOff(typesBySwitch[off]!);
        dayEntries.entries = [
          _entry('2026-06-02', FlowLevel.medium, first,
              tags: const ['creamy', 'ovulation_positive']),
          _entry('2026-06-10', FlowLevel.notBleeding, first),
        ];
        observations.observations = [
          _bbt('2026-06-02', first),
          _spotting('2026-06-10', second),
        ];

        final report = await buildService().syncNow();

        expect(report.blocked, isNull);
        expect(store.heldIds, {
          for (final records in recordsBySwitch.entries)
            if (records.key != off) ...records.value,
        });
        expect(await cursor(), cursorAt(second));
        expect(
          {for (final row in ledger.rows) row.recordId}
              .intersection(recordsBySwitch[off]!),
          isEmpty,
        );
      });
    }

    test('a type switched on later is written from then on, and the days '
        'skipped while it was off are not backfilled', () async {
      await seedGranted();
      store.switchOff(_basalBodyTemperature);
      final service = buildService();
      dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, first)];
      observations.observations = [_bbt('2026-06-02', first)];
      await service.syncNow();

      store.switchOn(_basalBodyTemperature);
      final unchanged = await service.syncNow();
      expect(unchanged.basalBodyTemperatureSamplesWritten, 0);
      expect(
        store.heldIds,
        isNot(contains(healthBbtRecordId(_bbtObservationId('2026-06-02')))),
        reason: 'forward-only: the cursor had moved past that reading',
      );

      observations.observations = [
        _bbt('2026-06-02', first),
        _bbt('2026-06-03', second),
      ];
      final later = await service.syncNow();
      expect(later.blocked, isNull);
      expect(later.basalBodyTemperatureSamplesWritten, 1);
      expect(
        store.heldIds,
        contains(healthBbtRecordId(_bbtObservationId('2026-06-03'))),
      );
    });

    test('Menstruation off: no flow record and no period record, and the '
        'other types are still written', () async {
      await seedGranted();
      store.switchOff(_menstruation);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, first, tags: const ['creamy']),
      ];

      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      expect(report.samplesWritten, 0);
      expect(report.periodRecordsWritten, 0);
      expect(report.cervicalMucusSamplesWritten, 1);
      expect(
        store.heldIds,
        {healthCervicalMucusRecordId(_entryId('2026-06-02'))},
      );
      expect(await cursor(), cursorAt(first));
      expect(ledgerRows(), {
        'entry ${healthCervicalMucusRecordId(_entryId('2026-06-02'))}',
      });
    });

    test('Menstruation switched on later: a day whose flow was never '
        'written gets no period record either, until a day of the episode '
        'is written', () async {
      await seedGranted();
      store.switchOff(_menstruation);
      final service = buildService();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, first, tags: const ['creamy']),
      ];
      await service.syncNow();

      // On again, nothing logged since. The day has a cervical-mucus
      // record in the store and no flow record: that is not "a day of the
      // episode is in the store".
      store.switchOn(_menstruation);
      final unchanged = await service.syncNow();
      expect(unchanged.blocked, isNull);
      expect(unchanged.periodRecordsWritten, 0);
      expect(
        store.heldIds,
        {healthCervicalMucusRecordId(_entryId('2026-06-02'))},
      );

      // The next day of the same period is logged: it is written, and the
      // period record with it, from the episode's true first day.
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, first, tags: const ['creamy']),
        _entry('2026-06-03', FlowLevel.medium, second),
      ];
      final later = await service.syncNow();
      expect(later.samplesWritten, 1);
      expect(later.periodRecordsWritten, 1);
      expect(store.heldIds, containsAll([
        _entryId('2026-06-03'),
        _periodId('2026-06-02'),
      ]));
      expect(store.heldIds, isNot(contains(_entryId('2026-06-02'))));
    });
  });

  group('iPhone: one of the seventeen write types is off', () {
    setUp(() => useStore(_SwitchedStore.iphone()));

    test('Acne off: her period and her other symptoms are written',
        () async {
      await seedGranted();
      store.switchOff(_acne);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy, first,
            tags: const ['cramps', 'acne']),
      ];

      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      expect(report.samplesWritten, 1);
      expect(store.heldIds, {
        _entryId('2026-06-02'),
        healthSymptomRecordId(_entryId('2026-06-02'), 'abdominalCramps'),
      });
      expect(await cursor(), cursorAt(first));
    });

    test('every symptom type of the day off: none is counted or '
        'remembered, the flow is written, and nothing fails', () async {
      await seedGranted();
      store
        ..switchOff(_acne)
        ..switchOff(_cramps);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.heavy, first,
            tags: const ['cramps', 'acne']),
      ];

      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      expect(report.symptomSamplesWritten, 0);
      expect(report.samplesWritten, 1);
      expect(store.heldIds, {_entryId('2026-06-02')});
      expect(ledgerRows(), {'entry ${_entryId('2026-06-02')}'});
      expect(await cursor(), cursorAt(first));
    });

    test('spotting off: the marker is skipped and not remembered, so a '
        'later tombstone has nothing to look for', () async {
      await seedGranted();
      store.switchOff(const {'intermenstrualBleeding'});
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.notBleeding, first),
      ];
      observations.observations = [_spotting('2026-06-02', first)];

      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      expect(report.samplesWritten, 0);
      expect(store.held, isEmpty);
      expect(
        ledger.rows.where((row) => row.kind == HealthExportLedgerKind.spotting),
        isEmpty,
      );
    });
  });

  group('asking: some types on is an answer, not a refusal', () {
    test('found partly granted on a first pass, the cursor is stamped and '
        'no request is raised', () async {
      await bind();
      store.switchOff(_basalBodyTemperature);
      dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, first)];

      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      expect(report.authorizationRequested, isFalse);
      expect(store.authCalls, 0);
      expect(await cursor(), isNot(anyOf(isNull, isEmpty)));
    });

    test('a request answered with some types on stamps the cursor: the pass '
        'goes ahead on the next change', () async {
      await bind();
      store
        ..status = HealthPermissionStatus.notAsked
        ..switchOff(_basalBodyTemperature);

      final report = await buildService().syncNow();

      expect(store.authCalls, 1);
      expect(report.authorizationRequested, isTrue);
      expect(report.blocked, isNull,
          reason: 'partly granted is not "the writes are still off"');
      expect(await cursor(), isNot(anyOf(isNull, isEmpty)));
    });

    test('no write type on is still denied, and still stops the pass',
        () async {
      await seedGranted();
      store.status = HealthPermissionStatus.denied;
      dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, first)];

      final report = await buildService().syncNow();

      expect(report.blocked, isA<HealthPlatformPermissionDenied>());
      expect(store.writeCalls, 0);
    });
  });

  group('a removal whose type is off is kept and tried again', () {
    test('a cleared reading stays in the ledger while Basal body '
        'temperature is off, and is removed once it is back on', () async {
      await seedGranted();
      final bbtId = healthBbtRecordId(_bbtObservationId('2026-06-02'));
      dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, first)];
      observations.observations = [_bbt('2026-06-02', first)];
      await buildService().syncNow();
      expect(store.heldIds, contains(bbtId));

      // The type is switched off, then the reading is cleared.
      store.switchOff(_basalBodyTemperature);
      observations.observations = const [];
      final service = buildService();
      final report = await service.syncNow();

      expect(report.blocked, isNull, reason: 'the pass must not fail');
      expect(store.deleteCalls, [
        [bbtId],
      ]);
      expect(store.heldIds, contains(bbtId), reason: 'still in the store');
      expect(ledgerRows(), contains('bbt $bbtId'),
          reason: 'and not forgotten');

      // Still off: tried again, still kept.
      await service.syncNow();
      expect(store.deleteCalls, hasLength(2));
      expect(ledgerRows(), contains('bbt $bbtId'));

      // Back on, after a relaunch: the ledger alone carries the removal.
      store.switchOn(_basalBodyTemperature);
      final after = await buildService().syncNow();

      expect(after.blocked, isNull);
      expect(store.heldIds, isNot(contains(bbtId)));
      expect(ledgerRows(), isNot(contains('bbt $bbtId')));
    });

    test('a symptom taken off its day stays owed while its type is off, and '
        'is removed once it is back on although the day is never edited '
        'again', () async {
      useStore(_SwitchedStore.iphone());
      await seedGranted();
      final entryId = _entryId('2026-06-02');
      final crampsId = healthSymptomRecordId(entryId, 'abdominalCramps');
      final headacheId = healthSymptomRecordId(entryId, 'headache');
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, first,
            tags: const ['cramps', 'headache']),
      ];
      await buildService().syncNow();

      // Cramps is switched off in Apple Health; then she removes the tag.
      store.switchOff(_cramps);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, second,
            tags: const ['headache']),
      ];
      final service = buildService();
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(await cursor(), cursorAt(second),
          reason: 'the cursor moves past the day');
      expect(store.heldIds, contains(crampsId));
      expect(ledgerRows(), {
        'entry $entryId',
        'entry $headacheId',
        'removalOwed $crampsId',
      });

      // The day is not eligible any more: the cursor is past it. The owed
      // removal is tried again on every pass all the same.
      final calls = store.deleteCalls.length;
      await service.syncNow();
      expect(store.deleteCalls, hasLength(calls + 1));
      expect(store.deleteCalls.last, [crampsId]);
      expect(ledgerRows(), contains('removalOwed $crampsId'));

      // Back on, after a relaunch.
      store.switchOn(_cramps);
      final relaunched = buildService();
      final after = await relaunched.syncNow();

      expect(after.blocked, isNull);
      expect(store.heldIds, isNot(contains(crampsId)));
      expect(ledgerRows(), {'entry $entryId', 'entry $headacheId'});

      // And once it is gone it is not asked for again.
      final settled = store.deleteCalls.length;
      await relaunched.syncNow();
      expect(store.deleteCalls, hasLength(settled));
    });

    test('a day changed to "not bleeding" while its flow type is off keeps '
        'its record owed, and loses it once the type is back on', () async {
      useStore(_SwitchedStore.iphone());
      await seedGranted();
      final entryId = _entryId('2026-06-02');
      dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, first)];
      await buildService().syncNow();
      expect(store.heldIds, {entryId});

      store.switchOff(_flow);
      dayEntries.entries = [_entry('2026-06-02', FlowLevel.notBleeding, second)];
      final report = await buildService().syncNow();

      expect(report.blocked, isNull);
      expect(report.samplesReconciled, 0, reason: 'nothing was removed');
      expect(await cursor(), cursorAt(second));
      expect(store.heldIds, {entryId});
      expect(ledgerRows(), {'removalOwed $entryId'});

      store.switchOn(_flow);
      final after = await buildService().syncNow();

      expect(after.blocked, isNull);
      expect(store.held, isEmpty);
      expect(ledgerRows(), isEmpty);
    });

    test('a day with no flow that was never written owes nothing, flow type '
        'off or on', () async {
      useStore(_SwitchedStore.iphone());
      await seedGranted();
      store.switchOff(_flow);
      dayEntries.entries = [_entry('2026-06-02', FlowLevel.notBleeding, first)];

      final service = buildService();
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(ledgerRows(), isEmpty);
      final calls = store.deleteCalls.length;
      await service.syncNow();
      expect(store.deleteCalls, hasLength(calls),
          reason: 'nothing is owed, so nothing is retried');
    });

    test('a period record whose days are gone stays remembered while '
        'Menstruation is off, and is removed once it is back on', () async {
      await seedGranted();
      final periodId = _periodId('2026-06-02');
      dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, first)];
      final service = buildService();
      await service.syncNow();
      expect(store.heldIds, contains(periodId));

      store.switchOff(_menstruation);
      dayEntries.entries = const [];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(store.heldIds, contains(periodId));
      expect(ledgerRows(), contains('period $periodId'));

      store.switchOn(_menstruation);
      final after = await service.syncNow();

      expect(after.blocked, isNull);
      expect(store.heldIds, isNot(contains(periodId)));
      expect(ledgerRows(), isNot(contains('period $periodId')));
    });

    test('with one type left off for good, a removal of another type is '
        'still acknowledged: nothing piles up', () async {
      await seedGranted();
      store.switchOff(_basalBodyTemperature);
      final entryId = _entryId('2026-06-02');
      final mucusId = healthCervicalMucusRecordId(entryId);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, first, tags: const ['creamy']),
      ];
      final service = buildService();
      await service.syncNow();
      expect(store.heldIds, contains(mucusId));

      dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, second)];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(store.deleteCalls, [
        [mucusId],
      ]);
      expect(store.heldIds, isNot(contains(mucusId)));
      expect(ledgerRows(), isNot(contains('entry $mucusId')));
      expect(ledgerRows(), isNot(contains('removalOwed $mucusId')));

      await service.syncNow();
      expect(store.deleteCalls, hasLength(1),
          reason: 'the removal was acknowledged, so it is not repeated');
    });

    test('a symptom put back on its day while its removal is owed is '
        'written, not removed', () async {
      useStore(_SwitchedStore.iphone());
      await seedGranted();
      final entryId = _entryId('2026-06-02');
      final crampsId = healthSymptomRecordId(entryId, 'abdominalCramps');
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, first, tags: const ['cramps']),
      ];
      final service = buildService();
      await service.syncNow();
      store.switchOff(_cramps);
      dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, second)];
      await service.syncNow();
      expect(ledgerRows(), contains('removalOwed $crampsId'));

      // Back on, and she adds the tag again.
      store.switchOn(_cramps);
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, third, tags: const ['cramps']),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(store.heldIds, contains(crampsId));
      expect(ledgerRows(), {'entry $entryId', 'entry $crampsId'});
      final calls = store.deleteCalls.length;
      await service.syncNow();
      expect(store.deleteCalls, hasLength(calls));
      expect(store.heldIds, contains(crampsId));
    });

    test('a symptom put back while its type is still off stays remembered: '
        'the store still holds the old sample', () async {
      useStore(_SwitchedStore.iphone());
      await seedGranted();
      final entryId = _entryId('2026-06-02');
      final crampsId = healthSymptomRecordId(entryId, 'abdominalCramps');
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, first, tags: const ['cramps']),
      ];
      final service = buildService();
      await service.syncNow();
      store.switchOff(_cramps);
      dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, second)];
      await service.syncNow();

      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, third, tags: const ['cramps']),
      ];
      final report = await service.syncNow();

      expect(report.blocked, isNull);
      expect(report.symptomSamplesWritten, 0);
      expect(ledgerRows(), {'entry $entryId', 'entry $crampsId'});
    });

    test('a removal that fails for another reason still blocks the pass, '
        'owed or not', () async {
      useStore(_SwitchedStore.iphone());
      await seedGranted();
      final entryId = _entryId('2026-06-02');
      final crampsId = healthSymptomRecordId(entryId, 'abdominalCramps');
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, first, tags: const ['cramps']),
      ];
      final service = buildService();
      await service.syncNow();
      store.switchOff(_cramps);
      dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, second)];
      await service.syncNow();

      store.deleteAnswer = const HealthPlatformResult.failed('boom');
      final failed = await service.syncNow();
      expect(failed.blocked, isA<HealthPlatformFailed>());
      expect(ledgerRows(), contains('removalOwed $crampsId'));

      store
        ..deleteAnswer = null
        ..switchOn(_cramps);
      final after = await service.syncNow();
      expect(after.blocked, isNull);
      expect(ledgerRows(), {'entry $entryId'});
    });

    test('unbinding forgets what was owed with the rest of the ledger',
        () async {
      useStore(_SwitchedStore.iphone());
      await seedGranted();
      dayEntries.entries = [
        _entry('2026-06-02', FlowLevel.medium, first, tags: const ['cramps']),
      ];
      final service = buildService();
      await service.syncNow();
      store.switchOff(_cramps);
      dayEntries.entries = [_entry('2026-06-02', FlowLevel.medium, second)];
      await service.syncNow();
      expect(ledgerRows().where((row) => row.startsWith('removalOwed')),
          isNotEmpty);

      await service.onUnbound();
      expect(ledger.rows, isEmpty);

      // Bound again: nothing of the old binding is retried.
      await seedGranted();
      dayEntries.entries = const [];
      final calls = store.deleteCalls.length;
      await service.syncNow();
      expect(store.deleteCalls, hasLength(calls));
    });
  });
}
