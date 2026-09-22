/// Issue #848: the local write paths reject a future-dated or pre-birth
/// day entry. Covers `upsertDayEntry` (via `saveDayEntryWithObservations`)
/// and `bulkUpsertDayEntries`, both of which now run
/// `DayEntryPolicy.validateDate` against an injected `today` seam.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/domain/models/local_date.dart';

DayEntry bulkEntry({
  required String id,
  required String localDate,
  String profileId = 'p1',
  DateTime? updatedAt,
}) =>
    DayEntry(
      id: id,
      profileId: profileId,
      localDate: localDate,
      tz: 'UTC',
      flow: FlowLevel.light,
      tags: const [],
      note: null,
      notePrivate: false,
      pms: false,
      updatedAt: updatedAt ?? DateTime.utc(2026, 9, 1, 8),
      dirty: false,
      localRev: 0,
      source: 'manual',
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late LunarLogStorage storage;

  final stamp = DateTime.utc(2026, 9, 1, 8);
  final today = LocalDate(2026, 9, 19);

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    storage = LunarLogStorage(
      db,
      clock: () => stamp,
      today: () => today,
    );
    await storage.upsertProfile(
      id: 'p1',
      displayName: 'Bounded',
      isMinor: true,
      birthYear: 2015,
      updatedAt: stamp,
    );
    await storage.upsertProfile(
      id: 'p2',
      displayName: 'Unknown Birth Year',
      isMinor: false,
      updatedAt: stamp,
    );
  });

  group('upsertDayEntry date bounds', () {
    test('today + 1 is accepted', () async {
      final saved = await storage.upsertDayEntry(
        profileId: 'p1',
        localDate: today.addDays(1).iso,
        tz: 'UTC',
        flow: FlowLevel.light,
      );
      expect(saved.localDate, today.addDays(1).iso);
      expect(
        await storage.getDayEntry(
          profileId: 'p1',
          localDate: today.addDays(1).iso,
        ),
        isNotNull,
      );
    });

    test('a date more than one day ahead is rejected and not stored',
        () async {
      await expectLater(
        storage.upsertDayEntry(
          profileId: 'p1',
          localDate: today.addDays(2).iso,
          tz: 'UTC',
          flow: FlowLevel.light,
        ),
        throwsArgumentError,
      );
      expect(
        await storage.getDayEntry(
          profileId: 'p1',
          localDate: today.addDays(2).iso,
        ),
        isNull,
      );
    });

    test('a far-future date (2999-01-01) is rejected', () async {
      await expectLater(
        storage.upsertDayEntry(
          profileId: 'p1',
          localDate: '2999-01-01',
          tz: 'UTC',
          flow: FlowLevel.light,
        ),
        throwsArgumentError,
      );
    });

    test('a date before the profile birth year is rejected', () async {
      await expectLater(
        storage.upsertDayEntry(
          profileId: 'p1',
          localDate: '2010-06-01',
          tz: 'UTC',
          flow: FlowLevel.light,
        ),
        throwsArgumentError,
      );
      expect(
        await storage.getDayEntry(profileId: 'p1', localDate: '2010-06-01'),
        isNull,
      );
    });

    test('a pre-birth-year date is accepted when birth_year is unknown',
        () async {
      final saved = await storage.upsertDayEntry(
        profileId: 'p2',
        localDate: '2010-06-01',
        tz: 'UTC',
        flow: FlowLevel.light,
      );
      expect(saved.localDate, '2010-06-01');
    });

    test('a malformed local date still throws (shape validation)', () async {
      await expectLater(
        storage.upsertDayEntry(
          profileId: 'p1',
          localDate: 'not-a-date',
          tz: 'UTC',
          flow: FlowLevel.light,
        ),
        throwsArgumentError,
      );
    });
  });

  group('bulkUpsertDayEntries date bounds', () {
    test('an in-bounds batch writes', () async {
      final written = await storage.bulkUpsertDayEntries([
        bulkEntry(id: '01ARZ3NDEKTSV4RRFFQ69G5FAV', localDate: '2026-09-01'),
        bulkEntry(id: '01ARZ3NDEKTSV4RRFFQ69G5FB0', localDate: '2026-09-02'),
      ]);
      expect(written, hasLength(2));
    });

    test('a future-dated row fails the whole batch (nothing persisted)',
        () async {
      await expectLater(
        storage.bulkUpsertDayEntries([
          bulkEntry(id: '01ARZ3NDEKTSV4RRFFQ69G5FAV', localDate: '2026-09-01'),
          bulkEntry(
            id: '01ARZ3NDEKTSV4RRFFQ69G5FB0',
            localDate: today.addDays(2).iso,
          ),
        ]),
        throwsArgumentError,
      );
      expect(await storage.getDayEntries(profileId: 'p1'), isEmpty);
    });

    test('a pre-birth-year row fails the whole batch', () async {
      await expectLater(
        storage.bulkUpsertDayEntries([
          bulkEntry(id: '01ARZ3NDEKTSV4RRFFQ69G5FAV', localDate: '2010-06-01'),
        ]),
        throwsArgumentError,
      );
      expect(await storage.getDayEntries(profileId: 'p1'), isEmpty);
    });

    test('an old date still writes for a profile with no birth year',
        () async {
      final written = await storage.bulkUpsertDayEntries([
        bulkEntry(
          id: '01ARZ3NDEKTSV4RRFFQ69G5FAV',
          localDate: '2010-06-01',
          profileId: 'p2',
        ),
      ]);
      expect(written, hasLength(1));
    });
  });
}
