/// Issue #140 review, LLA-084/LLA-094:
/// [DriftAccountExportSnapshotRepository] — a profile's entries,
/// observations, life-stage mode, and cycle overrides read together as one
/// atomic, point-in-time snapshot, so account export never straddles a
/// concurrent write.
library;

import 'dart:async';
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart' as mergelog;

import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart'
    show DayEntryMergeEventsCompanion, LunarLogDatabase, ProfileTagRegistryCompanion;
import 'package:lunarlog/data/db/tables.dart' as dbtables show FlowLevel;
import 'package:lunarlog/data/repositories/drift_account_export_snapshot_repository.dart';
import 'package:lunarlog/data/repositories/drift_cycle_overrides_repository.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profile_modes_repository.dart';
import 'package:lunarlog/data/repositories/drift_tag_registry_repository.dart';
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
  Stream<bool> watchHasAnyEntries(String profileId) =>
      _inner.watchHasAnyEntries(profileId);

  @override
  Stream<List<DayEntry>> watchForProfile(String profileId,
          {LocalDate? from, LocalDate? to}) =>
      _inner.watchForProfile(profileId, from: from, to: to);

  @override
  Future<void> delete(String profileId, LocalDate localDate) =>
      _inner.delete(profileId, localDate);

  // Issue #130: no merge-notice surface in this fake.
  @override
  Future<List<mergelog.DayEntryMergeEvent>> mergeEventsForDay(
          String profileId, LocalDate date) async =>
      const [];

  @override
  Future<void> dismissMergeEvent(String profileId, String eventId) async {}

  // Issue #130: no per-profile export surface in this fake.
  @override
  Future<List<mergelog.DayEntryMergeEvent>> mergeEventsForProfile(
          String profileId) async =>
      const [];
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
      tagRegistryRepository: DriftTagRegistryRepository(storage),
    );
    final profile = await storage.upsertProfile(displayName: 'A', isMinor: false);
    profileId = profile.id;
  });

  test(
      'returns entries, observations, profileMode, cycleOverrides, and '
      'customTags together for a fully-populated profile', () async {
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
    await storage.upsertProfileTagRegistryEntry(
      id: 'tag-1',
      profileId: profileId,
      code: 'cramps_severe',
      displayName: 'Severe Cramps',
      category: 'custom',
      intensityEnabled: true,
      sortOrder: 1,
      updatedAt: DateTime.utc(2026, 1, 1),
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
    expect(snapshot.customTags, hasLength(1));
    expect(snapshot.customTags.single.code, 'cramps_severe');
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
    expect(snapshot.mergeEvents, isEmpty);
    expect(snapshot.customTags, isEmpty);
  });

  test('customTags excludes deleted (tombstoned) tags', () async {
    final storage = db.storage;
    await storage.upsertProfileTagRegistryEntry(
      id: 'tag-active',
      profileId: profileId,
      code: 'tag_active',
      displayName: 'Active Tag',
      category: 'custom',
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    await db.into(db.profileTagRegistry).insert(
          ProfileTagRegistryCompanion.insert(
            id: 'tag-deleted',
            profileId: profileId,
            code: 'tag_deleted',
            displayName: 'Deleted Tag',
            category: 'custom',
            deletedAt: Value(DateTime.utc(2026, 1, 2)),
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
        );

    final snapshot = await snapshotRepo.forProfile(profileId);
    expect(snapshot.customTags, hasLength(1));
    expect(snapshot.customTags.single.id, 'tag-active');
  });

  test(
      "the snapshot carries the profile's window-live merge disclosures "
      '(Issue #130, export v11) — a dismissed one included (dismissal is a '
      'per-device display choice, not a deletion), an aged-out one '
      'excluded (the file never extends the retention window)', () async {
    final storage = db.storage;
    // Relative to the REAL clock: the repository-level read has no clock
    // injection, so the window filter compares against DateTime.now().
    final fresh = DateTime.now().toUtc().subtract(const Duration(days: 5));
    Future<void> seedMergeEvent(
      String id,
      String losingRowId,
      DateTime createdAt,
    ) =>
        (db.into(db.dayEntryMergeEvents).insert(
              DayEntryMergeEventsCompanion.insert(
                id: id,
                profileId: profileId,
                localDate: '2026-01-15',
                winningRowId: '01JREMOTE00000000000000000W',
                losingRowId: losingRowId,
                field: 'note',
                losingValueText: 'discarded text $id',
                createdAt: createdAt,
                updatedAt: createdAt,
              ),
            ));
    await seedMergeEvent('01JREMOTE0000000000000000FA',
        '01JREMOTE00000000000000000A', fresh);
    // Far outside the 30-day window.
    await seedMergeEvent(
        '01JREMOTE0000000000000000FB',
        '01JREMOTE00000000000000000B',
        DateTime.now().toUtc().subtract(const Duration(days: 60)));
    await storage.dismissDayEntryMergeEvent(
        profileId: profileId, eventId: '01JREMOTE0000000000000000FA');

    final snapshot = await snapshotRepo.forProfile(profileId);

    expect(snapshot.mergeEvents, hasLength(1));
    expect(snapshot.mergeEvents.single.losingValueText,
        'discarded text 01JREMOTE0000000000000000FA');
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
