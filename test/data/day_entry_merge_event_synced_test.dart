/// Storage-level tests for Issue #130's SYNCED merge-disclosure recording:
/// `LunarLogStorage._resolveSameDateConflicts` writes the same rows the
/// server's own resolver emits (`day_entry_merge_events`), with the losing
/// value's text retained for author recovery — and nothing else does
/// (tags-only merges and same-id convergences stay silent).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/sync/sync_transport.dart';
import 'package:lunarlog/domain/logging/merge_notice_dismissals.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late LunarLogStorage storage;
  // t0 stamps every local write; remote rows carry explicit stamps.
  final t0 = DateTime.utc(2026, 1, 15, 8);

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    storage = LunarLogStorage(db, clock: () => t0);
  });

  Future<String> seedProfile(String name) async {
    final profile = await storage.upsertProfile(displayName: name, isMinor: true);
    return profile.id;
  }

  RemoteDayEntryRow remoteRow(
    String id,
    String profileId, {
    String localDate = '2026-01-15',
    FlowLevel flow = FlowLevel.medium,
    List<String> tags = const ['remote'],
    String? note = 'from remote',
    required DateTime updatedAt,
    String? loggedByUserId,
    String? lastModifiedByUserId,
    DateTime? deletedAt,
  }) =>
      RemoteDayEntryRow(
        id: id,
        profileId: profileId,
        localDate: localDate,
        tz: 'UTC',
        flow: flow,
        tags: tags,
        note: note,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        loggedByUserId: loggedByUserId,
        lastModifiedByUserId: lastModifiedByUserId,
      );

  Future<List<DayEntryMergeEventData>> mergeRows(String profileId) async {
    final rows = await storage.getDayEntryMergeEventsForDay(
      profileId,
      '2026-01-15',
      now: t0.add(const Duration(days: 1)),
    );
    return rows;
  }

  group('same-date resolver, local loser', () {
    test('differing note and flow records two synced events carrying the '
        'losing text, dirty for push, with both row ids and authors',
        () async {
      final profileId = await seedProfile('A');
      final local = await storage.upsertDayEntry(
        profileId: profileId,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.heavy,
        tags: const ['local'],
        note: 'local note',
      );
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        flow: FlowLevel.light,
        note: 'remote note',
        updatedAt: DateTime.utc(2026, 1, 16),
        loggedByUserId: 'dad',
        lastModifiedByUserId: 'dad',
      ));
      final rows = await mergeRows(profileId);
      expect(rows, hasLength(2));
      final note = rows.singleWhere((r) => r.field == 'note');
      final flow = rows.singleWhere((r) => r.field == 'flow');
      // AC: the discarded text is retained for the losing author.
      expect(note.losingValueText, 'local note');
      expect(flow.losingValueText, 'heavy');
      // Row ids: the remote row won, the local row lost.
      expect(note.winningRowId, '01JREMOTE00000000000000000A');
      expect(note.losingRowId, local.id);
      // Authorship is carried as display attribution.
      expect(note.winningAuthorUserId, 'dad');
      // Dirty so the disclosure rides the next push to the server.
      expect(rows.every((r) => r.dirty), isTrue,
          reason: 'synced merge events must be marked dirty for push');
    });

    test('identical payload records nothing (nothing was discarded)',
        () async {
      final profileId = await seedProfile('A');
      await storage.upsertDayEntry(
        profileId: profileId,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.medium,
        note: 'same note',
      );
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        flow: FlowLevel.medium,
        note: 'same note',
        updatedAt: DateTime.utc(2026, 1, 16),
      ));
      expect(await mergeRows(profileId), isEmpty);
    });

    test('tags-only difference records nothing (tags are unioned)', () async {
      final profileId = await seedProfile('A');
      await storage.upsertDayEntry(
        profileId: profileId,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.medium,
        tags: const ['a'],
        note: 'same note',
      );
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        tags: const ['b'],
        flow: FlowLevel.medium,
        note: 'same note',
        updatedAt: DateTime.utc(2026, 1, 16),
      ));
      expect(await mergeRows(profileId), isEmpty);
    });

    test('a natural-key duplicate is not recorded twice', () async {
      final profileId = await seedProfile('A');
      final local = await storage.upsertDayEntry(
        profileId: profileId,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.heavy,
        note: 'local note',
      );
      // The server's own emission of the same discard, already pulled.
      await db.into(db.dayEntryMergeEvents).insert(
            DayEntryMergeEventsCompanion.insert(
              id: '01JREMOTE0000000000000000EV',
              profileId: profileId,
              localDate: '2026-01-15',
              winningRowId: '01JREMOTE00000000000000000A',
              losingRowId: local.id,
              field: 'note',
              losingValueText: 'local note',
              createdAt: DateTime.utc(2026, 1, 16),
              updatedAt: DateTime.utc(2026, 1, 16),
            ),
          );
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        flow: FlowLevel.light,
        note: 'remote note',
        updatedAt: DateTime.utc(2026, 1, 17),
      ));
      final rows = await mergeRows(profileId);
      // The note discard keeps the already-recorded row (the local id was
      // never minted); the flow discard is new.
      expect(rows.where((r) => r.field == 'note'), hasLength(1));
      expect(rows.where((r) => r.field == 'flow'), hasLength(1));
    });
  });

  group('same-date resolver, remote loser', () {
    test('the incoming remote row is the loser: its text is retained',
        () async {
      final profileId = await seedProfile('A');
      await storage.upsertDayEntry(
        profileId: profileId,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.light,
        note: 'kept local note',
      );
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000B',
        profileId,
        flow: FlowLevel.heavy,
        note: 'lost remote note',
        updatedAt: DateTime.utc(2026, 1, 14), // older: loses
        loggedByUserId: 'mom',
        lastModifiedByUserId: 'mom',
      ));
      final rows = await mergeRows(profileId);
      expect(rows, hasLength(2));
      final note = rows.singleWhere((r) => r.field == 'note');
      expect(note.losingValueText, 'lost remote note');
      expect(note.losingRowId, '01JREMOTE00000000000000000B');
      expect(note.losingAuthorUserId, 'mom');
    });
  });

  group('same-id convergence (ordinary edit of one row)', () {
    test('a per-id overwrite with a different note records nothing',
        () async {
      final profileId = await seedProfile('A');
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000C',
        profileId,
        note: 'first',
        updatedAt: DateTime.utc(2026, 1, 15),
      ));
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000C', // same id: no same-date resolver runs
        profileId,
        note: 'second',
        updatedAt: DateTime.utc(2026, 1, 16),
      ));
      expect(await mergeRows(profileId), isEmpty);
    });
  });

  group('remote apply of a merge event', () {
    test('inserts the row clean (not dirty), and skips it when the same '
        'discard is already held under a local id (dismissal keys stay '
        'stable)', () async {
      final profileId = await seedProfile('A');
      await storage.applyRemoteDayEntryMergeEvent(RemoteDayEntryMergeEventRow(
        id: '01JREMOTE00000000000000000D',
        profileId: profileId,
        localDate: '2026-01-15',
        winningRowId: '01JREMOTE00000000000000000A',
        losingRowId: '01JREMOTE00000000000000000B',
        field: 'note',
        losingValueText: 'a server-recorded discard',
        createdAt: DateTime.utc(2026, 1, 16),
        updatedAt: DateTime.utc(2026, 1, 16),
        serverVersion: 9,
      ));
      final rows = await mergeRows(profileId);
      expect(rows, hasLength(1));
      expect(rows.single.losingValueText, 'a server-recorded discard');
      expect(rows.single.dirty, isFalse);
      // The natural key is already held: a different-id row for the same
      // discard is a no-op, not a duplicate.
      await storage.applyRemoteDayEntryMergeEvent(RemoteDayEntryMergeEventRow(
        id: '01JREMOTE00000000000000000E',
        profileId: profileId,
        localDate: '2026-01-15',
        winningRowId: '01JREMOTE00000000000000000A',
        losingRowId: '01JREMOTE00000000000000000B',
        field: 'note',
        losingValueText: 'a server-recorded discard',
        createdAt: DateTime.utc(2026, 1, 17),
        updatedAt: DateTime.utc(2026, 1, 17),
        serverVersion: 10,
      ));
      expect(await mergeRows(profileId), hasLength(1));
    });

    test('throws a retryable error when the profile is not held locally',
        () async {
      await expectLater(
        storage.applyRemoteDayEntryMergeEvent(RemoteDayEntryMergeEventRow(
          id: '01JREMOTE00000000000000000F',
          profileId: '01JJJJJJJJJJJJJJJJJJJJJJJJ',
          localDate: '2026-01-15',
          winningRowId: '01JREMOTE00000000000000000A',
          losingRowId: '01JREMOTE00000000000000000B',
          field: 'flow',
          losingValueText: 'heavy',
          createdAt: DateTime.utc(2026, 1, 16),
          updatedAt: DateTime.utc(2026, 1, 16),
        )),
        throwsA(isA<RetryableSyncApplyError>()),
      );
    });
  });

  group('the 30-day display window and device-local dismissal', () {
    test('an event older than the window stops rendering; a dismissed id is '
        'filtered by the repository-level read via the settings store',
        () async {
      final profileId = await seedProfile('A');
      final fresh = DateTime.utc(2026, 1, 10);
      await db.into(db.dayEntryMergeEvents).insert(
            DayEntryMergeEventsCompanion.insert(
              id: '01JREMOTE00000000000000000G',
              profileId: profileId,
              localDate: '2026-01-15',
              winningRowId: '01JREMOTE00000000000000000A',
              losingRowId: '01JREMOTE00000000000000000B',
              field: 'note',
              losingValueText: 'fresh discard',
              createdAt: fresh,
              updatedAt: fresh,
            ),
          );
      await db.into(db.dayEntryMergeEvents).insert(
            DayEntryMergeEventsCompanion.insert(
              id: '01JREMOTE00000000000000000H',
              profileId: profileId,
              localDate: '2026-01-14',
              winningRowId: '01JREMOTE00000000000000000A',
              losingRowId: '01JREMOTE00000000000000000C',
              field: 'note',
              losingValueText: 'stale discard',
              createdAt: DateTime.utc(2025, 11, 1),
              updatedAt: DateTime.utc(2025, 11, 1),
            ),
          );
      // now = fresh + 10 days: the January event is inside the window, the
      // November one is far outside it.
      final visible = await storage.getDayEntryMergeEventsForDay(
        profileId,
        '2026-01-15',
        now: fresh.add(const Duration(days: 10)),
      );
      expect(visible.map((r) => r.losingValueText), ['fresh discard']);

      // Dismissal: device-local, keyed by event id, round-trips through the
      // settings store the repository read consumes.
      await storage.dismissDayEntryMergeEvent(
          profileId: profileId, eventId: '01JREMOTE00000000000000000G');
      final stored = await storage
          .getSetting(mergeNoticeDismissalsKey(profileId));
      expect(
        decodeMergeNoticeDismissals(stored),
        ['01JREMOTE00000000000000000G'],
      );
      // Idempotent.
      await storage.dismissDayEntryMergeEvent(
          profileId: profileId, eventId: '01JREMOTE00000000000000000G');
      expect(
        decodeMergeNoticeDismissals(await storage
            .getSetting(mergeNoticeDismissalsKey(profileId))),
        ['01JREMOTE00000000000000000G'],
      );
    });

    test('the per-PROFILE read (the local export surface) spans every date, '
        'stays inside the 30-day window, and ignores dismissals',
        () async {
      final profileId = await seedProfile('A');
      final otherProfileId = await seedProfile('B');
      final fresh = DateTime.utc(2026, 1, 10);
      Future<void> seed(
      String id,
      String profile,
      String date,
      String text,
      DateTime createdAt, {
      String losingRowId = '01JREMOTE00000000000000000Z',
    }) =>
          db.into(db.dayEntryMergeEvents).insert(
                DayEntryMergeEventsCompanion.insert(
                  id: id,
                  profileId: profile,
                  localDate: date,
                  winningRowId: '01JREMOTE00000000000000000A',
                  losingRowId: losingRowId,
                  field: 'note',
                  losingValueText: text,
                  createdAt: createdAt,
                  updatedAt: createdAt,
                ),
              );
      await seed('01JREMOTE00000000000000000I', profileId, '2026-01-13',
          'fresh one', fresh,
          losingRowId: '01JREMOTE00000000000000000B');
      await seed('01JREMOTE00000000000000000J', profileId, '2026-01-15',
          'fresh two', fresh,
          losingRowId: '01JREMOTE00000000000000000C');
      await seed('01JREMOTE00000000000000000K', profileId, '2025-12-01',
          'stale', DateTime.utc(2025, 11, 1),
          losingRowId: '01JREMOTE00000000000000000D');
      await seed('01JREMOTE00000000000000000L', otherProfileId, '2026-01-15',
          'other profile', fresh,
          losingRowId: '01JREMOTE00000000000000000E');

      final rows = await storage.getDayEntryMergeEventsForProfile(
        profileId,
        now: fresh.add(const Duration(days: 10)),
      );
      // Every in-window date for THIS profile, ordered by id; the stale row
      // and the other profile's row are both absent.
      expect(rows.map((r) => r.losingValueText), ['fresh one', 'fresh two']);

      // A dismissal removes the row from the DAY read (the notice surface)
      // but NOT from the profile read (the export surface): a dismissed
      // notice is a display choice, not a deletion of the record.
      await storage.dismissDayEntryMergeEvent(
          profileId: profileId, eventId: '01JREMOTE00000000000000000I');
      final afterDismiss = await storage.getDayEntryMergeEventsForProfile(
        profileId,
        now: fresh.add(const Duration(days: 10)),
      );
      expect(afterDismiss.map((r) => r.losingValueText),
          ['fresh one', 'fresh two']);
    });
  });

  group('the push path (dirty flags, markPushed, retry)', () {
    test('readDirty pages by id; markPushed clears on a rev match and '
        'refuses a stale one; bumpLocalRevForRetry re-dirties', () async {
      final profileId = await seedProfile('A');
      final loser = await storage.upsertDayEntry(
        profileId: profileId,
        localDate: '2026-01-14',
        tz: 'UTC',
        flow: FlowLevel.light,
        note: 'local original',
      );
      // A remote winner for the same date as a SECOND local row triggers
      // the resolver and leaves one dirty synced disclosure behind (the
      // flows match, so only the note loses — exactly one event).
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE0000000000000000R2',
        profileId,
        localDate: '2026-01-14',
        note: 'remote winner',
        flow: FlowLevel.light,
        updatedAt: t0.add(const Duration(hours: 1)),
      ));
      expect(loser.note, 'local original');
      final dirty = await storage.readDirtyDayEntryMergeEvents();
      expect(dirty, hasLength(1));
      expect(dirty.single.field, 'note');

      final page =
          await storage.readDirtyDayEntryMergeEvents(limit: 1);
      expect(page, hasLength(1));
      expect(
          await storage.readDirtyDayEntryMergeEvents(
              limit: 1, afterId: page.single.id),
          isEmpty);

      expect(
          await storage.markPushed(
              table: SyncTable.dayEntryMergeEvents,
              id: dirty.single.id,
              localRevAtPush: 99),
          isFalse,
          reason: 'a stale local_rev never clears dirty');
      expect(
          await storage.markPushed(
              table: SyncTable.dayEntryMergeEvents,
              id: dirty.single.id,
              localRevAtPush: dirty.single.localRev),
          isTrue);
      expect(await storage.readDirtyDayEntryMergeEvents(), isEmpty);

      // The retry affordance re-arms the row's push eligibility.
      await storage.bumpLocalRevForRetry(
          table: SyncTable.dayEntryMergeEvents, id: dirty.single.id);
      final reDirty = await storage.readDirtyDayEntryMergeEvents();
      expect(reDirty, hasLength(1));
      expect(reDirty.single.localRev, greaterThan(dirty.single.localRev));
    });

    test('a pull-only table is a harmless no-op through both paths',
        () async {
      expect(
          await storage.markPushed(
              table: SyncTable.profileGuardians,
              id: '01JREMOTE0000000000000000G9',
              localRevAtPush: 1),
          isFalse);
      await storage.bumpLocalRevForRetry(
          table: SyncTable.deletedProfiles,
          id: '01JREMOTE0000000000000000G8');
    });

    test('a push batch rejects more than 500 merge events', () {
      expect(
        () => PushBatch(
          mergeEvents: List.filled(PushBatch.maxRows + 1, const {}),
        ),
        throwsArgumentError,
      );
    });
  });
}
