/// per-table incremental pull, cursor advancement, and full reconciliation cadence and fallback — issue #437 split of `test/data/sync_engine_test.dart`.
/// Shared fixtures live in `sync_engine_support.dart`. Nothing here
/// touches Supabase.
library;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/sync/supabase_sync_engine.dart' show kCursorLookback;
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
            SyncTable.dayEntryMergeEvents => const [],
            SyncTable.profileTagRegistry => const [],
            SyncTable.deletedProfiles => const [],
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
            SyncTable.dayEntryMergeEvents => const [],
            SyncTable.profileTagRegistry => const [],
            SyncTable.deletedProfiles => const [],
          };

      await rig.start();

      expect((await rig.storage.getProfiles()).map((p) => p.id), [pA]);
      final state = await rig.state();
      expect(state.cursorProfiles, 100);
      expect(state.cursorDayEntries, 100);
      expect(state.lastFullPullAt, isNotNull);
      expect(state.lastFullPullAt!.toUtc(), t0);
    });

    test('full reconcile runs on bind and when the last full pull is older '
        'than 24h; not otherwise, and NOT just because a push saw resolved '
        'rows (issue #525)', () async {
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
          [100, 0, 100, 0, 0, 0, 0, 0, 0, 0, 0]); // 9th 0 is day_entry_merge_events (#130), 10th is profile_tag_registry (#257), 11th is deletedProfiles (#522)
      expect((await rig.state()).lastFullPullAt?.toUtc(), t0);

      // (c) Issue #525: a push whose answer carries resolved rows is no
      // longer, on its own, a reconcile trigger — applyPushResult already
      // applies each one correctly. The next cycle stays incremental-only
      // and lastFullPullAt is untouched.
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
          [100, 0, 100, 0, 0, 0, 0, 0, 0, 0, 0], // 9th 0 is day_entry_merge_events (#130), 10th is profile_tag_registry (#257), 11th is deletedProfiles (#522)
          reason: 'resolved rows in a push answer must not force a '
              'full reconcile (issue #525)');
      expect((await rig.state()).lastFullPullAt?.toUtc(), t0,
          reason: 'lastFullPullAt is untouched — no reconcile ran');

      // (d) Still not otherwise: the following cycle is incremental only too.
      rig.transport.pulls.clear();
      await rig.sync();
      expect(rig.transport.pulls.map((c) => c.afterVersion),
          [100, 0, 100, 0, 0, 0, 0, 0, 0, 0, 0]); // 9th 0 is day_entry_merge_events (#130), 10th is profile_tag_registry (#257), 11th is deletedProfiles (#522)

      // (e) Older than 24h: due again.
      rig.clock.now = rig.clock.now.add(const Duration(hours: 25));
      rig.transport.pulls.clear();
      await rig.sync();
      expect(rig.transport.pulls.map((c) => c.afterVersion),
          // 11 incremental + 11 reconcile afterVersion values
          // (deletedProfiles, issue #522, adds its `0` to each half;
          // dayEntryMergeEvents, issue #130, the tenth; profileTagRegistry,
          // issue #257, the eleventh).
          [100, 0, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      expect((await rig.state()).lastFullPullAt?.toUtc(), rig.clock.now);
    });

    group('issue #42: scheduled-reconcile version probe', () {
      /// A probe that answers "nothing changed" for the persisted cursors:
      /// every table's max at or below its cursor. Issue #130's
      /// dayEntryMergeEvents carries a probe answer too — the probe walks
      /// the shared `_pullTableOrder`, which grew with the table.
      Map<SyncTable, int> unchangedProbe() => {
        SyncTable.profiles: 100,
        SyncTable.profileGuardians: 0,
        SyncTable.dayEntries: 0,
        SyncTable.observations: 0,
        SyncTable.profileModes: 0,
        SyncTable.cycleOverrides: 0,
        SyncTable.careNotes: 0,
        SyncTable.visitPrepItems: 0,
        SyncTable.dayEntryMergeEvents: 0,
        SyncTable.profileTagRegistry: 0,
        SyncTable.deletedProfiles: 0,
      };

      Future<void> bindStale(Rig rig) => rig.storage.writeSyncState(
        kDefaultSyncState.copyWith(
          boundUserId: const Value(uidA),
          deviceId: 'device-1',
          cursorProfiles: 100,
          lastFullPullAt: Value(t0.subtract(const Duration(hours: 25))),
        ),
      );

      test('an unchanged probe skips the scheduled re-pull while still '
          'stamping a clean reconcile', () async {
        final rig = Rig();
        addTearDown(rig.dispose);
        await bindStale(rig);
        rig.transport.maxVersions = unchangedProbe();

        await rig.start();

        expect(
          rig.transport.pulls,
          hasLength(11),
          reason:
              'incremental only — the 11 reconcile re-pulls were '
              'skipped because nothing changed server-side',
        );
        expect(
          rig.transport.fetchMaxVersionCalls,
          hasLength(11),
          reason: 'one probe per pull table before the reconcile',
        );
        expect(
          (await rig.state()).lastFullPullAt?.toUtc(),
          t0,
          reason:
              'the skipped reconcile still counts: the staleness '
              'window restarts and the maintenance cadence is preserved',
        );
      });

      test('a probe above a cursor (the clamp lookback, or a real change) '
          'runs the full re-pull', () async {
        final rig = Rig();
        addTearDown(rig.dispose);
        await bindStale(rig);
        final probe = unchangedProbe();
        probe[SyncTable.dayEntries] = 1; // above the persisted cursor 0
        rig.transport.maxVersions = probe;

        await rig.start();

        expect(
          rig.transport.pulls,
          hasLength(22),
          reason:
              '11 incremental + 11 reconcile: the probe reported a '
              'change, so the full re-pull runs',
        );
        expect((await rig.state()).lastFullPullAt?.toUtc(), t0);
      });

      test('a failed probe (null) falls back to the full re-pull — sync is '
          'never silently skipped', () async {
        final rig = Rig();
        addTearDown(rig.dispose);
        await bindStale(rig);
        rig.transport.maxVersions = {}; // every table answers null ("unknown")

        await rig.start();

        expect(
          rig.transport.pulls,
          hasLength(22),
          reason: 'a probe failure is conservative: the full re-pull runs',
        );
        expect((await rig.state()).lastFullPullAt?.toUtc(), t0);
      });

      test('a forced reconcile is never skipped by the probe', () async {
        final rig = Rig();
        addTearDown(rig.dispose);
        await rig.storage.writeSyncState(
          kDefaultSyncState.copyWith(
            boundUserId: const Value(uidA),
            deviceId: 'device-1',
            cursorProfiles: 100,
            lastFullPullAt: Value(t0),
          ),
        );
        rig.transport.maxVersions = unchangedProbe();
        await rig.start(); // incremental only; nothing is due
        rig.transport.pulls.clear();

        rig.engine.triggerFullReconcile();
        await rig.engine.flush();

        expect(
          rig.transport.pulls,
          hasLength(22),
          reason:
              '11 incremental + 11 reconcile: the forced reconcile '
              're-pulled even though the probe says nothing changed',
        );
        expect(
          rig.transport.fetchMaxVersionCalls,
          isEmpty,
          reason: 'an explicit repair request never consults the probe',
        );
      });

      test('a fresh-bind reconcile is never skipped by the probe', () async {
        final rig = Rig();
        addTearDown(rig.dispose);
        rig.transport.maxVersions = {
          for (final table in SyncTable.values) table: 0,
        };

        await rig.start(); // binds on the empty database, reconciles

        expect(
          rig.transport.pulls,
          hasLength(22),
          reason:
              'a bind-time reconcile re-pulls everything regardless '
              'of the probe',
        );
        expect(
          rig.transport.fetchMaxVersionCalls,
          isEmpty,
          reason: 'a bind never consults the probe',
        );
      });
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
      // observations (Issue #240), the two Issue #188 tables, the two
      // Issue #128 tables, deletedProfiles (Issue #522), and merge events
      // (Issue #130) — 10 pull calls — and NO reconcile pull is made.
      expect(rig.transport.pullCount, pullsBeforeCycle4 + 11,
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
            SyncTable.dayEntryMergeEvents => const [],
            SyncTable.profileTagRegistry => const [],
            SyncTable.profileGuardians => [stuck],
            SyncTable.deletedProfiles => const [],
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

    // Issue #102: the bound above is only half the guarantee — the count
    // must also RESET when profileGuardians applies cleanly again
    // (`_onTablePullSettled`), so a household whose deferred row resolves
    // and later hits a NEW stuck row gets fresh rewinds instead of being
    // silently capped at 3 total failures for the engine's whole lifetime.
    // The test above never exercises a clean profileGuardians page between
    // failures, so a regression deleting the reset (or making the counter
    // cumulative rather than consecutive) leaves it green. This test drives
    // a defer across two consecutive cycles, lets the row resolve cleanly,
    // then defers again — the rewind must fire again on the new failure.
    test('issue #102: the guardian-defer bound is consecutive, not '
        'cumulative — two deferring cycles rewind, a clean profileGuardians '
        'apply resets the count, and the next failure rewinds again',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);

      // Cycle 1-2: an accepted membership for a profile that has not been
      // pulled yet (deferred, not stuck). Cycle 3 delivers the profile, so
      // the same membership applies cleanly. Cycle 4: a NEW membership for
      // a profile that never arrives (genuinely stuck).
      final pendingProfile = ulidN(30);
      final deferredGuardian = remoteGuardian('g-deferred',
          profileId: pendingProfile, userId: uidA, status: 'accepted',
          updatedAt: t0, serverVersion: 5);
      final stuckGuardian = remoteGuardian('g-stuck-2',
          profileId: ulidN(31), userId: uidA, status: 'accepted',
          updatedAt: t0, serverVersion: 20);
      var deliverProfile = false;
      rig.transport.pageResolver = (table, after, limit) => switch (table) {
            SyncTable.profiles =>
              (deliverProfile && after < 10) ? [remoteProfile(
                  pendingProfile, updatedAt: t0, serverVersion: 10)] : const [],
            SyncTable.profileGuardians => after < 5
                ? [deferredGuardian]
                : (after < 20 ? [stuckGuardian] : const []),
            _ => const [],
          };

      // Re-primes cursorProfiles to a nonzero value before cycles 1 and 2,
      // so a rewind back to 0 is observable; NOT before cycles 3 and 4,
      // which must run on whatever the previous cycle actually left there.
      Future<void> primeCursorProfiles() async {
        final s = await rig.state();
        await rig.storage.writeSyncState(s.copyWith(cursorProfiles: 100));
      }

      // Cycle 1: 1st consecutive defer — the rewind fires.
      await primeCursorProfiles();
      await rig.start();
      expect((await rig.state()).cursorProfiles, 0,
          reason: 'cycle 1: rewound (1st consecutive defer)');

      // Cycle 2: 2nd consecutive defer — still under the cap, still
      // rewinds. This is the two-consecutive-cycles defer the issue asked
      // to pin: without the rewind, the deferred row's profile (version
      // 10, below the profiles cursor) would never be re-pulled.
      await primeCursorProfiles();
      await rig.sync();
      expect((await rig.state()).cursorProfiles, 0,
          reason: 'cycle 2: rewound again (2nd consecutive defer)');

      // Cycle 3: the profile arrives. The rewind from cycle 2 left
      // cursorProfiles at 0, so the profile page (version 10) is pulled
      // and applied; the same guardian row then applies cleanly and the
      // consecutive-failure count resets.
      deliverProfile = true;
      await rig.sync();
      final state3 = await rig.state();
      expect(state3.cursorProfiles, 10,
          reason: 'the deferred profile finally arrived and was pulled');
      expect(state3.cursorProfileGuardians, 5,
          reason: 'the membership applied cleanly once its profile was '
              'held — the page cursor advanced');

      // Cycle 4: a NEW stuck membership. The reset makes this failure
      // consecutive-failure #1, so the rewind must fire again; without
      // `_onTablePullSettled`'s reset it would be #4 and the cap would
      // swallow it (cursorProfiles left at 10).
      await rig.sync();
      expect((await rig.state()).cursorProfiles, 0,
          reason: 'the bound re-armed after the clean cycle: the new '
              'failure rewinds again');
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
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

    test('issue #525: profileGuardians pages from its own persisted cursor, '
        'not from 0, on the second cycle onward', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final pA = ulidN(1);
      rig.transport.scriptPage(SyncTable.profiles, [
        remoteProfile(pA, updatedAt: t0, serverVersion: 1),
      ]);
      rig.transport.scriptPage(SyncTable.profileGuardians, [
        remoteGuardian('g-1',
            profileId: pA, userId: uidA, status: 'accepted', updatedAt: t0,
            serverVersion: 50),
      ]);
      await rig.start();
      expect((await rig.state()).cursorProfileGuardians, 50);

      // A second cycle: the guardian pull must start from the persisted
      // cursor (50), not re-scan the whole table from 0 — the exact perf
      // regression issue #525 closes.
      rig.transport.pulls.clear();
      rig.transport.scriptPage(SyncTable.profiles, const []);
      rig.transport.scriptPage(SyncTable.profileGuardians, const []);
      await rig.sync();

      final guardianCalls = rig.transport.pulls
          .where((c) => c.table == SyncTable.profileGuardians)
          .toList();
      expect(guardianCalls, hasLength(1));
      expect(guardianCalls.single.afterVersion, 50,
          reason: 'must resume from the persisted cursor, not re-scan '
              'from version 0 every cycle');
    });

    test('issue #597: deletedProfiles pages from its own persisted cursor, '
        'not from 0, on the second cycle onward', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final pA = ulidN(1);
      rig.transport.scriptPage(SyncTable.profiles, [
        remoteProfile(pA, updatedAt: t0, serverVersion: 1),
      ]);
      rig.transport.scriptPage(SyncTable.deletedProfiles, [
        RemoteDeletedProfileRow(
            profileId: ulidN(2), deletedAt: t0, serverVersion: 70),
      ]);
      await rig.start();
      expect((await rig.state()).cursorDeletedProfiles, 70);

      // A second cycle: the deletedProfiles pull must start from the
      // persisted cursor (70), not re-scan the whole table from 0 — the
      // same perf fix issue #525 already applied to profileGuardians.
      rig.transport.pulls.clear();
      rig.transport.scriptPage(SyncTable.profiles, const []);
      rig.transport.scriptPage(SyncTable.deletedProfiles, const []);
      await rig.sync();

      final deletedProfilesCalls = rig.transport.pulls
          .where((c) => c.table == SyncTable.deletedProfiles)
          .toList();
      expect(deletedProfilesCalls, hasLength(1));
      expect(deletedProfilesCalls.single.afterVersion, 70,
          reason: 'must resume from the persisted cursor, not re-scan '
              'from version 0 every cycle');
    });

    group('issue #521: cursor watermark clamp and lookback fallback', () {
      test('a watermark below a page\'s max version holds the cursor there '
          'instead of skipping past it; a later cycle with an advanced '
          'watermark completes the pull', () async {
        final rig = Rig();
        addTearDown(rig.dispose);
        await rig.bind(uidA);
        final pA = ulidN(1);
        final pB = ulidN(2);
        // One page carries both rows (nextval order, not commit order): a
        // naive `cursor = max(page)` would advance straight to 100 and
        // never look below it again.
        rig.transport.scriptPage(SyncTable.profiles, [
          remoteProfile(pA, updatedAt: t0, serverVersion: 55),
          remoteProfile(pB, updatedAt: t0, serverVersion: 100),
        ]);
        // A commit-safe watermark of 60 means: only server_version <= 60 is
        // guaranteed to have nothing still in flight below it.
        rig.transport.watermark = 60;

        await rig.start();

        expect((await rig.state()).cursorProfiles, 60,
            reason:
                'the cursor must not advance past the watermark even though '
                'the page\'s own maximum version was 100');
        // Both rows still apply this cycle — the clamp only bounds the
        // cursor, never what a delivered page applies.
        expect(await rig.storage.getProfile(pA), isNotNull);
        expect(await rig.storage.getProfile(pB), isNotNull);

        // A later cycle: the watermark has caught up, and the transport
        // (a real one would no longer return an already-delivered row
        // below the new `afterVersion`) serves nothing new — the persisted
        // cursor itself is what advances now that it is safe to.
        rig.transport.watermark = 150;
        rig.transport.scriptPage(SyncTable.profiles, const []);
        await rig.sync();
        expect((await rig.state()).cursorProfiles, 60,
            reason: 'nothing left below the new watermark to advance past — '
                'an empty page cannot itself move the cursor');
      });

      test('no watermark (the RPC is unavailable) falls back to a fixed '
          'lookback below the page\'s max version, floored at the previous '
          'cursor', () async {
        final rig = Rig();
        addTearDown(rig.dispose);
        await rig.bind(uidA);
        rig.transport.watermark = null; // simulates a server predating #521
        final pA = ulidN(1);
        rig.transport.scriptPage(
          SyncTable.profiles,
          [remoteProfile(pA, updatedAt: t0, serverVersion: 1000)],
        );

        await rig.start();

        expect((await rig.state()).cursorProfiles, 1000 - kCursorLookback,
            reason: 'falls back to maxVersion - kCursorLookback when the '
                'watermark RPC is unavailable');
      });

      test('the lookback fallback never regresses the cursor below where '
          'it already was', () async {
        final rig = Rig();
        addTearDown(rig.dispose);
        await rig.storage.writeSyncState(kDefaultSyncState.copyWith(
          boundUserId: const Value(uidA),
          deviceId: 'device-1',
          cursorProfiles: 40,
          lastFullPullAt: Value(t0),
        ));
        rig.transport.watermark = null;
        final pA = ulidN(1);
        // maxVersion(page, floor: 40) - kCursorLookback(50) would be
        // negative — must floor at the previous cursor (40), not go
        // backward.
        rig.transport.scriptPage(
          SyncTable.profiles,
          [remoteProfile(pA, updatedAt: t0, serverVersion: 55)],
        );

        await rig.start();

        expect((await rig.state()).cursorProfiles, 40,
            reason: 'the lookback clamp must never move the cursor '
                'backward past its previous value');
      });
    });
  });

  group('issue #598: sync_pull priming', () {
    test('an incremental cycle primes every sync_pull-covered table with '
        'its persisted starting cursor, before any pullPage call', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.storage.writeSyncState(kDefaultSyncState.copyWith(
        boundUserId: const Value(uidA),
        deviceId: 'device-1',
        lastFullPullAt: Value(t0),
        cursorProfiles: 5,
        cursorDayEntries: 7,
        cursorObservations: 9,
        cursorProfileModes: 11,
        cursorCycleOverrides: 13,
        cursorCareNotes: 15,
        cursorVisitPrepItems: 17,
        cursorProfileGuardians: 19,
        cursorDayEntryMergeEvents: 21,
        cursorProfileTagRegistry: 23,
      ));

      await rig.start();

      expect(rig.transport.primePullCycleCalls, hasLength(1));
      expect(rig.transport.primePullCycleCalls.single, {
        SyncTable.profiles: 5,
        SyncTable.profileGuardians: 19,
        SyncTable.dayEntries: 7,
        SyncTable.observations: 9,
        SyncTable.profileModes: 11,
        SyncTable.cycleOverrides: 13,
        SyncTable.careNotes: 15,
        SyncTable.visitPrepItems: 17,
        SyncTable.dayEntryMergeEvents: 21,
        SyncTable.profileTagRegistry: 23,
      }, reason: 'deletedProfiles is deliberately excluded — sync_pull does '
          'not cover it');
      expect(
        rig.transport.pulls.first.afterVersion,
        greaterThanOrEqualTo(0),
        reason: 'priming happens before the ordinary per-table pull loop '
            'below still runs unchanged',
      );
    });

    test('a full reconcile primes every sync_pull-covered table at cursor '
        'zero, regardless of any persisted cursor', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.storage.writeSyncState(kDefaultSyncState.copyWith(
        boundUserId: const Value(uidA),
        deviceId: 'device-1',
        // No lastFullPullAt: due for a full reconcile on bind.
        cursorProfiles: 500,
        cursorDayEntries: 500,
      ));

      await rig.start();

      // Binding with no lastFullPullAt runs an incremental pull (primed
      // from the persisted cursors above) AND, being due, a reconcile
      // (primed at all zeros) in the same cycle — the reconcile's own
      // prime is the LAST call, not necessarily the first.
      expect(rig.transport.primePullCycleCalls, hasLength(2));
      expect(rig.transport.primePullCycleCalls.last, {
        for (final table in const [
          SyncTable.profiles,
          SyncTable.profileGuardians,
          SyncTable.dayEntries,
          SyncTable.observations,
          SyncTable.profileModes,
          SyncTable.cycleOverrides,
          SyncTable.careNotes,
          SyncTable.visitPrepItems,
          SyncTable.dayEntryMergeEvents,
          SyncTable.profileTagRegistry,
        ])
          table: 0,
      }, reason: 'reconcile always pages from version 0, so priming must '
          'never reuse a persisted cursor');
    });

    test('the engine still pulls correctly when the transport never '
        'implements real priming (every existing fake/test predates issue '
        '#598) — primePullCycle is best-effort and never required', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final pA = ulidN(1);
      rig.transport.scriptPage(
        SyncTable.profiles,
        [remoteProfile(pA, updatedAt: t0, serverVersion: 1)],
      );

      await rig.start();

      expect(rig.transport.primePullCycleCalls, hasLength(1));
      expect((await rig.profile(pA)).id, pA,
          reason: 'FakeSyncTransport.primePullCycle only records the call '
              '— it never actually caches pullPage data — so this proves '
              'the ordinary per-table pull path is completely unaffected '
              'by priming being a no-op');
    });
  });
}
