part of 'storage.dart';

// The sync cursor + dirty-scan stores, extracted out of `LunarLogStorage`
// into their own class (issue #551 problem 1, part 1 step 2). This is the
// template extraction: the smallest role pair comes out first, so the
// remaining role extractions can follow the same recipe.
//
// `SyncCursorStorage` implements `SyncMetadataStore` (the combined
// `SyncCursorStore` + `SyncDirtyStore` role) over the same drift database
// `LunarLogStorage` uses, and shares the one `StorageClock` instance so the
// learned server offset stamped onto local writes and the offset read by
// `sweepTombstones` can never diverge. `LunarLogStorage` keeps implementing
// the role by delegating every member to its own `SyncCursorStorage` (the
// `LunarLogStorageSyncMetadata` mixin below), so every existing consumer
// and test compiles and behaves exactly as before.

/// The one storage clock, shared by [LunarLogStorage]'s local writes and by
/// the extracted [SyncCursorStorage] (issue #551 part 1 step 2): the
/// injected clock plus the learned `clockOffset` (`server_now - device_now`,
/// KTD4). It lives in one object because both sides stamp or reason about
/// time — local writes via [_now], the tombstone sweep via its default
/// cutoff — and a second copy of the offset would let them drift.
class StorageClock {
  StorageClock({DateTime Function()? clock})
      : _clock = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _clock;
  Duration _offset = Duration.zero;

  /// `server_now - device_now`, added to the clock when stamping local
  /// writes (KTD4). Zero until the sync engine learns it.
  Duration get offset => _offset;

  /// Sets the learned offset. In-memory only; the engine persists the value
  /// in `sync_state.server_clock_offset_ms` and restores it on open.
  void setOffset(Duration offset) {
    _offset = offset;
  }

  /// The instant a local write is stamped with: injected clock + offset.
  DateTime now() => _clock().toUtc().add(_offset);
}

/// Counts rows in [table] matching [column], optionally filtered by [where]
/// — the shared helper behind [SyncCursorStorage.dirtyCount],
/// [SyncCursorStorage.isEmpty] and `LunarLogStorageQueries.countAllRows`.
Future<int> _countRows<T extends Table, D>(
  LunarLogDatabase db,
  TableInfo<T, D> table,
  Expression<Object> column, [
  Expression<bool>? where,
]) async {
  final count = column.count();
  final query = db.selectOnly(table)..addColumns([count]);
  if (where != null) query.where(where);
  return (await query.getSingle()).read(count) ?? 0;
}

/// The two synced-table counts the upload-consent screen shows, shared by
/// `LunarLogStorageQueries.countAllRows` and [SyncCursorStorage.isEmpty].
Future<LocalRowCounts> _countAllRowCounts(LunarLogDatabase db) async {
  final [p, d] = await Future.wait([
    _countRows(db, db.profiles, db.profiles.id),
    _countRows(db, db.dayEntries, db.dayEntries.id),
  ]);
  return (profiles: p, dayEntries: d);
}

/// The `sync_state` cursor singleton and the dirty-row scans, extracted
/// verbatim from `LunarLogStorage` (issue #551 part 1 step 2). Constructed
/// with the same drift database and the same [StorageClock] the storage
/// uses; every member is a pure move.
class SyncCursorStorage implements SyncMetadataStore {
  SyncCursorStorage(this.db, this._clock);

  final LunarLogDatabase db;
  final StorageClock _clock;

  /// The learned clock offset (see [StorageClock]).
  Duration get clockOffset => _clock.offset;

  // ------------------------------------------------------- sync: dirty rows

  /// Profiles with unpushed local changes, tombstones included, ordered by
  /// id (ULIDs, so this is also insertion order). [afterId] resumes a
  /// keyset scan after that id (exclusive); [limit] bounds the page so a
  /// caller can stream a large dirty set batch by batch instead of
  /// materialising it all at once.
  @override
  Future<List<Profile>> readDirtyProfiles({int? limit, String? afterId}) {
    final query = db.select(db.profiles)
      ..where((t) =>
          t.dirty.equals(true) &
          (afterId == null
              ? const Constant(true)
              : t.id.isBiggerThanValue(afterId)))
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  /// Day entries with unpushed local changes, tombstones included, ordered
  /// by id. Same keyset-paging contract as [readDirtyProfiles].
  ///
  /// The dirty predicate is `t.dirty.equalsExp(const Constant(true))`
  /// (review follow-up, issue #197), not the more usual `t.dirty.equals` —
  /// `equals` binds its argument as a `?` placeholder, and sqlite cannot
  /// prove a bound parameter satisfies `ix_day_entries_dirty`'s partial
  /// index condition (`WHERE dirty = 1`) at plan time, so that predicate
  /// fell back to a full table scan despite the index existing. `Constant`
  /// writes the value as a SQL literal (`dirty = 1`) instead, which the
  /// partial index does match — see the `EXPLAIN QUERY PLAN` coverage in
  /// `test/data/storage_sync_test.dart`.
  @override
  Future<List<DayEntry>> readDirtyDayEntries({int? limit, String? afterId}) {
    final query = db.select(db.dayEntries)
      ..where((t) =>
          t.dirty.equalsExp(const Constant(true)) &
          (afterId == null
              ? const Constant(true)
              : t.id.isBiggerThanValue(afterId)))
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  /// Observations with unpushed local changes, tombstones included, ordered
  /// by id (Issue #240). Same keyset-paging contract as [readDirtyProfiles].
  @override
  Future<List<Observation>> readDirtyObservations({int? limit, String? afterId}) {
    final query = db.select(db.observations)
      ..where((t) =>
          t.dirty.equals(true) &
          (afterId == null
              ? const Constant(true)
              : t.id.isBiggerThanValue(afterId)))
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  /// Profile mode rows with unpushed local changes, ordered by profile id
  /// (Issue #188; there is no tombstone on this table). Same keyset-paging
  /// contract as [readDirtyProfiles].
  @override
  Future<List<ProfileModeData>> readDirtyProfileModes(
      {int? limit, String? afterId}) {
    final query = db.select(db.profileModes)
      ..where((t) =>
          t.dirty.equals(true) &
          (afterId == null
              ? const Constant(true)
              : t.profileId.isBiggerThanValue(afterId)))
      ..orderBy([(t) => OrderingTerm(expression: t.profileId)]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  /// Cycle overrides with unpushed local changes, tombstones included,
  /// ordered by id (Issue #188). Same keyset-paging contract as
  /// [readDirtyProfiles].
  @override
  Future<List<CycleOverrideData>> readDirtyCycleOverrides(
      {int? limit, String? afterId}) {
    final query = db.select(db.cycleOverrides)
      ..where((t) =>
          t.dirty.equals(true) &
          (afterId == null
              ? const Constant(true)
              : t.id.isBiggerThanValue(afterId)))
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  /// Care notes with unpushed local changes, tombstones included, ordered
  /// by id (Issue #128). Same keyset-paging contract as [readDirtyProfiles].
  @override
  Future<List<CareNoteData>> readDirtyCareNotes(
      {int? limit, String? afterId}) {
    final query = db.select(db.careNotes)
      ..where((t) =>
          t.dirty.equals(true) &
          (afterId == null
              ? const Constant(true)
              : t.id.isBiggerThanValue(afterId)))
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  /// Visit-prep items with unpushed local changes, tombstones included,
  /// ordered by id (Issue #128). Same keyset-paging contract as
  /// [readDirtyProfiles].
  @override
  Future<List<VisitPrepItemData>> readDirtyVisitPrepItems(
      {int? limit, String? afterId}) {
    final query = db.select(db.visitPrepItems)
      ..where((t) =>
          t.dirty.equals(true) &
          (afterId == null
              ? const Constant(true)
              : t.id.isBiggerThanValue(afterId)))
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  /// Guardian notes with unpushed local changes, tombstones included,
  /// ordered by id (Issue #801). Same keyset-paging contract as
  /// [readDirtyProfiles].
  @override
  Future<List<GuardianNoteData>> readDirtyGuardianNotes(
      {int? limit, String? afterId}) {
    final query = db.select(db.guardianNotes)
      ..where((t) =>
          t.dirty.equals(true) &
          (afterId == null
              ? const Constant(true)
              : t.id.isBiggerThanValue(afterId)))
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  /// Merge events with unpushed local changes, ordered by id (Issue #130;
  /// no tombstone on this table). Same keyset-paging contract as
  /// [readDirtyProfiles].
  @override
  Future<List<DayEntryMergeEventData>> readDirtyDayEntryMergeEvents(
      {int? limit, String? afterId}) {
    final query = db.select(db.dayEntryMergeEvents)
      ..where((t) =>
          t.dirty.equals(true) &
          (afterId == null
              ? const Constant(true)
              : t.id.isBiggerThanValue(afterId)))
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  /// Registry entries with unpushed local changes, ordered by id (Issue
  /// #257). Same keyset-paging contract as [readDirtyProfiles].
  @override
  Future<List<ProfileTagRegistryEntry>> readDirtyProfileTagRegistry(
      {int? limit, String? afterId}) {
    final query = db.select(db.profileTagRegistry)
      ..where((t) =>
          t.dirty.equals(true) &
          (afterId == null
              ? const Constant(true)
              : t.id.isBiggerThanValue(afterId)))
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  /// Number of rows, live and tombstoned, in every synced table that still
  /// need pushing.
  @override
  Future<int> dirtyCount() async {
    final p = await _countRows(db, db.profiles, db.profiles.id,
        db.profiles.dirty.equals(true));
    final d = await _countRows(db, db.dayEntries, db.dayEntries.id,
        db.dayEntries.dirty.equals(true));
    final o = await _countRows(db, db.observations, db.observations.id,
        db.observations.dirty.equals(true));
    final pm = await _countRows(db, db.profileModes, db.profileModes.profileId,
        db.profileModes.dirty.equals(true));
    final co = await _countRows(db, db.cycleOverrides, db.cycleOverrides.id,
        db.cycleOverrides.dirty.equals(true));
    final cn = await _countRows(
        db, db.careNotes, db.careNotes.id, db.careNotes.dirty.equals(true));
    final vp = await _countRows(db, db.visitPrepItems, db.visitPrepItems.id,
        db.visitPrepItems.dirty.equals(true));
    final me = await _countRows(db, db.dayEntryMergeEvents, db.dayEntryMergeEvents.id,
        db.dayEntryMergeEvents.dirty.equals(true));
    final tr = await _countRows(db, db.profileTagRegistry, db.profileTagRegistry.id,
        db.profileTagRegistry.dirty.equals(true));
    final gn = await _countRows(
        db, db.guardianNotes, db.guardianNotes.id, db.guardianNotes.dirty.equals(true));
    return p + d + o + pm + co + cn + vp + me + tr + gn;
  }

  /// True only when every synced table holds no row of any kind — a
  /// tombstone-only database is not empty (it has deletions to push).
  @override
  Future<bool> isEmpty() async {
    final counts = await _countAllRowCounts(db);
    if (counts.profiles != 0 || counts.dayEntries != 0) return false;
    if (await _countRows(db, db.observations, db.observations.id) != 0) {
      return false;
    }
    if (await _countRows(db, db.profileModes, db.profileModes.profileId) != 0) {
      return false;
    }
    if (await _countRows(db, db.cycleOverrides, db.cycleOverrides.id) != 0) {
      return false;
    }
    if (await _countRows(db, db.careNotes, db.careNotes.id) != 0) return false;
    if (await _countRows(db, db.visitPrepItems, db.visitPrepItems.id) != 0) {
      return false;
    }
    return await _countRows(db, db.guardianNotes, db.guardianNotes.id) == 0;
  }

  /// Flags every row, live and tombstoned, in every synced table for push
  /// (first sign-in upload, R14). Bumps `local_rev` like any local write.
  @override
  Future<void> markAllDirty() async {
    await db.transaction(() async {
      await db.update(db.profiles).write(ProfilesCompanion.custom(
            dirty: const Constant(true),
            localRev: db.profiles.localRev + const Constant(1),
          ));
      await db.update(db.dayEntries).write(DayEntriesCompanion.custom(
            dirty: const Constant(true),
            localRev: db.dayEntries.localRev + const Constant(1),
          ));
      await db.update(db.observations).write(ObservationsCompanion.custom(
            dirty: const Constant(true),
            localRev: db.observations.localRev + const Constant(1),
          ));
      await db.update(db.profileModes).write(ProfileModesCompanion.custom(
            dirty: const Constant(true),
            localRev: db.profileModes.localRev + const Constant(1),
          ));
      await db.update(db.cycleOverrides).write(CycleOverridesCompanion.custom(
            dirty: const Constant(true),
            localRev: db.cycleOverrides.localRev + const Constant(1),
          ));
      await db.update(db.careNotes).write(CareNotesCompanion.custom(
            dirty: const Constant(true),
            localRev: db.careNotes.localRev + const Constant(1),
          ));
      await db.update(db.visitPrepItems).write(VisitPrepItemsCompanion.custom(
            dirty: const Constant(true),
            localRev: db.visitPrepItems.localRev + const Constant(1),
          ));
      await db.update(db.dayEntryMergeEvents)
          .write(DayEntryMergeEventsCompanion.custom(
            dirty: const Constant(true),
            localRev: db.dayEntryMergeEvents.localRev + const Constant(1),
          ));
      await db.update(db.profileTagRegistry)
          .write(ProfileTagRegistryCompanion.custom(
            dirty: const Constant(true),
            localRev: db.profileTagRegistry.localRev + const Constant(1),
          ));
      await db.update(db.guardianNotes)
          .write(GuardianNotesCompanion.custom(
            dirty: const Constant(true),
            localRev: db.guardianNotes.localRev + const Constant(1),
          ));
    });
  }

  /// Issue #641 LLA-042: a dirty row whose `updated_at` is in the future (a
  /// client clock far ahead) is rejected by the server (`updated_at > now() +
  /// 5 minutes`), and because [_afterStored] refuses to move a timestamp
  /// backward, it stays permanently unsyncable until wall-clock time catches
  /// up — even after the client learns its clock is fast and corrects it
  /// (editing the row still picks the stored future time + 1ms). Rebase every
  /// dirty row whose `updated_at` exceeds [serverNow] + 5 minutes (the
  /// server's own rejection ceiling) to [serverNow] and bump `local_rev`, so
  /// the row becomes pushable again (the bump also clears any in-memory
  /// rejection keyed on the old rev) and, once accepted, wins LWW against
  /// anything genuinely older. Returns how many rows were rebased. Idempotent
  /// and cheap when nothing is future-stamped — the predicate matches only
  /// rows the server would reject.
  @override
  Future<int> rebaseFutureStampedRows({required DateTime serverNow}) async {
    final threshold = serverNow.toUtc().add(const Duration(minutes: 5));
    var rebased = 0;
    await db.transaction(() async {
      rebased += await (db.update(db.profiles)
            ..where((t) =>
                t.dirty.equals(true) &
                t.updatedAt.isBiggerThanValue(threshold)))
          .write(ProfilesCompanion.custom(
            updatedAt: Constant(serverNow.toUtc()),
            localRev: db.profiles.localRev + const Constant(1),
          ));
      rebased += await (db.update(db.dayEntries)
            ..where((t) =>
                t.dirty.equals(true) &
                t.updatedAt.isBiggerThanValue(threshold)))
          .write(DayEntriesCompanion.custom(
            updatedAt: Constant(serverNow.toUtc()),
            localRev: db.dayEntries.localRev + const Constant(1),
          ));
      rebased += await (db.update(db.observations)
            ..where((t) =>
                t.dirty.equals(true) &
                t.updatedAt.isBiggerThanValue(threshold)))
          .write(ObservationsCompanion.custom(
            updatedAt: Constant(serverNow.toUtc()),
            localRev: db.observations.localRev + const Constant(1),
          ));
      rebased += await (db.update(db.profileModes)
            ..where((t) =>
                t.dirty.equals(true) &
                t.updatedAt.isBiggerThanValue(threshold)))
          .write(ProfileModesCompanion.custom(
            updatedAt: Constant(serverNow.toUtc()),
            localRev: db.profileModes.localRev + const Constant(1),
          ));
      rebased += await (db.update(db.cycleOverrides)
            ..where((t) =>
                t.dirty.equals(true) &
                t.updatedAt.isBiggerThanValue(threshold)))
          .write(CycleOverridesCompanion.custom(
            updatedAt: Constant(serverNow.toUtc()),
            localRev: db.cycleOverrides.localRev + const Constant(1),
          ));
      rebased += await (db.update(db.careNotes)
            ..where((t) =>
                t.dirty.equals(true) &
                t.updatedAt.isBiggerThanValue(threshold)))
          .write(CareNotesCompanion.custom(
            updatedAt: Constant(serverNow.toUtc()),
            localRev: db.careNotes.localRev + const Constant(1),
          ));
      rebased += await (db.update(db.visitPrepItems)
            ..where((t) =>
                t.dirty.equals(true) &
                t.updatedAt.isBiggerThanValue(threshold)))
          .write(VisitPrepItemsCompanion.custom(
            updatedAt: Constant(serverNow.toUtc()),
            localRev: db.visitPrepItems.localRev + const Constant(1),
          ));
      rebased += await (db.update(db.profileTagRegistry)
            ..where((t) =>
                t.dirty.equals(true) &
                t.updatedAt.isBiggerThanValue(threshold)))
          .write(ProfileTagRegistryCompanion.custom(
            updatedAt: Constant(serverNow.toUtc()),
            localRev: db.profileTagRegistry.localRev + const Constant(1),
          ));
    });
    return rebased;
  }

  /// Sweeps tombstoned rows older than [retentionHorizon] (or [olderThan] if
  /// specified) whose `dirty` flag is false (Issue #203).
  ///
  /// Deletes are performed in referential integrity order (child tables before
  /// parents). Only clean (already synced or never dirty) tombstones are removed;
  /// rows pending upload are never swept.
  /// Returns the total number of swept rows.
  @override
  Future<int> sweepTombstones({
    Duration retentionHorizon = kTombstoneRetentionHorizon,
    DateTime? olderThan,
  }) async {
    final cutoff = olderThan ?? _clock.now().subtract(retentionHorizon);
    return await db.transaction(() async {
      var swept = 0;

      // 1. Observations (references day_entries and profiles)
      swept += await (db.delete(db.observations)
            ..where((t) =>
                t.deletedAt.isNotNull() &
                t.dirty.equals(false) &
                t.deletedAt.isSmallerOrEqualValue(cutoff)))
          .go();

      // 2. Visit prep items (references profiles)
      swept += await (db.delete(db.visitPrepItems)
            ..where((t) =>
                t.deletedAt.isNotNull() &
                t.dirty.equals(false) &
                t.deletedAt.isSmallerOrEqualValue(cutoff)))
          .go();

      // 3. Care notes (references profiles)
      swept += await (db.delete(db.careNotes)
            ..where((t) =>
                t.deletedAt.isNotNull() &
                t.dirty.equals(false) &
                t.deletedAt.isSmallerOrEqualValue(cutoff)))
          .go();

      // 4. Cycle overrides (references profiles)
      swept += await (db.delete(db.cycleOverrides)
            ..where((t) =>
                t.deletedAt.isNotNull() &
                t.dirty.equals(false) &
                t.deletedAt.isSmallerOrEqualValue(cutoff)))
          .go();

      // 4b. Profile tag registry (references profiles) — Issue #257.
      swept += await (db.delete(db.profileTagRegistry)
            ..where((t) =>
                t.deletedAt.isNotNull() &
                t.dirty.equals(false) &
                t.deletedAt.isSmallerOrEqualValue(cutoff)))
          .go();

      // 5. Day entries (references profiles, referenced by observations)
      // Only delete day entries that are no longer referenced by any remaining observations.
      final referencedDayEntryIds = db.selectOnly(db.observations)
        ..addColumns([db.observations.dayEntryId])
        ..where(db.observations.dayEntryId.isNotNull());

      swept += await (db.delete(db.dayEntries)
            ..where((t) =>
                t.deletedAt.isNotNull() &
                t.dirty.equals(false) &
                t.deletedAt.isSmallerOrEqualValue(cutoff) &
                t.id.isNotInQuery(referencedDayEntryIds)))
          .go();

      // 6. Profiles (root table)
      // Only delete profiles if no child records remain referencing them.
      final refObs = db.selectOnly(db.observations)..addColumns([db.observations.profileId]);
      final refDays = db.selectOnly(db.dayEntries)..addColumns([db.dayEntries.profileId]);
      final refGuardians = db.selectOnly(db.profileGuardians)..addColumns([db.profileGuardians.profileId]);
      final refModes = db.selectOnly(db.profileModes)..addColumns([db.profileModes.profileId]);
      final refOverrides = db.selectOnly(db.cycleOverrides)..addColumns([db.cycleOverrides.profileId]);
      final refNotes = db.selectOnly(db.careNotes)..addColumns([db.careNotes.profileId]);
      final refPrep = db.selectOnly(db.visitPrepItems)..addColumns([db.visitPrepItems.profileId]);
      final refRegistry = db.selectOnly(db.profileTagRegistry)
        ..addColumns([db.profileTagRegistry.profileId]);

      swept += await (db.delete(db.profiles)
            ..where((t) =>
                t.deletedAt.isNotNull() &
                t.dirty.equals(false) &
                t.deletedAt.isSmallerOrEqualValue(cutoff) &
                t.id.isNotInQuery(refObs) &
                t.id.isNotInQuery(refDays) &
                t.id.isNotInQuery(refGuardians) &
                t.id.isNotInQuery(refModes) &
                t.id.isNotInQuery(refOverrides) &
                t.id.isNotInQuery(refNotes) &
                t.id.isNotInQuery(refPrep) &
                t.id.isNotInQuery(refRegistry)))
          .go();

      return swept;
    });
  }

  // --------------------------------------------------------- sync: state row

  /// The `sync_state` singleton, or [kDefaultSyncState] when never written.
  @override
  Future<SyncStateRow> readSyncState() async {
    final row = await (db.select(db.syncState)..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    return row ?? kDefaultSyncState;
  }

  /// Replaces the `sync_state` singleton (the id is forced to 1).
  @override
  Future<void> writeSyncState(SyncStateRow state) async {
    await db
        .into(db.syncState)
        .insertOnConflictUpdate(state.copyWith(id: 1).toCompanion(false));
  }

  /// Sets the shared [StorageClock]'s offset (see [StorageClock.setOffset]).
  @override
  void setClockOffset(Duration offset) => _clock.setOffset(offset);
}

/// Delegation shim (issue #551 part 1 step 2): `LunarLogStorage` keeps
/// implementing [SyncMetadataStore] by forwarding each member to the
/// extracted [SyncCursorStorage] it owns. Every existing consumer and test
/// therefore keeps compiling against the same `LunarLogStorage` surface.
mixin LunarLogStorageSyncMetadata implements SyncMetadataStore {
  SyncMetadataStore get syncMetadata;

  @override
  Future<SyncStateRow> readSyncState() => syncMetadata.readSyncState();

  @override
  Future<void> writeSyncState(SyncStateRow state) =>
      syncMetadata.writeSyncState(state);

  @override
  void setClockOffset(Duration offset) => syncMetadata.setClockOffset(offset);

  @override
  Future<List<Profile>> readDirtyProfiles({int? limit, String? afterId}) =>
      syncMetadata.readDirtyProfiles(limit: limit, afterId: afterId);

  @override
  Future<List<DayEntry>> readDirtyDayEntries({int? limit, String? afterId}) =>
      syncMetadata.readDirtyDayEntries(limit: limit, afterId: afterId);

  @override
  Future<List<Observation>> readDirtyObservations({
    int? limit,
    String? afterId,
  }) =>
      syncMetadata.readDirtyObservations(limit: limit, afterId: afterId);

  @override
  Future<List<ProfileModeData>> readDirtyProfileModes({
    int? limit,
    String? afterId,
  }) =>
      syncMetadata.readDirtyProfileModes(limit: limit, afterId: afterId);

  @override
  Future<List<CycleOverrideData>> readDirtyCycleOverrides({
    int? limit,
    String? afterId,
  }) =>
      syncMetadata.readDirtyCycleOverrides(limit: limit, afterId: afterId);

  @override
  Future<List<CareNoteData>> readDirtyCareNotes({int? limit, String? afterId}) =>
      syncMetadata.readDirtyCareNotes(limit: limit, afterId: afterId);

  @override
  Future<List<VisitPrepItemData>> readDirtyVisitPrepItems({
    int? limit,
    String? afterId,
  }) =>
      syncMetadata.readDirtyVisitPrepItems(limit: limit, afterId: afterId);

  @override
  Future<List<GuardianNoteData>> readDirtyGuardianNotes({
    int? limit,
    String? afterId,
  }) =>
      syncMetadata.readDirtyGuardianNotes(limit: limit, afterId: afterId);

  @override
  Future<List<DayEntryMergeEventData>> readDirtyDayEntryMergeEvents({
    int? limit,
    String? afterId,
  }) =>
      syncMetadata.readDirtyDayEntryMergeEvents(limit: limit, afterId: afterId);

  @override
  Future<List<ProfileTagRegistryEntry>> readDirtyProfileTagRegistry({
    int? limit,
    String? afterId,
  }) =>
      syncMetadata.readDirtyProfileTagRegistry(limit: limit, afterId: afterId);

  @override
  Future<void> markAllDirty() => syncMetadata.markAllDirty();

  @override
  Future<int> dirtyCount() => syncMetadata.dirtyCount();

  @override
  Future<bool> isEmpty() => syncMetadata.isEmpty();

  @override
  Future<int> rebaseFutureStampedRows({required DateTime serverNow}) =>
      syncMetadata.rebaseFutureStampedRows(serverNow: serverNow);

  @override
  Future<int> sweepTombstones({
    Duration retentionHorizon = kTombstoneRetentionHorizon,
    DateTime? olderThan,
  }) =>
      syncMetadata.sweepTombstones(
        retentionHorizon: retentionHorizon,
        olderThan: olderThan,
      );
}
