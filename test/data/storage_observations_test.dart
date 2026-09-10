/// Issue #240: `LunarLogStorage`'s observations API — upsert (id-keyed, no
/// same-date resolver, unlike day entries), tombstone payload clearing,
/// dirty/local_rev bookkeeping, `readDirtyObservations`, and
/// `applyRemoteObservation`'s per-id LWW rule plus its referential-
/// integrity guard. Mirrors `storage_sync_test.dart`'s shape for the
/// existing tables.
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
    await storage.upsertDayEntry(
      profileId: 'p1',
      localDate: '2026-09-01',
      tz: 'UTC',
      flow: FlowLevel.none,
      updatedAt: t0,
    );
  });

  Future<Observation?> observationById(String id) => (db.select(
    db.observations,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<String> entryId() async =>
      (await storage.getDayEntries(profileId: 'p1')).single.id;

  RemoteObservationRow remoteObservation(
    String id, {
    required String dayEntryId,
    String profileId = 'p1',
    String localDate = '2026-09-01',
    String? category = 'pain',
    String? code = 'migraine',
    int? intensity = 3,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) => RemoteObservationRow(
    id: id,
    dayEntryId: dayEntryId,
    profileId: profileId,
    localDate: localDate,
    tz: 'UTC',
    category: category,
    code: code,
    intensity: intensity,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );

  group('upsertObservation', () {
    test('inserts a new observation, dirty, local_rev 1', () async {
      final dayEntryId = await entryId();
      final o = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        code: 'migraine',
        intensity: 3,
      );
      expect(o.category, 'pain');
      expect(o.code, 'migraine');
      expect(o.intensity, 3);
      expect(o.dirty, isTrue);
      expect(o.localRev, 1);
      expect(o.dayEntryId, dayEntryId);
    });

    test('issue #252: an appointments (single-event) observation round-'
        'trips a non-null observed_at', () async {
      final dayEntryId = await entryId();
      // Appointments are issue #252's clearest single-event category: the
      // observation carries the exact moment (#240's nullable observed_at
      // column), not just the entry's local date.
      final at = DateTime.utc(2026, 9, 1, 14, 30);
      final o = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        observedAt: at,
        tz: 'UTC',
        category: 'appointments',
        code: 'doctor_appt',
      );
      expect(o.category, 'appointments');
      expect(o.observedAt, at);
      final reread = await observationById(o.id);
      expect(
        reread!.observedAt,
        at,
        reason: 'the exact time survives the write, not just the date',
      );
    });

    test(
      'updating by id in place bumps updated_at strictly and local_rev',
      () async {
        final dayEntryId = await entryId();
        final first = await storage.upsertObservation(
          id: 'o1',
          dayEntryId: dayEntryId,
          profileId: 'p1',
          localDate: '2026-09-01',
          tz: 'UTC',
          category: 'pain',
          code: 'migraine',
          updatedAt: t0,
        );
        clock.now = t0; // same instant: the strict-bump rule must still apply
        final second = await storage.upsertObservation(
          id: 'o1',
          dayEntryId: dayEntryId,
          profileId: 'p1',
          localDate: '2026-09-01',
          tz: 'UTC',
          category: 'pain',
          code: 'headache',
          updatedAt: t0,
        );
        expect(second.id, first.id);
        expect(second.code, 'headache');
        expect(second.localRev, 2);
        expect(second.updatedAt.isAfter(first.updatedAt), isTrue);
      },
    );

    test('multiple live rows for the same (profile, date, category) are '
        'allowed — no same-date resolver, unlike day entries', () async {
      final dayEntryId = await entryId();
      await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'sex',
        code: 'protected',
      );
      await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'sex',
        code: 'unprotected',
      );
      final rows = await storage.getObservationsForDayEntry(dayEntryId);
      expect(rows, hasLength(2));
    });

    test('throws for a category over the length bound', () async {
      final dayEntryId = await entryId();
      expect(
        () => storage.upsertObservation(
          dayEntryId: dayEntryId,
          profileId: 'p1',
          localDate: '2026-09-01',
          tz: 'UTC',
          category: 'x' * 65,
        ),
        throwsArgumentError,
      );
    });

    test('throws for an intensity outside 1-5', () async {
      final dayEntryId = await entryId();
      expect(
        () => storage.upsertObservation(
          dayEntryId: dayEntryId,
          profileId: 'p1',
          localDate: '2026-09-01',
          tz: 'UTC',
          category: 'pain',
          intensity: 6,
        ),
        throwsArgumentError,
      );
    });

    test('throws for a code over the length bound', () async {
      final dayEntryId = await entryId();
      expect(
        () => storage.upsertObservation(
          dayEntryId: dayEntryId,
          profileId: 'p1',
          localDate: '2026-09-01',
          tz: 'UTC',
          category: 'pain',
          code: 'x' * (kMaxObservationCodeLength + 1),
        ),
        throwsArgumentError,
      );
    });

    test('accepts a code exactly at the length bound', () async {
      final dayEntryId = await entryId();
      final observation = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        code: 'x' * kMaxObservationCodeLength,
      );
      expect(observation.code, hasLength(kMaxObservationCodeLength));
    });

    test('throws for a valueText over the length bound', () async {
      final dayEntryId = await entryId();
      expect(
        () => storage.upsertObservation(
          dayEntryId: dayEntryId,
          profileId: 'p1',
          localDate: '2026-09-01',
          tz: 'UTC',
          category: 'pain',
          valueText: 'x' * (kMaxObservationValueTextLength + 1),
        ),
        throwsArgumentError,
      );
    });

    test('throws for a unit over the length bound', () async {
      final dayEntryId = await entryId();
      expect(
        () => storage.upsertObservation(
          dayEntryId: dayEntryId,
          profileId: 'p1',
          localDate: '2026-09-01',
          tz: 'UTC',
          category: 'bbt',
          unit: 'x' * (kMaxObservationUnitLength + 1),
        ),
        throwsArgumentError,
      );
    });

    test('throws for a sourceId over the length bound', () async {
      final dayEntryId = await entryId();
      expect(
        () => storage.upsertObservation(
          dayEntryId: dayEntryId,
          profileId: 'p1',
          localDate: '2026-09-01',
          tz: 'UTC',
          category: 'pain',
          sourceId: 'x' * (kMaxObservationSourceIdLength + 1),
        ),
        throwsArgumentError,
      );
    });

    test('throws for a raw payload over the UTF-8 byte bound even when '
        'String.length is under it (multi-byte characters near the '
        'limit — review finding: the bound is UTF-8 bytes, not UTF-16 code '
        'units)', () async {
      final dayEntryId = await entryId();
      // Each '💙' is one UTF-16 code unit pair (2 code units) but encodes to
      // 4 UTF-8 bytes, so half as many code units as `kMaxObservationRawLength`
      // still exceeds it in bytes.
      final raw = '💙' * ((kMaxObservationRawLength ~/ 4) + 1);
      expect(raw.length, lessThan(kMaxObservationRawLength));
      expect(
        () => storage.upsertObservation(
          dayEntryId: dayEntryId,
          profileId: 'p1',
          localDate: '2026-09-01',
          tz: 'UTC',
          category: 'pain',
          raw: raw,
        ),
        throwsArgumentError,
      );
    });

    test('accepts a raw payload of multi-byte characters at exactly the '
        'UTF-8 byte bound', () async {
      final dayEntryId = await entryId();
      // 4 bytes each; kMaxObservationRawLength is divisible by 4.
      expect(kMaxObservationRawLength % 4, 0);
      final raw = '💙' * (kMaxObservationRawLength ~/ 4);
      final observation = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        raw: raw,
      );
      expect(observation.raw, raw);
    });
  });

  group('getObservationsForProfile', () {
    test('returns every observation across the profile\'s day entries, '
        'filtering tombstones by default (Issue #240; account export '
        '`kAccountExportSchemaVersion` v3 reads through this)', () async {
      final dayEntryId = await entryId();
      final live = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        code: 'migraine',
      );
      final tombstoned = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'mood',
        code: 'anxious',
      );
      await storage.softDeleteObservation(tombstoned.id);

      final rows = await storage.getObservationsForProfile('p1');
      expect(rows.map((r) => r.id), [live.id]);

      final withTombstones = await storage.getObservationsForProfile(
        'p1',
        includeTombstones: true,
      );
      expect(withTombstones, hasLength(2));
    });

    test('is empty for a profile with no observations', () async {
      expect(await storage.getObservationsForProfile('p1'), isEmpty);
    });
  });

  group('softDeleteObservation', () {
    test('clears the payload, category included, but keeps '
        'local_date/tz/day_entry_id', () async {
      final dayEntryId = await entryId();
      final o = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        code: 'migraine',
        intensity: 3,
        valueText: 'note-like text',
      );
      await storage.softDeleteObservation(o.id);
      final row = await observationById(o.id);
      expect(row!.deletedAt, isNotNull);
      expect(row.code, isNull);
      expect(row.intensity, isNull);
      expect(row.valueText, isNull);
      expect(
        row.category,
        isNull,
        reason:
            'review finding: category is cleared on tombstone too, '
            'no longer the exception to the tombstone-payload rule',
      );
      expect(row.localDate, '2026-09-01');
      expect(row.dayEntryId, dayEntryId);
      expect(row.dirty, isTrue);
    });

    test('is idempotent: re-deleting a tombstone does not bump updated_at '
        'again', () async {
      final dayEntryId = await entryId();
      final o = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
      );
      await storage.softDeleteObservation(o.id);
      final first = await observationById(o.id);
      clock.now = clock.now.add(const Duration(minutes: 5));
      await storage.softDeleteObservation(o.id);
      final second = await observationById(o.id);
      expect(second!.updatedAt, first!.updatedAt);
    });

    test('is a no-op for an id not held locally', () async {
      await storage.softDeleteObservation('nonexistent');
      expect(await observationById('nonexistent'), isNull);
    });
  });

  group('dirty tracking', () {
    test('dirtyCount includes observations', () async {
      final dayEntryId = await entryId();
      final before = await storage.dirtyCount();
      await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
      );
      expect(await storage.dirtyCount(), before + 1);
    });

    test('readDirtyObservations pages by id, tombstones included', () async {
      final dayEntryId = await entryId();
      final a = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        code: 'a',
      );
      await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        code: 'b',
      );
      final page1 = await storage.readDirtyObservations(limit: 1);
      expect(page1, hasLength(1));
      final page2 = await storage.readDirtyObservations(
        limit: 1,
        afterId: page1.single.id,
      );
      expect(page2, hasLength(1));
      expect(page2.single.id, isNot(page1.single.id));

      await storage.softDeleteObservation(a.id);
      final all = await storage.readDirtyObservations();
      expect(all.map((o) => o.id), containsAll([a.id]));
    });

    test('markPushed clears dirty only when local_rev still matches', () async {
      final dayEntryId = await entryId();
      final o = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
      );
      final cleared = await storage.markPushed(
        table: SyncTable.observations,
        id: o.id,
        localRevAtPush: o.localRev,
      );
      expect(cleared, isTrue);
      expect((await observationById(o.id))!.dirty, isFalse);
    });

    test('markPushed declines when a local write landed since the push '
        'was assembled (AE11)', () async {
      final dayEntryId = await entryId();
      final o = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
      );
      final staleRev = o.localRev;
      await storage.upsertObservation(
        id: o.id,
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        code: 'migraine',
      );
      final cleared = await storage.markPushed(
        table: SyncTable.observations,
        id: o.id,
        localRevAtPush: staleRev,
      );
      expect(cleared, isFalse);
      expect((await observationById(o.id))!.dirty, isTrue);
    });

    test('markAllDirty flags every observation and bumps local_rev', () async {
      final dayEntryId = await entryId();
      final o = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
      );
      await storage.markPushed(
        table: SyncTable.observations,
        id: o.id,
        localRevAtPush: o.localRev,
      );
      expect((await observationById(o.id))!.dirty, isFalse);
      await storage.markAllDirty();
      final row = await observationById(o.id);
      expect(row!.dirty, isTrue);
      expect(row.localRev, o.localRev + 1);
    });
  });

  group('isEmpty', () {
    test('a database holding an observation is not reported empty '
        '(observations are counted alongside profiles/day entries, not '
        'just the two LocalRowCounts fields)', () async {
      // The fixture profile/day entry from setUp already make isEmpty()
      // false on their own; this test's point is that isEmpty()'s own
      // logic explicitly checks observations too (see its doc comment),
      // not that this particular fixture happens to be non-empty for an
      // unrelated reason — a regression that dropped the observations
      // check from isEmpty() would not be caught by any *other* test in
      // this file, since every one of them already has a day entry.
      final dayEntryId = await entryId();
      await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
      );
      expect(await storage.isEmpty(), isFalse);
    });
  });

  group('applyRemoteObservation', () {
    test('inserts a new remote row not dirty', () async {
      final dayEntryId = await entryId();
      final applied = await storage.applyRemoteObservation(
        remoteObservation('r1', dayEntryId: dayEntryId, updatedAt: t0),
      );
      expect(applied, isTrue);
      final row = await observationById('r1');
      expect(row!.dirty, isFalse);
      expect(row.category, 'pain');
      expect(row.code, 'migraine');
    });

    test('per-id LWW: an older remote row is declined, keeping the local '
        'copy', () async {
      final dayEntryId = await entryId();
      await storage.applyRemoteObservation(
        remoteObservation(
          'r1',
          dayEntryId: dayEntryId,
          code: 'newer',
          updatedAt: t0.add(const Duration(hours: 1)),
        ),
      );
      final applied = await storage.applyRemoteObservation(
        remoteObservation(
          'r1',
          dayEntryId: dayEntryId,
          code: 'older',
          updatedAt: t0,
        ),
      );
      expect(applied, isFalse);
      expect((await observationById('r1'))!.code, 'newer');
    });

    test('the remote copy wins a tie', () async {
      final dayEntryId = await entryId();
      await storage.applyRemoteObservation(
        remoteObservation(
          'r1',
          dayEntryId: dayEntryId,
          code: 'first',
          updatedAt: t0,
        ),
      );
      final applied = await storage.applyRemoteObservation(
        remoteObservation(
          'r1',
          dayEntryId: dayEntryId,
          code: 'second',
          updatedAt: t0,
        ),
      );
      expect(applied, isTrue);
      expect((await observationById('r1'))!.code, 'second');
    });

    test(
      'a tombstoned remote row clears the payload, category included',
      () async {
        final dayEntryId = await entryId();
        await storage.applyRemoteObservation(
          remoteObservation(
            'r1',
            dayEntryId: dayEntryId,
            code: 'migraine',
            updatedAt: t0,
          ),
        );
        await storage.applyRemoteObservation(
          remoteObservation(
            'r1',
            dayEntryId: dayEntryId,
            category: null,
            code: null,
            intensity: null,
            updatedAt: t0.add(const Duration(hours: 1)),
            deletedAt: t0.add(const Duration(hours: 1)),
          ),
        );
        final row = await observationById('r1');
        expect(row!.deletedAt, isNotNull);
        expect(row.code, isNull);
        expect(
          row.category,
          isNull,
          reason:
              'review finding: category is cleared on tombstone too, '
              'no longer the exception to the tombstone-payload rule',
        );
      },
    );

    test('throws RetryableSyncApplyError when the day entry is not held '
        'locally', () async {
      expect(
        () => storage.applyRemoteObservation(
          remoteObservation(
            'r1',
            dayEntryId: 'nonexistent-day-entry',
            updatedAt: t0,
          ),
        ),
        throwsA(isA<RetryableSyncApplyError>()),
      );
    });
  });

  group('applyRemotePage / applyRemoteRows / applyResolved', () {
    test('applyRemotePage advances cursor_observations in the same '
        'transaction as the rows', () async {
      final dayEntryId = await entryId();
      await storage.applyRemotePage(
        table: SyncTable.observations,
        rows: [remoteObservation('r1', dayEntryId: dayEntryId, updatedAt: t0)],
        newCursor: 5,
      );
      expect((await storage.readSyncState()).cursorObservations, 5);
      expect(await observationById('r1'), isNotNull);
    });

    test('applyRemoteRows applies an observation alongside a profile in '
        'one transaction', () async {
      final dayEntryId = await entryId();
      await storage.applyRemoteRows([
        remoteObservation('r1', dayEntryId: dayEntryId, updatedAt: t0),
      ]);
      expect(await observationById('r1'), isNotNull);
    });

    test('applyResolved only touches an id already held locally (never '
        'inserts)', () async {
      await storage.applyResolved([
        remoteObservation('never-seen', dayEntryId: 'whatever', updatedAt: t0),
      ]);
      expect(await observationById('never-seen'), isNull);
    });

    test('applyResolved overwrites a held row with dirty = false', () async {
      final dayEntryId = await entryId();
      final o = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        code: 'mine',
        updatedAt: t0,
      );
      await storage.applyResolved([
        remoteObservation(
          o.id,
          dayEntryId: dayEntryId,
          code: 'servers',
          updatedAt: t0.add(const Duration(hours: 1)),
        ),
      ]);
      final row = await observationById(o.id);
      expect(row!.code, 'servers');
      expect(row.dirty, isFalse);
    });
  });
}
