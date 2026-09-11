/// Issue #172: `LunarLogStorage.bulkUpsertDayEntries` — the single-transaction
/// bulk-write seam the future Clue importer (#190) will drive instead of the
/// per-row `save`. Covers: one transaction / one stream emission per batch
/// (including the 3,650-row import fixture), day-before-observation ordering,
/// id reuse, last-wins duplicates, the live-date fallback, empty input, and
/// fail-fast validation.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/domain/limits.dart';

class FixedClock {
  FixedClock(this.now);

  DateTime now;

  DateTime call() => now;
}

/// One bulk day-entry input carrying [id]/[localDate]/[flow]/[note].
DayEntry bulkEntry({
  required String id,
  required String localDate,
  FlowLevel flow = FlowLevel.light,
  String? note,
  String profileId = 'p1',
  DateTime? updatedAt,
  String source = 'manual',
  String? sourceId,
  String? importId,
}) =>
    DayEntry(
      id: id,
      profileId: profileId,
      localDate: localDate,
      tz: 'UTC',
      flow: flow,
      tags: const [],
      note: note,
      pms: false,
      updatedAt: updatedAt ?? DateTime.utc(2026, 9, 1, 8),
      dirty: false,
      localRev: 0,
      source: source,
      sourceId: sourceId,
      importId: importId,
    );

/// One bulk observation input attached to [dayEntryId].
Observation bulkObservation({
  required String id,
  required String dayEntryId,
  required String localDate,
  String? category = 'pain',
  String? code = 'migraine',
  String profileId = 'p1',
  DateTime? updatedAt,
}) =>
    Observation(
      id: id,
      dayEntryId: dayEntryId,
      profileId: profileId,
      localDate: localDate,
      tz: 'UTC',
      category: category,
      code: code,
      excluded: false,
      source: 'manual',
      updatedAt: updatedAt ?? DateTime.utc(2026, 9, 1, 8),
      dirty: false,
      localRev: 0,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late FixedClock clock;
  late LunarLogStorage storage;

  final t0 = DateTime.utc(2026, 9, 1, 8);

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    clock = FixedClock(t0);
    storage = LunarLogStorage(db, clock: clock.call);
    await storage.upsertProfile(
      id: 'p1',
      displayName: 'Riley',
      isMinor: true,
      updatedAt: t0,
    );
  });

  /// Lets pending drift stream notifications flush, then returns.
  Future<void> flushStreams() =>
      Future<void>.delayed(const Duration(milliseconds: 100));

  group('bulkUpsertDayEntries', () {
    test('empty call writes nothing and opens no transaction', () async {
      final emissions = <List<DayEntry>>[];
      final sub =
          storage.watchDayEntries(profileId: 'p1').listen(emissions.add);
      addTearDown(() => sub.cancel());
      await flushStreams();
      emissions.clear();

      expect(await storage.bulkUpsertDayEntries(const []), isEmpty);

      await flushStreams();
      expect(emissions, isEmpty);
      expect(await storage.getDayEntries(profileId: 'p1'), isEmpty);
    });

    test('writes entries and observations in one batch, one emission each',
        () async {
      final dayEmissions = <List<DayEntry>>[];
      final daySub =
          storage.watchDayEntries(profileId: 'p1').listen(dayEmissions.add);
      addTearDown(() => daySub.cancel());
      final obsEmissions = <List<Observation>>[];
      final obsSub = storage
          .watchObservationsForDayEntry('bulk-e1')
          .listen(obsEmissions.add);
      addTearDown(() => obsSub.cancel());
      await flushStreams();
      dayEmissions.clear();
      obsEmissions.clear();

      final written = await storage.bulkUpsertDayEntries(
        [
          bulkEntry(id: 'bulk-e1', localDate: '2026-08-01'),
          bulkEntry(id: 'bulk-e2', localDate: '2026-08-02', note: 'hello'),
        ],
        observations: [
          bulkObservation(
              id: 'bulk-o1',
              dayEntryId: 'bulk-e1',
              localDate: '2026-08-01'),
        ],
      );

      await flushStreams();

      // The persisted rows keep the caller's ids, in input order.
      expect([for (final e in written) e.id], ['bulk-e1', 'bulk-e2']);
      expect(
          await storage.getDayEntries(profileId: 'p1'), hasLength(2));
      expect(await storage.getObservationsForDayEntry('bulk-e1'),
          hasLength(1));
      // Exactly one emission per stream for the whole batch (AC1/AC3):
      // drift coalesces a transaction's invalidations into one event.
      expect(dayEmissions, hasLength(1));
      expect(dayEmissions.single, hasLength(2));
      expect(obsEmissions, hasLength(1));
      expect(obsEmissions.single, hasLength(1));
    });

    test('3,650-row import is one batch: one emission, all rows land',
        () async {
      final base = DateTime.utc(2016, 1, 1);
      final entries = [
        for (var i = 0; i < 3650; i++)
          bulkEntry(
            id: 'history-$i',
            localDate: base
                .add(Duration(days: i))
                .toIso8601String()
                .substring(0, 10),
          ),
      ];
      final dayEmissions = <List<DayEntry>>[];
      final sub =
          storage.watchDayEntries(profileId: 'p1').listen(dayEmissions.add);
      addTearDown(() => sub.cancel());
      await flushStreams();
      dayEmissions.clear();

      final stopwatch = Stopwatch()..start();
      final written = await storage.bulkUpsertDayEntries(entries);
      final elapsed = stopwatch.elapsed;
      await flushStreams();

      expect(written, hasLength(3650));
      expect(await storage.getDayEntries(profileId: 'p1'), hasLength(3650));
      // O(1) batches, not O(n) transactions: a single emission for all
      // 3,650 rows.
      expect(dayEmissions, hasLength(1));
      expect(dayEmissions.single, hasLength(3650));
      // A loose wall-clock bound (generous on slow CI): the batch must
      // complete, not grind per-row. The emission count above is the real
      // O(1) assertion; this only guards against a pathological stall.
      expect(elapsed, lessThan(const Duration(seconds: 60)),
          reason: '3,650-row bulk import took $elapsed');
    });

    test('per-row saves emit per row; the bulk path emits once', () async {
      // Baseline: ten per-row saves produce one emission each (plus the
      // initial empty emission) — the O(n) shape #172 replaces.
      final perRowEmissions = <List<DayEntry>>[];
      final perRowSub = storage
          .watchDayEntries(profileId: 'p1')
          .listen(perRowEmissions.add);
      addTearDown(() => perRowSub.cancel());
      await flushStreams();
      final perRowBase = DateTime.utc(2020, 1, 1);
      for (var i = 0; i < 10; i++) {
        await storage.upsertDayEntry(
          profileId: 'p1',
          localDate: perRowBase
              .add(Duration(days: i))
              .toIso8601String()
              .substring(0, 10),
          tz: 'UTC',
          flow: FlowLevel.light,
        );
      }
      await flushStreams();
      await perRowSub.cancel();

      final bulkEmissions = <List<DayEntry>>[];
      final bulkSub = storage
          .watchDayEntries(profileId: 'p1')
          .listen(bulkEmissions.add);
      addTearDown(() => bulkSub.cancel());
      await flushStreams();
      bulkEmissions.clear();
      final bulkBase = DateTime.utc(2021, 1, 1);
      await storage.bulkUpsertDayEntries([
        for (var i = 0; i < 10; i++)
          bulkEntry(
            id: 'contrast-$i',
            localDate: bulkBase
                .add(Duration(days: i))
                .toIso8601String()
                .substring(0, 10),
          ),
      ]);
      await flushStreams();

      expect(perRowEmissions.length, greaterThan(bulkEmissions.length),
          reason: '10 per-row saves (${perRowEmissions.length} emissions) '
              'must emit more than one 10-row bulk batch '
              '(${bulkEmissions.length} emissions)');
      expect(bulkEmissions, hasLength(1));
    });

    test('duplicate dates and ids within a batch are last-wins', () async {
      final written = await storage.bulkUpsertDayEntries([
        bulkEntry(id: 'dup-a', localDate: '2026-07-01', flow: FlowLevel.light),
        bulkEntry(id: 'dup-b', localDate: '2026-07-01', flow: FlowLevel.heavy),
        bulkEntry(id: 'dup-c', localDate: '2026-07-02', note: 'first'),
        bulkEntry(id: 'dup-c', localDate: '2026-07-02', note: 'second'),
      ]);

      final rows = await storage.getDayEntries(profileId: 'p1');
      expect(rows, hasLength(2));
      final byDate = {for (final r in rows) r.localDate: r};
      // The second id for the same date updated the first row in place.
      expect(byDate['2026-07-01']!.flow, FlowLevel.heavy);
      expect(byDate['2026-07-01']!.id, 'dup-a');
      expect(byDate['2026-07-02']!.note, 'second');
      expect(byDate['2026-07-02']!.id, 'dup-c');
      expect(written, hasLength(4));
    });

    test('a fresh bulk id for an already-imported date updates it in place',
        () async {
      await storage.upsertDayEntry(
        id: 'existing-1',
        profileId: 'p1',
        localDate: '2026-06-01',
        tz: 'UTC',
        flow: FlowLevel.light,
        updatedAt: t0,
      );

      final written = await storage.bulkUpsertDayEntries([
        bulkEntry(
            id: 'reimport-1',
            localDate: '2026-06-01',
            flow: FlowLevel.heavy),
      ]);

      final rows = await storage.getDayEntries(profileId: 'p1');
      expect(rows, hasLength(1));
      expect(rows.single.id, 'existing-1');
      expect(rows.single.flow, FlowLevel.heavy);
      expect(rows.single.localRev, 2);
      expect(written.single.id, 'existing-1');
    });

    test('bulk update by an existing id bumps strictly after the stored stamp',
        () async {
      await storage.upsertDayEntry(
        id: 'stamp-1',
        profileId: 'p1',
        localDate: '2026-06-02',
        tz: 'UTC',
        flow: FlowLevel.light,
        updatedAt: t0,
      );

      final written = await storage.bulkUpsertDayEntries([
        bulkEntry(
            id: 'stamp-1',
            localDate: '2026-06-02',
            flow: FlowLevel.heavy,
            updatedAt: t0),
      ]);

      expect(written.single.updatedAt.isAfter(t0), isTrue);
      expect(written.single.localRev, 2);
      expect(written.single.dirty, isTrue);
    });

    test('a bad row fails the whole batch with nothing persisted', () async {
      final tooLong = List.filled(kMaxNoteLength + 1, 'x').join();
      await expectLater(
        storage.bulkUpsertDayEntries([
          bulkEntry(id: 'good-1', localDate: '2026-05-01'),
          bulkEntry(id: 'bad-1', localDate: '2026-05-02', note: tooLong),
        ]),
        throwsArgumentError,
      );
      expect(await storage.getDayEntries(profileId: 'p1'), isEmpty);
    });

    test('an observation with a null category fails the batch', () async {
      await expectLater(
        storage.bulkUpsertDayEntries(
          [bulkEntry(id: 'cat-e1', localDate: '2026-05-03')],
          observations: [
            bulkObservation(
                id: 'cat-o1',
                dayEntryId: 'cat-e1',
                localDate: '2026-05-03',
                category: null),
          ],
        ),
        throwsArgumentError,
      );
      expect(await storage.getDayEntries(profileId: 'p1'), isEmpty);
      expect(await storage.getObservationsForDayEntry('cat-e1'), isEmpty);
    });

    test('provenance round-trips through the bulk path', () async {
      final written = await storage.bulkUpsertDayEntries([
        bulkEntry(
          id: 'prov-1',
          localDate: '2026-04-01',
          source: 'clue_import',
          sourceId: 'clue-day-1',
          importId: 'job-1',
        ),
      ]);
      expect(written.single.source, 'clue_import');
      expect(written.single.sourceId, 'clue-day-1');
      expect(written.single.importId, 'job-1');
    });
  });
}
