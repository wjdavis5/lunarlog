/// Issue #551 part 2: the table-agnostic guard around the one remote-apply
/// skeleton ([LunarLogStorageRemoteApply._applyRemoteRow]).
///
/// Every synced table whose rows carry `dirty`/`local_rev` is driven
/// through its `applyRemote*` entry point in two shapes — a brand-new remote
/// row (the insert path) and a strictly-newer remote row over a locally
/// dirty row (the update path) — and the stored row is asserted clean:
/// `dirty == false` and (on the insert path) `local_rev == 0`. A table
/// whose remote apply forgot to clear `dirty` would be re-pushed on every
/// cycle forever (#102); this is the single test that fails if that
/// regresses anywhere, without naming a storage method per table.
///
/// `profile_guardians` and `day_entry_history` are deliberately absent:
/// both are pull-only and carry no `dirty`/`local_rev` column at all, so
/// they cannot exhibit the bug.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';

class FixedClock {
  FixedClock(this.now);

  DateTime now;

  DateTime call() => now;
}

/// One synced table's two apply scenarios. [readFresh]/[readOverwrite]
/// return the stored `(dirty, localRev)` pair. [applyOverwrite] must both
/// seed a dirty local row and apply a strictly-newer remote row over it.
class _ApplyCase {
  const _ApplyCase({
    required this.label,
    required this.applyFresh,
    required this.readFresh,
    this.applyOverwrite,
    this.readOverwrite,
  });

  final String label;
  final Future<void> Function() applyFresh;
  final Future<(bool, int)> Function() readFresh;
  final Future<void> Function()? applyOverwrite;
  final Future<(bool, int)> Function()? readOverwrite;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late FixedClock clock;
  late LunarLogStorage storage;

  final t0 = DateTime.utc(2026, 1, 1, 8);
  final t1 = DateTime.utc(2026, 1, 2, 8);
  final t2 = DateTime.utc(2026, 1, 3, 8);

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    clock = FixedClock(t0);
    storage = LunarLogStorage(db, clock: clock.call);
    await storage.upsertProfile(
        id: 'p1', displayName: 'Riley', isMinor: true, updatedAt: t0);
    // Observations reference a day entry; seed one so their parent guard
    // passes.
    await storage.upsertDayEntry(
      id: 'd-parent',
      profileId: 'p1',
      localDate: '2026-01-01',
      tz: 'UTC',
      flow: FlowLevel.medium,
    );
  });

  Future<Profile> readProfile(String id) async =>
      (await (db.select(db.profiles)..where((t) => t.id.equals(id)))
          .getSingle());

  Future<DayEntry> readDayEntry(String id) async =>
      (await (db.select(db.dayEntries)..where((t) => t.id.equals(id)))
          .getSingle());

  Future<Observation> readObservation(String id) async =>
      (await (db.select(db.observations)..where((t) => t.id.equals(id)))
          .getSingle());

  Future<ProfileModeData> readProfileMode(String profileId) async =>
      (await (db.select(db.profileModes)
            ..where((t) => t.profileId.equals(profileId)))
          .getSingle());

  Future<CycleOverrideData> readCycleOverride(String id) async =>
      (await (db.select(db.cycleOverrides)..where((t) => t.id.equals(id)))
          .getSingle());

  Future<CareNoteData> readCareNote(String id) async =>
      (await (db.select(db.careNotes)..where((t) => t.id.equals(id)))
          .getSingle());

  Future<VisitPrepItemData> readVisitPrepItem(String id) async =>
      (await (db.select(db.visitPrepItems)..where((t) => t.id.equals(id)))
          .getSingle());

  Future<GuardianNoteData> readGuardianNote(String id) async =>
      (await (db.select(db.guardianNotes)..where((t) => t.id.equals(id)))
          .getSingle());

  Future<DayEntryMergeEventData> readMergeEvent(String id) async =>
      (await (db.select(db.dayEntryMergeEvents)
            ..where((t) => t.id.equals(id)))
          .getSingle());

  Future<ProfileTagRegistryEntry> readTagRegistry(String id) async =>
      (await (db.select(db.profileTagRegistry)..where((t) => t.id.equals(id)))
          .getSingle());

  RemoteProfileRow remoteProfile(String id, DateTime updatedAt) =>
      RemoteProfileRow(
        id: id,
        displayName: 'Remote',
        isMinor: false,
        sortOrder: 0,
        archivedAt: null,
        createdAt: updatedAt,
        updatedAt: updatedAt,
        deletedAt: null,
      );

  final cases = <_ApplyCase>[
    _ApplyCase(
      label: 'profiles',
      applyFresh: () =>
          storage.applyRemoteProfile(remoteProfile('p-fresh', t1)),
      readFresh: () async {
        final row = await readProfile('p-fresh');
        return (row.dirty, row.localRev);
      },
      applyOverwrite: () async {
        await storage.upsertProfile(
            id: 'p-over', displayName: 'Over', isMinor: false);
        await storage.applyRemoteProfile(remoteProfile('p-over', t2));
      },
      readOverwrite: () async {
        final row = await readProfile('p-over');
        return (row.dirty, row.localRev);
      },
    ),
    _ApplyCase(
      label: 'day_entries',
      applyFresh: () => storage.applyRemoteDayEntry(RemoteDayEntryRow(
        id: 'e-fresh',
        profileId: 'p1',
        localDate: '2026-02-10',
        tz: 'UTC',
        flow: FlowLevel.medium,
        tags: const ['remote'],
        note: 'fresh',
        updatedAt: t1,
        deletedAt: null,
      )),
      readFresh: () async {
        final row = await readDayEntry('e-fresh');
        return (row.dirty, row.localRev);
      },
      applyOverwrite: () async {
        await storage.upsertDayEntry(
          id: 'e-over',
          profileId: 'p1',
          localDate: '2026-02-11',
          tz: 'UTC',
          flow: FlowLevel.light,
        );
        await storage.applyRemoteDayEntry(RemoteDayEntryRow(
          id: 'e-over',
          profileId: 'p1',
          localDate: '2026-02-11',
          tz: 'UTC',
          flow: FlowLevel.medium,
          tags: const ['remote'],
          note: 'remote',
          updatedAt: t2,
          deletedAt: null,
        ));
      },
      readOverwrite: () async {
        final row = await readDayEntry('e-over');
        return (row.dirty, row.localRev);
      },
    ),
    _ApplyCase(
      label: 'observations',
      applyFresh: () => storage.applyRemoteObservation(RemoteObservationRow(
        id: 'o-fresh',
        dayEntryId: 'd-parent',
        profileId: 'p1',
        localDate: '2026-01-01',
        tz: 'UTC',
        category: 'mood',
        updatedAt: t1,
        deletedAt: null,
      )),
      readFresh: () async {
        final row = await readObservation('o-fresh');
        return (row.dirty, row.localRev);
      },
      applyOverwrite: () async {
        await storage.upsertObservation(
          id: 'o-over',
          dayEntryId: 'd-parent',
          profileId: 'p1',
          localDate: '2026-01-01',
          tz: 'UTC',
          category: 'mood',
        );
        await storage.applyRemoteObservation(RemoteObservationRow(
          id: 'o-over',
          dayEntryId: 'd-parent',
          profileId: 'p1',
          localDate: '2026-01-01',
          tz: 'UTC',
          category: 'mood',
          updatedAt: t2,
          deletedAt: null,
        ));
      },
      readOverwrite: () async {
        final row = await readObservation('o-over');
        return (row.dirty, row.localRev);
      },
    ),
    _ApplyCase(
      label: 'profile_modes',
      applyFresh: () async {
        await storage.upsertProfile(
            id: 'p-mode', displayName: 'Mode', isMinor: false);
        await storage.applyRemoteProfileMode(RemoteProfileModeRow(
            profileId: 'p-mode', mode: 'pregnancy', updatedAt: t1));
      },
      readFresh: () async {
        final row = await readProfileMode('p-mode');
        return (row.dirty, row.localRev);
      },
      applyOverwrite: () async {
        await storage.upsertProfileMode(profileId: 'p-mode', mode: 'tracking');
        await storage.applyRemoteProfileMode(RemoteProfileModeRow(
            profileId: 'p-mode', mode: 'pregnancy', updatedAt: t2));
      },
      readOverwrite: () async {
        final row = await readProfileMode('p-mode');
        return (row.dirty, row.localRev);
      },
    ),
    _ApplyCase(
      label: 'cycle_overrides',
      applyFresh: () =>
          storage.applyRemoteCycleOverride(RemoteCycleOverrideRow(
        id: 'c-fresh',
        profileId: 'p1',
        cycleStartDate: '2026-01-05',
        updatedAt: t1,
        deletedAt: null,
      )),
      readFresh: () async {
        final row = await readCycleOverride('c-fresh');
        return (row.dirty, row.localRev);
      },
      applyOverwrite: () async {
        await storage.upsertCycleOverride(
            id: 'c-over', profileId: 'p1', cycleStartDate: '2026-01-06');
        await storage.applyRemoteCycleOverride(RemoteCycleOverrideRow(
          id: 'c-over',
          profileId: 'p1',
          cycleStartDate: '2026-01-06',
          updatedAt: t2,
          deletedAt: null,
        ));
      },
      readOverwrite: () async {
        final row = await readCycleOverride('c-over');
        return (row.dirty, row.localRev);
      },
    ),
    _ApplyCase(
      label: 'care_notes',
      applyFresh: () =>
          storage.applyRemoteCareNote(RemoteCareNoteRow(
        id: 'n-fresh',
        profileId: 'p1',
        body: 'fresh',
        updatedAt: t1,
        deletedAt: null,
      )),
      readFresh: () async {
        final row = await readCareNote('n-fresh');
        return (row.dirty, row.localRev);
      },
      applyOverwrite: () async {
        await storage.upsertCareNote(
            id: 'n-over', profileId: 'p1', body: 'local');
        await storage.applyRemoteCareNote(RemoteCareNoteRow(
          id: 'n-over',
          profileId: 'p1',
          body: 'remote',
          updatedAt: t2,
          deletedAt: null,
        ));
      },
      readOverwrite: () async {
        final row = await readCareNote('n-over');
        return (row.dirty, row.localRev);
      },
    ),
    _ApplyCase(
      label: 'visit_prep_items',
      applyFresh: () =>
          storage.applyRemoteVisitPrepItem(RemoteVisitPrepItemRow(
        id: 'v-fresh',
        profileId: 'p1',
        body: 'fresh',
        updatedAt: t1,
        deletedAt: null,
      )),
      readFresh: () async {
        final row = await readVisitPrepItem('v-fresh');
        return (row.dirty, row.localRev);
      },
      applyOverwrite: () async {
        await storage.addVisitPrepItem(
            id: 'v-over', profileId: 'p1', body: 'local');
        await storage.applyRemoteVisitPrepItem(RemoteVisitPrepItemRow(
          id: 'v-over',
          profileId: 'p1',
          body: 'remote',
          updatedAt: t2,
          deletedAt: null,
        ));
      },
      readOverwrite: () async {
        final row = await readVisitPrepItem('v-over');
        return (row.dirty, row.localRev);
      },
    ),
    _ApplyCase(
      label: 'guardian_notes',
      applyFresh: () =>
          storage.applyRemoteGuardianNote(RemoteGuardianNoteRow(
        id: 'g-fresh',
        profileId: 'p1',
        localDate: '2026-02-20',
        tz: 'UTC',
        body: 'fresh',
        updatedAt: t1,
        deletedAt: null,
      )),
      readFresh: () async {
        final row = await readGuardianNote('g-fresh');
        return (row.dirty, row.localRev);
      },
      applyOverwrite: () async {
        await storage.upsertGuardianNote(
          id: 'g-over',
          profileId: 'p1',
          localDate: '2026-02-21',
          tz: 'UTC',
          body: 'local',
        );
        await storage.applyRemoteGuardianNote(RemoteGuardianNoteRow(
          id: 'g-over',
          profileId: 'p1',
          localDate: '2026-02-21',
          tz: 'UTC',
          body: 'remote',
          updatedAt: t2,
          deletedAt: null,
        ));
      },
      readOverwrite: () async {
        final row = await readGuardianNote('g-over');
        return (row.dirty, row.localRev);
      },
    ),
    _ApplyCase(
      label: 'day_entry_merge_events',
      applyFresh: () =>
          storage.applyRemoteDayEntryMergeEvent(RemoteDayEntryMergeEventRow(
        id: 'm-fresh',
        profileId: 'p1',
        localDate: '2026-03-01',
        winningRowId: 'wr',
        losingRowId: 'lr-fresh',
        field: 'note',
        losingValueText: 'lost',
        createdAt: t1,
        updatedAt: t1,
      )),
      readFresh: () async {
        final row = await readMergeEvent('m-fresh');
        return (row.dirty, row.localRev);
      },
    ),
    _ApplyCase(
      label: 'profile_tag_registry',
      applyFresh: () =>
          storage.applyRemoteProfileTagRegistryEntry(RemoteProfileTagRegistryRow(
        id: 't-fresh',
        profileId: 'p1',
        code: 'symptom_fresh',
        displayName: 'Fresh',
        category: 'custom',
        createdAt: t1,
        updatedAt: t1,
        deletedAt: null,
      )),
      readFresh: () async {
        final row = await readTagRegistry('t-fresh');
        return (row.dirty, row.localRev);
      },
      applyOverwrite: () async {
        await storage.upsertProfileTagRegistryEntry(
          id: 't-over',
          profileId: 'p1',
          code: 'symptom_over',
          displayName: 'Over',
        );
        await storage.applyRemoteProfileTagRegistryEntry(
            RemoteProfileTagRegistryRow(
          id: 't-over',
          profileId: 'p1',
          code: 'symptom_over',
          displayName: 'Remote',
          category: 'custom',
          createdAt: t1,
          updatedAt: t2,
          deletedAt: null,
        ));
      },
      readOverwrite: () async {
        final row = await readTagRegistry('t-over');
        return (row.dirty, row.localRev);
      },
    ),
  ];

  test('every synced table is covered', () {
    // The list must stay exhaustive as tables land: each has a distinct
    // label and every `dirty`-bearing synced table is represented.
    expect(cases.map((c) => c.label).toSet(), hasLength(cases.length));
    expect(cases, hasLength(10));
  });

  for (final c in cases) {
    test('${c.label}: remote apply lands clean (dirty=false, localRev=0)',
        () async {
      await c.applyFresh();
      final fresh = await c.readFresh();
      expect(fresh.$1, isFalse,
          reason: '${c.label}: a remote-delivered row must never be dirty, '
              'or it is pushed back forever (#102)');
      expect(fresh.$2, 0,
          reason: '${c.label}: an inserted remote row starts at local_rev 0');

      if (c.applyOverwrite != null) {
        await c.applyOverwrite!();
        final over = await c.readOverwrite!();
        expect(over.$1, isFalse,
            reason: '${c.label}: a remote overwrite of a dirty local row '
                'must clear dirty (#102)');
      }
    });
  }
}
