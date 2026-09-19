/// Issue #801: `LunarLogStorage`'s guardian_notes API — one dated,
/// author-scoped note per row, per-id LWW, payload-free tombstones, dirty/
/// local_rev bookkeeping, `readDirty*` keyset paging, `markPushed`, the
/// `applyRemote*` rule plus the referential-integrity guard, and the
/// no-cross-author-merge invariant (two authors on one date are two rows).
/// Mirrors `storage_care_content_test.dart`'s shape.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
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

  RemoteGuardianNoteRow remoteNote(
    String id, {
    String profileId = 'p1',
    String localDate = '2026-09-12',
    String tz = 'UTC',
    String body = 'Seemed withdrawn this week.',
    required DateTime updatedAt,
    DateTime? deletedAt,
    String? loggedByUserId,
    int serverVersion = 0,
  }) =>
      RemoteGuardianNoteRow(
        id: id,
        profileId: profileId,
        localDate: localDate,
        tz: tz,
        body: body,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        serverVersion: serverVersion,
        loggedByUserId: loggedByUserId,
      );

  test('upsert creates a dirty dated note; a second write updates in place',
      () async {
    final row = await storage.upsertGuardianNote(
      profileId: 'p1',
      localDate: '2026-09-12',
      tz: 'America/New_York',
      body: 'First.',
      loggedByUserId: 'u1',
    );
    expect(row.profileId, 'p1');
    expect(row.localDate, '2026-09-12');
    expect(row.tz, 'America/New_York');
    expect(row.body, 'First.');
    expect(row.loggedByUserId, 'u1');
    expect(row.dirty, isTrue);
    expect(row.localRev, 1);

    clock.now = t1;
    final again = await storage.upsertGuardianNote(
      id: row.id,
      profileId: 'p1',
      localDate: '2026-09-12',
      tz: 'America/New_York',
      body: 'Revised.',
      loggedByUserId: 'u1',
    );
    expect(again.id, row.id);
    expect(again.body, 'Revised.');
    expect(again.localRev, 2);
    expect(again.updatedAt, t1);
    expect(await storage.getGuardianNotesForProfile('p1'), hasLength(1));
  });

  test('a stale-clock update still bumps updated_at past the stored value',
      () async {
    final row = await storage.upsertGuardianNote(
      profileId: 'p1',
      localDate: '2026-09-12',
      tz: 'UTC',
      body: 'First.',
      updatedAt: t1,
    );
    final again = await storage.upsertGuardianNote(
      id: row.id,
      profileId: 'p1',
      localDate: '2026-09-12',
      tz: 'UTC',
      body: 'Revised.',
      updatedAt: t0,
    );
    expect(again.updatedAt.isAfter(t1), isTrue,
        reason: 'never equal: the server declines equal-timestamp edits');
  });

  test('two authors on the same date are two live rows (no merge)', () async {
    final mom = await storage.upsertGuardianNote(
      profileId: 'p1',
      localDate: '2026-09-12',
      tz: 'UTC',
      body: 'Mom wrote this.',
      loggedByUserId: 'u-mom',
    );
    final dad = await storage.upsertGuardianNote(
      profileId: 'p1',
      localDate: '2026-09-12',
      tz: 'UTC',
      body: 'Dad wrote this.',
      loggedByUserId: 'u-dad',
    );
    expect(mom.id, isNot(dad.id));
    final live = await storage.getGuardianNotesForProfile('p1');
    expect(live, hasLength(2));
    expect(live.map((r) => r.body),
        containsAll(['Mom wrote this.', 'Dad wrote this.']));
  });

  test('findLiveGuardianNoteForDate matches author + date, ignoring tombstones',
      () async {
    final mine = await storage.upsertGuardianNote(
      profileId: 'p1',
      localDate: '2026-09-12',
      tz: 'UTC',
      body: 'Mine.',
      loggedByUserId: 'u1',
    );
    await storage.upsertGuardianNote(
      profileId: 'p1',
      localDate: '2026-09-12',
      tz: 'UTC',
      body: 'Theirs.',
      loggedByUserId: 'u2',
    );
    final found = await storage.findLiveGuardianNoteForDate(
        profileId: 'p1', localDate: '2026-09-12', authorUserId: 'u1');
    expect(found?.id, mine.id);
    expect(
        await storage.findLiveGuardianNoteForDate(
            profileId: 'p1', localDate: '2026-09-13', authorUserId: 'u1'),
        isNull);

    await storage.softDeleteGuardianNote(mine.id);
    expect(
        await storage.findLiveGuardianNoteForDate(
            profileId: 'p1', localDate: '2026-09-12', authorUserId: 'u1'),
        isNull);
  });

  test('an over-length body throws rather than persisting', () async {
    await expectLater(
      storage.upsertGuardianNote(
        profileId: 'p1',
        localDate: '2026-09-12',
        tz: 'UTC',
        body: 'x' * (kMaxCareNoteLength + 1),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(await storage.getGuardianNotesForProfile('p1'), isEmpty);
  });

  test('soft delete tombstones with a cleared body, keeping date/tz',
      () async {
    final row = await storage.upsertGuardianNote(
      profileId: 'p1',
      localDate: '2026-09-12',
      tz: 'America/New_York',
      body: 'Gone soon.',
    );
    clock.now = t1;
    await storage.softDeleteGuardianNote(row.id);

    expect(await storage.getGuardianNotesForProfile('p1'), isEmpty,
        reason: 'UI reads filter tombstones');
    final tombstones = await storage.getGuardianNotesForProfile('p1',
        includeTombstones: true);
    expect(tombstones.single.body, isEmpty);
    expect(tombstones.single.localDate, '2026-09-12');
    expect(tombstones.single.tz, 'America/New_York');
    expect(tombstones.single.deletedAt, isNotNull);
    expect(tombstones.single.dirty, isTrue);

    final stamp = tombstones.single.updatedAt;
    clock.now = t2;
    await storage.softDeleteGuardianNote(row.id);
    final again = await storage.getGuardianNotesForProfile('p1',
        includeTombstones: true);
    expect(again.single.updatedAt, stamp, reason: 're-delete is a no-op');
  });

  test('applyRemoteGuardianNote inserts clean, declines older, applies delete',
      () async {
    await storage.applyRemoteGuardianNote(
        remoteNote('g1', updatedAt: t1, loggedByUserId: 'u1', serverVersion: 5));
    final inserted = (await storage.getGuardianNotesForProfile('p1')).single;
    expect(inserted.dirty, isFalse);
    expect(inserted.loggedByUserId, 'u1');

    // An older remote copy is declined: the local value survives.
    final changed = await storage.applyRemoteGuardianNote(remoteNote('g1',
        body: 'stale', updatedAt: t0, loggedByUserId: 'u1', serverVersion: 6));
    expect(changed, isFalse);
    expect((await storage.getGuardianNotesForProfile('p1')).single.body,
        'Seemed withdrawn this week.');

    // A newer tombstone lands payload-free.
    clock.now = t2;
    await storage.applyRemoteGuardianNote(remoteNote('g1',
        body: 'stale',
        updatedAt: t2,
        deletedAt: t2,
        loggedByUserId: 'u1',
        serverVersion: 7));
    final tombstone = (await storage.getGuardianNotesForProfile('p1',
            includeTombstones: true))
        .single;
    expect(tombstone.body, isEmpty);
    expect(tombstone.deletedAt, isNotNull);
  });

  test('applyRemoteGuardianNote is retryable when the profile is absent',
      () async {
    await expectLater(
      storage.applyRemoteGuardianNote(remoteNote('g9',
          profileId: 'missing', updatedAt: t1)),
      throwsA(isA<RetryableSyncApplyError>()),
    );
  });

  test('readDirty pages by id; markPushed clears on a rev match', () async {
    final a = await storage.upsertGuardianNote(
        profileId: 'p1', localDate: '2026-09-12', tz: 'UTC', body: 'A.');
    await storage.upsertGuardianNote(
        profileId: 'p1', localDate: '2026-09-12', tz: 'UTC', body: 'B.');
    final dirty = await storage.readDirtyGuardianNotes();
    expect(dirty, hasLength(2));

    final page = await storage.readDirtyGuardianNotes(limit: 1);
    expect(page, hasLength(1));
    final rest = await storage.readDirtyGuardianNotes(
        limit: 1, afterId: page.single.id);
    expect(rest.single.id, isNot(page.single.id));

    expect(
        await storage.markPushed(
            table: SyncTable.guardianNotes, id: a.id, localRevAtPush: 99),
        isFalse,
        reason: 'a stale local_rev never clears dirty');
    expect(
        await storage.markPushed(
            table: SyncTable.guardianNotes,
            id: a.id,
            localRevAtPush: a.localRev),
        isTrue);
    expect(await storage.readDirtyGuardianNotes(), hasLength(1));
  });
}
