/// Issue #128: `LunarLogStorage`'s care_notes and visit_prep_items API —
/// per-profile standing notes and checklist items with #224-style
/// payload-free tombstones, dirty/local_rev bookkeeping, `readDirty*`
/// keyset paging, `markPushed`, the `applyRemote*` per-id LWW rule plus the
/// referential-integrity guard, and the R5 revocation-wipe extension.
/// Mirrors `storage_modes_test.dart`'s shape.
library;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
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
  final t1 = DateTime.utc(2026, 9, 2, 8);
  final t2 = DateTime.utc(2026, 9, 3, 8);

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    clock = FixedClock(t0);
    storage = LunarLogStorage(db, clock: clock.call);
    await storage.upsertProfile(
        id: 'p1', displayName: 'Riley', isMinor: true, updatedAt: t0);
  });

  RemoteCareNoteRow remoteNote(
    String id, {
    String profileId = 'p1',
    String body = 'Prefers the blue inhaler.',
    required DateTime updatedAt,
    DateTime? deletedAt,
    String? loggedByUserId,
    String? lastModifiedByUserId,
    int serverVersion = 0,
  }) =>
      RemoteCareNoteRow(
        id: id,
        profileId: profileId,
        body: body,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        serverVersion: serverVersion,
        loggedByUserId: loggedByUserId,
        lastModifiedByUserId: lastModifiedByUserId,
      );

  RemoteVisitPrepItemRow remoteItem(
    String id, {
    String profileId = 'p1',
    String body = 'Ask about iron levels.',
    bool isChecked = false,
    String? checkedByUserId,
    DateTime? checkedAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
    int serverVersion = 0,
  }) =>
      RemoteVisitPrepItemRow(
        id: id,
        profileId: profileId,
        body: body,
        isChecked: isChecked,
        checkedByUserId: checkedByUserId,
        checkedAt: checkedAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        serverVersion: serverVersion,
      );

  group('care_notes', () {
    test('upsert creates a dirty note; a second write updates in place',
        () async {
      final row = await storage.upsertCareNote(
          profileId: 'p1', body: 'First.');
      expect(row.profileId, 'p1');
      expect(row.body, 'First.');
      expect(row.dirty, isTrue);
      expect(row.localRev, 1);
      expect(row.updatedAt, t0);
      expect(row.deletedAt, isNull);

      clock.now = t1;
      final again = await storage.upsertCareNote(
          id: row.id, profileId: 'p1', body: 'Revised.');
      expect(again.id, row.id);
      expect(again.body, 'Revised.');
      expect(again.localRev, 2);
      expect(again.updatedAt, t1);
      expect(await storage.getCareNotesForProfile('p1'), hasLength(1));
    });

    test('an update with a stale clock still bumps updated_at past stored',
        () async {
      final row = await storage.upsertCareNote(
          profileId: 'p1', body: 'First.', updatedAt: t1);
      final again = await storage.upsertCareNote(
          id: row.id, profileId: 'p1', body: 'Revised.', updatedAt: t0);
      expect(again.updatedAt.isAfter(t1), isTrue,
          reason: 'never equal: the server declines equal-timestamp edits');
    });

    test('an over-length body throws rather than persisting', () async {
      await expectLater(
        storage.upsertCareNote(
            profileId: 'p1',
            body: 'x' * (kMaxCareNoteLength + 1)),
        throwsA(isA<ArgumentError>()),
      );
      expect(await storage.getCareNotesForProfile('p1'), isEmpty);
    });

    test('soft delete tombstones with a cleared body; re-delete is a no-op',
        () async {
      final row =
          await storage.upsertCareNote(profileId: 'p1', body: 'Gone soon.');
      clock.now = t1;
      await storage.softDeleteCareNote(row.id);

      expect(await storage.getCareNotesForProfile('p1'), isEmpty,
          reason: 'UI reads filter tombstones');
      final tombstones = await storage.getCareNotesForProfile('p1',
          includeTombstones: true);
      expect(tombstones, hasLength(1));
      expect(tombstones.single.body, isEmpty);
      expect(tombstones.single.deletedAt, isNotNull);
      expect(tombstones.single.dirty, isTrue);

      // Idempotent: a second delete changes nothing.
      final stamp = tombstones.single.updatedAt;
      clock.now = t2;
      await storage.softDeleteCareNote(row.id);
      final again = await storage.getCareNotesForProfile('p1',
          includeTombstones: true);
      expect(again.single.updatedAt, stamp);
    });

    test('a newer write to a tombstone revives it', () async {
      final row =
          await storage.upsertCareNote(profileId: 'p1', body: 'Back.');
      await storage.softDeleteCareNote(row.id);
      clock.now = t1;
      final revived = await storage.upsertCareNote(
          id: row.id, profileId: 'p1', body: 'Back again.');
      expect(revived.deletedAt, isNull);
      expect(revived.body, 'Back again.');
    });

    test('watch emits the list reactively', () async {
      final emissions = <int>[];
      final sub = storage.watchCareNotesForProfile('p1').listen((rows) {
        emissions.add(rows.length);
      });
      addTearDown(sub.cancel);
      await storage.upsertCareNote(profileId: 'p1', body: 'One.');
      await storage.upsertCareNote(profileId: 'p1', body: 'Two.');
      await pumpEventQueue();
      expect(emissions.last, 2);
    });

    test('readDirty pages by id; markPushed clears on a rev match',
        () async {
      final a =
          await storage.upsertCareNote(profileId: 'p1', body: 'A.');
      await storage.upsertCareNote(profileId: 'p1', body: 'B.');
      final dirty = await storage.readDirtyCareNotes();
      expect(dirty.map((r) => r.id), containsAll([a.id]));
      expect(dirty, hasLength(2));

      final page =
          await storage.readDirtyCareNotes(limit: 1);
      expect(page, hasLength(1));
      final rest = await storage.readDirtyCareNotes(
          limit: 1, afterId: page.single.id);
      expect(rest, hasLength(1));
      expect(rest.single.id, isNot(page.single.id));

      expect(
          await storage.markPushed(
              table: SyncTable.careNotes,
              id: a.id,
              localRevAtPush: 99),
          isFalse,
          reason: 'a stale local_rev never clears dirty');
      expect(
          await storage.markPushed(
              table: SyncTable.careNotes,
              id: a.id,
              localRevAtPush: a.localRev),
          isTrue);
      expect(await storage.readDirtyCareNotes(), hasLength(1));
    });
  });

  group('visit_prep_items', () {
    test('add lands unchecked; edit keeps the check state', () async {
      final item = await storage.addVisitPrepItem(
          profileId: 'p1', body: 'Bring the chart.');
      expect(item.isChecked, isFalse);
      expect(item.checkedByUserId, isNull);
      expect(item.checkedAt, isNull);
      expect(item.dirty, isTrue);

      final edited = await storage.editVisitPrepItem(
          id: item.id, body: 'Bring the growth chart.');
      expect(edited!.body, 'Bring the growth chart.');
      expect(edited.isChecked, isFalse);
    });

    test('editing an unknown id is a null no-op', () async {
      expect(
          await storage.editVisitPrepItem(id: 'missing', body: 'x'),
          isNull);
    });

    test('an over-length body throws on add and on edit', () async {
      await expectLater(
        storage.addVisitPrepItem(
            profileId: 'p1', body: 'y' * (kMaxVisitPrepItemLength + 1)),
        throwsA(isA<ArgumentError>()),
      );
      final item = await storage.addVisitPrepItem(
          profileId: 'p1', body: 'Fine.');
      await expectLater(
        storage.editVisitPrepItem(
            id: item.id, body: 'y' * (kMaxVisitPrepItemLength + 1)),
        throwsA(isA<ArgumentError>()),
      );
      expect(
          (await storage.getVisitPrepItemsForProfile('p1')).single.body,
          'Fine.');
    });

    test('check records who and when; uncheck clears both', () async {
      final item =
          await storage.addVisitPrepItem(profileId: 'p1', body: 'Ask.');
      clock.now = t1;
      final checked = await storage.setVisitPrepItemChecked(
          id: item.id, checked: true, checkedByUserId: 'user-dad');
      expect(checked!.isChecked, isTrue);
      expect(checked.checkedByUserId, 'user-dad');
      expect(checked.checkedAt, t1);

      clock.now = t2;
      final unchecked = await storage.setVisitPrepItemChecked(
          id: item.id, checked: false);
      expect(unchecked!.isChecked, isFalse);
      expect(unchecked.checkedByUserId, isNull);
      expect(unchecked.checkedAt, isNull);
    });

    test('checking an unknown or tombstoned id is a null no-op', () async {
      expect(
          await storage.setVisitPrepItemChecked(
              id: 'missing', checked: true),
          isNull);
      final item =
          await storage.addVisitPrepItem(profileId: 'p1', body: 'Ask.');
      await storage.softDeleteVisitPrepItem(item.id);
      expect(
          await storage.setVisitPrepItemChecked(
              id: item.id, checked: true),
          isNull);
    });

    test('unchecked items sort before checked ones', () async {
      final a =
          await storage.addVisitPrepItem(profileId: 'p1', body: 'Open.');
      final b =
          await storage.addVisitPrepItem(profileId: 'p1', body: 'Done.');
      await storage.setVisitPrepItemChecked(
          id: b.id, checked: true, checkedByUserId: 'u1');
      final rows = await storage.getVisitPrepItemsForProfile('p1');
      expect(rows.map((r) => r.id), [a.id, b.id]);
    });

    test('clearChecked tombstones only the checked items and reports them',
        () async {
      final open =
          await storage.addVisitPrepItem(profileId: 'p1', body: 'Open.');
      final done =
          await storage.addVisitPrepItem(profileId: 'p1', body: 'Done.');
      await storage.setVisitPrepItemChecked(
          id: done.id, checked: true, checkedByUserId: 'u1');

      expect(await storage.clearCheckedVisitPrepItems('p1'), 1);
      final live = await storage.getVisitPrepItemsForProfile('p1');
      expect(live.map((r) => r.id), [open.id],
          reason: 'unchecked items survive the clear');
      final tombstones = await storage.getVisitPrepItemsForProfile('p1',
          includeTombstones: true);
      final cleared =
          tombstones.singleWhere((r) => r.id == done.id);
      expect(cleared.body, isEmpty);
      expect(cleared.isChecked, isFalse);
      expect(cleared.checkedByUserId, isNull);
      expect(cleared.checkedAt, isNull);
      expect(cleared.dirty, isTrue,
          reason: 'the clear itself syncs');

      expect(await storage.clearCheckedVisitPrepItems('p1'), 0,
          reason: 'clearing twice clears nothing new');
    });

    test('soft delete clears the body and the check state', () async {
      final item =
          await storage.addVisitPrepItem(profileId: 'p1', body: 'Ask.');
      await storage.setVisitPrepItemChecked(
          id: item.id, checked: true, checkedByUserId: 'u1');
      await storage.softDeleteVisitPrepItem(item.id);
      final tombstones = await storage.getVisitPrepItemsForProfile('p1',
          includeTombstones: true);
      expect(tombstones.single.body, isEmpty);
      expect(tombstones.single.isChecked, isFalse);
      expect(tombstones.single.checkedByUserId, isNull);
    });
  });

  group('sync bookkeeping (Issue #128 tables)', () {
    test('dirtyCount, markAllDirty, and isEmpty account for both tables',
        () async {
      expect(await storage.isEmpty(), isFalse,
          reason: 'the setUp profile already exists');
      expect(await storage.dirtyCount(), 1);

      await storage.upsertCareNote(profileId: 'p1', body: 'Note.');
      await storage.addVisitPrepItem(profileId: 'p1', body: 'Item.');
      expect(await storage.dirtyCount(), 3);

      await storage.markAllDirty();
      final dirtyNotes = await storage.readDirtyCareNotes();
      final dirtyItems = await storage.readDirtyVisitPrepItems();
      expect(dirtyNotes, hasLength(1));
      expect(dirtyItems, hasLength(1));
    });

    test('readDirtyVisitPrepItems pages by id; markPushed clears on a match',
        () async {
      final a = await storage.addVisitPrepItem(
          profileId: 'p1', body: 'A.');
      await storage.addVisitPrepItem(profileId: 'p1', body: 'B.');
      final page = await storage.readDirtyVisitPrepItems(limit: 1);
      expect(page, hasLength(1));
      final rest = await storage.readDirtyVisitPrepItems(
          limit: 1, afterId: page.single.id);
      expect(rest.single.id, isNot(page.single.id));
      expect(
          await storage.markPushed(
              table: SyncTable.visitPrepItems,
              id: a.id,
              localRevAtPush: a.localRev),
          isTrue);
    });
  });

  group('applyRemote (per-id LWW)', () {
    test('a newer remote note wins; an older one loses; ties go remote',
        () async {
      final local = await storage.upsertCareNote(
          profileId: 'p1', body: 'Local.', updatedAt: t1);

      expect(
          await storage.applyRemoteCareNote(remoteNote(local.id,
              body: 'Older remote.', updatedAt: t0)),
          isFalse);
      expect((await storage.getCareNotesForProfile('p1')).single.body,
          'Local.');

      expect(
          await storage.applyRemoteCareNote(remoteNote(local.id,
              body: 'Newer remote.', updatedAt: t2)),
          isTrue);
      expect((await storage.getCareNotesForProfile('p1')).single.body,
          'Newer remote.');

      // Equal timestamps: the remote copy wins (KTD5).
      expect(
          await storage.applyRemoteCareNote(remoteNote(local.id,
              body: 'Tie remote.', updatedAt: t2)),
          isTrue);
      expect((await storage.getCareNotesForProfile('p1')).single.body,
          'Tie remote.');
    });

    test('a remote tombstone clears the body; resolved never inserts',
        () async {
      final local = await storage.upsertCareNote(
          profileId: 'p1', body: 'Local.', updatedAt: t1);
      expect(
          await storage.applyRemoteCareNote(remoteNote(local.id,
              body: 'Stale.',
              updatedAt: t2,
              deletedAt: t2)),
          isTrue);
      final tombstones = await storage.getCareNotesForProfile('p1',
          includeTombstones: true);
      expect(tombstones.single.body, isEmpty);
      expect(tombstones.single.deletedAt, t2);

      // applyResolved (push resolutions) never inserts an unknown id.
      await storage.applyResolved([
        remoteNote('unknown-id', body: 'Nope.', updatedAt: t2),
      ]);
      expect(await storage.getCareNotesForProfile('p1',
          includeTombstones: true), hasLength(1));
    });

    test('a remote row for an unknown profile is retryable', () async {
      await expectLater(
        storage.applyRemoteCareNote(remoteNote('n-x',
            profileId: 'missing-profile', updatedAt: t1)),
        throwsA(isA<RetryableSyncApplyError>()),
      );
      await expectLater(
        storage.applyRemoteVisitPrepItem(remoteItem('i-x',
            profileId: 'missing-profile', updatedAt: t1)),
        throwsA(isA<RetryableSyncApplyError>()),
      );
    });

    test('a remote prep item applies its check state; pages carry cursors',
        () async {
      expect(
          await storage.applyRemoteVisitPrepItem(remoteItem('i-1',
              isChecked: true,
              checkedByUserId: 'user-dad',
              checkedAt: t1,
              updatedAt: t1)),
          isTrue);
      final stored =
          (await storage.getVisitPrepItemsForProfile('p1')).single;
      expect(stored.isChecked, isTrue);
      expect(stored.checkedByUserId, 'user-dad');

      await storage.applyRemotePage(
          table: SyncTable.visitPrepItems,
          rows: [
            remoteItem('i-2', updatedAt: t2),
          ],
          newCursor: 41);
      expect((await storage.readSyncState()).cursorVisitPrepItems, 41);
      expect(await storage.getVisitPrepItemsForProfile('p1'),
          hasLength(2));

      await storage.applyRemotePage(
          table: SyncTable.careNotes,
          rows: [remoteNote('n-9', updatedAt: t2)],
          newCursor: 42);
      expect((await storage.readSyncState()).cursorCareNotes, 42);
    });

    test('applyRemoteRows lands both tables in one transaction', () async {
      await storage.applyRemoteRows([
        remoteNote('n-a', updatedAt: t1),
        remoteItem('i-a', updatedAt: t1),
      ]);
      expect(await storage.getCareNotesForProfile('p1'), hasLength(1));
      expect(await storage.getVisitPrepItemsForProfile('p1'), hasLength(1));
    });
  });

  group('R5 revocation wipe (Issue #128 extension)', () {
    test('a revoked membership tombstones the shared care content too',
        () async {
      await storage.upsertCareNote(profileId: 'p1', body: 'Secret note.');
      final item = await storage.addVisitPrepItem(
          profileId: 'p1', body: 'Secret item.');
      await storage.setVisitPrepItemChecked(
          id: item.id, checked: true, checkedByUserId: 'u-revoked');
      await storage.writeSyncState(
          kDefaultSyncState.copyWith(boundUserId: const Value('u-revoked')));

      await storage.applyRemoteRows([
        RemoteProfileGuardianRow(
          id: 'g-1',
          profileId: 'p1',
          userId: 'u-revoked',
          role: 'caregiver',
          status: 'revoked',
          displayName: null,
          invitedBy: null,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ]);

      // UI reads see nothing on either surface...
      expect(await storage.getCareNotesForProfile('p1'), isEmpty);
      expect(await storage.getVisitPrepItemsForProfile('p1'), isEmpty);
      // ...full-fidelity reads see payload-free tombstones, never pushed.
      final notes = await storage.getCareNotesForProfile('p1',
          includeTombstones: true);
      expect(notes.single.body, isEmpty);
      expect(notes.single.dirty, isFalse);
      final items = await storage.getVisitPrepItemsForProfile('p1',
          includeTombstones: true);
      expect(items.single.body, isEmpty);
      expect(items.single.isChecked, isFalse);
      expect(items.single.checkedByUserId, isNull);
      expect(items.single.dirty, isFalse);
    });
  });
}
