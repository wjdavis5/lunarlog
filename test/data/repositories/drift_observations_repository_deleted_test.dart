/// Unit tests for [DriftObservationsRepository]'s Issue #1561 seam,
/// [DeletedObservationReader.wasDeletedBySource]: the health import asks
/// whether a spotting entry it once wrote was deleted, so that it does not
/// write it again.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late DriftDayEntriesRepository dayEntries;
  late DriftObservationsRepository observations;

  final date = LocalDate.fromIso('2026-08-01');

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    dayEntries = DriftDayEntriesRepository(db.storage);
    observations = DriftObservationsRepository(db.storage);
    await db.storage.upsertProfile(
      id: 'p1',
      displayName: 'Riley',
      isMinor: true,
      updatedAt: DateTime.utc(2026, 9, 1, 8),
    );
  });

  /// An imported spotting entry, as the health import writes one: a day to
  /// hang it on, then the observation with the store's record id.
  Future<Observation> saveImportedSpotting(String sourceId) async {
    final day = await dayEntries.save(
      DayEntry(
        id: '',
        profileId: 'p1',
        localDate: date,
        tz: 'America/Chicago',
        flow: FlowLevel.none,
        source: DayEntrySource.healthkit,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    return observations.save(
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
  }

  Future<bool> wasDeleted(
    String sourceId, {
    ObservationSource source = ObservationSource.appleHealth,
    String profileId = 'p1',
  }) =>
      observations.wasDeletedBySource(
        profileId: profileId,
        source: source,
        sourceId: sourceId,
      );

  test('a live imported observation was not deleted', () async {
    await saveImportedSpotting('rec-1');
    expect(await wasDeleted('rec-1'), isFalse);
  });

  test('one that was never imported was not deleted', () async {
    expect(await wasDeleted('rec-1'), isFalse);
  });

  test('deleting the observation is remembered by the record it came from',
      () async {
    final saved = await saveImportedSpotting('rec-1');
    await observations.delete(saved.id);

    expect(await wasDeleted('rec-1'), isTrue);
    // Only under that record, that source and that profile.
    expect(await wasDeleted('rec-2'), isFalse);
    expect(
      await wasDeleted('rec-1', source: ObservationSource.healthConnect),
      isFalse,
    );
    expect(await wasDeleted('rec-1', profileId: 'p2'), isFalse);
  });

  test('deleting the whole day deletes its observation with it', () async {
    await saveImportedSpotting('rec-1');
    await dayEntries.delete('p1', date);

    expect(await wasDeleted('rec-1'), isTrue);
  });
}
