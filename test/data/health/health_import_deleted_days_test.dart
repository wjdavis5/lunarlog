/// Issue #1561 end to end: the health import over the real repositories and
/// a real database, so that what the storage layer remembers when she
/// deletes a row and what the import does with it are tested together.
///
/// `health_import_service_test.dart` pins the import's rules against test
/// doubles, and `health_import_deletions_storage_test.dart` pins what the
/// storage layer remembers. Neither would notice the two disagreeing about
/// a name or a source, which is how the first design missed the way the day
/// sheet removes an entry.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/health/health_import_service.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/health/health_deviation.dart';
import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';

const _profileId = 'p1';
const _ownerId = 'owner-user';
const _tz = 'America/New_York';

class _Platform implements HealthPlatformStore {
  @override
  Future<HealthPlatformResult> bindProfile(HealthGuardFacts facts) async =>
      const HealthPlatformAllowed();

  @override
  Future<HealthPlatformResult> requestImportAuthorization(
    HealthGuardFacts facts,
  ) async =>
      const HealthPlatformAllowed();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The health store: whatever [samples] holds is what every read returns,
/// as a whole-history read does.
class _Store implements HealthImportSource {
  List<HealthFlowSample> samples = [];

  @override
  Future<HealthReadResult> readMenstrualFlowPage(
    HealthGuardFacts facts, {
    required DateTime start,
    required DateTime end,
    required int pageSize,
    String? cursor,
  }) async =>
      HealthReadResult.samples(samples);

  @override
  Future<HealthDeviationReadResult> readCycleDeviations(
    HealthGuardFacts facts, {
    required DateTime start,
    required DateTime end,
  }) async =>
      const HealthDeviationReadResult.unavailable();

  @override
  Future<HealthPlatformResult> commitImport(
    HealthGuardFacts facts,
    String commitToken,
  ) async =>
      const HealthPlatformResult.allowed();

  @override
  Future<bool> pastDataSwitchOffered() async => true;

  @override
  Future<HealthPlatformResult> requestPastDataAccess(
    HealthGuardFacts facts,
  ) async =>
      const HealthPlatformResult.allowed();
}

HealthFlowSample _flow(String id, HealthFlowValue flow) {
  final start = DateTime.parse('2026-09-10T04:00:00Z');
  return HealthFlowSample(
    recordId: id,
    flow: flow,
    start: start,
    end: start.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
    tzName: _tz,
  );
}

HealthFlowSample _spotting(String id) {
  final start = DateTime.parse('2026-09-11T04:00:00Z');
  return HealthFlowSample(
    recordId: id,
    kind: HealthSampleKind.intermenstrualBleeding,
    start: start,
    end: start,
    offset: Duration.zero,
  );
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late DriftDayEntriesRepository days;
  late DriftObservationsRepository observations;
  late _Store store;
  late LocalHealthImportService import;
  late LocalHealthImportService Function(HealthImportPlatform) importFor;

  final flowDate = LocalDate(2026, 9, 10);
  final spottingDate = LocalDate(2026, 9, 11);

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    days = DriftDayEntriesRepository(db.storage);
    observations = DriftObservationsRepository(db.storage);
    final profiles = DriftProfilesRepository(db.storage);
    await db.storage.upsertProfile(
      id: _profileId,
      displayName: 'Ada',
      isMinor: false,
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final binding = HealthSyncBinding(DriftSettingsStore(db.storage));
    await binding.bind(
      profile: (await profiles.findById(_profileId))!,
      signedInUserId: _ownerId,
      ownerUserId: _ownerId,
      minorBindingAllowed: false,
    );
    store = _Store()
      ..samples = [
        _flow('rec-1', HealthFlowValue.heavy),
        _spotting('spot-1'),
      ];
    importFor = (platform) => LocalHealthImportService(
      importPlatform: platform,
      platform: _Platform(),
      source: store,
      binding: binding,
      minorBindingAllowed: false,
      profiles: profiles,
      dayEntries: days,
      observations: observations,
      guardiansForProfile: (_) async => [
        ProfileGuardian(
          id: 'g1',
          profileId: _profileId,
          userId: _ownerId,
          role: GuardianRole.primaryGuardian,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
      signedInUserId: () => _ownerId,
      today: () => LocalDate(2026, 9, 15),
    );
    import = importFor(HealthImportPlatform.appleHealth);
  });

  Future<int> rowsFor(String sourceId) async => [
        for (final row in await db.select(db.dayEntries).get())
          if (row.sourceId == sourceId) row,
      ].length;

  Future<List<Observation>> spottingOn(LocalDate date) async {
    final day = await days.find(_profileId, date);
    if (day == null) return const [];
    return [
      for (final o in await observations.listForDayEntry(day.id))
        if (o.category == ObservationCategory.spotting) o,
    ];
  }

  Future<int> spottingRows() async => [
        for (final row in await db.select(db.observations).get())
          if (row.sourceId == 'spot-1') row,
      ].length;

  test('the first import writes the day and the spotting entry', () async {
    final summary = await import.importNow();
    expect(summary.daysWritten, 1);
    expect(summary.spottingDaysWritten, 1);
    expect((await days.find(_profileId, flowDate))!.flow, FlowLevel.heavy);
    expect(await spottingOn(spottingDate), hasLength(1));
  });

  test('a day she deletes stays deleted, with its row and after the row '
      'has been swept', () async {
    await import.importNow();
    await days.delete(_profileId, flowDate);

    var summary = await import.importNow();
    expect(summary.daysWritten, 0);
    expect(summary.daysKeptManual, 1);
    expect(await days.find(_profileId, flowDate), isNull);
    expect(await rowsFor('rec-1'), 1, reason: 'no second row for the record');

    // A clean deleted row is swept two days after it has synced.
    await (db.delete(db.dayEntries)
          ..where((t) => t.sourceId.equals('rec-1')))
        .go();
    summary = await import.importNow();
    expect(summary.daysWritten, 0);
    expect(summary.daysKeptManual, 1);
    expect(await rowsFor('rec-1'), 0);
  });

  test('a different record for the day is the store\'s news', () async {
    await import.importNow();
    await days.delete(_profileId, flowDate);
    store.samples = [_flow('rec-2', HealthFlowValue.light)];

    expect((await import.importNow()).daysWritten, 1);
    final day = (await days.find(_profileId, flowDate))!;
    expect(day.flow, FlowLevel.light);
    expect(day.sourceId, 'rec-2');
  });

  // The day sheet removes one entry from a day by saving the day with the
  // entry's id to delete. The first design remembered nothing on that path.
  test('spotting she unticks in the day sheet stays off', () async {
    await import.importNow();
    final day = (await days.find(_profileId, spottingDate))!;
    final entry = (await spottingOn(spottingDate)).single;
    await days.saveDayEntryWithObservations(
      entry: day,
      observationIdsToDelete: [entry.id],
    );
    expect(await spottingOn(spottingDate), isEmpty);

    final summary = await import.importNow();
    expect(summary.spottingDaysWritten, 0);
    expect(await spottingOn(spottingDate), isEmpty);
    expect(await spottingRows(), 1, reason: 'no second row for the record');
  });

  test('deleting a day takes its imported spotting with it, for good',
      () async {
    await import.importNow();
    await days.delete(_profileId, spottingDate);

    final summary = await import.importNow();
    expect(summary.spottingDaysWritten, 0);
    expect(await days.find(_profileId, spottingDate), isNull,
        reason: 'no empty day is made to hang it on');
    expect(await spottingRows(), 1);
  });

  // Undo saves the same rows again, as the day sheet's Undo does.
  test('a deletion she undoes is forgotten at the next import', () async {
    await import.importNow();
    final day = (await days.find(_profileId, flowDate))!;
    await days.delete(_profileId, flowDate);
    expect(await db.storage.readHealthImportDeletions(_profileId),
        hasLength(1));

    await days.saveDayEntryWithObservations(entry: day);
    final summary = await import.importNow();
    expect(summary.daysUnchanged, greaterThanOrEqualTo(1));
    expect(summary.daysKeptManual, 0);
    expect(await db.storage.readHealthImportDeletions(_profileId), isEmpty);
    expect((await days.find(_profileId, flowDate))!.id, day.id);
  });

  // On an iPhone the days carry one source and the entries on them another,
  // and "Remove imported data" removes one source at a time. The review of
  // an earlier version found that removing the days' source left what she
  // had removed from the other one remembered, with no way to clear it.
  test('after Apple Health\'s imported data is removed, an import brings '
      'back what she had deleted from it too', () async {
    await import.importNow();
    await days.delete(_profileId, flowDate);
    final spottingDay = (await days.find(_profileId, spottingDate))!;
    await days.saveDayEntryWithObservations(
      entry: spottingDay,
      observationIdsToDelete: [(await spottingOn(spottingDate)).single.id],
    );
    expect(await db.storage.readHealthImportDeletions(_profileId),
        hasLength(2));
    expect((await import.importNow()).daysWritten, 0);

    await db.storage.applyLocalImportedDataPurge(
      profileId: _profileId,
      source: 'healthkit',
    );
    expect(await db.storage.readHealthImportDeletions(_profileId), isEmpty);

    final summary = await import.importNow();
    expect(summary.daysWritten, 1);
    expect(summary.spottingDaysWritten, 1);
    expect((await days.find(_profileId, flowDate))!.flow, FlowLevel.heavy);
    expect(await spottingOn(spottingDate), hasLength(1));
  });

  test('Health Connect: a day she deletes stays deleted until the store '
      'changes the record', () async {
    final hc = importFor(HealthImportPlatform.healthConnect);
    final start = DateTime.parse('2026-09-10T04:00:00Z');
    HealthFlowSample record(HealthFlowValue flow, DateTime modifiedAt) =>
        HealthFlowSample(
          recordId: 'hc-1',
          flow: flow,
          start: start,
          end: start.add(const Duration(hours: 1)),
          offset: Duration.zero,
          modifiedAt: modifiedAt,
        );
    final first = DateTime.utc(2026, 9, 10, 6);
    store.samples = [record(HealthFlowValue.heavy, first)];

    expect((await hc.importNow()).daysWritten, 1);
    final imported = (await days.find(_profileId, flowDate))!;
    expect(imported.source, DayEntrySource.healthConnect);
    expect(imported.sourceId, 'hc-1@${first.millisecondsSinceEpoch}');

    await days.delete(_profileId, flowDate);
    final summary = await hc.importNow();
    expect(summary.daysWritten, 0);
    expect(summary.daysKeptManual, 1);
    expect(await days.find(_profileId, flowDate), isNull);

    // The store changes the record: its news, and the day is imported.
    final later = DateTime.utc(2026, 9, 14, 6);
    store.samples = [record(HealthFlowValue.light, later)];
    expect((await hc.importNow()).daysWritten, 1);
    final back = (await days.find(_profileId, flowDate))!;
    expect(back.flow, FlowLevel.light);
    expect(back.sourceId, 'hc-1@${later.millisecondsSinceEpoch}');
  });

  test('a symptom she logs on a day she deleted does not let the record '
      'back in', () async {
    await import.importNow();
    await days.delete(_profileId, flowDate);
    await days.save(
      DayEntry(
        id: '',
        profileId: _profileId,
        localDate: flowDate,
        tz: _tz,
        flow: FlowLevel.none,
        tags: const ['cramps'],
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    await import.importNow();
    final day = (await days.find(_profileId, flowDate))!;
    expect(day.flow, FlowLevel.none);
    expect(day.source, DayEntrySource.manual);
    expect(day.sourceId, isNull);
  });
}
