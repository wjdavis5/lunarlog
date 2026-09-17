/// Storage-level tests for Issue #170's pull-only `day_entry_history`
/// table: the remote-apply round trip (per-page atomicity, cursor advance,
/// retryable rollback), row immutability on re-delivery, the profile wipe
/// cascade, and the domain read seam (`getDayEntryHistoryForProfile`:
/// newest-first ordering, the 90-day window, the domain mapping).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/models/day_entry_history.dart';

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

  RemoteDayEntryHistoryRow historyRow(
    String id,
    String profileId,
    String entryId, {
    DateTime? changedAt,
    String changeKind = 'logged',
    List<String> changedFields = const ['local_date', 'flow'],
    String changedByUserId = 'guardian-a',
    int serverVersion = 1,
  }) =>
      RemoteDayEntryHistoryRow(
        id: id,
        entryId: entryId,
        profileId: profileId,
        changedByUserId: changedByUserId,
        changedAt: changedAt ?? DateTime.utc(2026, 1, 16),
        changeKind: changeKind,
        changedFields: changedFields,
        serverVersion: serverVersion,
      );

  group('remote apply', () {
    test('inserts a pulled row, and a re-delivered row is a no-op '
        '(rows are immutable)', () async {
      final profileId = await seedProfile('A');
      final row = historyRow(
        '01FEED00000000000000000A',
        profileId,
        '01ENTRYAAAAAAAAAAAAAAAAAAA',
        changedAt: DateTime.utc(2026, 1, 16),
      );
      expect(await storage.applyRemoteDayEntryHistory(row), isTrue);
      final stored = await db.select(db.dayEntryHistory).get();
      expect(stored, hasLength(1));
      expect(stored.single.changeKind, 'logged');
      expect(stored.single.changedFields, ['local_date', 'flow']);
      expect(stored.single.changedByUserId, 'guardian-a');

      // The same row re-delivered by a later page is idempotent: the
      // per-id rule lets the remote copy win ties, so the identical row
      // re-applies — but only ever as the same content (rows are
      // immutable server-side; nothing else can arrive for this id).
      await storage.applyRemoteDayEntryHistory(row);
      final afterRedelivery = await db.select(db.dayEntryHistory).get();
      expect(afterRedelivery, hasLength(1));
      expect(afterRedelivery.single.id, stored.single.id);
      expect(afterRedelivery.single.changedAt, stored.single.changedAt);
    });

    test('throws a retryable error when the profile is not held locally',
        () async {
      await expectLater(
        storage.applyRemoteDayEntryHistory(historyRow(
          '01FEED00000000000000000B',
          '01JJJJJJJJJJJJJJJJJJJJJJJJ',
          '01ENTRYAAAAAAAAAAAAAAAAAAA',
        )),
        throwsA(isA<RetryableSyncApplyError>()),
      );
    });

    test('applyRemotePage stores rows and advances the cursor atomically; '
        'a retryable page rolls the cursor back with it', () async {
      final profileId = await seedProfile('A');
      final state = await storage.readSyncState();
      expect(state.cursorDayEntryHistory, 0);

      await storage.applyRemotePage(
        table: SyncTable.dayEntryHistory,
        rows: [
          historyRow('01FEED00000000000000000C', profileId, '01ENTRYAAAAAAAAAAAAAAAAAAA',
              serverVersion: 7, changeKind: 'updated', changedFields: ['note']),
          historyRow('01FEED00000000000000000D', profileId, '01ENTRYAAAAAAAAAAAAAAAAAAA',
              serverVersion: 8,
              changeKind: 'merged_discard',
              changedFields: ['note']),
        ],
        newCursor: 8,
      );
      expect(
        (await storage.readSyncState()).cursorDayEntryHistory, 8,
        reason: 'the page transaction advances the table cursor');
      expect(await db.select(db.dayEntryHistory).get(), hasLength(2));

      // A page whose row references a profile not held locally throws and
      // leaves neither rows nor a moved cursor behind.
      await expectLater(
        storage.applyRemotePage(
          table: SyncTable.dayEntryHistory,
          rows: [
            historyRow('01FEED00000000000000000E', '01JJJJJJJJJJJJJJJJJJJJJJJJ',
                '01ENTRYAAAAAAAAAAAAAAAAAAA', serverVersion: 9),
          ],
          newCursor: 9,
        ),
        throwsA(isA<RetryableSyncApplyError>()),
      );
      expect((await storage.readSyncState()).cursorDayEntryHistory, 8);
      expect(await db.select(db.dayEntryHistory).get(), hasLength(2));
    });

    test('applyRemoteRows (the reconcile path) applies history rows '
        'alongside the profiles they reference', () async {
      final profileId = await seedProfile('A');
      await storage.applyRemoteRows([
        historyRow('01FEED00000000000000000F', profileId, '01ENTRYAAAAAAAAAAAAAAAAAAA',
            serverVersion: 3, changeKind: 'tombstoned',
            changedFields: ['deleted_at', 'flow', 'tags', 'note']),
      ]);
      final rows = await db.select(db.dayEntryHistory).get();
      expect(rows, hasLength(1));
      expect(rows.single.changeKind, 'tombstoned');
    });

    test('a profile purge wipes its history rows; the pull-only table is a '
        'no-op through both push-path helpers', () async {
      final profileId = await seedProfile('A');
      await storage.applyRemoteDayEntryHistory(
          historyRow('01FEED00000000000000000G', profileId, '01ENTRYAAAAAAAAAAAAAAAAAAA'));
      // The same wipe path a server-delivered deleted_profiles row and a
      // guardian revocation both take.
      await storage.applyLocalProfilePurge(profileId);
      expect(await db.select(db.dayEntryHistory).get(), isEmpty);

      expect(
          await storage.markPushed(
              table: SyncTable.dayEntryHistory,
              id: '01FEED00000000000000000G',
              localRevAtPush: 1),
          isFalse,
          reason: 'the pull-only table never pushes: nothing to clear');
      await storage.bumpLocalRevForRetry(
          table: SyncTable.dayEntryHistory, id: '01FEED00000000000000000G');
    });
  });

  group('the read seam (getDayEntryHistoryForProfile)', () {
    test('returns newest-first domain rows scoped to the profile, inside '
        'the 90-day window, honouring the limit', () async {
      final profileId = await seedProfile('A');
      final otherProfileId = await seedProfile('B');
      final fresh = DateTime.utc(2026, 1, 10);
      Future<void> seed(
        String id,
        String profile,
        DateTime changedAt,
        String kind,
        List<String> fields,
      ) =>
          db.into(db.dayEntryHistory).insert(
                DayEntryHistoryCompanion.insert(
                  id: id,
                  entryId: '01ENTRYAAAAAAAAAAAAAAAAAAA',
                  profileId: profile,
                  changedByUserId: 'guardian-a',
                  changedAt: changedAt,
                  changeKind: kind,
                  changedFields: fields,
                ),
              );

      await seed('01FEED00000000000000000H', profileId, fresh, 'logged',
          ['local_date', 'note']);
      await seed('01FEED00000000000000000J', profileId,
          fresh.add(const Duration(hours: 1)), 'merged_discard', ['note']);
      await seed('01FEED00000000000000000K', profileId,
          DateTime.utc(2025, 10, 1), 'updated', ['flow']);
      await seed('01FEED00000000000000000M', otherProfileId, fresh, 'logged',
          ['local_date']);

      final rows = await storage.getDayEntryHistoryForProfile(
        profileId,
        now: fresh.add(const Duration(days: 10)),
      );
      // This profile only, in-window only, newest first.
      expect(rows.map((r) => r.id), [
        '01FEED00000000000000000J',
        '01FEED00000000000000000H',
      ]);
      // Domain mapping: kind parsed, fields carried, attribution kept.
      final discard = rows.first;
      expect(discard.kind, DayEntryChangeKind.mergedDiscard);
      expect(discard.changedFields, ['note']);
      expect(discard.changedByUserId, 'guardian-a');
      expect(discard.entryId, '01ENTRYAAAAAAAAAAAAAAAAAAA');
      expect(discard.kind.toDb(), 'merged_discard');

      expect(
        (await storage.getDayEntryHistoryForProfile(
          profileId,
          now: fresh.add(const Duration(days: 10)),
          limit: 1,
        ))
            .map((r) => r.id),
        ['01FEED00000000000000000J'],
        reason: 'the limit bounds the feed page',
      );
    });

    test('DayEntryChangeKind.fromDb degrades an unknown wire value to '
        'updated rather than throwing', () {
      expect(DayEntryChangeKind.fromDb('logged'), DayEntryChangeKind.logged);
      expect(
          DayEntryChangeKind.fromDb('merged_discard'), DayEntryChangeKind.mergedDiscard);
      expect(DayEntryChangeKind.fromDb('tombstoned'), DayEntryChangeKind.tombstoned);
      expect(DayEntryChangeKind.fromDb('nonsense'), DayEntryChangeKind.updated);
    });
  });
}
