/// push batching and `markPushed` revisions, resolved/declined rows, the clock offset, and rejected-row retry — issue #437 split of `test/data/sync_engine_test.dart`.
/// Shared fixtures live in `sync_engine_support.dart`. Nothing here
/// touches Supabase.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/sync/sync_transport.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart'
    show kRejectedCopy, syncStatusCopy;

import 'sync_engine_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('push', () {
    test('sends every dirty row including tombstones, profiles before day '
        'entries, in batches of at most the batch size, and markPushed uses '
        'the local_rev captured before the request (AE11)', () async {
      final rig = Rig(batchSize: 4);
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final s = rig.storage;
      final p1 = await s.upsertProfile(displayName: 'A', isMinor: false);
      final p2 = await s.upsertProfile(displayName: 'B', isMinor: true);
      final p3 = await s.upsertProfile(displayName: 'C', isMinor: false);
      final entries = <DayEntry>[];
      for (var d = 1; d <= 6; d++) {
        entries.add(await s.upsertDayEntry(
            profileId: p1.id,
            localDate: '2026-01-0$d',
            tz: 'UTC',
            flow: FlowLevel.light));
      }
      await s.softDeleteDayEntry(profileId: p1.id, localDate: '2026-01-06');
      final tombstoneId = entries[5].id;
      final edited = entries[0];

      // A local edit lands while the first batch is in flight.
      rig.transport.onPush = (batch) async {
        if (rig.transport.pushes.length == 1) {
          await s.upsertDayEntry(
              profileId: p1.id,
              localDate: '2026-01-01',
              tz: 'UTC',
              flow: FlowLevel.heavy);
        }
      };

      await rig.start();

      final pushes = rig.transport.pushes;
      expect(pushes.length, greaterThanOrEqualTo(2));
      expect(ids(pushes[0].profiles), [p1.id, p2.id, p3.id]..sort(),
          reason: 'profiles ride in the earliest batch');
      expect(pushes[0].dayEntries, hasLength(4));
      expect(pushes[1].profiles, isEmpty);
      expect(pushes[1].dayEntries, hasLength(2));
      for (final batch in pushes) {
        expect(batch.rowCount, lessThanOrEqualTo(8));
        expect(batch.profiles.length, lessThanOrEqualTo(4));
        expect(batch.dayEntries.length, lessThanOrEqualTo(4));
      }
      final allEntryIds = pushes.expand((b) => ids(b.dayEntries)).toSet();
      expect(allEntryIds, containsAll(entries.map((e) => e.id)));
      final tombstone = pushes
          .expand((b) => b.dayEntries)
          .firstWhere((r) => r['id'] == tombstoneId);
      expect(tombstone['deleted_at'], isNotNull,
          reason: 'tombstones are pushed');

      // The edited row was pushed twice: once in batch 1 (old rev, whose
      // markPushed must not clear the newer local_rev) and again later.
      final editedPushes = pushes
          .where((b) => ids(b.dayEntries).contains(edited.id))
          .length;
      expect(editedPushes, 2,
          reason: 'markPushed with the pre-request rev leaves the row dirty');
      expect(await s.dirtyCount(), 0);
      expect((await rig.entry(p1.id, edited.id)).flow, FlowLevel.heavy);
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
      expect(rig.engine.snapshot.dirtyCount, 0);
    });

    test('a batch is never larger than 500 rows per table by default',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      final start = DateTime.utc(2024, 1, 1);
      for (var i = 0; i < 501; i++) {
        final d = start.add(Duration(days: i));
        final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
        await rig.storage.upsertDayEntry(
            profileId: p.id, localDate: date, tz: 'UTC', flow: FlowLevel.light);
      }
      await rig.start();
      expect(rig.transport.pushes, hasLength(2));
      expect(rig.transport.pushes[0].dayEntries, hasLength(500));
      expect(rig.transport.pushes[1].dayEntries, hasLength(1));
      expect(await rig.storage.dirtyCount(), 0);
    });

    /// Creates [count] dirty day entries for [profileId] on consecutive
    /// dates starting 2020-01-01, so a large-import push can be tested
    /// without depending on any particular seed data.
    Future<void> seedDirtyEntries(
      LunarLogStorage storage,
      String profileId,
      int count,
    ) async {
      final start = DateTime.utc(2020, 1, 1);
      for (var i = 0; i < count; i++) {
        final d = start.add(Duration(days: i));
        final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
        await storage.upsertDayEntry(
            profileId: profileId,
            localDate: date,
            tz: 'UTC',
            flow: FlowLevel.light);
      }
    }

    test('Issue #177: a 1,200-row dirty set streams in 3 batches, never '
        'more than 500 rows in one transport call, and the snapshot '
        'reports pushedRows/totalDirtyRows advancing batch by batch',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p =
          await rig.storage.upsertProfile(displayName: 'A', isMinor: false);
      // The profile itself is not part of this dirty set: only the 1,200
      // day entries are, so every push batch is entries-only and the
      // per-call row cap is unambiguous.
      await rig.storage.markPushed(
          table: SyncTable.profiles,
          id: p.id,
          localRevAtPush:
              (await rig.storage.readDirtyProfiles()).single.localRev);
      await seedDirtyEntries(rig.storage, p.id, 1200);
      expect(await rig.storage.dirtyCount(), 1200);

      final progressAtEachCall = <SyncSnapshot>[];
      rig.transport.onPush = (_) => progressAtEachCall.add(rig.engine.snapshot);

      await rig.start();

      expect(rig.transport.pushes, hasLength(3),
          reason: '1,200 rows at the default 500-row batch size is 3 calls');
      expect(rig.transport.pushes[0].dayEntries, hasLength(500));
      expect(rig.transport.pushes[1].dayEntries, hasLength(500));
      expect(rig.transport.pushes[2].dayEntries, hasLength(200));
      for (final batch in rig.transport.pushes) {
        expect(batch.rowCount, lessThanOrEqualTo(500),
            reason: 'the transport never receives more than 500 rows in '
                'one call, however large the dirty set — the engine '
                'streams and encodes one batch at a time instead of '
                'materialising the whole dirty set up front');
      }
      final allIds = rig.transport.pushes.expand((b) => ids(b.dayEntries));
      expect(allIds.toSet(), hasLength(1200),
          reason: 'every row is sent exactly once');
      expect(await rig.storage.dirtyCount(), 0);

      // Progress as observed at the moment each call was recorded: the
      // total is fixed at the start of this cycle's push, and pushedRows
      // reflects only batches that had already committed before this call.
      expect(progressAtEachCall, hasLength(3));
      expect(progressAtEachCall[0].totalDirtyRows, 1200);
      expect(progressAtEachCall[0].pushedRows, 0);
      expect(progressAtEachCall[1].totalDirtyRows, 1200);
      expect(progressAtEachCall[1].pushedRows, 500);
      expect(progressAtEachCall[2].totalDirtyRows, 1200);
      expect(progressAtEachCall[2].pushedRows, 1000);
      expect(rig.engine.snapshot.pushedRows, 1200);
      expect(rig.engine.snapshot.totalDirtyRows, 1200);
    });

    test('Issue #177 finding #1: a profile created mid-cycle (after batch 1 '
        'is acknowledged) is not permanently skipped by a latched '
        '"profiles done" flag — it is pushed no later than the batch '
        'carrying its own day entry, never after, with zero rejections',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p =
          await rig.storage.upsertProfile(displayName: 'A', isMinor: false);
      await rig.storage.markPushed(
          table: SyncTable.profiles,
          id: p.id,
          localRevAtPush:
              (await rig.storage.readDirtyProfiles()).single.localRev);
      await seedDirtyEntries(rig.storage, p.id, 1200);

      String? newProfileId;
      String? newEntryId;
      rig.transport.onPush = (_) async {
        if (rig.transport.pushes.length == 1 && newProfileId == null) {
          final p2 = await rig.storage.upsertProfile(
              displayName: 'B (created mid-cycle)', isMinor: false);
          final e2 = await rig.storage.upsertDayEntry(
              profileId: p2.id,
              localDate: '2030-01-01',
              tz: 'UTC',
              flow: FlowLevel.light);
          newProfileId = p2.id;
          newEntryId = e2.id;
        }
      };

      await rig.start();

      expect(newProfileId, isNotNull, reason: 'the mid-cycle write ran');
      final profileBatchIndex = rig.transport.pushes
          .indexWhere((b) => ids(b.profiles).contains(newProfileId));
      final entryBatchIndex = rig.transport.pushes
          .indexWhere((b) => ids(b.dayEntries).contains(newEntryId));
      expect(profileBatchIndex, isNot(-1),
          reason: 'the new profile must be pushed within this cycle — a '
              'permanently latched "profiles done" flag would silently '
              'skip it forever');
      expect(entryBatchIndex, isNot(-1),
          reason: 'the new entry must be pushed within this cycle');
      expect(profileBatchIndex, lessThanOrEqualTo(entryBatchIndex),
          reason: 'the profile must be pushed before or with its own day '
              'entry, never after — after would reject the entry on a '
              'foreign key the server has not seen yet');
      expect(rig.engine.snapshot.rejectedCount, 0,
          reason: 'the profile always arrives no later than its entry, so '
              'nothing is ever rejected on a missing foreign key');
      expect(await rig.storage.dirtyCount(), 0);
    });

    test('Issue #177 finding #3: no readDirtyProfiles/readDirtyDayEntries '
        'call during a push returns more rows than the batch size, even '
        'while un-rejecting a day entry mid-push', () async {
      final rig = Rig(
        batchSize: 4,
        storageFactory: (db, clock) => CountingStorage(db, clock: clock),
      );
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final counting = rig.storage as CountingStorage;

      final p =
          await rig.storage.upsertProfile(displayName: 'A', isMinor: false);
      final e = await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      // Push 1: both the profile and its entry are rejected.
      rig.transport.scriptPushResult(rejectedIds: [p.id, e.id]);
      await rig.start();
      expect(rig.engine.snapshot.rejectedCount, 2);

      // A pile of unrelated dirty day entries — well over the batch size
      // — under a second, already-clean profile, so ordinary paged
      // batches carry them regardless of the un-rejection exercised below.
      final p2 =
          await rig.storage.upsertProfile(displayName: 'B', isMinor: false);
      await rig.storage.markPushed(
          table: SyncTable.profiles,
          id: p2.id,
          localRevAtPush: (await rig.storage.readDirtyProfiles())
              .firstWhere((row) => row.id == p2.id)
              .localRev);
      await seedDirtyEntries(rig.storage, p2.id, 20);

      // Editing p bumps its local_rev, making it pushable again; its
      // accepted push should un-reject e (finding #2) with no storage read
      // large enough to exceed the batch size (finding #3) — this is
      // exactly what the pre-fix `_unrejectEntriesOf`'s unbounded
      // `readDirtyDayEntries()` call would have returned (well over 20
      // rows) had it still been in place.
      await rig.storage.upsertProfile(
          id: p.id, displayName: 'A Fixed', isMinor: false);
      await rig.sync();

      expect(rig.engine.snapshot.rejectedCount, 0);
      expect((await rig.entry(p.id, e.id)).dirty, isFalse,
          reason: 'e was un-rejected and re-sent once p was accepted');
      for (final n in counting.profilePageLengths) {
        expect(n, lessThanOrEqualTo(4),
            reason: 'a readDirtyProfiles call returned more than the batch '
                'size — an unbounded read slipped into the push path');
      }
      for (final n in counting.dayEntryPageLengths) {
        expect(n, lessThanOrEqualTo(4),
            reason: 'a readDirtyDayEntries call returned more than the '
                'batch size — this is exactly what the pre-fix '
                '_unrejectEntriesOf\'s unbounded read would trip');
      }
    });

    test('Issue #177: a _SyncPaused between batches (the device locks '
        'mid-import) leaves the not-yet-sent batches dirty; the next cycle '
        'resumes and pushes only what is left, never re-pushing an '
        'already-acknowledged row', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p =
          await rig.storage.upsertProfile(displayName: 'A', isMinor: false);
      await rig.storage.markPushed(
          table: SyncTable.profiles,
          id: p.id,
          localRevAtPush:
              (await rig.storage.readDirtyProfiles()).single.localRev);
      await seedDirtyEntries(rig.storage, p.id, 1200);

      // Locks the gate as soon as batch 1 is recorded, so the checkpoint
      // ahead of batch 2 throws _SyncPaused before any further encoding or
      // network call.
      rig.transport.onPush = (_) {
        if (rig.transport.pushes.length == 1) rig.gate.lock();
      };

      await rig.start();

      expect(rig.transport.pushes, hasLength(1),
          reason: 'batch 1 committed; the paused checkpoint stops batch 2 '
              'before it is built or sent');
      expect(rig.engine.snapshot.phase, SyncPhase.paused);
      expect(await rig.storage.dirtyCount(), 700,
          reason: 'batches 2 and 3 (700 rows) are left dirty for the next '
              'cycle — nothing was re-read or re-encoded for them yet');
      final firstBatchIds = ids(rig.transport.pushes[0].dayEntries).toSet();
      expect(firstBatchIds, hasLength(500));

      rig.transport.onPush = null;
      rig.gate.unlock();
      await rig.engine.flush();

      expect(rig.transport.pushes, hasLength(3),
          reason: 'the resumed cycle finishes the remaining 700 rows in 2 '
              'more batches, starting from the next dirty rows');
      expect(rig.transport.pushes[1].dayEntries, hasLength(500));
      expect(rig.transport.pushes[2].dayEntries, hasLength(200));
      final resumedIds = rig.transport.pushes
          .skip(1)
          .expand((b) => ids(b.dayEntries))
          .toSet();
      expect(resumedIds.intersection(firstBatchIds), isEmpty,
          reason: 'no already-acknowledged row is re-pushed on resume');
      expect(resumedIds, hasLength(700));
      expect(await rig.storage.dirtyCount(), 0);
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
    });

    test('AE6: a transport that throws after the server accepted leaves rows '
        'dirty; the next cycle re-pushes an identical payload', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      rig.transport.nextPushError = const SyncTransportError.network();

      await rig.start();
      expect(rig.transport.pushes, hasLength(1));
      expect(await rig.storage.dirtyCount(), 2, reason: 'nothing cleared');
      expect(rig.engine.snapshot.phase, SyncPhase.error);
      expect(rig.engine.snapshot.lastError, SyncErrorKind.network);
      expect(rig.transport.pulls, isEmpty, reason: 'a failed push ends the cycle');

      await rig.sync();
      expect(rig.transport.pushes, hasLength(2));
      expect(rig.transport.pushes[1].profiles, rig.transport.pushes[0].profiles);
      expect(rig.transport.pushes[1].dayEntries,
          rig.transport.pushes[0].dayEntries);
      expect(await rig.storage.dirtyCount(), 0);
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
    });

    test('resolved rows (losers and declined) are applied dirty = false '
        'before the pull; a declined edit is reverted in the same cycle',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      final e = await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      // The server holds a newer copy: the local edit is declined.
      final serverCopy = remoteEntry(e.id,
          profileId: p.id,
          flow: FlowLevel.heavy,
          updatedAt: t0.add(const Duration(hours: 1)),
          serverVersion: 5);
      rig.transport.scriptPushResult(resolved: [serverCopy]);
      DayEntry? atPull;
      rig.transport.onPull = (call) async {
        atPull ??= await rig.entry(p.id, e.id);
      };

      await rig.start();

      expect(atPull, isNotNull, reason: 'the pull ran after the push');
      expect(atPull!.flow, FlowLevel.heavy,
          reason: 'server copy applied before the first pull');
      expect(atPull!.dirty, isFalse);
      final after = await rig.entry(p.id, e.id);
      expect(after.flow, FlowLevel.heavy);
      expect(after.dirty, isFalse);
      expect(await rig.storage.dirtyCount(), 0);
    });

    test('the clock offset from server_now is stored and applied to '
        'subsequent local writes', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      rig.transport.scriptPushResult(
          serverNow: t0.add(const Duration(minutes: 5)));

      await rig.start();

      expect(rig.storage.clockOffset, const Duration(minutes: 5));
      expect((await rig.state()).serverClockOffsetMs, 5 * 60 * 1000);
      rig.clock.now = t0.add(const Duration(seconds: 1));
      final e = await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      expect(e.updatedAt, t0.add(const Duration(minutes: 5, seconds: 1)));
    });

    test('a rejected row stays dirty, is not retried until edited again, and '
        'is counted in the snapshot', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      final e = await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      rig.transport.scriptPushResult(rejectedIds: [e.id]);

      await rig.start();
      expect(rig.transport.pushes, hasLength(1));
      expect((await rig.entry(p.id, e.id)).dirty, isTrue);
      expect((await rig.profile(p.id)).dirty, isFalse);
      expect(rig.engine.snapshot.phase, SyncPhase.idle,
          reason: 'a rejection is not a cycle failure');
      expect(rig.engine.snapshot.rejectedCount, 1);
      expect(rig.engine.snapshot.dirtyCount, 1);

      await rig.sync();
      await rig.sync();
      expect(rig.transport.pushes, hasLength(1),
          reason: 'the rejected row is not re-pushed in a tight loop');
      expect(rig.engine.snapshot.rejectedCount, 1);

      // A later local edit bumps local_rev: pushed again, accepted.
      await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.heavy);
      await rig.sync();
      expect(rig.transport.pushes, hasLength(2));
      expect(ids(rig.transport.pushes[1].dayEntries), [e.id]);
      expect((await rig.entry(p.id, e.id)).dirty, isFalse);
      expect(rig.engine.snapshot.rejectedCount, 0);
    });

    test('SyncTransportError.rejected (a transport with no per-row results) '
        'marks the whole batch rejected, not a cycle failure, and is not '
        're-pushed until edited again', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      final e = await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      rig.transport.nextPushError = SyncTransportError.rejected([p.id, e.id]);

      await rig.start();
      expect(rig.transport.pushes, hasLength(1),
          reason: 'the batch is recorded before the transport throws');
      expect((await rig.profile(p.id)).dirty, isTrue);
      expect((await rig.entry(p.id, e.id)).dirty, isTrue);
      expect(rig.engine.snapshot.phase, SyncPhase.idle,
          reason: 'a whole-batch rejection is not a cycle failure');
      expect(rig.engine.snapshot.rejectedCount, 2);
      expect(
        syncStatusCopy(
          snapshot: rig.engine.snapshot,
          authState: AuthSessionState.signedIn,
          now: t0,
        ),
        kRejectedCopy,
        reason: 'the status reflects "some entries could not be uploaded"',
      );

      await rig.sync();
      expect(rig.transport.pushes, hasLength(1),
          reason: 'both rejected rows are excluded from the next push');
    });

    test('rejected day entries are un-rejected and re-sent when their parent '
        'profile is accepted', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      final e = await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);

      // Push 1: both profile and day entry are rejected by server
      rig.transport.scriptPushResult(rejectedIds: [p.id, e.id]);
      await rig.start();
      expect(rig.transport.pushes, hasLength(1));
      expect(rig.engine.snapshot.rejectedCount, 2);

      // Push 2: user edits profile, bumps localRev. Entry e is NOT edited.
      await rig.storage.upsertProfile(
          id: p.id, displayName: 'A Fixed', isMinor: false);
      // Profile is accepted on push 2; un-rejected entry e is automatically re-sent on push 3
      rig.transport.scriptPushResult();
      rig.transport.scriptPushResult();
      await rig.sync();
      expect(rig.transport.pushes, hasLength(3));
      expect(ids(rig.transport.pushes[1].profiles), [p.id]);
      expect(ids(rig.transport.pushes[2].dayEntries), [e.id]);
      expect(rig.engine.snapshot.rejectedCount, 0);
      expect((await rig.entry(p.id, e.id)).dirty, isFalse);
    });

    test('reconcileDue clears rejected rows so they are retried on full '
        'reconciliation cadence', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      final e = await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);

      // Push 1: e is rejected
      rig.transport.scriptPushResult(rejectedIds: [e.id]);
      await rig.start();
      expect(rig.transport.pushes, hasLength(1));
      expect(rig.engine.snapshot.rejectedCount, 1);

      // Sync without reconcile due: not pushed
      await rig.sync();
      expect(rig.transport.pushes, hasLength(1));

      // Advance clock past 24 hours so reconcile is due
      rig.clock.now = t0.add(const Duration(hours: 25));
      rig.transport.scriptPushResult(); // accepted
      await rig.sync();
      expect(rig.transport.pushes, hasLength(2));
      expect(ids(rig.transport.pushes[1].dayEntries), [e.id]);
      expect(rig.engine.snapshot.rejectedCount, 0);
    });

    test('R8: a storage apply failure between push batches leaves the '
        'committed batch pushed and the failing batch dirty; the next cycle '
        're-pushes only what is left', () async {
      // Two dirty profiles and NO day entries: at batchSize 1 that is what
      // yields two batches ([pA], [pB]). One profile plus one day entry
      // would collapse into a single batch, because `_chunk` appends the
      // first day entries to the *last* profile batch - the failure would
      // then land inside batch 1, before anything committed, which is not
      // the cross-batch failure this test exists to pin.
      final rig = Rig(
          batchSize: 1,
          storageFactory: (db, clock) => HookedStorage(db, clock: clock));
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      await rig.storage.upsertProfile(displayName: 'A', isMinor: false);
      await rig.storage.upsertProfile(displayName: 'B', isMinor: false);
      final offsetBefore = (await rig.state()).serverClockOffsetMs;
      expect(offsetBefore, isNull);
      // Batch 1 answers with a server clock five minutes ahead, so the
      // in-memory offset it sets is visibly different from the persisted one.
      rig.transport.scriptPushResult(
          serverNow: t0.add(const Duration(minutes: 5)));

      final hooked = rig.storage as HookedStorage;
      var markPushedCalls = 0;
      hooked.beforeMarkPushed = (table, id) async {
        markPushedCalls++;
        // The first write of batch 2, after batch 1 fully committed. A plain
        // Exception (not a SyncTransportError) lands in `_cycle`'s general
        // catch, so the kind is `other`.
        if (markPushedCalls == 2) throw Exception('storage apply failed');
      };

      await rig.start();

      final pushes = rig.transport.pushes;
      expect(pushes, hasLength(2),
          reason: 'two profile-only batches were sent; a collapse back into '
              'one batch would silently void every assertion below');
      expect(pushes[0].profiles, hasLength(1));
      expect(pushes[1].profiles, hasLength(1));
      expect(pushes[0].dayEntries, isEmpty);
      expect(pushes[1].dayEntries, isEmpty);
      final committedId = ids(pushes[0].profiles).single;
      final failedId = ids(pushes[1].profiles).single;

      expect((await rig.profile(committedId)).dirty, isFalse,
          reason: 'batch 1 markPushed committed and nothing rolled it back');
      expect((await rig.profile(failedId)).dirty, isTrue);
      expect(await rig.storage.dirtyCount(), 1);
      expect(rig.engine.snapshot.phase, SyncPhase.error);
      expect(rig.engine.snapshot.lastError, SyncErrorKind.other);
      expect(rig.transport.pulls, isEmpty,
          reason: 'a failed push ends the cycle');
      expect(rig.storage.clockOffset, const Duration(minutes: 5),
          reason: 'the in-memory offset from batch 1 did take effect');
      expect((await rig.state()).serverClockOffsetMs,
          const Duration(minutes: 5).inMilliseconds,
          reason: 'the persist happens immediately per committed batch');

      hooked.beforeMarkPushed = null;
      await rig.sync();

      expect(rig.transport.pushes, hasLength(3));
      expect(rig.transport.pushes[2].profiles, hasLength(1));
      expect(ids(rig.transport.pushes[2].profiles), [failedId],
          reason: 'only the row left over is re-pushed');
      expect(await rig.storage.dirtyCount(), 0);
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
    });
  });
}
