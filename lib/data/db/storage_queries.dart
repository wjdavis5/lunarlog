part of 'storage.dart';

// Local reads and private query/row helpers for [LunarLogStorage] (part of
// `storage.dart`, mixed into the class below). UI reads filter tombstones;
// full-fidelity reads (tombstones included) exist for sync.
// Moved verbatim from `storage.dart` (#434).

/// The `sync_state` row as read when none has been written yet.
const SyncStateRow kDefaultSyncState = SyncStateRow(
  id: 1,
  deviceId: '',
  cursorProfiles: 0,
  cursorDayEntries: 0,
  cursorObservations: 0,
  cursorProfileModes: 0,
  cursorCycleOverrides: 0,
  cursorCareNotes: 0,
  cursorVisitPrepItems: 0,
);

/// Local-read and query-helper members mixed into [LunarLogStorage].
mixin LunarLogStorageQueries {
  LunarLogDatabase get db;

  /// Profiles for UI reads ([includeTombstones] false, default) or for sync
  /// (true), ordered by [Profiles.sortOrder] then id for stable lists.
  Future<List<Profile>> getProfiles({bool includeTombstones = false}) =>
      _profilesQuery(includeTombstones: includeTombstones).get();

  /// Stream variant of [getProfiles] for reactive UI.
  Stream<List<Profile>> watchProfiles({bool includeTombstones = false}) =>
      _profilesQuery(includeTombstones: includeTombstones).watch();

  /// The single profile [id], or null when no such row is held. An indexed
  /// primary-key lookup rather than a scan of [getProfiles].
  ///
  /// Tombstones are excluded by default — exactly the filter [getProfiles]
  /// applies — so a tombstoned id reads as null; pass
  /// [includeTombstones] `true` for the full-fidelity row that sync needs.
  Future<Profile?> getProfile(String id, {bool includeTombstones = false}) {
    final query = db.select(db.profiles)..where((t) => t.id.equals(id));
    if (!includeTombstones) {
      query.where((t) => t.deletedAt.isNull());
    }
    return query.getSingleOrNull();
  }

  /// Day entries for one profile — UI reads (default) filter tombstones;
  /// `includeTombstones: true` gives full-fidelity reads for sync.
  /// [updatedAfter] narrows to rows changed after that instant
  /// (incremental-sync support). [fromLocalDate]/[toLocalDate] narrow to an
  /// inclusive `yyyy-MM-dd` range (issue #197: the calendar's windowed
  /// subscription) — lexicographic string comparison on that format sorts
  /// identically to chronological order, so no date parsing is needed here.
  /// Per-profile isolation (R3) is structural: every query is scoped to
  /// exactly one profileId.
  Future<List<DayEntry>> getDayEntries({
    required String profileId,
    bool includeTombstones = false,
    DateTime? updatedAfter,
    String? fromLocalDate,
    String? toLocalDate,
  }) {
    return _dayEntryQuery(
      profileId: profileId,
      includeTombstones: includeTombstones,
      updatedAfter: updatedAfter,
      fromLocalDate: fromLocalDate,
      toLocalDate: toLocalDate,
    ).get();
  }

  /// The live day entry for (profileId, localDate), or null when that date
  /// holds no entry — including when its only row is a tombstone, which
  /// [getDayEntries] excludes for UI reads too. Scoped to the one
  /// [profileId], so another profile's entry for the same date never
  /// answers this query.
  ///
  /// Returns the first matching row rather than throwing on multiples: two
  /// live rows for one (profileId, localDate) are impossible anyway, because
  /// of the partial unique index `uq_day_entries_profile_date_live`
  /// (`kLiveDayEntryIndexSql` in `lib/data/db/db.dart`).
  Future<DayEntry?> getDayEntry({
    required String profileId,
    required String localDate,
  }) async {
    final rows = await _dayEntryQuery(
      profileId: profileId,
      includeTombstones: false,
      localDate: localDate,
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  /// The day entry (live OR tombstoned) for (profileId, source, sourceId),
  /// or null when none exists — Issue #140 review, item 5: an importer must
  /// dedup against this exact triple, including tombstones, before
  /// planning a new row, since the server's partial unique index
  /// `day_entries_profile_source_source_id_uq` is not scoped to live rows
  /// either (`supabase/migrations/20260908170000_import_provenance.sql`).
  /// [sourceId] is never null in practice for a caller of this method — the
  /// index itself only applies `where source_id is not null` — but this
  /// still answers a null query the ordinary way (no match) rather than
  /// throwing.
  Future<DayEntry?> findDayEntryBySource({
    required String profileId,
    required String source,
    required String? sourceId,
  }) async {
    if (sourceId == null) return null;
    // Issue #140 review round 2, item 7: `get()` + first, not
    // `getSingleOrNull` — the server's partial unique index constrains
    // this triple, but this store's own local rows are never guaranteed
    // unique on it (e.g. a row written before that index existed, or by a
    // path that doesn't go through it), so more than one local match must
    // read as "found one", never throw.
    final rows = await (db.select(db.dayEntries)
          ..where((t) =>
              t.profileId.equals(profileId) &
              t.source.equals(source) &
              t.sourceId.equals(sourceId))
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Stream variant of [getDayEntries] for reactive UI. See [getDayEntries]
  /// for [fromLocalDate]/[toLocalDate] (issue #197).
  Stream<List<DayEntry>> watchDayEntries({
    required String profileId,
    bool includeTombstones = false,
    DateTime? updatedAfter,
    String? fromLocalDate,
    String? toLocalDate,
  }) {
    return _dayEntryQuery(
      profileId: profileId,
      includeTombstones: includeTombstones,
      updatedAfter: updatedAfter,
      fromLocalDate: fromLocalDate,
      toLocalDate: toLocalDate,
    ).watch();
  }

  /// Observations attached to [dayEntryId] — UI reads (default) filter
  /// tombstones; `includeTombstones: true` gives full-fidelity reads.
  Future<List<Observation>> getObservationsForDayEntry(
    String dayEntryId, {
    bool includeTombstones = false,
  }) {
    final query = db.select(db.observations)
      ..where((t) {
        var condition = t.dayEntryId.equals(dayEntryId);
        if (!includeTombstones) condition = condition & t.deletedAt.isNull();
        return condition;
      })
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);
    return query.get();
  }

  /// Stream variant of [getObservationsForDayEntry] for reactive UI.
  Stream<List<Observation>> watchObservationsForDayEntry(
    String dayEntryId, {
    bool includeTombstones = false,
  }) {
    final query = db.select(db.observations)
      ..where((t) {
        var condition = t.dayEntryId.equals(dayEntryId);
        if (!includeTombstones) condition = condition & t.deletedAt.isNull();
        return condition;
      })
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);
    return query.watch();
  }

  /// Every observation attached to any of [profileId]'s day entries — Issue
  /// #240, used by [DriftObservationsRepository.listForProfile] for account
  /// export (`kAccountExportSchemaVersion` v3). UI reads (default) filter
  /// tombstones, mirroring [getObservationsForDayEntry].
  Future<List<Observation>> getObservationsForProfile(
    String profileId, {
    bool includeTombstones = false,
  }) {
    final query = db.select(db.observations)
      ..where((t) {
        var condition = t.profileId.equals(profileId);
        if (!includeTombstones) condition = condition & t.deletedAt.isNull();
        return condition;
      })
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);
    return query.get();
  }

  /// The profile's mode row, or null when none was ever written (which
  /// means `tracking` — the lazy-default contract; callers fall back to
  /// [LifecycleMode.tracking] rather than storing a default row).
  Future<ProfileModeData?> getProfileMode(String profileId) =>
      _profileModeOrNull(profileId);

  /// Stream variant of [getProfileMode] for reactive UI.
  Stream<ProfileModeData?> watchProfileMode(String profileId) =>
      (db.select(db.profileModes)
            ..where((t) => t.profileId.equals(profileId)))
          .watchSingleOrNull();

  /// A profile's manual cycle corrections — UI reads (default) filter
  /// tombstones; `includeTombstones: true` gives full-fidelity reads for
  /// sync. Ordered by `cycle_start_date` then id.
  Future<List<CycleOverrideData>> getCycleOverridesForProfile(
    String profileId, {
    bool includeTombstones = false,
  }) {
    return _cycleOverrideQuery(profileId,
            includeTombstones: includeTombstones)
        .get();
  }

  /// Stream variant of [getCycleOverridesForProfile] for reactive UI.
  Stream<List<CycleOverrideData>> watchCycleOverridesForProfile(
    String profileId, {
    bool includeTombstones = false,
  }) {
    return _cycleOverrideQuery(profileId,
            includeTombstones: includeTombstones)
        .watch();
  }

  /// A profile's standing care notes — UI reads (default) filter
  /// tombstones; `includeTombstones: true` gives full-fidelity reads for
  /// sync. Ordered by `updated_at` then id (stable for the UI list).
  Future<List<CareNoteData>> getCareNotesForProfile(
    String profileId, {
    bool includeTombstones = false,
  }) {
    return _careNoteQuery(profileId, includeTombstones: includeTombstones)
        .get();
  }

  /// Stream variant of [getCareNotesForProfile] for reactive UI.
  Stream<List<CareNoteData>> watchCareNotesForProfile(
    String profileId, {
    bool includeTombstones = false,
  }) {
    return _careNoteQuery(profileId, includeTombstones: includeTombstones)
        .watch();
  }

  /// A profile's visit-prep items — UI reads (default) filter tombstones;
  /// `includeTombstones: true` gives full-fidelity reads for sync.
  /// Checked items sort after unchecked ones (unchecked first, then by
  /// `updated_at`, then id), so the open questions stay on top while what
  /// was covered remains visible below until cleared.
  Future<List<VisitPrepItemData>> getVisitPrepItemsForProfile(
    String profileId, {
    bool includeTombstones = false,
  }) {
    return _visitPrepItemQuery(profileId,
            includeTombstones: includeTombstones)
        .get();
  }

  /// Stream variant of [getVisitPrepItemsForProfile] for reactive UI.
  Stream<List<VisitPrepItemData>> watchVisitPrepItemsForProfile(
    String profileId, {
    bool includeTombstones = false,
  }) {
    return _visitPrepItemQuery(profileId,
            includeTombstones: includeTombstones)
        .watch();
  }

  Future<String?> getSetting(String key) async {
    final row = await (db.select(db.appSettings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Stream<String?> watchSetting(String key) {
    final query = db.select(db.appSettings)..where((t) => t.key.equals(key));
    return query.watchSingleOrNull().map((row) => row?.value);
  }

  // ------------------------------------------------------- sync: dirty rows

  /// Profiles with unpushed local changes, tombstones included, ordered by
  /// id (ULIDs, so this is also insertion order). [afterId] resumes a
  /// keyset scan after that id (exclusive); [limit] bounds the page so a
  /// caller can stream a large dirty set batch by batch instead of
  /// materialising it all at once.
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

  /// Number of rows, live and tombstoned, in every synced table that still
  /// need pushing.
  Future<int> dirtyCount() async {
    final p = await _count(db.profiles, db.profiles.id,
        db.profiles.dirty.equals(true));
    final d = await _count(db.dayEntries, db.dayEntries.id,
        db.dayEntries.dirty.equals(true));
    final o = await _count(db.observations, db.observations.id,
        db.observations.dirty.equals(true));
    final pm = await _count(db.profileModes, db.profileModes.profileId,
        db.profileModes.dirty.equals(true));
    final co = await _count(db.cycleOverrides, db.cycleOverrides.id,
        db.cycleOverrides.dirty.equals(true));
    final cn = await _count(
        db.careNotes, db.careNotes.id, db.careNotes.dirty.equals(true));
    final vp = await _count(db.visitPrepItems, db.visitPrepItems.id,
        db.visitPrepItems.dirty.equals(true));
    return p + d + o + pm + co + cn + vp;
  }

  /// Row counts, live and tombstoned, of the two synced tables the upload-
  /// consent screen shows (R14, AS4) — observations and the two Issue #188
  /// tables are deliberately not extra fields here (no UI surface for them
  /// yet; see [isEmpty], which does account for them so a device holding
  /// only those rows is never silently treated as empty).
  Future<LocalRowCounts> countAllRows() async {
    final [p, d] = await Future.wait([
      _count(db.profiles, db.profiles.id),
      _count(db.dayEntries, db.dayEntries.id),
    ]);
    return (profiles: p, dayEntries: d);
  }

  /// True only when every synced table holds no row of any kind — a
  /// tombstone-only database is not empty (it has deletions to push).
  Future<bool> isEmpty() async {
    final counts = await countAllRows();
    if (counts.profiles != 0 || counts.dayEntries != 0) return false;
    if (await _count(db.observations, db.observations.id) != 0) return false;
    if (await _count(db.profileModes, db.profileModes.profileId) != 0) {
      return false;
    }
    if (await _count(db.cycleOverrides, db.cycleOverrides.id) != 0) {
      return false;
    }
    if (await _count(db.careNotes, db.careNotes.id) != 0) return false;
    return await _count(db.visitPrepItems, db.visitPrepItems.id) == 0;
  }

  // --------------------------------------------------------- sync: state row

  /// The `sync_state` singleton, or [kDefaultSyncState] when never written.
  Future<SyncStateRow> readSyncState() async {
    final row = await (db.select(db.syncState)..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    return row ?? kDefaultSyncState;
  }

  /// The device-local `health_sync_state` anchor for [platform], or null
  /// when never written (Issue #186 — never synced to the server).
  Future<HealthSyncStateRow?> readHealthSyncAnchor(String platform) async {
    final row = await (db.select(db.healthSyncState)
          ..where((t) => t.platform.equals(platform)))
        .getSingleOrNull();
    return row;
  }

  Future<List<ProfileGuardianData>> getGuardiansForProfile(String profileId) =>
      (db.select(db.profileGuardians)..where((t) => t.profileId.equals(profileId)))
          .get();

  Stream<List<ProfileGuardianData>> watchGuardiansForProfile(String profileId) =>
      (db.select(db.profileGuardians)..where((t) => t.profileId.equals(profileId)))
          .watch();

  Future<void> _ensureSyncStateRow() async {
    await db.into(db.syncState).insert(
          const SyncStateCompanion(id: Value(1)),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<int> _count<T extends Table, D>(
    TableInfo<T, D> table,
    Expression<Object> column, [
    Expression<bool>? where,
  ]) async {
    final count = column.count();
    final query = db.selectOnly(table)..addColumns([count]);
    if (where != null) query.where(where);
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// The shared builder behind [getProfiles] and [watchProfiles]: ordered by
  /// [Profiles.sortOrder] then id, tombstones filtered unless
  /// [includeTombstones].
  Selectable<Profile> _profilesQuery({required bool includeTombstones}) {
    final query = db.select(db.profiles)
      ..orderBy([
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.id),
      ]);
    if (!includeTombstones) {
      query.where((t) => t.deletedAt.isNull());
    }
    return query;
  }

  /// The shared builder behind the day-entry reads. [localDate] narrows to
  /// one date (the single-row [getDayEntry] lookup); the list reads omit it.
  /// [fromLocalDate]/[toLocalDate] narrow to an inclusive range instead of a
  /// single date (issue #197) — `day_entries(profile_id, local_date)`
  /// (`kDayEntriesProfileDateIndexSql` in `lib/data/db/db.dart`) makes this
  /// a cheap index range scan rather than a full-table scan.
  Selectable<DayEntry> _dayEntryQuery({
    required String profileId,
    required bool includeTombstones,
    String? localDate,
    String? fromLocalDate,
    String? toLocalDate,
    DateTime? updatedAfter,
  }) {
    final query = db.select(db.dayEntries)
      ..where((row) {
        var condition = row.profileId.equals(profileId);
        if (localDate != null) {
          condition = condition & row.localDate.equals(localDate);
        }
        if (fromLocalDate != null) {
          condition =
              condition & row.localDate.isBiggerOrEqualValue(fromLocalDate);
        }
        if (toLocalDate != null) {
          condition =
              condition & row.localDate.isSmallerOrEqualValue(toLocalDate);
        }
        if (!includeTombstones) {
          condition = condition & row.deletedAt.isNull();
        }
        if (updatedAfter != null) {
          condition = condition & row.updatedAt.isBiggerThanValue(updatedAfter);
        }
        return condition;
      })
      ..orderBy([(row) => OrderingTerm(expression: row.localDate)]);
    return query;
  }

  Future<List<DayEntry>> _liveDayEntries(String profileId, String localDate) {
    final query = db.select(db.dayEntries)
      ..where((t) =>
          t.profileId.equals(profileId) &
          t.localDate.equals(localDate) &
          t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);
    return query.get();
  }

  Future<DayEntry?> _liveDayEntry(String profileId, String localDate) async {
    final rows = await _liveDayEntries(profileId, localDate);
    if (rows.length > 1) {
      throw StateError(
          'more than one live day entry for $profileId $localDate');
    }
    return rows.isEmpty ? null : rows.single;
  }

  Future<DayEntry?> _dayEntryOrNull(String id) =>
      (db.select(db.dayEntries)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<Profile?> _profileOrNull(String id) =>
      (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Profile> _profileById(String id) async {
    final row = await _profileOrNull(id);
    if (row == null) throw StateError('profile disappeared: $id');
    return row;
  }

  Future<Observation?> _observationOrNull(String id) =>
      (db.select(db.observations)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<Observation> _observationById(String id) async {
    final row = await _observationOrNull(id);
    if (row == null) throw StateError('observation disappeared: $id');
    return row;
  }

  Future<ProfileModeData?> _profileModeOrNull(String profileId) =>
      (db.select(db.profileModes)
            ..where((t) => t.profileId.equals(profileId)))
          .getSingleOrNull();

  Future<ProfileModeData> _profileModeById(String profileId) async {
    final row = await _profileModeOrNull(profileId);
    if (row == null) throw StateError('profile mode disappeared: $profileId');
    return row;
  }

  Future<CycleOverrideData?> _cycleOverrideOrNull(String id, String profileId) =>
      (db.select(db.cycleOverrides)
            ..where((t) => t.id.equals(id) & t.profileId.equals(profileId)))
          .getSingleOrNull();

  Future<CycleOverrideData> _cycleOverrideById(
      String id, String profileId) async {
    final row = await _cycleOverrideOrNull(id, profileId);
    if (row == null) throw StateError('cycle override disappeared: $id');
    return row;
  }

  /// The shared builder behind [getCycleOverridesForProfile] and its watch
  /// variant: ordered by `cycle_start_date` then id, tombstones filtered
  /// unless [includeTombstones].
  Selectable<CycleOverrideData> _cycleOverrideQuery(
    String profileId, {
    required bool includeTombstones,
  }) {
    final query = db.select(db.cycleOverrides)
      ..where((t) {
        var condition = t.profileId.equals(profileId);
        if (!includeTombstones) {
          condition = condition & t.deletedAt.isNull();
        }
        return condition;
      })
      ..orderBy([
        (t) => OrderingTerm(expression: t.cycleStartDate),
        (t) => OrderingTerm(expression: t.id),
      ]);
    return query;
  }

  Future<CareNoteData?> _careNoteOrNull(String id) =>
      (db.select(db.careNotes)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<CareNoteData> _careNoteById(String id) async {
    final row = await _careNoteOrNull(id);
    if (row == null) throw StateError('care note disappeared: $id');
    return row;
  }

  /// The shared builder behind [getCareNotesForProfile] and its watch
  /// variant: ordered by `updated_at` then id, tombstones filtered unless
  /// [includeTombstones].
  Selectable<CareNoteData> _careNoteQuery(
    String profileId, {
    required bool includeTombstones,
  }) {
    final query = db.select(db.careNotes)
      ..where((t) {
        var condition = t.profileId.equals(profileId);
        if (!includeTombstones) {
          condition = condition & t.deletedAt.isNull();
        }
        return condition;
      })
      ..orderBy([
        (t) => OrderingTerm(expression: t.updatedAt),
        (t) => OrderingTerm(expression: t.id),
      ]);
    return query;
  }

  Future<VisitPrepItemData?> _visitPrepItemOrNull(String id) =>
      (db.select(db.visitPrepItems)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<VisitPrepItemData> _visitPrepItemById(String id) async {
    final row = await _visitPrepItemOrNull(id);
    if (row == null) throw StateError('visit prep item disappeared: $id');
    return row;
  }

  /// The checked, live items behind [clearCheckedVisitPrepItems].
  Selectable<VisitPrepItemData> _carePrepCheckedQuery(String profileId) {
    final query = db.select(db.visitPrepItems)
      ..where((t) =>
          t.profileId.equals(profileId) &
          t.isChecked.equals(true) &
          t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.id)]);
    return query;
  }

  /// The shared builder behind [getVisitPrepItemsForProfile] and its watch
  /// variant: unchecked first (open questions on top, covered items below
  /// until cleared), then by `updated_at`, then id; tombstones filtered
  /// unless [includeTombstones].
  Selectable<VisitPrepItemData> _visitPrepItemQuery(
    String profileId, {
    required bool includeTombstones,
  }) {
    final query = db.select(db.visitPrepItems)
      ..where((t) {
        var condition = t.profileId.equals(profileId);
        if (!includeTombstones) {
          condition = condition & t.deletedAt.isNull();
        }
        return condition;
      })
      ..orderBy([
        (t) => OrderingTerm(expression: t.isChecked),
        (t) => OrderingTerm(expression: t.updatedAt),
        (t) => OrderingTerm(expression: t.id),
      ]);
    return query;
  }

}
