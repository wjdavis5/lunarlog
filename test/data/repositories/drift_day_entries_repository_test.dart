/// Unit tests for [DriftDayEntriesRepository]'s Issue #850 U5 seam:
/// [LatestDayEntryReader.latestEntryFor]. Storage semantics themselves live
/// in the `storage_*` suites; this file pins the bounded latest-entry read
/// the guardian logistics card depends on.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_imported_data_purge_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/domain/health/health_import_deletions.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late DriftDayEntriesRepository repository;

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    repository = DriftDayEntriesRepository(db.storage);
    await db.storage.upsertProfile(
      id: 'p1',
      displayName: 'Riley',
      isMinor: true,
      updatedAt: DateTime.utc(2026, 9, 1, 8),
    );
  });

  Future<void> saveEntry(String iso, {String? note, List<String> tags = const []}) =>
      repository.save(
        DayEntry(
          id: '',
          profileId: 'p1',
          localDate: LocalDate.fromIso(iso),
          tz: 'America/Chicago',
          flow: FlowLevel.medium,
          tags: tags,
          note: note,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );

  // Issue #1561: what the health import is told about days she deleted, by
  // the repository whose `delete` she reaches. Against a real database, so
  // what a deleted row keeps and what a save under its id does are the
  // storage layer's real answers.
  group('deleting an imported day (#1561)', () {
    final date = LocalDate.fromIso('2026-08-01');
    late DriftObservationsRepository observations;

    setUp(() => observations = DriftObservationsRepository(db.storage));

    Future<DayEntry> saveDay({
      DayEntrySource source = DayEntrySource.healthkit,
      String? sourceId = 'rec-1',
      String id = '',
    }) =>
        repository.save(
          DayEntry(
            id: id,
            profileId: 'p1',
            localDate: date,
            tz: 'America/Chicago',
            flow: FlowLevel.heavy,
            source: source,
            sourceId: sourceId,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

    Future<Observation> saveSpotting(DayEntry day, String sourceId) =>
        observations.save(
          Observation(
            id: '',
            dayEntryId: day.id,
            profileId: 'p1',
            localDate: date,
            tz: 'America/Chicago',
            category: ObservationCategory.spotting,
            code: ObservationCategory.spotting.wireCode,
            source: ObservationSource.appleHealth,
            sourceId: sourceId,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

    Future<DayEntry?> deletedRow(String sourceId) =>
        repository.findDeletedBySource(
          profileId: 'p1',
          source: DayEntrySource.healthkit,
          sourceId: sourceId,
        );

    test('nothing is remembered before she deletes anything', () async {
      await saveDay();
      expect(await repository.handDeletedRecords('p1'), isEmpty);
      expect(await deletedRow('rec-1'), isNull, reason: 'the row is live');
    });

    test('deleting it remembers the record it came from, and when', () async {
      await saveDay();
      final before = DateTime.now().toUtc();
      await repository.delete('p1', date);

      final remembered = await repository.handDeletedRecords('p1');
      expect(remembered.keys, [healthImportDeletionId('healthkit', 'rec-1')]);
      expect(
        remembered.values.single.isBefore(before.subtract(
          const Duration(seconds: 1),
        )),
        isFalse,
      );
      // Another profile's memory is its own.
      expect(await repository.handDeletedRecords('p2'), isEmpty);
    });

    test('the deleted row keeps its provenance and loses its content',
        () async {
      await saveDay();
      await repository.delete('p1', date);

      expect(await repository.find('p1', date), isNull);
      final deleted = await deletedRow('rec-1');
      expect(deleted, isNotNull);
      expect(deleted!.deletedAt, isNotNull);
      expect(deleted.flow, FlowLevel.none);
      expect(deleted.source, DayEntrySource.healthkit);
      expect(deleted.sourceId, 'rec-1');
      expect(await deletedRow('rec-2'), isNull);
    });

    test('a day she logged herself leaves nothing behind', () async {
      await saveDay(source: DayEntrySource.manual, sourceId: null);
      await repository.delete('p1', date);
      expect(await repository.handDeletedRecords('p1'), isEmpty);
    });

    test('deleting a day that is not there changes nothing', () async {
      await repository.delete('p1', date);
      expect(await repository.handDeletedRecords('p1'), isEmpty);
    });

    test('deleting the day remembers its imported spotting entry too',
        () async {
      final day = await saveDay(source: DayEntrySource.manual, sourceId: null);
      await saveSpotting(day, 'spot-1');
      await repository.delete('p1', date);

      expect(
        (await repository.handDeletedRecords('p1')).keys,
        [healthImportDeletionId('apple_health', 'spot-1')],
      );
    });

    test('deleting one imported entry remembers that entry', () async {
      final day = await saveDay(source: DayEntrySource.manual, sourceId: null);
      final spotting = await saveSpotting(day, 'spot-1');
      await observations.delete(spotting.id);

      expect(
        (await repository.handDeletedRecords('p1')).keys,
        [healthImportDeletionId('apple_health', 'spot-1')],
      );
      // Deleting it again, or one that is not there, adds nothing.
      await observations.delete(spotting.id);
      await observations.delete('no-such-entry');
      expect(await repository.handDeletedRecords('p1'), hasLength(1));
    });

    test('saving under a deleted row\'s id brings that row back', () async {
      final first = await saveDay();
      await repository.delete('p1', date);
      expect(await repository.find('p1', date), isNull);

      // What the import does for a deleted row that is not her deletion.
      final revived = await saveDay(id: first.id);
      expect(revived.id, first.id);
      final live = await repository.find('p1', date);
      expect(live, isNotNull);
      expect(live!.id, first.id);
      expect(live.flow, FlowLevel.heavy);
      expect(await deletedRow('rec-1'), isNull);
    });

    test('"Remove imported data" forgets what she deleted from that source, '
        'and its own deleted rows are not her deletions', () async {
      final day = await saveDay();
      await saveSpotting(day, 'spot-1');
      await repository.delete('p1', date);
      expect(await repository.handDeletedRecords('p1'), hasLength(2));

      final purge = DriftImportedDataPurgeRepository(db.storage);
      await purge.applyLocalPurge(profileId: 'p1', source: 'healthkit');
      // The day's record is forgotten; the spotting entry is another
      // source's and stays.
      expect(
        (await repository.handDeletedRecords('p1')).keys,
        [healthImportDeletionId('apple_health', 'spot-1')],
      );

      // A purge on its own: the rows are deleted, and nothing is remembered.
      final other = LocalDate.fromIso('2026-08-02');
      await repository.save(
        DayEntry(
          id: '',
          profileId: 'p1',
          localDate: other,
          tz: 'America/Chicago',
          flow: FlowLevel.light,
          source: DayEntrySource.healthkit,
          sourceId: 'rec-9',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await purge.applyLocalPurge(profileId: 'p1', source: 'healthkit');
      expect(await repository.find('p1', other), isNull);
      expect(await deletedRow('rec-9'), isNotNull);
      expect(
        (await repository.handDeletedRecords('p1')).keys,
        isNot(contains(healthImportDeletionId('healthkit', 'rec-9'))),
      );
    });
  });

  test('latestEntryFor returns null for a profile with no entries', () async {
    expect(await repository.latestEntryFor('p1'), isNull);
  });

  test('latestEntryFor returns the row at the greatest civil date, not the '
      'most recently written', () async {
    await saveEntry('2026-08-01');
    await saveEntry('2026-07-15');
    await saveEntry('2026-08-10');

    final latest = await repository.latestEntryFor('p1');
    expect(latest, isNotNull);
    expect(latest!.localDate, LocalDate(2026, 8, 10));
  });

  test('latestEntryFor excludes tombstones', () async {
    await saveEntry('2026-08-01');
    await saveEntry('2026-08-10');
    await repository.delete('p1', LocalDate(2026, 8, 10));

    final latest = await repository.latestEntryFor('p1');
    expect(latest, isNotNull);
    expect(latest!.localDate, LocalDate(2026, 8, 1));
  });

  test('latestEntryFor is scoped to the requested profile (R3)', () async {
    await db.storage.upsertProfile(
      id: 'p2',
      displayName: 'Sam',
      isMinor: false,
      updatedAt: DateTime.utc(2026, 9, 1, 8),
    );
    await saveEntry('2026-08-01');
    await repository.save(
      DayEntry(
        id: '',
        profileId: 'p2',
        localDate: LocalDate(2026, 8, 20),
        tz: 'America/Chicago',
        flow: FlowLevel.medium,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    expect(
      (await repository.latestEntryFor('p1'))!.localDate,
      LocalDate(2026, 8, 1),
    );
    expect(
      (await repository.latestEntryFor('p2'))!.localDate,
      LocalDate(2026, 8, 20),
    );
  });

  test('DriftDayEntriesRepository satisfies the LatestDayEntryReader seam',
      () {
    expect(repository, isA<LatestDayEntryReader>());
  });
}
