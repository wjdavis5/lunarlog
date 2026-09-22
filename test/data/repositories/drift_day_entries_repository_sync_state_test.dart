/// Unit tests for [DriftDayEntriesRepository]'s Issue #1071 follow-up seam:
/// [DayEntrySyncStateReader.hasBeenShared]. Storage semantics themselves live
/// in the `storage_*` suites; this file pins the "has the note really been
/// shared" read the day sheet's privacy lock depends on — true only for a
/// live row whose non-empty note has `dirty == false` (already pushed).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart' show SyncTable;
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late DriftDayEntriesRepository repository;

  final date = LocalDate(2026, 8, 30);

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

  Future<void> saveNote(String? note) => repository.save(
        DayEntry(
          id: '',
          profileId: 'p1',
          localDate: date,
          tz: 'America/Chicago',
          flow: FlowLevel.medium,
          note: note,
          updatedAt: DateTime.utc(2026, 8, 30, 12),
        ),
      );

  /// Clears the row's `dirty` flag the way a completed sync push would
  /// (matching `local_rev` so the guarded UPDATE actually matches).
  Future<void> markPushed() async {
    final row = (await db.storage.getDayEntry(
      profileId: 'p1',
      localDate: date.iso,
    ))!;
    await db.storage.markPushed(
      table: SyncTable.dayEntries,
      id: row.id,
      localRevAtPush: row.localRev,
    );
  }

  test('hasBeenShared is false when no row exists for the date', () async {
    expect(await repository.hasBeenShared('p1', date), isFalse);
  });

  test('hasBeenShared is false for an empty note, pushed or not', () async {
    await saveNote(null);
    expect(await repository.hasBeenShared('p1', date), isFalse);

    await markPushed();
    expect(await repository.hasBeenShared('p1', date), isFalse);
  });

  test('hasBeenShared is false for a note that has never been pushed '
      '(a dirty local-only row)', () async {
    await saveNote('Felt off today');

    expect(await repository.hasBeenShared('p1', date), isFalse);
  });

  test('hasBeenShared is true once the note has actually been pushed',
      () async {
    await saveNote('Felt off today');
    await markPushed();

    expect(await repository.hasBeenShared('p1', date), isTrue);
  });

  test('hasBeenShared reads false again after the row is tombstoned',
      () async {
    await saveNote('Felt off today');
    await markPushed();
    await repository.delete('p1', date);

    expect(await repository.hasBeenShared('p1', date), isFalse);
  });

  test('hasBeenShared is scoped to the requested profile (R3)', () async {
    await db.storage.upsertProfile(
      id: 'p2',
      displayName: 'Sam',
      isMinor: false,
      updatedAt: DateTime.utc(2026, 9, 1, 8),
    );
    await saveNote('Felt off today');
    await markPushed();

    expect(await repository.hasBeenShared('p1', date), isTrue);
    expect(await repository.hasBeenShared('p2', date), isFalse);
  });

  test('DriftDayEntriesRepository satisfies the DayEntrySyncStateReader seam',
      () {
    expect(repository, isA<DayEntrySyncStateReader>());
  });
}
