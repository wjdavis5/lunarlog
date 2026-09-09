/// Issue #188: `LunarLogStorage`'s profile_modes and cycle_overrides API —
/// lazy per-profile mode rows (no tombstone), id-keyed manual cycle
/// corrections with #224-style payload-free tombstones, dirty/local_rev
/// bookkeeping, `readDirty*` keyset paging, `markPushed`, and the
/// `applyRemote*` per-id LWW rule plus the referential-integrity guard.
/// Mirrors `storage_observations_test.dart`'s shape.
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
        id: 'p1', displayName: 'Riley', isMinor: true, updatedAt: t0);
  });

  RemoteProfileModeRow remoteMode(
    String profileId, {
    String mode = 'perimenopause',
    String? modeStartedOn = '2026-09-01',
    String? birthControlMethod = 'pill',
    bool healthSyncConsent = false,
    required DateTime updatedAt,
    int serverVersion = 0,
  }) =>
      RemoteProfileModeRow(
        profileId: profileId,
        mode: mode,
        modeStartedOn: modeStartedOn,
        birthControlMethod: birthControlMethod,
        birthControlStartedOn: '2026-01-01',
        birthControlStoppedOn: null,
        healthSyncConsent: healthSyncConsent,
        updatedAt: updatedAt,
        serverVersion: serverVersion,
      );

  RemoteCycleOverrideRow remoteOverride(
    String id, {
    String profileId = 'p1',
    String cycleStartDate = '2026-08-14',
    bool excludedFromAverage = true,
    bool manualStart = true,
    String? noteId = 'note-1',
    required DateTime updatedAt,
    DateTime? deletedAt,
    int serverVersion = 0,
  }) =>
      RemoteCycleOverrideRow(
        id: id,
        profileId: profileId,
        cycleStartDate: cycleStartDate,
        excludedFromAverage: excludedFromAverage,
        manualStart: manualStart,
        noteId: noteId,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        serverVersion: serverVersion,
      );

  group('profile_modes (Issue #188)', () {
    test('the row is created lazily on first write and keyed by profile id',
        () async {
      expect(await storage.getProfileMode('p1'), isNull,
          reason: 'an absent row means tracking — nothing is pre-created');
      final row = await storage.upsertProfileMode(
          profileId: 'p1',
          mode: 'conceive',
          modeStartedOn: '2026-09-02',
          birthControlMethod: 'pill',
          birthControlStartedOn: '2026-09-01',
          healthSyncConsent: true);
      expect(row.profileId, 'p1');
      expect(row.mode, 'conceive');
      expect(row.modeStartedOn, '2026-09-02');
      expect(row.birthControlMethod, 'pill');
      expect(row.healthSyncConsent, true);
      expect(row.dirty, isTrue);
      expect(row.localRev, 1);
      expect(row.updatedAt, t0);

      // One row per profile: the second write updates in place.
      final again = await storage.upsertProfileMode(
          profileId: 'p1', mode: 'pregnancy', updatedAt: t0);
      expect(again.mode, 'pregnancy');
      expect(again.localRev, 2,
          reason: 'the same row is revised, not duplicated');
      expect(await db.select(db.profileModes).get(), hasLength(1));
    });

    test('an update stamps updated_at strictly after the stored value',
        () async {
      await storage.upsertProfileMode(
          profileId: 'p1', mode: 'tracking', updatedAt: t0);
      // The clock did not move: stored + 1ms.
      final bumped =
          await storage.upsertProfileMode(profileId: 'p1', mode: 'conceive');
      expect(bumped.updatedAt, t0.add(const Duration(milliseconds: 1)));
      // A later clock wins outright.
      clock.now = t0.add(const Duration(hours: 2));
      final later = await storage.upsertProfileMode(
          profileId: 'p1', mode: 'pregnancy');
      expect(later.updatedAt, clock.now);
    });

    test('payload validation mirrors the server CHECKs', () async {
      await expectLater(
        storage.upsertProfileMode(
            profileId: 'p1', mode: 'tracking', modeStartedOn: '09/02/2026'),
        throwsArgumentError,
      );
      await expectLater(
        storage.upsertProfileMode(
            profileId: 'p1',
            mode: 'tracking',
            birthControlMethod: List.filled(65, 'x').join()),
        throwsArgumentError,
      );
    });

    test('a mode switch never touches day entries or observations (A2-32)',
        () async {
      await storage.upsertDayEntry(
          profileId: 'p1',
          localDate: '2026-09-01',
          tz: 'UTC',
          flow: FlowLevel.medium,
          updatedAt: t0);
      final entryBefore =
          (await storage.getDayEntries(profileId: 'p1')).single;
      await storage.upsertProfileMode(
          profileId: 'p1', mode: 'conceive', modeStartedOn: '2026-09-02');
      final entryAfter = (await storage.getDayEntries(profileId: 'p1')).single;
      expect(entryAfter.id, entryBefore.id);
      expect(entryAfter.updatedAt, entryBefore.updatedAt);
      expect(await db.select(db.observations).get(), isEmpty);
    });

    test('readDirtyProfileModes pages by profile id and markPushed gates on '
        'local_rev', () async {
      await storage.upsertProfile(id: 'p2', displayName: 'A', isMinor: false);
      await storage.upsertProfile(id: 'p3', displayName: 'B', isMinor: false);
      await storage.upsertProfileMode(profileId: 'p3', mode: 'tracking');
      await storage.upsertProfileMode(profileId: 'p1', mode: 'conceive');

      final page1 = await storage.readDirtyProfileModes(limit: 1);
      expect(page1.map((m) => m.profileId), ['p1']);
      final page2 =
          await storage.readDirtyProfileModes(limit: 1, afterId: 'p1');
      expect(page2.map((m) => m.profileId), ['p3']);

      expect(await storage.markPushed(
          table: SyncTable.profileModes, id: 'p1', localRevAtPush: 99),
      isFalse,
          reason: 'a stale local_rev never clears dirty');
      expect(await storage.markPushed(
          table: SyncTable.profileModes, id: 'p1', localRevAtPush: 1),
      isTrue);
      expect((await storage.getProfileMode('p1'))!.dirty, isFalse);
      expect(await storage.readDirtyProfileModes(), hasLength(1));
    });

    test('dirtyCount/markAllDirty/isEmpty account for the table', () async {
      // The setUp-seeded profile is itself dirty, so the floor is 1.
      expect(await storage.dirtyCount(), 1);
      await storage.upsertProfileMode(profileId: 'p1', mode: 'conceive');
      expect(await storage.dirtyCount(), 2);
      expect(await storage.isEmpty(), isFalse,
          reason: 'a mode row is a push waiting to happen');
      await storage.markAllDirty();
      expect(await storage.readDirtyProfileModes(), hasLength(1));
    });

    test('applyRemoteProfileMode: LWW per profile id, remote wins ties',
        () async {
      await storage.upsertProfileMode(
          profileId: 'p1',
          mode: 'tracking',
          healthSyncConsent: false,
          updatedAt: t0);
      // Older remote: declined.
      expect(
          await storage.applyRemoteProfileMode(remoteMode('p1',
              mode: 'conceive',
              updatedAt: t0.subtract(const Duration(minutes: 1)))),
      isFalse);
      expect((await storage.getProfileMode('p1'))!.mode, 'tracking');
      // Newer remote: applied, not dirty, local_rev kept.
      final newer = t0.add(const Duration(minutes: 5));
      expect(
          await storage.applyRemoteProfileMode(
              remoteMode('p1', mode: 'pregnancy', updatedAt: newer)),
      isTrue);
      final applied = await storage.getProfileMode('p1');
      expect(applied!.mode, 'pregnancy');
      expect(applied.dirty, isFalse);
      expect(applied.localRev, 1,
          reason: 'a remote apply never touches local_rev');
      // Tie: the remote copy wins.
      final tie = remoteMode('p1', mode: 'postpartum', updatedAt: newer);
      expect(await storage.applyRemoteProfileMode(tie), isTrue);
      expect((await storage.getProfileMode('p1'))!.mode, 'postpartum');
    });

    test('applyRemoteProfileMode inserts (dirty=false, local_rev=0) when no '
        'row is held', () async {
      expect(
          await storage.applyRemoteProfileMode(
              remoteMode('p1', mode: 'tracking', updatedAt: t0)),
      isTrue);
      final row = await storage.getProfileMode('p1');
      expect(row!.mode, 'tracking');
      expect(row.dirty, isFalse);
      expect(row.localRev, 0);
    });

    test('applyRemoteProfileMode throws RetryableSyncApplyError for a '
        'profile not held locally, and applyResolved never inserts',
        () async {
      await expectLater(
        storage.applyRemoteProfileMode(remoteMode('nope', updatedAt: t0)),
        throwsA(isA<RetryableSyncApplyError>()),
      );
      // onlyExisting (a push resolution) is a no-op for an unheld row.
      await storage.applyResolved(
          [remoteMode('nope', mode: 'conceive', updatedAt: t0)]);
      expect(await storage.getProfileMode('nope'), isNull);
    });
  });

  group('cycle_overrides (Issue #188)', () {
    test('upsert creates and updates by id, dirty and local_rev stamped',
        () async {
      final row = await storage.upsertCycleOverride(
          id: 'ov1',
          profileId: 'p1',
          cycleStartDate: '2026-08-14',
          excludedFromAverage: true,
          manualStart: false,
          noteId: 'note-1');
      expect(row.dirty, isTrue);
      expect(row.localRev, 1);
      expect(row.deletedAt, isNull);

      final edited = await storage.upsertCycleOverride(
          id: 'ov1',
          profileId: 'p1',
          cycleStartDate: '2026-08-15',
          excludedFromAverage: false,
          manualStart: true);
      expect(edited.cycleStartDate, '2026-08-15');
      expect(edited.manualStart, isTrue);
      expect(edited.localRev, 2);
      expect(
          await db
              .select(db.cycleOverrides)
              .get()
              .then((rows) => rows.length),
      1,
          reason: 'the same id revises its row');
    });

    test('payload validation mirrors the server CHECKs', () async {
      await expectLater(
        storage.upsertCycleOverride(
            profileId: 'p1', cycleStartDate: '2026-8-14'),
        throwsArgumentError,
      );
      await expectLater(
        storage.upsertCycleOverride(
            profileId: 'p1',
            cycleStartDate: '2026-08-14',
            noteId: List.filled(65, 'x').join()),
        throwsArgumentError,
      );
    });

    test('softDelete tombstones payload-free and idempotently, keeping '
        'cycle_start_date (issue #224)', () async {
      await storage.upsertCycleOverride(
          id: 'ov1',
          profileId: 'p1',
          cycleStartDate: '2026-08-14',
          excludedFromAverage: true,
          manualStart: true,
          noteId: 'note-1');
      await storage.softDeleteCycleOverride(id: 'ov1', profileId: 'p1');

      final tombstoned = (await storage
              .getCycleOverridesForProfile('p1', includeTombstones: true))
          .single;
      expect(tombstoned.deletedAt, isNotNull);
      expect(tombstoned.excludedFromAverage, isFalse);
      expect(tombstoned.manualStart, isFalse);
      expect(tombstoned.noteId, isNull);
      expect(tombstoned.cycleStartDate, '2026-08-14',
          reason: 'identity, not payload');
      expect(tombstoned.dirty, isTrue);

      // Idempotent: re-deleting does not bump anything.
      final at = tombstoned.updatedAt;
      await storage.softDeleteCycleOverride(id: 'ov1', profileId: 'p1');
      final again = (await storage
              .getCycleOverridesForProfile('p1', includeTombstones: true))
          .single;
      expect(again.updatedAt, at);
      expect(again.localRev, tombstoned.localRev);

      // UI reads filter tombstones.
      expect(await storage.getCycleOverridesForProfile('p1'), isEmpty);
    });

    test('reads are per-profile and ordered by cycle_start_date', () async {
      await storage.upsertProfile(id: 'p2', displayName: 'A', isMinor: false);
      await storage.upsertCycleOverride(
          profileId: 'p1', cycleStartDate: '2026-09-01');
      await storage.upsertCycleOverride(
          profileId: 'p1', cycleStartDate: '2026-08-01');
      await storage.upsertCycleOverride(
          profileId: 'p2', cycleStartDate: '2026-07-01');
      final rows = await storage.getCycleOverridesForProfile('p1');
      expect(rows.map((r) => r.cycleStartDate), ['2026-08-01', '2026-09-01']);
    });

    test('readDirtyCycleOverrides pages and markPushed clears by id',
        () async {
      await storage.upsertCycleOverride(id: 'a', profileId: 'p1',
          cycleStartDate: '2026-08-01');
      await storage.upsertCycleOverride(id: 'b', profileId: 'p1',
          cycleStartDate: '2026-08-02');
      final page = await storage.readDirtyCycleOverrides(limit: 1);
      expect(page.map((r) => r.id), ['a']);
      final rest = await storage.readDirtyCycleOverrides(
          limit: 10, afterId: 'a');
      expect(rest.map((r) => r.id), ['b']);

      expect(
          await storage.markPushed(
              table: SyncTable.cycleOverrides, id: 'b', localRevAtPush: 1),
      isTrue);
      expect(await storage.readDirtyCycleOverrides(), hasLength(1));
      // The seeded profile is dirty too, so the count is profile + override.
      expect(await storage.dirtyCount(), 2);
    });

    test('applyRemoteCycleOverride: LWW, tombstone clears payload, '
        'retryable profile guard, applyResolved never inserts', () async {
      final local = await storage.upsertCycleOverride(
          id: 'ov1',
          profileId: 'p1',
          cycleStartDate: '2026-08-14',
          excludedFromAverage: false,
          manualStart: false,
          noteId: null);

      // Older remote declined.
      expect(
          await storage.applyRemoteCycleOverride(remoteOverride('ov1',
              excludedFromAverage: true,
              updatedAt: local.updatedAt.subtract(
                  const Duration(minutes: 1)))),
      isFalse);

      // Newer live remote applied.
      final newer = local.updatedAt.add(const Duration(minutes: 5));
      expect(
          await storage.applyRemoteCycleOverride(
              remoteOverride('ov1', updatedAt: newer)),
      isTrue);
      var row = (await storage
              .getCycleOverridesForProfile('p1', includeTombstones: true))
          .single;
      expect(row.excludedFromAverage, isTrue);
      expect(row.noteId, 'note-1');
      expect(row.dirty, isFalse);

      // A newer tombstone clears the payload.
      expect(
          await storage.applyRemoteCycleOverride(
              remoteOverride('ov1', updatedAt: newer.add(
                  const Duration(minutes: 1)), deletedAt: newer)),
      isTrue);
      row = (await storage
              .getCycleOverridesForProfile('p1', includeTombstones: true))
          .single;
      expect(row.deletedAt, isNotNull);
      expect(row.excludedFromAverage, isFalse);
      expect(row.manualStart, isFalse);
      expect(row.noteId, isNull);
      expect(row.cycleStartDate, '2026-08-14');

      // Referential guard + resolution no-insert.
      await expectLater(
        storage.applyRemoteCycleOverride(
            remoteOverride('ovX', profileId: 'nope', updatedAt: newer)),
        throwsA(isA<RetryableSyncApplyError>()),
      );
      await storage.applyResolved(
          [remoteOverride('ov-new', updatedAt: newer)]);
      expect(
          await storage.getCycleOverridesForProfile('p1',
              includeTombstones: true),
          hasLength(1),
          reason: 'a resolution never inserts a row');
    });

    test('a brand-new remote override inserts dirty=false, local_rev=0',
        () async {
      expect(
          await storage.applyRemoteCycleOverride(
              remoteOverride('ov2', updatedAt: t0, serverVersion: 42)),
      isTrue);
      final row = (await storage
              .getCycleOverridesForProfile('p1', includeTombstones: true))
          .single;
      expect(row.id, 'ov2');
      expect(row.dirty, isFalse);
      expect(row.localRev, 0);
    });

    test('markAllDirty and isEmpty account for overrides', () async {
      await storage.upsertCycleOverride(profileId: 'p1',
          cycleStartDate: '2026-08-01');
      expect(await storage.isEmpty(), isFalse);
      await storage.markAllDirty();
      expect(await storage.readDirtyCycleOverrides(), hasLength(1));
    });
  });

  test('kMaxBirthControlMethodLength/kMaxCycleOverrideNoteIdLength mirror '
      'the server bounds (Issue #188)', () {
    expect(kMaxBirthControlMethodLength, 64);
    expect(kMaxCycleOverrideNoteIdLength, 64);
  });
}
