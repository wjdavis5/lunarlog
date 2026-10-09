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
import 'package:lunarlog/domain/health/health_import_deletions.dart'
    show healthImportDeletionId;
import 'package:lunarlog/domain/logging/quick_log.dart' show undoQuickLog;
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

  group('the undo\'s delete (Issue #1587 item 1)', () {
    test('DriftDayEntriesRepository satisfies the UndoDayEntryDeleter seam',
        () {
      expect(repository, isA<UndoDayEntryDeleter>());
    });

    test('undoQuickLog of a day the tap created forgets the store records '
        'an import attached, instead of shadowing them', () async {
      final day = await repository.save(
        DayEntry(
          id: '',
          profileId: 'p1',
          localDate: LocalDate(2026, 8, 1),
          tz: 'UTC',
          flow: FlowLevel.medium,
          source: DayEntrySource.healthkit,
          sourceId: 'rec-1',
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      );
      await repository.saveDayEntryWithObservations(
        entry: day,
        observationsToUpsert: [
          Observation(
            id: '',
            dayEntryId: day.id,
            profileId: 'p1',
            localDate: LocalDate(2026, 8, 1),
            tz: 'UTC',
            category: ObservationCategory.spotting,
            code: ObservationCategory.spotting.wireCode,
            source: ObservationSource.appleHealth,
            sourceId: 'spot-1',
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        ],
      );

      await undoQuickLog(
        repository,
        profileId: 'p1',
        previous: null,
        date: LocalDate(2026, 8, 1),
      );

      // The day is gone (and so is the spotting entry, cascaded)…
      expect(await repository.find('p1', LocalDate(2026, 8, 1)), isNull);
      // …but nothing was remembered as "she removed this store data": an
      // import may bring both records back.
      expect(await repository.deletedHealthRecords('p1'), isEmpty);
    });

    test('the ordinary delete still remembers them, so the seam is the '
        'difference', () async {
      final day = await repository.save(
        DayEntry(
          id: '',
          profileId: 'p1',
          localDate: LocalDate(2026, 8, 1),
          tz: 'UTC',
          flow: FlowLevel.medium,
          source: DayEntrySource.healthkit,
          sourceId: 'rec-1',
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      );
      expect(day.source, DayEntrySource.healthkit);

      await repository.delete('p1', LocalDate(2026, 8, 1));

      expect(
        (await repository.deletedHealthRecords('p1')).keys,
        [healthImportDeletionId('healthkit', 'rec-1')],
      );
    });
  });
}
