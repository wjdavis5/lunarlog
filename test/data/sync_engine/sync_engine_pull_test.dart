/// per-table incremental pull, cursor advancement, and full reconciliation cadence and fallback — issue #437 split of `test/data/sync_engine_test.dart`.
/// Shared fixtures live in `sync_engine_support.dart`. Nothing here
/// touches Supabase.
library;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/sync/sync_transport.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';

import 'sync_engine_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('pull', () {
    test('per-table incremental pull applies pages in order and advances '
        'only that table\'s cursor; a throwing page leaves the cursor at the '
        'previous page', () async {
      final rig = Rig(pageSize: 2);
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final pA = ulidN(1);
      final pB = ulidN(2);
      final pC = ulidN(3);
      rig.transport.scriptPages(SyncTable.profiles, [
        [
          remoteProfile(pA, updatedAt: t0, serverVersion: 1),
          remoteProfile(pB, updatedAt: t0, serverVersion: 2),
        ],
        [remoteProfile(pC, updatedAt: t0, serverVersion: 3)],
      ]);
      rig.transport.scriptPages(SyncTable.dayEntries, [
        [
          remoteEntry(ulidN(10),
              profileId: pA, localDate: '2026-01-01', updatedAt: t0,
              serverVersion: 10),
          remoteEntry(ulidN(11),
              profileId: pA, localDate: '2026-01-02', updatedAt: t0,
              serverVersion: 11),
        ],
      ]);
      // The second day-entries page throws.
      rig.transport.onPull = (call) {
        if (call.table == SyncTable.dayEntries && call.afterVersion == 11) {
          rig.transport.nextPullError = const SyncTransportError.network();
        }
      };

      await rig.start();

      final calls = rig.transport.pulls;
      expect(calls.map((c) => (c.table, c.afterVersion)).toList(), [
        (SyncTable.profiles, 0),
        (SyncTable.profiles, 2),
        (SyncTable.profileGuardians, 0),
        (SyncTable.dayEntries, 0),
        (SyncTable.dayEntries, 11),
      ]);
      final state = await rig.state();
      expect(state.cursorProfiles, 3);
      expect(state.cursorDayEntries, 11);
      expect((await rig.storage.getProfiles()).map((p) => p.id),
          containsAll([pA, pB, pC]));
      expect(await rig.storage.getDayEntries(profileId: pA), hasLength(2));
      expect(rig.engine.snapshot.phase, SyncPhase.error);
      expect(rig.engine.snapshot.lastError, SyncErrorKind.network);
    });

    test('a profiles page ending at 900 does not move cursor_day_entries; '
        'day entries 501 to 899 are still pulled', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.storage.writeSyncState(kDefaultSyncState.copyWith(
        boundUserId: const Value(uidA),
        deviceId: 'device-1',
        cursorProfiles: 0,
        cursorDayEntries: 500,
        lastFullPullAt: Value(t0),
      ));
      final pA = ulidN(1);
      rig.transport.pageResolver = (table, after, limit) => switch (table) {
            SyncTable.profiles => after < 900
                ? [remoteProfile(pA, updatedAt: t0, serverVersion: 900)]
                : const [],
            SyncTable.profileGuardians => const [],
            SyncTable.dayEntries => after < 899
                ? [
                    remoteEntry(ulidN(600),
                        profileId: pA,
                        localDate: '2026-01-01',
                        updatedAt: t0,
                        serverVersion: 600),
                    remoteEntry(ulidN(899),
                        profileId: pA,
                        localDate: '2026-01-02',
                        updatedAt: t0,
                        serverVersion: 899),
                  ]
                : const [],
            SyncTable.observations => const [],
            SyncTable.profileModes => const [],
            SyncTable.cycleOverrides => const [],
            SyncTable.careNotes => const [],
            SyncTable.visitPrepItems => const [],
          };

      await rig.start();

      final entryCalls =
          rig.transport.pulls.where((c) => c.table == SyncTable.dayEntries);
      expect(entryCalls.first.afterVersion, 500,
          reason: 'the profiles page did not touch the day-entries cursor');
      final state = await rig.state();
      expect(state.cursorProfiles, 900);
      expect(state.cursorDayEntries, 899);
      expect(await rig.storage.getDayEntries(profileId: pA), hasLength(2));
    });

    test('a full-reconcile row with server_version below the cursor is still '
        'applied under LWW and both cursors stay unchanged', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.storage.writeSyncState(kDefaultSyncState.copyWith(
        boundUserId: const Value(uidA),
        deviceId: 'device-1',
        cursorProfiles: 100,
        cursorDayEntries: 100,
        lastFullPullAt: Value(t0.subtract(const Duration(hours: 25))),
      ));
      final pA = ulidN(1);
      rig.transport.pageResolver = (table, after, limit) => switch (table) {
            SyncTable.profiles => after == 0
                ? [remoteProfile(pA, updatedAt: t0, serverVersion: 50)]
                : const [],
            SyncTable.profileGuardians => const [],
            SyncTable.dayEntries => const [],
            SyncTable.observations => const [],
            SyncTable.profileModes => const [],
            SyncTable.cycleOverrides => const [],
            SyncTable.careNotes => const [],
            SyncTable.visitPrepItems => const [],
          };

      await rig.start();

      expect((await rig.storage.getProfiles()).map((p) => p.id), [pA]);
      final state = await rig.state();
      expect(state.cursorProfiles, 100);
      expect(state.cursorDayEntries, 100);
      expect(state.lastFullPullAt, isNotNull);
      expect(state.lastFullPullAt!.toUtc(), t0);
    });

    test('full reconcile runs on bind, after a push that returned resolved '
        'rows, and when the last full pull is older than 24h; not otherwise',
        () async {
      // (a) Bind on an empty database: reconcile stamps last_full_pull_at.
      final bindRig = Rig();
      addTearDown(bindRig.dispose);
      await bindRig.start();
      expect((await bindRig.state()).lastFullPullAt?.toUtc(), t0);

      // (b) Bound, recent full pull, cursors at 100: incremental only.
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.storage.writeSyncState(kDefaultSyncState.copyWith(
        boundUserId: const Value(uidA),
        deviceId: 'device-1',
        cursorProfiles: 100,
        cursorDayEntries: 100,
        lastFullPullAt: Value(t0),
      ));
      await rig.start();
      expect(rig.transport.pulls.map((c) => c.afterVersion),
          [100, 0, 100, 0, 0, 0, 0, 0]);
      expect((await rig.state()).lastFullPullAt?.toUtc(), t0);

      // (c) A push with resolved rows makes a reconcile due.
      rig.clock.now = t0.add(const Duration(hours: 1));
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      rig.transport.scriptPushResult(resolved: [
        remoteProfile(p.id,
            displayName: 'Server',
            updatedAt: t0.add(const Duration(hours: 2)),
            serverVersion: 101),
      ]);
      rig.transport.pulls.clear();
      await rig.sync();
      expect(rig.transport.pulls.map((c) => c.afterVersion),
          [100, 0, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      expect((await rig.state()).lastFullPullAt?.toUtc(), rig.clock.now);

      // (d) Not otherwise: the next cycle is incremental only.
      rig.transport.pulls.clear();
      await rig.sync();
      expect(rig.transport.pulls.map((c) => c.afterVersion),
          [100, 0, 100, 0, 0, 0, 0, 0]);

      // (e) Older than 24h: due again.
      rig.clock.now = rig.clock.now.add(const Duration(hours: 25));
      rig.transport.pulls.clear();
      await rig.sync();
      expect(rig.transport.pulls.map((c) => c.afterVersion),
          [100, 0, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      expect((await rig.state()).lastFullPullAt?.toUtc(), rig.clock.now);
    });

    test('a retryable apply failure on pull leaves the cursor and is retried '
        'next cycle once the profile is held', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final pA = ulidN(1);
      final orphan = remoteEntry(ulidN(10),
          profileId: pA, localDate: '2026-01-01', updatedAt: t0,
          serverVersion: 10);
      // Cycle 1: the day entry arrives before its profile.
      rig.transport.scriptPage(SyncTable.dayEntries, [orphan]);
      await rig.start();
      expect((await rig.state()).cursorDayEntries, 0);
      expect(rig.engine.snapshot.phase, SyncPhase.idle,
          reason: 'retryable, not fatal');

      // Cycle 2: the profile is there now; the entry applies.
      rig.transport.scriptPage(SyncTable.profiles,
          [remoteProfile(pA, updatedAt: t0, serverVersion: 1)]);
      rig.transport.scriptPage(SyncTable.dayEntries, [orphan]);
      await rig.sync();
      expect((await rig.state()).cursorDayEntries, 10);
      expect(await rig.storage.getDayEntries(profileId: pA), hasLength(1));
    });

    test('a full-reconcile page that fails as a batch falls back to '
        'per-row application, and a row still left orphaned defers the '
        'next full-pull stamp (retried next cycle)', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      final staleFullPull = t0.subtract(const Duration(hours: 25));
      await rig.bind(uidA, lastFullPullAt: staleFullPull);
      final pA = ulidN(1);
      final orphan = remoteEntry(ulidN(10),
          profileId: pA, localDate: '2026-01-01', updatedAt: t0,
          serverVersion: 10);
      // Incremental dayEntries gets nothing; the reconcile dayEntries call
      // (which starts over from version 0, same as incremental here) gets
      // the orphan — `applyRemoteRows` fails the whole page as one
      // transaction, `_applyReconcilePage` falls back to applying rows one
      // by one, and the entry alone still fails (its profile page was
      // never supplied), so it is left for the next cycle.
      rig.transport.scriptPage(SyncTable.dayEntries, const []);
      rig.transport.scriptPage(SyncTable.dayEntries, [orphan]);

      await rig.start();

      expect(rig.engine.snapshot.phase, SyncPhase.idle,
          reason: 'a retryable apply failure is not a cycle failure');
      expect(await rig.storage.getDayEntries(profileId: pA), isEmpty);
      expect((await rig.state()).lastFullPullAt?.toUtc(), staleFullPull,
          reason: 'reconcile is retried, so the full-pull stamp does not '
              'advance yet');
    });

    test('R9: a full-reconcile page that fails as a batch lands the rows the '
        'per-row fallback can apply and defers only the orphan', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      final staleFullPull = t0.subtract(const Duration(hours: 25));
      await rig.bind(uidA, lastFullPullAt: staleFullPull);
      // pA is held locally so the remote entry referencing it can apply.
      // Creating it marks it dirty, so pA also rides this cycle's push -
      // harmless, but it is why this test asserts nothing about
      // `transport.pushes`.
      final pA = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      const orphanProfileId = 'no-such-profile';
      final orphan = remoteEntry(ulidN(10),
          profileId: orphanProfileId, localDate: '2026-01-01', updatedAt: t0,
          serverVersion: 10);
      final appliable = remoteEntry(ulidN(11),
          profileId: pA.id, localDate: '2026-02-02', updatedAt: t0,
          serverVersion: 11);
      // The incremental dayEntries pull gets nothing; the reconcile page
      // carries both rows, so `applyRemoteRows` fails the whole page as one
      // transaction and `_applyReconcilePage` re-applies it row by row.
      //
      // THE ROW ORDER IS DELIBERATE - DO NOT REORDER. The orphan must come
      // first. `_applyReconcilePage` iterates the page in order, so with the
      // appliable row first a `break`-on-first-failure regression would
      // produce byte-identical results (the good row would already have
      // landed) and this test would pass against the very bug it exists to
      // catch.
      rig.transport.scriptPage(SyncTable.dayEntries, const []);
      rig.transport.scriptPage(SyncTable.dayEntries, [orphan, appliable]);

      await rig.start();

      final landed = await rig.storage.getDayEntries(profileId: pA.id);
      expect(landed, hasLength(1),
          reason: 'the appliable row lands even though an earlier row in the '
              'same page failed');
      expect(landed.single.id, appliable.id);
      expect(landed.single.localDate, '2026-02-02');
      expect(landed.single.flow, FlowLevel.medium);
      expect(landed.single.note, 'from remote');
      expect(landed.single.tags, ['remote']);
      expect(
          await rig.storage.getDayEntries(
              profileId: orphanProfileId, includeTombstones: true),
          isEmpty,
          reason: 'the orphan is deferred, not persisted');
      expect(rig.engine.snapshot.phase, SyncPhase.idle,
          reason: 'a retryable apply failure is not a cycle failure');
      final state = await rig.state();
      expect(state.lastFullPullAt?.toUtc(), staleFullPull,
          reason: 'the deferred row keeps the full-pull stamp where it was, '
              'so the reconcile is retried next cycle');
      expect(state.cursorProfiles, 0);
      expect(state.cursorDayEntries, 0,
          reason: 'a reconcile applies without moving the per-table cursors');
    });

    test('an un-appliable reconcile row retries up to 3 times before advancing '
        'lastFullPullAt to bound the loop', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      final staleFullPull = t0.subtract(const Duration(hours: 25));
      await rig.bind(uidA, lastFullPullAt: staleFullPull);

      const orphanProfileId = 'no-such-profile';
      final orphan = remoteEntry(ulidN(20),
          profileId: orphanProfileId, localDate: '2026-01-01', updatedAt: t0,
          serverVersion: 20);

      // Incremental pulls return empty. Reconcile pages return the orphan.
      // Cycle 1: start() runs cycle 1.
      rig.transport.scriptPage(SyncTable.dayEntries, const []); // incremental
      rig.transport.scriptPage(SyncTable.dayEntries, [orphan]); // reconcile
      await rig.start();

      var state = await rig.state();
      expect(state.lastFullPullAt?.toUtc(), staleFullPull,
          reason: 'cycle 1 failed reconcile retry, stamp still stale');

      // Cycle 2: requestSync runs cycle 2.
      rig.transport.scriptPage(SyncTable.dayEntries, const []); // incremental
      rig.transport.scriptPage(SyncTable.dayEntries, [orphan]); // reconcile
      await rig.sync();

      state = await rig.state();
      expect(state.lastFullPullAt?.toUtc(), staleFullPull,
          reason: 'cycle 2 failed reconcile retry, stamp still stale');

      // Cycle 3: 3rd consecutive retry reaches limit, advancing lastFullPullAt.
      rig.transport.scriptPage(SyncTable.dayEntries, const []); // incremental
      rig.transport.scriptPage(SyncTable.dayEntries, [orphan]); // reconcile
      await rig.sync();

      state = await rig.state();
      expect(state.lastFullPullAt?.toUtc(), t0,
          reason: 'cycle 3 reached retry bound; lastFullPullAt advanced to t0');

      // Cycle 4: full reconcile is no longer due because lastFullPullAt is fresh.
      final pullsBeforeCycle4 = rig.transport.pullCount;
      rig.transport.scriptPage(SyncTable.dayEntries, const []); // incremental
      await rig.sync();

      // Incremental pull checks profiles, profileGuardians, dayEntries,
      // observations (Issue #240), the two Issue #188 tables, and the two
      // Issue #128 tables — 8 pull calls — and NO reconcile pull is made.
      expect(rig.transport.pullCount, pullsBeforeCycle4 + 8,
          reason: 'cycle 4 ran incremental pulls only, no full reconcile');
    });

    test('finding #4: an unresolvable profileGuardians row bounds the '
        'cursorProfiles rewind to 3 consecutive cycles, then stops forcing '
        'a full profile re-pull', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);

      // An accepted membership whose profile never arrives - the one case
      // finding #8 leaves able to keep throwing here. It never changes and
      // never resolves.
      final stuck = remoteGuardian('g-stuck',
          profileId: 'no-such-profile', userId: uidA, status: 'accepted',
          updatedAt: t0);
      rig.transport.pageResolver = (table, after, limit) => switch (table) {
            SyncTable.profiles => const [],
            SyncTable.dayEntries => const [],
            SyncTable.observations => const [],
            SyncTable.profileModes => const [],
            SyncTable.cycleOverrides => const [],
            SyncTable.careNotes => const [],
            SyncTable.visitPrepItems => const [],
            SyncTable.profileGuardians => [stuck],
          };

      // Re-primes cursorProfiles to a nonzero value before each cycle, so a
      // rewind back to 0 is observable independently of whatever the
      // previous cycle left behind.
      Future<void> primeCursorProfiles() async {
        final s = await rig.state();
        await rig.storage.writeSyncState(s.copyWith(cursorProfiles: 100));
      }

      // Cycle 1: 1st consecutive failure - the rewind still fires.
      await primeCursorProfiles();
      await rig.start();
      expect((await rig.state()).cursorProfiles, 0,
          reason: 'cycle 1: rewound (1st consecutive failure)');

      // Cycle 2: 2nd consecutive failure - still under the cap, still
      // rewinds.
      await primeCursorProfiles();
      await rig.sync();
      expect((await rig.state()).cursorProfiles, 0,
          reason: 'cycle 2: rewound (2nd consecutive failure)');

      // Cycle 3: 3rd consecutive failure reaches kMaxConsecutiveReconcileRetries
      // - the rewind is skipped this time.
      await primeCursorProfiles();
      await rig.sync();
      expect((await rig.state()).cursorProfiles, 100,
          reason: 'cycle 3: cap reached, cursorProfiles is left alone');

      // Cycle 4: the row is still stuck, but the bound holds - it does not
      // force a full profile re-pull every cycle forever.
      await primeCursorProfiles();
      await rig.sync();
      expect((await rig.state()).cursorProfiles, 100,
          reason: 'cycle 4: still bounded, cursorProfiles stays put');

      expect(rig.engine.snapshot.phase, SyncPhase.idle,
          reason: 'an unresolvable guardian row is retried, not fatal');
    });

    test('R5, finding #9: revoke -> re-invite -> reconcile brings the '
        'profile and its entries back, instead of the revocation tombstone '
        'outliving every later server row forever', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final pShared = ulidN(1);
      final entryId = ulidN(10);
      // Never touched again for the rest of the test: neither revoking nor
      // re-accepting a guardian invitation bumps the server's
      // profiles.updated_at (or the day entry's).
      final sharedProfile =
          remoteProfile(pShared, updatedAt: t0, serverVersion: 1);
      final sharedEntry = remoteEntry(entryId,
          profileId: pShared, localDate: '2026-01-15', updatedAt: t0,
          serverVersion: 1);

      // Cycle 1: the profile is shared and the invitation accepted.
      rig.transport.scriptPage(SyncTable.profiles, [sharedProfile]);
      rig.transport.scriptPage(SyncTable.profileGuardians, [
        remoteGuardian('g-1',
            profileId: pShared,
            userId: uidA,
            status: 'accepted',
            updatedAt: t0,
            serverVersion: 1),
      ]);
      rig.transport.scriptPage(SyncTable.dayEntries, [sharedEntry]);
      await rig.start();

      expect(await rig.storage.getProfile(pShared), isNotNull);
      expect(
          await rig.storage.getDayEntries(profileId: pShared), hasLength(1));

      // Cycle 2: guardianship is revoked - R5 wipes the profile and its
      // entries locally at the revocation timestamp.
      final revokedAt = t0.add(const Duration(hours: 1));
      rig.transport.scriptPage(SyncTable.profileGuardians, [
        remoteGuardian('g-1',
            profileId: pShared,
            userId: uidA,
            status: 'revoked',
            updatedAt: revokedAt,
            serverVersion: 2),
      ]);
      await rig.sync();

      expect(await rig.storage.getProfile(pShared), isNull,
          reason: 'revoked access hides the shared profile');
      expect(await rig.storage.getDayEntries(profileId: pShared), isEmpty);

      // Cycle 3: re-invited and re-accepted. The membership flips back to
      // accepted, but the profile row itself is untouched server-side (the
      // accept RPC never bumps profiles.updated_at), so it stays hidden
      // until a reconcile re-delivers it.
      final reacceptedAt = revokedAt.add(const Duration(hours: 1));
      rig.transport.scriptPage(SyncTable.profileGuardians, [
        remoteGuardian('g-1',
            profileId: pShared,
            userId: uidA,
            status: 'accepted',
            updatedAt: reacceptedAt,
            serverVersion: 3),
      ]);
      await rig.sync();

      expect(await rig.storage.getProfile(pShared), isNull,
          reason: 'accepting the invite alone does not restore the profile');

      // Cycle 4: a reconcile (here, 24h staleness; in the app, the sharing
      // flow also triggers one directly on acceptance) re-delivers the
      // server's profile and day-entry rows, still stamped at their
      // original, never-touched updated_at. Before the fix, that
      // timestamp had permanently lost to the tombstone's (bumped to
      // revokedAt); after the fix the tombstone kept its pre-revocation
      // updated_at, so the server's copy ties under KTD5 and wins
      // normally.
      rig.clock.now = t0.add(const Duration(hours: 25));
      rig.transport.scriptPage(SyncTable.profiles, const []); // incremental
      rig.transport.scriptPage(SyncTable.dayEntries, const []); // incremental
      rig.transport
          .scriptPage(SyncTable.profileGuardians, const []); // incremental
      rig.transport.scriptPage(SyncTable.profiles, [sharedProfile]); // reconcile
      rig.transport.scriptPage(SyncTable.dayEntries, [sharedEntry]); // reconcile
      rig.transport
          .scriptPage(SyncTable.profileGuardians, const []); // reconcile
      await rig.sync();

      final revived = await rig.storage.getProfile(pShared);
      expect(revived, isNotNull,
          reason: 'the profile is visible again once the server row '
              'reconciles');
      expect(revived!.deletedAt, isNull);
      final entries = await rig.storage.getDayEntries(profileId: pShared);
      expect(entries, hasLength(1));
      expect(entries.single.deletedAt, isNull);
      expect(entries.single.note, 'from remote');
    });
  });
}
