/// Issue #140 review, LLA-084/LLA-094:
/// [DriftAccountExportSnapshotRepository] — a profile's entries,
/// observations, life-stage mode, and cycle overrides read together as one
/// atomic, point-in-time snapshot, so account export never straddles a
/// concurrent write.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/db/tables.dart' as dbtables show FlowLevel;
import 'package:lunarlog/data/repositories/drift_account_export_snapshot_repository.dart';
import 'package:lunarlog/data/repositories/drift_cycle_overrides_repository.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profile_modes_repository.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';

/// Wraps a real [DayEntriesRepository], yielding the event loop twice right
/// after its own read returns (Issue #140 review, LLA-094 regression
/// proof): gives a concurrently-launched, independently-scheduled write
/// every chance to actually reach the database and commit in the gap
/// between the entries read and whatever [AccountExportSnapshotRepository]
/// reads next -- without performing that write itself (a write nested
/// inside this call's own stack would run inside the SAME transaction
/// [AccountExportSnapshotRepository.forProfile] opened, which proves
/// nothing about a genuinely separate writer).
class _YieldingDayEntriesRepository implements DayEntriesRepository {
  _YieldingDayEntriesRepository(this._inner);

  final DayEntriesRepository _inner;

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async {
    final result = await _inner.listForProfile(profileId);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return result;
  }

  @override
  Future<DayEntry> save(DayEntry entry) => _inner.save(entry);

  @override
  Future<DayEntry> saveDayEntryWithObservations({
    required DayEntry entry,
    List<Observation> observationsToUpsert = const [],
    List<String> observationIdsToDelete = const [],
  }) =>
      _inner.saveDayEntryWithObservations(
        entry: entry,
        observationsToUpsert: observationsToUpsert,
        observationIdsToDelete: observationIdsToDelete,
      );

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) =>
      _inner.find(profileId, localDate);

  @override
  Future<bool> hasAnyEntries(String profileId) =>
      _inner.hasAnyEntries(profileId);

  @override
  Stream<List<DayEntry>> watchForProfile(String profileId,
          {LocalDate? from, LocalDate? to}) =>
      _inner.watchForProfile(profileId, from: from, to: to);

  @override
  Future<void> delete(String profileId, LocalDate localDate) =>
      _inner.delete(profileId, localDate);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late DriftAccountExportSnapshotRepository snapshotRepo;
  late String profileId;

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final storage = db.storage;
    snapshotRepo = DriftAccountExportSnapshotRepository(
      storage: storage,
      entriesRepository: DriftDayEntriesRepository(storage),
      observationsRepository: DriftObservationsRepository(storage),
      profileModesRepository: DriftProfileModesRepository(storage),
      cycleOverridesRepository: DriftCycleOverridesRepository(storage),
    );
    final profile = await storage.upsertProfile(displayName: 'A', isMinor: false);
    profileId = profile.id;
  });

  test(
      'returns entries, observations, profileMode, and cycleOverrides '
      'together for a fully-populated profile', () async {
    final storage = db.storage;
    final entry = await storage.upsertDayEntry(
      profileId: profileId,
      localDate: '2026-01-05',
      tz: 'UTC',
      flow: dbtables.FlowLevel.heavy,
    );
    await storage.upsertObservation(
      dayEntryId: entry.id,
      profileId: profileId,
      localDate: '2026-01-05',
      tz: 'UTC',
      category: 'pain',
      code: 'cramps',
    );
    await storage.upsertProfileMode(
      profileId: profileId,
      mode: 'conceive',
      birthControlMethod: 'pill',
    );
    await storage.upsertCycleOverride(
      profileId: profileId,
      cycleStartDate: '2026-01-05',
      excludedFromAverage: true,
    );

    final snapshot = await snapshotRepo.forProfile(profileId);

    expect(snapshot.entries, hasLength(1));
    expect(snapshot.entries.single.flow.toDb(), 'heavy');
    expect(snapshot.observations, hasLength(1));
    expect(snapshot.observations.single.category, 'pain');
    expect(snapshot.profileMode, isNotNull);
    expect(snapshot.profileMode!.mode, LifecycleMode.conceive);
    expect(snapshot.profileMode!.birthControlMethod, 'pill');
    expect(snapshot.cycleOverrides, hasLength(1));
    expect(snapshot.cycleOverrides.single.excludedFromAverage, isTrue);
  });

  test('profileMode is null when no profile_modes row was ever written',
      () async {
    final snapshot = await snapshotRepo.forProfile(profileId);
    expect(snapshot.profileMode, isNull);
  });

  test('every list is empty for a profile with no history at all', () async {
    final snapshot = await snapshotRepo.forProfile(profileId);
    expect(snapshot.entries, isEmpty);
    expect(snapshot.observations, isEmpty);
    expect(snapshot.cycleOverrides, isEmpty);
  });

  test(
      'a write independently launched right after the read starts never '
      'lands split between entries and observations (Issue #140 review, '
      'LLA-094) — either both the new day and its observation are in the '
      'snapshot, or neither is', () async {
    final storage = db.storage;
    // Seed one day already fully present before the race, so the profile
    // is never completely empty (a stronger check than the "everything
    // empty" case above).
    await storage.upsertDayEntry(
      profileId: profileId,
      localDate: '2026-01-01',
      tz: 'UTC',
      flow: dbtables.FlowLevel.light,
    );

    // The entries repository yields the event loop twice right after its
    // own read returns (see _YieldingDayEntriesRepository's own doc
    // comment) -- every chance for the independently-launched write below
    // to actually reach the database in the gap before the NEXT read
    // (observations) runs, exactly the window LLA-094 describes. Without
    // forProfile wrapping both reads in one transaction, that write lands
    // in this gap and the snapshot below would show the new observation
    // without its day entry.
    final raceProneSnapshotRepo = DriftAccountExportSnapshotRepository(
      storage: storage,
      entriesRepository:
          _YieldingDayEntriesRepository(DriftDayEntriesRepository(storage)),
      observationsRepository: DriftObservationsRepository(storage),
      profileModesRepository: DriftProfileModesRepository(storage),
      cycleOverridesRepository: DriftCycleOverridesRepository(storage),
    );

    final snapshotFuture = raceProneSnapshotRepo.forProfile(profileId);
    // Fired right after starting the read above, not awaited here --
    // independently scheduled, exactly like a background sync write would
    // be relative to an export read running at the same time.
    final writeFuture = storage
        .upsertDayEntry(
      profileId: profileId,
      localDate: '2026-01-06',
      tz: 'UTC',
      flow: dbtables.FlowLevel.medium,
    )
        .then((entry) => storage.upsertObservation(
              dayEntryId: entry.id,
              profileId: profileId,
              localDate: '2026-01-06',
              tz: 'UTC',
              category: 'pain',
              code: 'headache',
            ));

    final snapshot = await snapshotFuture;
    await writeFuture;

    final hasNewEntry =
        snapshot.entries.any((e) => e.localDate.iso == '2026-01-06');
    final hasNewObservation =
        snapshot.observations.any((o) => o.localDate.iso == '2026-01-06');
    expect(hasNewEntry, hasNewObservation,
        reason: 'the snapshot must never include the new observation '
            'without its day entry (an orphan parseAccountImport would '
            'reject outright), or vice versa');
  });
}
