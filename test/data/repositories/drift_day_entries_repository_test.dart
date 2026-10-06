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
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
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

  // Issue #1561: the health import asks whether a day it once wrote was
  // deleted. `find` answers for live rows only.
  group('findDeletedBySource (#1561)', () {
    Future<void> saveImported(String iso, String sourceId) => repository.save(
          DayEntry(
            id: '',
            profileId: 'p1',
            localDate: LocalDate.fromIso(iso),
            tz: 'America/Chicago',
            flow: FlowLevel.heavy,
            source: DayEntrySource.healthkit,
            sourceId: sourceId,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

    Future<DayEntry?> deletedBy(
      String sourceId, {
      DayEntrySource source = DayEntrySource.healthkit,
      String profileId = 'p1',
    }) =>
        repository.findDeletedBySource(
          profileId: profileId,
          source: source,
          sourceId: sourceId,
        );

    test('a live imported day is not a deleted one', () async {
      await saveImported('2026-08-01', 'rec-1');
      expect(await deletedBy('rec-1'), isNull);
    });

    test('a deleted imported day is found by the record it came from, with '
        'its content gone and its provenance kept', () async {
      await saveImported('2026-08-01', 'rec-1');
      await repository.delete('p1', LocalDate.fromIso('2026-08-01'));

      expect(await repository.find('p1', LocalDate.fromIso('2026-08-01')),
          isNull);
      final deleted = await deletedBy('rec-1');
      expect(deleted, isNotNull);
      expect(deleted!.deletedAt, isNotNull);
      expect(deleted.flow, FlowLevel.none);
      expect(deleted.source, DayEntrySource.healthkit);
      expect(deleted.sourceId, 'rec-1');
      expect(deleted.localDate, LocalDate.fromIso('2026-08-01'));
      // The deletion is the row's last change.
      expect(deleted.updatedAt, deleted.deletedAt);
    });

    test('nothing is found under another record, source or profile',
        () async {
      await saveImported('2026-08-01', 'rec-1');
      await repository.delete('p1', LocalDate.fromIso('2026-08-01'));

      expect(await deletedBy('rec-2'), isNull);
      expect(
        await deletedBy('rec-1', source: DayEntrySource.healthConnect),
        isNull,
      );
      expect(await deletedBy('rec-1', profileId: 'p2'), isNull);
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
