part of 'storage.dart';

// Remote applies for [LunarLogStorage] (part of `storage.dart`, mixed into
// the class below). Every remote apply compares *before* writing (LWW per
// id; the remote copy wins ties), writes `dirty = false`, and never
// regresses `updated_at`. Same-date conflicts tombstone the loser with the
// winner's timestamp.
// Moved verbatim from `storage.dart` (#434).

/// Issue #42: the per-page batched lookup cache behind
/// [LunarLogStorageRemoteApply.applyRemotePage] /
/// [LunarLogStorageRemoteApply.applyRemoteRows]. A pull page used to run
/// three individual SELECTs per row inside its transaction — the row's own
/// local copy by id, its referenced parent (profile / day entry) by id, and
/// the same-date live peers — up to ~1500 statements per 500-row page.
/// [LunarLogStorageRemoteApply._prefetchPageRows] now batch-reads all of
/// them into this cache with chunked `IN (...)` selects before the row loop
/// starts, and every write in the apply path stores what it wrote back into
/// the cache (via SQL `RETURNING`, at zero extra statement cost) so later
/// rows in the same page see exactly what a live SELECT would have seen.
///
/// The maps hold `null` values for ids that were prefetched and found
/// absent — a *known-absent* row must not re-run a SELECT (new-row-heavy
/// first-sync pages are the ones with the most misses) — and a key that is
/// simply not present means "not prefetched", for which every read falls
/// back to the live per-row SELECT (the pre-#42 behavior, always correct).
/// [evictProfile] drops everything cached about one profile after a
/// revocation/purge wipe rewrote it wholesale, for the same reason: fall
/// back to live reads rather than reason about staleness.
class _PageLookup {
  /// Live same-date peers, keyed by [peerKey] (`profileId|localDate`),
  /// ordered by id exactly like the live `_liveDayEntries` query the
  /// same-date resolver used to issue per row.
  final Map<String, List<DayEntry>> livePeers = {};

  final Map<String, Profile?> profiles = {};
  final Map<String, DayEntry?> dayEntries = {};
  final Map<String, Observation?> observations = {};
  final Map<String, ProfileModeData?> profileModes = {};
  final Map<String, CycleOverrideData?> cycleOverrides = {};
  final Map<String, CareNoteData?> careNotes = {};
  final Map<String, VisitPrepItemData?> visitPrepItems = {};

  /// Issue #130's tenth synced table, prefetched by id exactly like the
  /// care tables (Issue #42's pattern applied when the table landed).
  final Map<String, DayEntryMergeEventData?> dayEntryMergeEvents = {};

  /// Issue #257's eleventh synced table, prefetched by id exactly like the
  /// care tables.
  final Map<String, ProfileTagRegistryEntry?> profileTagRegistry = {};

  final Map<String, ProfileGuardianData?> guardians = {};

  static String peerKey(String profileId, String localDate) =>
      '$profileId|$localDate';

  /// [LunarLogStorageRemoteApply._prefetchLivePeers]'s known-pair filler:
  /// a (profile, date) with no live row must read as an empty list, not as
  /// an unknown key (which would fall back to a live SELECT).
  void noteLivePeerPair(String profileId, String localDate) {
    livePeers.putIfAbsent(peerKey(profileId, localDate), () => const []);
  }

  /// One row collected by the live-peer prefetch.
  void addLivePeer(DayEntry row) {
    final key = peerKey(row.profileId, row.localDate);
    final list = livePeers.putIfAbsent(key, () => []);
    livePeers[key] = [...list, row];
  }

  /// The write-through for every day-entry write in the apply path: the
  /// row's own by-id entry, plus its slot in the (profile, date) live-peer
  /// list (replaced in id order when live, removed when tombstoned) so a
  /// later row in the same page resolves against what this write left.
  void storeDayEntry(DayEntry row) {
    dayEntries[row.id] = row;
    final key = peerKey(row.profileId, row.localDate);
    if (!livePeers.containsKey(key)) return;
    final live = livePeers[key]!;
    final next = row.deletedAt == null
        ? _replaceById(live, row)
        : _removeById(live, row.id);
    livePeers[key] = next;
  }

  /// Replaces [row]'s entry (or inserts it in id order — the lists mirror
  /// the live query's `ORDER BY id`, which the resolver's outcome can
  /// depend on when several peers compete).
  static List<DayEntry> _replaceById(List<DayEntry> rows, DayEntry row) {
    final next = <DayEntry>[];
    var inserted = false;
    for (final existing in rows) {
      if (existing.id == row.id) {
        next.add(row);
        inserted = true;
      } else {
        next.add(existing);
      }
    }
    if (!inserted) {
      var i = 0;
      while (i < next.length && next[i].id.compareTo(row.id) < 0) {
        i++;
      }
      next.insert(i, row);
    }
    return next;
  }

  static List<DayEntry> _removeById(List<DayEntry> rows, String id) => [
    for (final row in rows)
      if (row.id != id) row,
  ];

  /// The revocation/purge wipe
  /// ([LunarLogStorageRemoteApply._tombstoneRevokedSharedProfile]) rewrites
  /// every row of [profileId] across seven tables with bulk UPDATEs whose
  /// affected rows this cache cannot enumerate. Rather than reason about
  /// which cached copies stay decision-equivalent, drop everything cached
  /// about the profile: every later read in the same page falls back to a
  /// live SELECT, which is always correct.
  void evictProfile(String profileId) {
    final prefix = '$profileId|';
    livePeers.removeWhere((key, _) => key.startsWith(prefix));
    dayEntries.removeWhere((_, row) => row?.profileId == profileId);
    observations.removeWhere((_, row) => row?.profileId == profileId);
    profileModes.remove(profileId);
    cycleOverrides.removeWhere((_, row) => row?.profileId == profileId);
    careNotes.removeWhere((_, row) => row?.profileId == profileId);
    visitPrepItems.removeWhere((_, row) => row?.profileId == profileId);
    dayEntryMergeEvents.removeWhere((_, row) => row?.profileId == profileId);
    profileTagRegistry.removeWhere((_, row) => row?.profileId == profileId);
    profiles.remove(profileId);
  }
}

/// Remote-apply members mixed into [LunarLogStorage].
mixin LunarLogStorageRemoteApply on LunarLogStorageQueries, LunarLogStorageLocalWrites {
  // ---------------------------------------------------- sync: remote applies

  /// Applies a server copy of a profile keyed by id (KTD5 per-id rule:
  /// newer `updated_at` wins, the remote copy wins ties). Writes
  /// `dirty = false` without touching `local_rev`. Returns whether the row
  /// was written; `false` means the local copy is newer and was kept.
  Future<bool> applyRemoteProfile(RemoteProfileRow remote) =>
      db.transaction(() => _applyProfile(remote, onlyExisting: false));

  /// Applies a server copy of a day entry keyed by id (per-id rule as for
  /// profiles). For a live remote row the same-date rule runs against any
  /// other live local row for that (profile, date) first: a local loser is
  /// tombstoned with the winner's timestamp and marked dirty; a remote loser
  /// is stored as a tombstone (not dirty — the server resolves it when the
  /// local winner is pushed). When a remote winner absorbs tags from a local
  /// loser, it is marked dirty so the merge reaches the server. The partial
  /// unique index is therefore never violated. Throws [RetryableSyncApplyError]
  /// when the entry's profile is not held locally yet.
  Future<bool> applyRemoteDayEntry(RemoteDayEntryRow remote) =>
      db.transaction(() => _applyDayEntry(remote, onlyExisting: false));

  /// Applies a server copy of an observation keyed by id (Issue #240;
  /// per-id rule as for profiles — there is no same-date resolver here,
  /// unlike day entries: multiple live rows per (profile, date, category)
  /// are the entire point of this child table, so no local uniqueness ever
  /// competes). Throws [RetryableSyncApplyError] when the observation's day
  /// entry is not held locally yet.
  Future<bool> applyRemoteObservation(RemoteObservationRow remote) =>
      db.transaction(() => _applyObservation(remote, onlyExisting: false));

  /// Applies a server copy of a profile mode row keyed by profile id
  /// (Issue #188; per-id LWW rule as for profiles — one row per profile,
  /// no tombstone). Throws [RetryableSyncApplyError] when the profile is
  /// not held locally yet.
  Future<bool> applyRemoteProfileMode(RemoteProfileModeRow remote) =>
      db.transaction(() => _applyProfileMode(remote, onlyExisting: false));

  /// Applies a server copy of a cycle override keyed by (id, profile id)
  /// (Issue #188; per-id LWW rule as for day entries, minus the same-date
  /// resolver). Throws [RetryableSyncApplyError] when the profile is not
  /// held locally yet.
  Future<bool> applyRemoteCycleOverride(RemoteCycleOverrideRow remote) =>
      db.transaction(() => _applyCycleOverride(remote, onlyExisting: false));

  /// Applies a server copy of a care note keyed by id (Issue #128; per-id
  /// LWW rule as for cycle overrides — a newer `updated_at` wins, the
  /// remote copy wins ties; a tombstone clears `body`). Throws
  /// [RetryableSyncApplyError] when the profile is not held locally yet.
  Future<bool> applyRemoteCareNote(RemoteCareNoteRow remote) =>
      db.transaction(() => _applyCareNote(remote, onlyExisting: false));

  /// Applies a server copy of a visit-prep item keyed by id (Issue #128;
  /// same per-id LWW rule as care notes; a tombstone clears `body` and the
  /// check state). Throws [RetryableSyncApplyError] when the profile is
  /// not held locally yet.
  Future<bool> applyRemoteVisitPrepItem(RemoteVisitPrepItemRow remote) =>
      db.transaction(() => _applyVisitPrepItem(remote, onlyExisting: false));

  /// Applies a server copy of a merge event keyed by id (Issue #130; the
  /// per-id LWW rule the other profile-scoped tables use, with NO
  /// same-date resolver and no tombstone — rows are immutable
  /// machine-written disclosures, and the natural-key dedupe inside is the
  /// only collision that can occur). Throws [RetryableSyncApplyError] when
  /// the profile is not held locally yet.
  Future<bool> applyRemoteDayEntryMergeEvent(
          RemoteDayEntryMergeEventRow remote) =>
      db.transaction(() => _applyMergeEvent(remote, onlyExisting: false));

  /// Applies a server copy of a custom-tag registry row keyed by id
  /// (Issue #257; the per-id LWW rule as for care notes, minus nothing —
  /// retirement (hiddenAt) is an ordinary payload column, and a tombstone
  /// clears the payload client-side exactly like the server's structural
  /// CHECK does). Throws [RetryableSyncApplyError] when the profile is not
  /// held locally yet.
  Future<bool> applyRemoteProfileTagRegistryEntry(
          RemoteProfileTagRegistryRow remote) =>
      db.transaction(() => _applyTagRegistryEntry(remote, onlyExisting: false));

  /// Applies one pull page: every row (all of [table]) and the table's new
  /// cursor in ONE transaction, so a crash can only re-fetch rows, never
  /// skip them (KTD2). A throwing row rolls the whole page back, cursor
  /// included. Issue #42: the per-row lookups run against a page-wide
  /// batched prefetch (see [_PageLookup]) built inside the same
  /// transaction.
  Future<void> applyRemotePage({
    required SyncTable table,
    required List<RemoteRow> rows,
    required int newCursor,
  }) async {
    for (final row in rows) {
      if (row.table != table) {
        throw ArgumentError.value(row, 'rows',
            'row ${row.id} belongs to ${row.table}, page is for $table');
      }
    }
    await db.transaction(() async {
      final cache = await _prefetchPageRows(rows);
      for (final row in rows) {
        await _applyPageRow(row, cache);
      }
      await _updateTableCursor(table, newCursor);
    });
  }

  Future<void> _applyPageRow(RemoteRow row, _PageLookup cache) =>
      _pageRowAppliers[row.runtimeType]!(row, cache);

  /// Per-runtime-type dispatch for [_applyPageRow] — a map rather than an
  /// exhaustive type switch since Issue #130's tenth row type: the switch
  /// sat permanently over the quality gate's per-method complexity
  /// ceiling (ten pattern cases score complexity 11, and CRAP's `+ comp`
  /// term alone exceeds the 10.0 threshold at any coverage), while a
  /// lookup stays flat as row types are added (the same growth rationale
  /// as row_codec.dart's `_syncTableNames`). Issue #42: every closure
  /// threads the page-wide [_PageLookup] into its applier exactly as the
  /// pre-#130 switch did, so the prefetch is never dropped on dispatch.
  late final Map<Type, Future<void> Function(RemoteRow, _PageLookup)>
      _pageRowAppliers = {
    RemoteProfileRow: (r, c) => _applyProfile(r as RemoteProfileRow, onlyExisting: false, cache: c),
    RemoteDayEntryRow: (r, c) => _applyDayEntry(r as RemoteDayEntryRow, onlyExisting: false, cache: c),
    RemoteProfileGuardianRow: (r, c) => _applyProfileGuardian(r as RemoteProfileGuardianRow, cache: c),
    RemoteObservationRow: (r, c) => _applyObservation(r as RemoteObservationRow, onlyExisting: false, cache: c),
    RemoteProfileModeRow: (r, c) => _applyProfileMode(r as RemoteProfileModeRow, onlyExisting: false, cache: c),
    RemoteCycleOverrideRow: (r, c) => _applyCycleOverride(r as RemoteCycleOverrideRow, onlyExisting: false, cache: c),
    RemoteCareNoteRow: (r, c) => _applyCareNote(r as RemoteCareNoteRow, onlyExisting: false, cache: c),
    RemoteVisitPrepItemRow: (r, c) => _applyVisitPrepItem(r as RemoteVisitPrepItemRow, onlyExisting: false, cache: c),
    RemoteDayEntryMergeEventRow: (r, c) => _applyMergeEvent(r as RemoteDayEntryMergeEventRow, onlyExisting: false, cache: c),
    RemoteProfileTagRegistryRow: (r, c) => _applyTagRegistryEntry(r as RemoteProfileTagRegistryRow, onlyExisting: false, cache: c),
    RemoteDeletedProfileRow: (r, c) => _applyDeletedProfile(r as RemoteDeletedProfileRow, cache: c),
  };

  /// Issue #42: builds the page-wide [_PageLookup] — one chunked
  /// `IN (...)` select per referenced table, plus one live-peers fetch for
  /// the page's live (profile, date) pairs — replacing the three per-row
  /// SELECTs the row loop used to issue (own copy, referenced parent,
  /// same-date peers; up to ~1500 statements per 500-row page). Runs inside
  /// the caller's page transaction; reads only.
  Future<_PageLookup> _prefetchPageRows(List<RemoteRow> rows) async {
    final cache = _PageLookup();
    final profileIds = <String>{
      for (final row in rows.whereType<RemoteProfileRow>()) row.id,
    };
    profileIds.addAll([
      for (final row in rows.whereType<RemoteDayEntryRow>()) row.profileId,
    ]);
    profileIds.addAll([
      for (final row in rows.whereType<RemoteProfileGuardianRow>())
        row.profileId,
    ]);
    profileIds.addAll([
      for (final row in rows.whereType<RemoteObservationRow>()) row.profileId,
    ]);
    profileIds.addAll([
      for (final row in rows.whereType<RemoteProfileModeRow>()) row.profileId,
    ]);
    profileIds.addAll([
      for (final row in rows.whereType<RemoteCycleOverrideRow>()) row.profileId,
    ]);
    profileIds.addAll([
      for (final row in rows.whereType<RemoteCareNoteRow>()) row.profileId,
    ]);
    profileIds.addAll([
      for (final row in rows.whereType<RemoteVisitPrepItemRow>()) row.profileId,
    ]);
    profileIds.addAll([
      for (final row in rows.whereType<RemoteDayEntryMergeEventRow>())
        row.profileId,
    ]);
    profileIds.addAll([
      for (final row in rows.whereType<RemoteProfileTagRegistryRow>())
        row.profileId,
    ]);
    profileIds.addAll([
      for (final row in rows.whereType<RemoteDeletedProfileRow>())
        row.profileId,
    ]);
    final dayEntryIds = <String>{
      for (final row in rows.whereType<RemoteDayEntryRow>()) row.id,
    };
    dayEntryIds.addAll([
      for (final row in rows.whereType<RemoteObservationRow>()) row.dayEntryId,
    ]);
    await _prefetchByIds(
      cache.profiles,
      profileIds,
      readChunk: (ids) =>
          (db.select(db.profiles)..where((t) => t.id.isIn(ids))).get(),
      idOf: (row) => row.id,
    );
    await _prefetchByIds(
      cache.dayEntries,
      dayEntryIds,
      readChunk: (ids) =>
          (db.select(db.dayEntries)..where((t) => t.id.isIn(ids))).get(),
      idOf: (row) => row.id,
    );
    await _prefetchByIds(
      cache.observations,
      {for (final row in rows.whereType<RemoteObservationRow>()) row.id},
      readChunk: (ids) =>
          (db.select(db.observations)..where((t) => t.id.isIn(ids))).get(),
      idOf: (row) => row.id,
    );
    await _prefetchByIds(
      cache.profileModes,
      {for (final row in rows.whereType<RemoteProfileModeRow>()) row.profileId},
      readChunk: (ids) => (db.select(
        db.profileModes,
      )..where((t) => t.profileId.isIn(ids))).get(),
      idOf: (row) => row.profileId,
    );
    await _prefetchByIds(
      cache.cycleOverrides,
      {for (final row in rows.whereType<RemoteCycleOverrideRow>()) row.id},
      readChunk: (ids) =>
          (db.select(db.cycleOverrides)..where((t) => t.id.isIn(ids))).get(),
      idOf: (row) => row.id,
    );
    await _prefetchByIds(
      cache.careNotes,
      {for (final row in rows.whereType<RemoteCareNoteRow>()) row.id},
      readChunk: (ids) =>
          (db.select(db.careNotes)..where((t) => t.id.isIn(ids))).get(),
      idOf: (row) => row.id,
    );
    await _prefetchByIds(
      cache.visitPrepItems,
      {for (final row in rows.whereType<RemoteVisitPrepItemRow>()) row.id},
      readChunk: (ids) =>
          (db.select(db.visitPrepItems)..where((t) => t.id.isIn(ids))).get(),
      idOf: (row) => row.id,
    );
    await _prefetchByIds(
      cache.dayEntryMergeEvents,
      {for (final row in rows.whereType<RemoteDayEntryMergeEventRow>()) row.id},
      readChunk: (ids) => (db.select(db.dayEntryMergeEvents)
            ..where((t) => t.id.isIn(ids)))
          .get(),
      idOf: (row) => row.id,
    );
    await _prefetchByIds(
      cache.profileTagRegistry,
      {for (final row in rows.whereType<RemoteProfileTagRegistryRow>()) row.id},
      readChunk: (ids) => (db.select(db.profileTagRegistry)
            ..where((t) => t.id.isIn(ids)))
          .get(),
      idOf: (row) => row.id,
    );
    await _prefetchByIds(
      cache.guardians,
      {for (final row in rows.whereType<RemoteProfileGuardianRow>()) row.id},
      readChunk: (ids) =>
          (db.select(db.profileGuardians)..where((t) => t.id.isIn(ids))).get(),
      idOf: (row) => row.id,
    );
    await _prefetchLivePeers(cache, rows);
    return cache;
  }

  /// [_prefetchPageRows]'s per-table filler: chunked `IN (...)` selects,
  /// every prefetched id ending up a map key (found rows, or `null` for
  /// known-absent).
  Future<void> _prefetchByIds<T extends DataClass>(
    Map<String, T?> into,
    Set<String> ids, {
    required Future<List<T>> Function(List<String> ids) readChunk,
    required String Function(T row) idOf,
  }) async {
    if (ids.isEmpty) return;
    for (final chunk in chunkedBy(ids.toList(), kSyncBatchChunkSize)) {
      for (final row in await readChunk(chunk)) {
        into[idOf(row)] = row;
      }
    }
    for (final id in ids) {
      into.putIfAbsent(id, () => null);
    }
  }

  /// [_prefetchPageRows]'s same-date peer fetch: one chunked select over
  /// the page's live rows' profiles (all live entries of those profiles,
  /// id-ordered like the live query it replaces), kept only for the
  /// (profile, date) pairs the page actually resolves.
  Future<void> _prefetchLivePeers(
    _PageLookup cache,
    List<RemoteRow> rows,
  ) async {
    final datesByProfile = <String, Set<String>>{};
    for (final row in rows.whereType<RemoteDayEntryRow>()) {
      if (row.deletedAt == null) {
        datesByProfile.putIfAbsent(row.profileId, () => {}).add(row.localDate);
      }
    }
    if (datesByProfile.isEmpty) return;
    for (final chunk in chunkedBy(
      datesByProfile.keys.toList(),
      kSyncBatchChunkSize,
    )) {
      final live =
          await (db.select(db.dayEntries)
                ..where((t) => t.profileId.isIn(chunk) & t.deletedAt.isNull())
                ..orderBy([(t) => OrderingTerm(expression: t.id)]))
              .get();
      for (final row in live) {
        if (datesByProfile[row.profileId]?.contains(row.localDate) ?? false) {
          cache.addLivePeer(row);
        }
      }
    }
    for (final entry in datesByProfile.entries) {
      for (final date in entry.value) {
        cache.noteLivePeerPair(entry.key, date);
      }
    }
  }

  /// Issue #42: the cached read every per-row by-id lookup in the apply
  /// path funnels through — the prefetched value when the page prefetched
  /// [id] (found *or* known-absent), otherwise the live per-row SELECT the
  /// pre-#42 code always issued (never wrong, just unbatched).
  Future<T?> _lookupCached<T extends DataClass>(
    _PageLookup? cache,
    Map<String, T?> Function(_PageLookup) mapOf,
    String id,
    Future<T?> Function(String) live,
  ) async {
    final known = cache == null ? null : mapOf(cache);
    if (known == null || !known.containsKey(id)) return live(id);
    return known[id];
  }

  /// Issue #42: the cached same-date peer read — the prefetched,
  /// write-through-maintained list when the page prefetched the pair,
  /// otherwise the live `_liveDayEntries` query.
  Future<List<DayEntry>> _livePeersCached(
    _PageLookup? cache,
    String profileId,
    String localDate,
  ) async {
    if (cache == null) return _liveDayEntries(profileId, localDate);
    return cache.livePeers[_PageLookup.peerKey(profileId, localDate)] ??
        _liveDayEntries(profileId, localDate);
  }

  Future<void> _updateTableCursor(SyncTable table, int newCursor) async {
    await _ensureSyncStateRow();
    await (db.update(db.syncState)..where((t) => t.id.equals(1)))
        .write(_cursorCompanions[table]!(newCursor));
  }

  /// The per-table pull-cursor companion for [_updateTableCursor] — a map
  /// rather than an exhaustive switch since Issue #130's tenth SyncTable
  /// (the same growth rationale as [_pageRowAppliers] above). Issue #525:
  /// profileGuardians has a persisted cursor too; Issue #597:
  /// deletedProfiles likewise.
  static final Map<SyncTable, SyncStateCompanion Function(int)>
      _cursorCompanions = {
    SyncTable.profiles: (c) => SyncStateCompanion(cursorProfiles: Value(c)),
    SyncTable.dayEntries: (c) => SyncStateCompanion(cursorDayEntries: Value(c)),
    SyncTable.observations: (c) => SyncStateCompanion(cursorObservations: Value(c)),
    SyncTable.profileModes: (c) => SyncStateCompanion(cursorProfileModes: Value(c)),
    SyncTable.cycleOverrides: (c) => SyncStateCompanion(cursorCycleOverrides: Value(c)),
    SyncTable.careNotes: (c) => SyncStateCompanion(cursorCareNotes: Value(c)),
    SyncTable.visitPrepItems: (c) => SyncStateCompanion(cursorVisitPrepItems: Value(c)),
    SyncTable.dayEntryMergeEvents: (c) => SyncStateCompanion(cursorDayEntryMergeEvents: Value(c)),
    SyncTable.profileTagRegistry: (c) => SyncStateCompanion(cursorProfileTagRegistry: Value(c)),
    SyncTable.profileGuardians: (c) => SyncStateCompanion(cursorProfileGuardians: Value(c)),
    SyncTable.deletedProfiles: (c) => SyncStateCompanion(cursorDeletedProfiles: Value(c)),
  };

  /// Applies one full-reconcile page (rows of one or more tables) in ONE
  /// transaction without touching any cursor (KTD2). Same per-row rules as
  /// [applyRemoteProfile] / [applyRemoteDayEntry] / [applyRemoteObservation];
  /// profiles, then day entries, then observations, then the two Issue
  /// #188 tables (both reference only a profile, which is already applied
  /// by the time their turns come). A throwing row rolls the page back —
  /// callers that need per-row independence fall back to the single-row
  /// applies. Issue #42: the per-row lookups run against a page-wide
  /// batched prefetch (see [_PageLookup]) built inside the same
  /// transaction.
  Future<void> applyRemoteRows(List<RemoteRow> rows) async {
    await db.transaction(() async {
      final cache = await _prefetchPageRows(rows);
      await _applyEach<RemoteProfileRow>(
        rows,
        cache,
        (row, c) => _applyProfile(row, onlyExisting: false, cache: c),
      );
      await _applyEach<RemoteProfileGuardianRow>(
        rows,
        cache,
        (row, c) => _applyProfileGuardian(row, cache: c),
      );
      await _applyEach<RemoteDayEntryRow>(
        rows,
        cache,
        (row, c) => _applyDayEntry(row, onlyExisting: false, cache: c),
      );
      await _applyEach<RemoteObservationRow>(
        rows,
        cache,
        (row, c) => _applyObservation(row, onlyExisting: false, cache: c),
      );
      await _applyEach<RemoteProfileModeRow>(
        rows,
        cache,
        (row, c) => _applyProfileMode(row, onlyExisting: false, cache: c),
      );
      await _applyEach<RemoteCycleOverrideRow>(
        rows,
        cache,
        (row, c) => _applyCycleOverride(row, onlyExisting: false, cache: c),
      );
      await _applyEach<RemoteCareNoteRow>(
        rows,
        cache,
        (row, c) => _applyCareNote(row, onlyExisting: false, cache: c),
      );
      await _applyEach<RemoteVisitPrepItemRow>(
        rows,
        cache,
        (row, c) => _applyVisitPrepItem(row, onlyExisting: false, cache: c),
      );
      // Issue #130: merge events follow the care tables (a row references
      // only a profile, already applied by the time its turn comes).
      await _applyEach<RemoteDayEntryMergeEventRow>(
        rows,
        cache,
        (row, c) => _applyMergeEvent(row, onlyExisting: false, cache: c),
      );
      // Issue #257: the tag registry follows merge events (a row
      // references only a profile; nothing references the registry).
      await _applyEach<RemoteProfileTagRegistryRow>(
        rows,
        cache,
        (row, c) => _applyTagRegistryEntry(row, onlyExisting: false, cache: c),
      );
      // Issue #522: last, so a deletion signal for a profile that also had
      // ordinary content rows in this same heterogeneous batch wins over
      // them — the wipe is the final word, never undone by a row applied
      // earlier in this loop.
      await _applyEach<RemoteDeletedProfileRow>(
        rows,
        cache,
        (row, c) => _applyDeletedProfile(row, cache: c),
      );
    });
  }

  /// [applyRemoteRows]'s per-type dispatch, split out (issue #525 review)
  /// so that method reads as a flat sequence of statements with no
  /// decision points of its own, instead of nine `for` loops whose branch
  /// count kept pushing its CRAP score over the gate as tables were added.
  /// This one loop is exercised once per type instead.
  Future<void> _applyEach<T extends RemoteRow>(
    List<RemoteRow> rows,
    _PageLookup cache,
    Future<void> Function(T row, _PageLookup cache) apply,
  ) async {
    for (final row in rows.whereType<T>()) {
      await apply(row, cache);
    }
  }

  /// Applies the server's `resolved` copies returned by a push (rows the
  /// server tombstoned by resolution or declined as older): same rules as
  /// [applyRemoteProfile] / [applyRemoteDayEntry] / [applyRemoteObservation] /
  /// [applyRemoteProfileMode] / [applyRemoteCycleOverride], written with
  /// `dirty = false`, profiles before day entries before observations
  /// before the two Issue #188 tables. Ids not held locally are no-ops — a
  /// resolution never inserts. One transaction for the batch.
  Future<void> applyResolved(List<RemoteRow> rows) async {
    await db.transaction(() async {
      for (final row in rows.whereType<RemoteProfileRow>()) {
        await _applyProfile(row, onlyExisting: true);
      }
      for (final row in rows.whereType<RemoteDayEntryRow>()) {
        await _applyDayEntry(row, onlyExisting: true);
      }
      for (final row in rows.whereType<RemoteObservationRow>()) {
        await _applyObservation(row, onlyExisting: true);
      }
      for (final row in rows.whereType<RemoteProfileModeRow>()) {
        await _applyProfileMode(row, onlyExisting: true);
      }
      for (final row in rows.whereType<RemoteCycleOverrideRow>()) {
        await _applyCycleOverride(row, onlyExisting: true);
      }
      for (final row in rows.whereType<RemoteCareNoteRow>()) {
        await _applyCareNote(row, onlyExisting: true);
      }
      for (final row in rows.whereType<RemoteVisitPrepItemRow>()) {
        await _applyVisitPrepItem(row, onlyExisting: true);
      }
      for (final row in rows.whereType<RemoteDayEntryMergeEventRow>()) {
        await _applyMergeEvent(row, onlyExisting: true);
      }
      for (final row in rows.whereType<RemoteProfileTagRegistryRow>()) {
        await _applyTagRegistryEntry(row, onlyExisting: true);
      }
    });
  }

  /// Issue #523: the atomic entry point for one push batch's storage-side
  /// outcome — clearing `dirty` on every [accepted] row ([markPushed]) and
  /// applying the server's [resolved] copies ([applyResolved]), all in ONE
  /// `db.transaction()`.
  ///
  /// Before this method existed, `SupabaseSyncApply.applyPushResult` ran
  /// these as separate transactions (each `markPushed` call is its own
  /// atomic write; `applyResolved` opens its own transaction afterwards). A
  /// crash — or a failing write — between the last `markPushed` and
  /// `applyResolved` left a *declined* row `dirty = false` holding the
  /// client's LOSING value: a declined row is never `UPDATE`d server-side,
  /// so its `server_version` never advances past the client's persisted
  /// cursor, and the incremental pull never corrects it either. The
  /// divergence was silent and permanent until the next 24h full reconcile
  /// happened to re-page that row.
  ///
  /// `db.transaction()` nests safely (drift runs a nested call in the
  /// existing transaction zone rather than opening a second one — see
  /// `ConnectionUser.transaction` in the `drift` package), so this method
  /// simply calls the two already-transactional pieces from within one
  /// outer transaction: either the whole batch's outcome lands, or a
  /// failure partway through (a resolved row whose referenced parent is not
  /// held locally, say) rolls back every `markPushed` write alongside it,
  /// and the next cycle's dirty scan sees the row still dirty and pushes it
  /// again — never a mix of "pushed" and "wrong content".
  Future<void> applyPushResult({
    required List<({SyncTable table, String id, int localRevAtPush})>
        accepted,
    required List<RemoteRow> resolved,
  }) async {
    await db.transaction(() async {
      // Issue #42: the per-row `markPushed` loop this replaced issued one
      // UPDATE per accepted row (up to PushBatch.maxRows per table per
      // batch); [markPushedBatch] folds the same guarded UPDATEs into one
      // statement per chunk, with the identical `local_rev` guard.
      if (accepted.isNotEmpty) {
        await markPushedBatch(accepted);
      }
      if (resolved.isNotEmpty) {
        await applyResolved(resolved);
      }
    });
  }

  // ---------------------------------------------------------------- internal

  Future<bool> _applyProfile(
    RemoteProfileRow remote, {
    required bool onlyExisting,
    _PageLookup? cache,
  }) async {
    final local = await _lookupCached(
      cache,
      (c) => c.profiles,
      remote.id,
      _profileOrNull,
    );
    if (local == null && onlyExisting) return false;
    // LLA-041: a row `_tombstoneRevokedSharedProfile` wiped for a guardian
    // revocation carries `accessRevokedAt` non-null and, deliberately, an
    // untouched `updated_at` — which, for a row that was dirty with an
    // unpushed clock-ahead edit at wipe time, can be newer than any
    // timestamp the server will ever deliver for it again. The ordinary
    // per-id rule would then keep the wiped row forever and a later
    // re-share could never restore it. Bypass that rule entirely while the
    // marker is set: any remote delivery — live or tombstoned — wins
    // unconditionally, and the write below always clears the marker, so
    // normal per-id LWW resumes from the restored value.
    final bypassLww = local?.accessRevokedAt != null;
    if (local != null &&
        !bypassLww &&
        !remoteWinsById(
            localUpdatedAt: local.updatedAt,
            remoteUpdatedAt: remote.updatedAt)) {
      return false;
    }
    final tombstone = remote.isTombstone;
    final updatedAt = remote.updatedAt.toUtc();
    final deletedAt = remote.deletedAt?.toUtc();
    if (local == null) {
      // Issue #42: insertReturning (SQL RETURNING, no extra statement)
      // yields the stored row for the page cache — a day entry later in
      // the same heterogeneous page reads its profile through the cache
      // and must see this insert.
      final written = await db
          .into(db.profiles)
          .insertReturning(
            ProfilesCompanion.insert(
              id: remote.id,
              displayName: tombstone ? '' : remote.displayName,
              isMinor: remote.isMinor,
              sortOrder: Value(remote.sortOrder),
              archivedAt: Value(remote.archivedAt?.toUtc()),
              createdAt: remote.createdAt.toUtc(),
              updatedAt: updatedAt,
              deletedAt: Value(deletedAt),
              dirty: const Value(false),
              localRev: const Value(0),
              mode: Value(remote.mode),
              bbtUnit: Value(remote.bbtUnit),
              weightUnit: Value(remote.weightUnit),
              trackingPreferences: Value(remote.trackingPreferences),
              birthYear: Value(remote.birthYear),
              relationship: Value(remote.relationship),
              transferredAt: Value(remote.transferredAt?.toUtc()),
              transferredToUserId: Value(remote.transferredToUserId),
              lastPeriodStart: Value(remote.lastPeriodStart),
              typicalCycleLengthDays: Value(remote.typicalCycleLengthDays),
              typicalPeriodLengthDays: Value(remote.typicalPeriodLengthDays),
              // Issue #637, LLA-039: a fresh local row from a genuine remote
              // delivery has, by definition, just been confirmed against
              // the server's real bbt_unit/weight_unit.
              unitsUnconfirmed: const Value(false),
            ),
          );
      cache?.profiles[written.id] = written;
      return true;
    }
    final written =
        await (db.update(
          db.profiles,
        )..where((t) => t.id.equals(remote.id))).writeReturning(
          ProfilesCompanion(
            displayName: Value(tombstone ? '' : remote.displayName),
            isMinor: Value(remote.isMinor),
            sortOrder: Value(remote.sortOrder),
            archivedAt: Value(remote.archivedAt?.toUtc()),
            createdAt: Value(remote.createdAt.toUtc()),
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            dirty: const Value(false),
            mode: Value(remote.mode),
            bbtUnit: Value(remote.bbtUnit),
            weightUnit: Value(remote.weightUnit),
            trackingPreferences: Value(remote.trackingPreferences),
            birthYear: Value(remote.birthYear),
            relationship: Value(remote.relationship),
            transferredAt: Value(remote.transferredAt?.toUtc()),
            transferredToUserId: Value(remote.transferredToUserId),
            lastPeriodStart: Value(remote.lastPeriodStart),
            typicalCycleLengthDays: Value(remote.typicalCycleLengthDays),
            typicalPeriodLengthDays: Value(remote.typicalPeriodLengthDays),
            // LLA-041: any remote delivery reaching this write — including the
            // bypass path above — is a genuine server value, so the eviction
            // marker (if any) is cleared and ordinary per-id LWW resumes for
            // whatever comes next.
            accessRevokedAt: const Value(null),
            // Issue #637, LLA-039: this write is a genuine remote delivery
            // (the per-id rule already said remote beats — or bypasses — the
            // local copy), so bbt_unit/weight_unit above are the server's real
            // values now, confirmed.
            unitsUnconfirmed: const Value(false),
          ),
        );
    cache?.profiles[written.first.id] = written.first;
    return true;
  }

  Future<bool> _applyProfileGuardian(
    RemoteProfileGuardianRow remote, {
    _PageLookup? cache,
  }) async {
    // Referential integrity up front, mirroring the day-entry rule: a
    // guardian row whose profile is not held locally yet (invite accepted
    // on another device, profile page still in flight) is a typed,
    // retryable failure - never a raw FK exception that wedges the cycle.
    // Retried only when [remote] is `accepted`, where the profile really is
    // expected to show up (a later page, or the next reconcile) and an
    // unresolvable row is a genuine inconsistency worth surfacing. A
    // pending or revoked membership whose profile was never held locally
    // never gets one: `profiles_select_guardians` only returns a profile
    // row for an accepted membership, so this device will never receive it
    // for as long as the row stays non-accepted, and `applyRemotePage` is
    // one transaction per page with no persisted guardian cursor - throwing
    // here would roll the whole page back and re-fail identically forever
    // (finding #8). Skipped instead: nothing to apply, nothing lost.
    if (await _lookupCached(
          cache,
          (c) => c.profiles,
          remote.profileId,
          _profileOrNull,
        ) ==
        null) {
      if (remote.status != 'accepted') return false;
      throw RetryableSyncApplyError(
          'profile_guardian ${remote.id} references a profile not held locally');
    }

    final existing = await _lookupCached(
      cache,
      (c) => c.guardians,
      remote.id,
      _guardianOrNull,
    );

    // LLA-035: ordered by the server-owned `server_version`, not
    // `updated_at` — this table's `updated_at` is directly client-writable
    // (see `remoteWinsByVersion`'s doc comment), so a per-id-by-time rule
    // here would let an accepted guardian's forged future timestamp
    // permanently outrank a later, authoritative revocation.
    if (existing != null &&
        !remoteWinsByVersion(
            localServerVersion: existing.serverVersion,
            remoteServerVersion: remote.serverVersion)) {
      return false;
    }

    // R5: when this device's bound user is no longer an accepted guardian,
    // access to the shared profile is revoked locally too - the profile
    // and its day entries are tombstoned (payload cleared, not dirty, so
    // the wipe is never pushed back) in the same transaction as the
    // membership upsert.
    final boundUserId = (await readSyncState()).boundUserId;
    if (boundUserId != null &&
        remote.userId == boundUserId &&
        remote.status != 'accepted') {
      await _tombstoneRevokedSharedProfile(
        remote.profileId,
        remote.updatedAt,
        cache: cache,
      );
    }

    // Issue #42: insertReturning + DoUpdate is exactly insertOnConflictUpdate
    // (see drift's own doc on the latter) while also yielding the written
    // row for the page cache at no extra statement cost.
    final written = await db
        .into(db.profileGuardians)
        .insertReturning(
          ProfileGuardiansCompanion.insert(
            id: remote.id,
            profileId: remote.profileId,
            userId: remote.userId,
            role: remote.role,
            status: Value(remote.status),
            displayName: Value(remote.displayName),
            invitedBy: Value(remote.invitedBy),
            createdAt: remote.createdAt.toUtc(),
            updatedAt: remote.updatedAt.toUtc(),
            serverVersion: Value(remote.serverVersion),
          ),
          onConflict: DoUpdate(
            (_) => ProfileGuardiansCompanion.insert(
              id: remote.id,
              profileId: remote.profileId,
              userId: remote.userId,
              role: remote.role,
              status: Value(remote.status),
              displayName: Value(remote.displayName),
              invitedBy: Value(remote.invitedBy),
              createdAt: remote.createdAt.toUtc(),
              updatedAt: remote.updatedAt.toUtc(),
              serverVersion: Value(remote.serverVersion),
            ),
          ),
        );
    cache?.guardians[written.id] = written;
    return true;
  }

  /// Revocation wipe (R5): tombstones the shared profile and every live day
  /// entry of it at the server's revocation timestamp. Tombstones carry no
  /// payload (issue #224: `flow` is cleared alongside `note`/`tags`, same as
  /// every other tombstone-producing path) and are marked not dirty - the
  /// server already knows, so the wipe must never be pushed back. Rows with
  /// unpushed local edits are wiped too: once revoked, the server rejects
  /// those pushes regardless.
  ///
  /// Issue #128: the profile's care notes and visit-prep items are wiped
  /// the same way (payload cleared, not dirty). They are the same category
  /// of health content as day entries — leaving them readable offline
  /// after revocation would keep a removed guardian's access alive on the
  /// device.
  ///
  /// Issue #532: three more per-profile tables carry the same category of
  /// health content and were missing from this wipe entirely — because the
  /// wipe is an `UPDATE`, not a `DELETE`, sqlite's FK cascade never fires
  /// for them (the per-day-entry observation cascade in
  /// `softDeleteDayEntry` only runs for a *local* delete, and this
  /// revocation path bypasses it with these raw bulk updates):
  /// * `observations` — payload cleared exactly like [_softDeleteObservation]
  ///   (`category`/`observedAt`/`code`/`valueNum`/`valueText`/`unit`/
  ///   `intensity`/`raw` cleared, `excluded` reset to false; `sourceId`/
  ///   `importId` survive, mirroring that method's own provenance
  ///   exception).
  /// * `cycle_overrides` — payload cleared exactly like
  ///   [softDeleteCycleOverride] (`excludedFromAverage`/`manualStart` reset
  ///   to false, `noteId` cleared; `cycleStartDate` (identity) kept).
  /// * `profile_modes` — this table has NO tombstone (Issue #188's settled
  ///   shape: an absent row already means `tracking`), so there is no
  ///   `deletedAt` to set; the row is instead reset to that same absent-row
  ///   default (`mode = tracking`, every optional column cleared) so a
  ///   removed guardian's device stops showing the birth-control method or
  ///   life-stage mode the moment access is revoked, exactly like every
  ///   other table here stops showing its content.
  ///
  /// `updated_at` is deliberately left untouched (finding #9): neither
  /// `revoke_guardian` nor `accept_guardian_invitation` bumps the server's
  /// `profiles.updated_at`, so stamping the tombstone with `revokedAt` would
  /// make it permanently newer than any row a later re-share can ever
  /// deliver - `remoteWinsById` (KTD5) would then keep the tombstone forever
  /// and the profile could never come back. Leaving `updated_at` where it
  /// was means a later server row (even one carrying its original,
  /// never-touched timestamp) ties or wins normally and un-tombstones it.
  /// `profile_modes` has no per-id `updated_at` conflict of its own to
  /// protect here (a later remote row still overwrites this reset row
  /// outright under [_applyProfileMode]'s per-id LWW rule), so it is left
  /// alone for the same reason the others are.
  ///
  /// LLA-041 (issue #635): leaving `updated_at` untouched only makes the
  /// *clean* re-share case above work — a row that was dirty with an
  /// unpushed, clock-ahead edit at wipe time keeps that same too-new
  /// `updated_at`, which then permanently outranks the server's real value
  /// too. `profiles.accessRevokedAt` is stamped here precisely to cover
  /// that gap: [_applyProfile] bypasses the per-id rule entirely while it
  /// is set, so any later delivery of this profile id restores it
  /// unconditionally rather than losing to a stale local timestamp that
  /// was never a legitimate LWW competitor in the first place.
  Future<void> _tombstoneRevokedSharedProfile(
    String profileId,
    DateTime revokedAt, {
    _PageLookup? cache,
  }) async {
    // Issue #42: the bulk UPDATEs below rewrite every row of [profileId]
    // across seven tables — rows a page-wide lookup cache may hold copies
    // of. Evicting the profile from the cache (rather than reasoning about
    // which stale copies stay decision-equivalent) makes every later read
    // in the same page fall back to a live SELECT, which is always
    // correct.
    cache?.evictProfile(profileId);
    final stamp = revokedAt.toUtc();
    await (db.update(db.dayEntries)
          ..where((t) =>
              t.profileId.equals(profileId) & t.deletedAt.isNull()))
        .write(DayEntriesCompanion(
          flow: const Value(FlowLevel.none),
          note: const Value(null),
          tags: const Value(<String>[]),
          deletedAt: Value(stamp),
          dirty: const Value(false),
        ));
    await (db.update(db.observations)
          ..where((t) =>
              t.profileId.equals(profileId) & t.deletedAt.isNull()))
        .write(ObservationsCompanion(
          category: const Value(null),
          observedAt: const Value(null),
          code: const Value(null),
          valueNum: const Value(null),
          valueText: const Value(null),
          unit: const Value(null),
          intensity: const Value(null),
          excluded: const Value(false),
          raw: const Value(null),
          deletedAt: Value(stamp),
          dirty: const Value(false),
        ));
    await (db.update(db.cycleOverrides)
          ..where((t) =>
              t.profileId.equals(profileId) & t.deletedAt.isNull()))
        .write(CycleOverridesCompanion(
          excludedFromAverage: const Value(false),
          manualStart: const Value(false),
          noteId: const Value(null),
          deletedAt: Value(stamp),
          dirty: const Value(false),
        ));
    await (db.update(db.profileModes)
          ..where((t) => t.profileId.equals(profileId)))
        .write(const ProfileModesCompanion(
          mode: Value('tracking'),
          modeStartedOn: Value(null),
          birthControlMethod: Value(null),
          birthControlStartedOn: Value(null),
          birthControlStoppedOn: Value(null),
          healthSyncConsent: Value(false),
          dirty: Value(false),
        ));
    await (db.update(db.careNotes)
          ..where((t) =>
              t.profileId.equals(profileId) & t.deletedAt.isNull()))
        .write(CareNotesCompanion(
          body: const Value(''),
          deletedAt: Value(stamp),
          dirty: const Value(false),
        ));
    await (db.update(db.visitPrepItems)
          ..where((t) =>
              t.profileId.equals(profileId) & t.deletedAt.isNull()))
        .write(VisitPrepItemsCompanion(
          body: const Value(''),
          isChecked: const Value(false),
          checkedByUserId: const Value(null),
          checkedAt: const Value(null),
          deletedAt: Value(stamp),
          dirty: const Value(false),
        ));
    // Issue #130: the profile's merge-disclosure rows are hard-deleted
    // locally (the table has no tombstone). They describe discarded health
    // content on a profile this guardian can no longer see — leaving them
    // readable offline would keep the removed guardian's access alive,
    // exactly the gap the wipes above close for every other table. Not
    // dirty, never pushed back: the server's own rows are the authority.
    await (db.delete(db.dayEntryMergeEvents)
          ..where((t) => t.profileId.equals(profileId)))
        .go();
    // Issue #257: the profile's custom-tag registry rows are TOMBSTONED,
    // not hard-deleted (they are ordinary synced rows whose deletion the
    // server propagates through the ordinary pull) — payload cleared per
    // the table's structural CHECK, `code` surviving, and the local labels
    // leave the device exactly like every other wiped table above. Not
    // dirty, never pushed back: the server's own wipe is the authority.
    await (db.update(db.profileTagRegistry)
          ..where((t) =>
              t.profileId.equals(profileId) & t.deletedAt.isNull()))
        .write(ProfileTagRegistryCompanion(
          displayName: const Value(''),
          category: const Value(''),
          intensityEnabled: const Value(false),
          hiddenAt: const Value(null),
          sortOrder: const Value(null),
          deletedAt: Value(stamp),
          dirty: const Value(false),
        ));
    await (db.update(db.profiles)
          ..where((t) => t.id.equals(profileId) & t.deletedAt.isNull()))
        .write(ProfilesCompanion(
          displayName: const Value(''),
          deletedAt: Value(stamp),
          dirty: const Value(false),
          // LLA-041: marks this row's `updated_at` as a cache-eviction
          // artifact rather than a genuine LWW competitor — see
          // [_applyProfile]'s bypass and this method's doc comment.
          accessRevokedAt: Value(stamp),
        ));
  }

  /// Issue #522: applies a `deleted_profiles` row — the narrow tombstone a
  /// server-side hard purge (`delete_profile_data()`/`delete_account_data()`)
  /// writes for a profile it physically `DELETE`s, since the ordinary
  /// incremental pull and 24h reconcile only ever transport rows that still
  /// exist. Cascades exactly like a guardian revocation ([_applyProfileGuardian]'s
  /// [_tombstoneRevokedSharedProfile] call, issue #532): every profile-scoped
  /// content table is wiped the same way and the local profile is
  /// tombstoned, all in the caller's transaction. Idempotent: a profile
  /// already tombstoned, or never held locally at all, still runs the wipe
  /// harmlessly (every `UPDATE` matches zero rows).
  ///
  /// Unlike [_tombstoneRevokedSharedProfile]'s revocation case, there is no
  /// "leave `updated_at` alone so a later re-share can win normally" concern
  /// here — a hard-purged profile's server row is gone permanently, so
  /// nothing will ever compete with this tombstone under KTD5's per-id rule.
  Future<void> _applyDeletedProfile(
    RemoteDeletedProfileRow remote, {
    _PageLookup? cache,
  }) => _tombstoneRevokedSharedProfile(
    remote.profileId,
    remote.deletedAt,
    cache: cache,
  );

  /// Issue #472: the local half of `ProfilesRepository.applyServerPurge` —
  /// applies the SAME tombstone wipe [_applyDeletedProfile] applies for a
  /// server-delivered `deleted_profiles` row, but immediately, right after
  /// the caller's own `delete_profile_data()` RPC call succeeds, rather
  /// than waiting for the next sync pull to notice. This is deliberately
  /// not a new/parallel wipe: it is the exact same
  /// [_tombstoneRevokedSharedProfile] call [_applyDeletedProfile] and
  /// guardian-revocation ([_applyProfileGuardian]'s R5 cascade) both use,
  /// so local state converges identically no matter which path notices the
  /// purge first — a later delivery of the real `deleted_profiles` row (or
  /// another device's own local purge) re-applies the same wipe harmlessly.
  Future<void> applyLocalProfilePurge(String profileId) =>
      _tombstoneRevokedSharedProfile(profileId, _now());

  Future<bool> _applyDayEntry(
    RemoteDayEntryRow remote, {
    required bool onlyExisting,
    _PageLookup? cache,
  }) async {
    final local = await _lookupCached(
      cache,
      (c) => c.dayEntries,
      remote.id,
      _dayEntryOrNull,
    );
    if (_shouldSkipDayEntryApply(
        local: local, onlyExisting: onlyExisting, remote: remote)) {
      return false;
    }
    // Referential integrity is checked up front so the failure is a typed,
    // retryable one rather than a raw constraint exception from sqlite.
    await _ensureDayEntryProfileExists(remote, cache: cache);
    await _recordResolvedOverwriteIfAny(
      remote,
      local: local,
      onlyExisting: onlyExisting,
    );

    var updatedAt = remote.updatedAt.toUtc();
    var deletedAt = remote.deletedAt?.toUtc();
    var tags = remote.tags;
    var dirty = false;
    if (deletedAt == null) {
      (updatedAt, deletedAt, tags, dirty) = await _resolveSameDateConflicts(
        remote,
        updatedAt,
        cache: cache,
      );
    }
    final tombstone = deletedAt != null;
    if (local == null) {
      final written = await db
          .into(db.dayEntries)
          .insertReturning(
            DayEntriesCompanion.insert(
              id: remote.id,
              profileId: remote.profileId,
              localDate: remote.localDate,
              tz: remote.tz,
              flow: _dayEntryFlow(tombstone, remote),
              tags: Value(_dayEntryTags(tombstone, tags)),
              note: Value(_dayEntryNote(tombstone, remote)),
              pms: Value(_dayEntryPms(tombstone, remote)),
              updatedAt: updatedAt,
              deletedAt: Value(deletedAt),
              dirty: Value(dirty),
              localRev: Value(dirty ? 1 : 0),
              loggedByUserId: Value(remote.loggedByUserId),
              lastModifiedByUserId: Value(remote.lastModifiedByUserId),
              // Issue #159: never cleared for a tombstone (unlike
              // flow/tags/note above) -- provenance survives a delete.
              source: Value(remote.source),
              sourceId: Value(remote.sourceId),
              importId: Value(remote.importId),
              // Issue #637, LLA-039: a fresh local row from a genuine remote
              // delivery has, by definition, just been confirmed against
              // the server's real pms.
              pmsUnconfirmed: const Value(false),
            ),
          );
      cache?.storeDayEntry(written);
      return true;
    }
    final written =
        await (db.update(
          db.dayEntries,
        )..where((t) => t.id.equals(remote.id))).writeReturning(
          DayEntriesCompanion(
            profileId: Value(remote.profileId),
            localDate: Value(remote.localDate),
            tz: Value(remote.tz),
            flow: Value(_dayEntryFlow(tombstone, remote)),
            tags: Value(_dayEntryTags(tombstone, tags)),
            note: Value(_dayEntryNote(tombstone, remote)),
            pms: Value(_dayEntryPms(tombstone, remote)),
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            dirty: Value(dirty),
            localRev: dirty ? Value(local.localRev + 1) : const Value.absent(),
            loggedByUserId: Value(
              remote.loggedByUserId ?? local.loggedByUserId,
            ),
            lastModifiedByUserId: Value(
              remote.lastModifiedByUserId ?? local.lastModifiedByUserId,
            ),
            source: Value(remote.source),
            sourceId: Value(remote.sourceId),
            importId: Value(remote.importId),
            // Issue #637, LLA-039: this write is a genuine remote delivery (the
            // per-id rule already said remote beats the local copy, or this is
            // the same-date resolver's outcome), so `pms` above is the server's
            // real value now, confirmed.
            pmsUnconfirmed: const Value(false),
          ),
        );
    cache?.storeDayEntry(written.first);
    return true;
  }

  /// Issue #124 (AC4): a push resolution (`applyResolved`) overwriting a
  /// held live local copy with a differing note/flow discarded this
  /// device's values in favour of the server's kept copy — record it.
  /// Only the `onlyExisting` path: an ordinary pull overwrite is the
  /// normal change feed (the row itself carries the attribution), not a
  /// resolution. Tombstone resolutions record nothing — the resulting
  /// "removed" feed row covers them.
  Future<void> _recordResolvedOverwriteIfAny(
    RemoteDayEntryRow remote, {
    required DayEntry? local,
    required bool onlyExisting,
  }) async {
    if (onlyExisting &&
        local != null &&
        local.deletedAt == null &&
        !remote.isTombstone) {
      await _recordMergeDiscardIfAny(
        profileId: remote.profileId,
        localDateIso: remote.localDate,
        resolutionStamp: remote.updatedAt,
        winnerActorId: remote.lastModifiedByUserId ?? remote.loggedByUserId,
        loserActorId: local.lastModifiedByUserId ?? local.loggedByUserId,
        loserNote: local.note,
        winnerNote: remote.note,
        loserFlow: local.flow,
        winnerFlow: remote.flow,
        loserEntryId: remote.id,
      );
    }
  }

  /// Whether [_applyDayEntry] should no-op without writing anything:
  /// [onlyExisting] with no local row held, or the per-id rule (KTD5) says
  /// the local copy is not beaten by [remote] and stays as-is.
  bool _shouldSkipDayEntryApply({
    required DayEntry? local,
    required bool onlyExisting,
    required RemoteDayEntryRow remote,
  }) {
    if (local == null && onlyExisting) return true;
    if (local != null &&
        !remoteWinsById(
            localUpdatedAt: local.updatedAt,
            remoteUpdatedAt: remote.updatedAt)) {
      return true;
    }
    return false;
  }

  /// Throws [RetryableSyncApplyError] when [remote]'s profile is not held
  /// locally yet, checked up front so the failure is a typed, retryable one
  /// rather than a raw constraint exception from sqlite.
  Future<void> _ensureDayEntryProfileExists(
    RemoteDayEntryRow remote, {
    _PageLookup? cache,
  }) async {
    if (await _lookupCached(
          cache,
          (c) => c.profiles,
          remote.profileId,
          _profileOrNull,
        ) ==
        null) {
      throw RetryableSyncApplyError(
          'day entry ${remote.id} references a profile not held locally');
    }
  }

  /// [_applyObservation]'s referential check, split out for the same CRAP-
  /// gate reason as [_ensureDayEntryProfileExists] (issue #42 review):
  /// throws [RetryableSyncApplyError] when the observation's day entry is
  /// not held locally yet.
  Future<void> _ensureObservationDayEntryExists(
    RemoteObservationRow remote, {
    _PageLookup? cache,
  }) async {
    if (await _lookupCached(
          cache,
          (c) => c.dayEntries,
          remote.dayEntryId,
          _dayEntryOrNull,
        ) ==
        null) {
      throw RetryableSyncApplyError(
        'observation ${remote.id} references a day entry not held locally',
      );
    }
  }

  /// The redacted payload columns for an observation row: the remote values
  /// as-is when live, or every payload column cleared (`excluded` reset to
  /// `false`) for a tombstone — mirroring `_dayEntryFlow`/`_dayEntryTags`/
  /// `_dayEntryNote`'s precedent, but built once as a single record so
  /// [_applyObservation]'s insert and update branches can share it instead of
  /// repeating the same ternaries twice. Split into a cleared constant and a
  /// live builder so no single method carries ten conditionals (the CRAP
  /// gate counts each `?:`). `sourceId`/`importId` (Issue #159) are
  /// deliberately NOT part of this record — provenance survives a
  /// tombstone (unlike every column here), so [_applyObservation] always
  /// writes them from `remote` directly, tombstone or not.
  ({
    DateTime? observedAt,
    String? category,
    String? code,
    double? valueNum,
    String? valueText,
    String? unit,
    int? intensity,
    bool excluded,
    String? raw,
  }) _observationPayload(RemoteObservationRow remote, bool tombstone) =>
      tombstone ? _clearedObservationPayload : _liveObservationPayload(remote);

  /// Every payload column cleared: what a tombstone carries locally (the
  /// server's `observations_tombstone_payload_check` enforces the same).
  static const ({
    DateTime? observedAt,
    String? category,
    String? code,
    double? valueNum,
    String? valueText,
    String? unit,
    int? intensity,
    bool excluded,
    String? raw,
  }) _clearedObservationPayload = (
    observedAt: null,
    category: null,
    code: null,
    valueNum: null,
    valueText: null,
    unit: null,
    intensity: null,
    excluded: false,
    raw: null,
  );

  /// The remote values as-is for a live row.
  ({
    DateTime? observedAt,
    String? category,
    String? code,
    double? valueNum,
    String? valueText,
    String? unit,
    int? intensity,
    bool excluded,
    String? raw,
  }) _liveObservationPayload(RemoteObservationRow remote) => (
        observedAt: remote.observedAt?.toUtc(),
        category: remote.category,
        code: remote.code,
        valueNum: remote.valueNum,
        valueText: remote.valueText,
        unit: remote.unit,
        intensity: remote.intensity,
        excluded: remote.excluded,
        raw: remote.raw,
      );

  /// Issue #240: applies a server copy of an observation keyed by id — the
  /// same per-id LWW rule [_applyProfile] uses, with no same-date resolver
  /// (unlike [_applyDayEntry]): multiple live rows per (profile, date,
  /// category) are the entire point of this child table, so no local
  /// uniqueness constraint ever competes for one to win against.
  Future<bool> _applyObservation(
    RemoteObservationRow remote, {
    required bool onlyExisting,
    _PageLookup? cache,
  }) async {
    final local = await _lookupCached(
      cache,
      (c) => c.observations,
      remote.id,
      _observationOrNull,
    );
    if (local == null && onlyExisting) return false;
    if (local != null &&
        !remoteWinsById(
            localUpdatedAt: local.updatedAt,
            remoteUpdatedAt: remote.updatedAt)) {
      return false;
    }
    // Referential integrity up front, mirroring [_ensureDayEntryProfileExists]:
    // a typed, retryable failure rather than a raw constraint exception.
    await _ensureObservationDayEntryExists(remote, cache: cache);
    final tombstone = remote.isTombstone;
    final updatedAt = remote.updatedAt.toUtc();
    final deletedAt = remote.deletedAt?.toUtc();
    final payload = _observationPayload(remote, tombstone);
    if (local == null) {
      final written = await db
          .into(db.observations)
          .insertReturning(
            ObservationsCompanion.insert(
              id: remote.id,
              dayEntryId: remote.dayEntryId,
              profileId: remote.profileId,
              localDate: remote.localDate,
              observedAt: Value(payload.observedAt),
              tz: remote.tz,
              category: Value(payload.category),
              code: Value(payload.code),
              valueNum: Value(payload.valueNum),
              valueText: Value(payload.valueText),
              unit: Value(payload.unit),
              intensity: Value(payload.intensity),
              excluded: Value(payload.excluded),
              source: Value(remote.source),
              // Issue #159: sourceId/importId are never cleared for a
              // tombstone (unlike every column in `payload` above) --
              // written from `remote` directly regardless of tombstone.
              sourceId: Value(remote.sourceId),
              importId: Value(remote.importId),
              // Issue #186: the round-trip marker rides with the other
              // provenance columns (never cleared on a tombstone).
              exportedToPlatformAt: Value(remote.exportedToPlatformAt?.toUtc()),
              raw: Value(payload.raw),
              updatedAt: updatedAt,
              deletedAt: Value(deletedAt),
              dirty: const Value(false),
              localRev: const Value(0),
              loggedByUserId: Value(remote.loggedByUserId),
              lastModifiedByUserId: Value(remote.lastModifiedByUserId),
            ),
          );
      cache?.observations[written.id] = written;
      return true;
    }
    final written =
        await (db.update(
          db.observations,
        )..where((t) => t.id.equals(remote.id))).writeReturning(
          ObservationsCompanion(
            dayEntryId: Value(remote.dayEntryId),
            profileId: Value(remote.profileId),
            localDate: Value(remote.localDate),
            observedAt: Value(payload.observedAt),
            tz: Value(remote.tz),
            category: Value(payload.category),
            code: Value(payload.code),
            valueNum: Value(payload.valueNum),
            valueText: Value(payload.valueText),
            unit: Value(payload.unit),
            intensity: Value(payload.intensity),
            excluded: Value(payload.excluded),
            source: Value(remote.source),
            sourceId: Value(remote.sourceId),
            importId: Value(remote.importId),
            exportedToPlatformAt: Value(
              remote.exportedToPlatformAt?.toUtc() ??
                  local.exportedToPlatformAt,
            ),
            raw: Value(payload.raw),
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            dirty: const Value(false),
            loggedByUserId: Value(
              remote.loggedByUserId ?? local.loggedByUserId,
            ),
            lastModifiedByUserId: Value(
              remote.lastModifiedByUserId ?? local.lastModifiedByUserId,
            ),
          ),
        );
    cache?.observations[written.first.id] = written.first;
    return true;
  }

  /// Issue #188: applies a server copy of a profile mode row keyed by
  /// profile id — the same per-id LWW rule [_applyProfile] uses. No
  /// tombstone exists on this table. Throws [RetryableSyncApplyError] when
  /// the profile is not held locally yet (checked up front so the failure
  /// is typed rather than a raw constraint exception, mirroring
  /// [_ensureDayEntryProfileExists]).
  Future<bool> _applyProfileMode(
    RemoteProfileModeRow remote, {
    required bool onlyExisting,
    _PageLookup? cache,
  }) async {
    final local = await _lookupCached(
      cache,
      (c) => c.profileModes,
      remote.profileId,
      _profileModeOrNull,
    );
    if (local == null && onlyExisting) return false;
    if (local != null &&
        !remoteWinsById(
            localUpdatedAt: local.updatedAt,
            remoteUpdatedAt: remote.updatedAt)) {
      return false;
    }
    if (await _lookupCached(
          cache,
          (c) => c.profiles,
          remote.profileId,
          _profileOrNull,
        ) ==
        null) {
      throw RetryableSyncApplyError(
          'profile mode ${remote.profileId} references a profile not held locally');
    }
    final updatedAt = remote.updatedAt.toUtc();
    if (local == null) {
      final written = await db
          .into(db.profileModes)
          .insertReturning(
            ProfileModesCompanion.insert(
              profileId: remote.profileId,
              mode: Value(remote.mode),
              modeStartedOn: Value(remote.modeStartedOn),
              birthControlMethod: Value(remote.birthControlMethod),
              birthControlStartedOn: Value(remote.birthControlStartedOn),
              birthControlStoppedOn: Value(remote.birthControlStoppedOn),
              healthSyncConsent: Value(remote.healthSyncConsent),
              updatedAt: updatedAt,
              dirty: const Value(false),
              localRev: const Value(0),
            ),
          );
      cache?.profileModes[written.profileId] = written;
      return true;
    }
    final written =
        await (db.update(
          db.profileModes,
        )..where((t) => t.profileId.equals(remote.profileId))).writeReturning(
          ProfileModesCompanion(
            mode: Value(remote.mode),
            modeStartedOn: Value(remote.modeStartedOn),
            birthControlMethod: Value(remote.birthControlMethod),
            birthControlStartedOn: Value(remote.birthControlStartedOn),
            birthControlStoppedOn: Value(remote.birthControlStoppedOn),
            healthSyncConsent: Value(remote.healthSyncConsent),
            updatedAt: Value(updatedAt),
            dirty: const Value(false),
          ),
        );
    cache?.profileModes[written.first.profileId] = written.first;
    return true;
  }

  /// The redacted payload columns for a cycle override row: the remote
  /// values as-is when live, or the cleared state for a tombstone
  /// (`excluded_from_average`/`manual_start` reset to false, `note_id`
  /// nulled — mirroring the server's
  /// `cycle_overrides_tombstone_payload_check`). `cycle_start_date` is
  /// identity and always written from `remote` directly.
  ({bool excludedFromAverage, bool manualStart, String? noteId})
      _cycleOverridePayload(RemoteCycleOverrideRow remote, bool tombstone) =>
          tombstone
              ? (excludedFromAverage: false, manualStart: false, noteId: null)
              : (
                  excludedFromAverage: remote.excludedFromAverage,
                  manualStart: remote.manualStart,
                  noteId: remote.noteId,
                );

  /// Issue #188: applies a server copy of a cycle override keyed by
  /// (id, profile id) — the same per-id LWW rule [_applyObservation] uses,
  /// with no same-date resolver. A tombstone clears the payload columns
  /// (see [_cycleOverridePayload]).
  Future<bool> _applyCycleOverride(
    RemoteCycleOverrideRow remote, {
    required bool onlyExisting,
    _PageLookup? cache,
  }) async {
    final local = await _lookupCached(
      cache,
      (c) => c.cycleOverrides,
      remote.id,
      _cycleOverrideOrNullById,
    );
    if (local == null && onlyExisting) return false;
    if (local != null &&
        !remoteWinsById(
            localUpdatedAt: local.updatedAt,
            remoteUpdatedAt: remote.updatedAt)) {
      return false;
    }
    if (await _lookupCached(
          cache,
          (c) => c.profiles,
          remote.profileId,
          _profileOrNull,
        ) ==
        null) {
      throw RetryableSyncApplyError(
          'cycle override ${remote.id} references a profile not held locally');
    }
    final tombstone = remote.isTombstone;
    final updatedAt = remote.updatedAt.toUtc();
    final deletedAt = remote.deletedAt?.toUtc();
    final payload = _cycleOverridePayload(remote, tombstone);
    if (local == null) {
      final written = await db
          .into(db.cycleOverrides)
          .insertReturning(
            CycleOverridesCompanion.insert(
              id: remote.id,
              profileId: remote.profileId,
              cycleStartDate: remote.cycleStartDate,
              excludedFromAverage: Value(payload.excludedFromAverage),
              manualStart: Value(payload.manualStart),
              noteId: Value(payload.noteId),
              updatedAt: updatedAt,
              deletedAt: Value(deletedAt),
              dirty: const Value(false),
              localRev: const Value(0),
            ),
          );
      cache?.cycleOverrides[written.id] = written;
      return true;
    }
    final written =
        await (db.update(db.cycleOverrides)..where(
              (t) =>
                  t.id.equals(remote.id) & t.profileId.equals(remote.profileId),
            ))
            .writeReturning(
              CycleOverridesCompanion(
                cycleStartDate: Value(remote.cycleStartDate),
                excludedFromAverage: Value(payload.excludedFromAverage),
                manualStart: Value(payload.manualStart),
                noteId: Value(payload.noteId),
                updatedAt: Value(updatedAt),
                deletedAt: Value(deletedAt),
                dirty: const Value(false),
              ),
            );
    cache?.cycleOverrides[written.first.id] = written.first;
    return true;
  }

  /// Issue #551: the shared skeleton behind every per-id-LWW remote apply
  /// ([_applyCareNote], [_applyVisitPrepItem], and — not yet migrated,
  /// kept mechanical and reviewable — [_applyCycleOverride] and friends):
  /// read the local row, bail if [onlyExisting] and there is none, defer
  /// to [remoteWinsById] against [localUpdatedAt]/[remoteUpdatedAt],
  /// require the referenced profile to exist locally (else a
  /// [RetryableSyncApplyError] naming [entityLabel] and [remoteId]), then
  /// [insert] or [update]. Each caller still owns its own tombstone/payload
  /// shaping (e.g. redacting a tombstone's body) inside those callbacks —
  /// this only centralises the guard/bail/retryable clauses that were
  /// hand-written identically at every one of these call sites.
  Future<bool> _applyKeyedRow<TRemote, TLocal extends DataClass>({
    required TRemote remote,
    required Future<TLocal?> Function() readLocal,
    required bool onlyExisting,
    required DateTime Function(TRemote) remoteUpdatedAt,
    required DateTime Function(TLocal) localUpdatedAt,
    required String Function(TRemote) parentProfileId,
    required String entityLabel,
    required String remoteId,
    required Future<void> Function(TRemote remote) insert,
    required Future<void> Function(TRemote remote, TLocal local) update,
    _PageLookup? cache,
  }) async {
    final local = await readLocal();
    if (local == null && onlyExisting) return false;
    if (local != null &&
        !remoteWinsById(
            localUpdatedAt: localUpdatedAt(local),
            remoteUpdatedAt: remoteUpdatedAt(remote))) {
      return false;
    }
    if (await _lookupCached(
          cache,
          (c) => c.profiles,
          parentProfileId(remote),
          _profileOrNull,
        ) ==
        null) {
      throw RetryableSyncApplyError(
          '$entityLabel $remoteId references a profile not held locally');
    }
    if (local == null) {
      await insert(remote);
      return true;
    }
    await update(remote, local);
    return true;
  }

  /// Issue #128: applies a server copy of a care note keyed by id — the
  /// same per-id LWW rule [_applyCycleOverride] uses, with no resolver. A
  /// tombstone clears `body` (mirroring the server's
  /// `care_notes_tombstone_payload_check`).
  Future<bool> _applyCareNote(
    RemoteCareNoteRow remote, {
    required bool onlyExisting,
    _PageLookup? cache,
  }) {
    final tombstone = remote.isTombstone;
    final updatedAt = remote.updatedAt.toUtc();
    final deletedAt = remote.deletedAt?.toUtc();
    return _applyKeyedRow<RemoteCareNoteRow, CareNoteData>(
      remote: remote,
      readLocal: () =>
          _lookupCached(cache, (c) => c.careNotes, remote.id, _careNoteOrNull),
      onlyExisting: onlyExisting,
      remoteUpdatedAt: (r) => r.updatedAt,
      localUpdatedAt: (l) => l.updatedAt,
      parentProfileId: (r) => r.profileId,
      entityLabel: 'care note',
      remoteId: remote.id,
      insert: (r) => _insertCareNote(r, tombstone, updatedAt, deletedAt, cache),
      update: (r, local) =>
          _updateCareNote(r, local, tombstone, updatedAt, deletedAt, cache),
      cache: cache,
    );
  }

  /// The insert half of [_applyCareNote], split out so neither method
  /// exceeds the CRAP-gate complexity budget on its own.
  Future<void> _insertCareNote(
    RemoteCareNoteRow remote,
    bool tombstone,
    DateTime updatedAt,
    DateTime? deletedAt,
    _PageLookup? cache,
  ) async {
    final written = await db
        .into(db.careNotes)
        .insertReturning(
          CareNotesCompanion.insert(
            id: remote.id,
            profileId: remote.profileId,
            body: tombstone ? '' : remote.body,
            updatedAt: updatedAt,
            deletedAt: Value(deletedAt),
            dirty: const Value(false),
            localRev: const Value(0),
            loggedByUserId: Value(remote.loggedByUserId),
            lastModifiedByUserId: Value(remote.lastModifiedByUserId),
          ),
        );
    cache?.careNotes[written.id] = written;
  }

  /// The update half of [_applyCareNote], split out for the same reason. A
  /// null stamp on the remote copy never wipes a known local one (the
  /// _applyObservation precedent: pull/resolved rows always carry stamps;
  /// only a hand-built row is ever null here).
  Future<void> _updateCareNote(
    RemoteCareNoteRow remote,
    CareNoteData local,
    bool tombstone,
    DateTime updatedAt,
    DateTime? deletedAt,
    _PageLookup? cache,
  ) async {
    final written =
        await (db.update(
          db.careNotes,
        )..where((t) => t.id.equals(remote.id))).writeReturning(
          CareNotesCompanion(
            body: Value(tombstone ? '' : remote.body),
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            dirty: const Value(false),
            loggedByUserId: Value(
              remote.loggedByUserId ?? local.loggedByUserId,
            ),
            lastModifiedByUserId: Value(
              remote.lastModifiedByUserId ?? local.lastModifiedByUserId,
            ),
          ),
        );
    cache?.careNotes[written.first.id] = written.first;
  }

  /// The redacted payload columns for a visit-prep item row: the cleared
  /// state for a tombstone (mirroring the server's
  /// `visit_prep_items_tombstone_payload_check`); otherwise the remote
  /// values as-is, attribution stamps included.
  ///
  /// LLA-040 (issue #635): this used to preserve the *stored* check stamp
  /// whenever `remote.isChecked == local.isChecked`, reasoning that an
  /// unchanged boolean meant no real check-state transition happened — a
  /// mirror of the `sync_push` RPC's own CASE logic, which keeps the
  /// stored `checked_by_user_id`/`checked_at` server-side when a *push*
  /// doesn't actually change `is_checked` (so a co-guardian's text-only
  /// edit is never mis-attributed as a new check). That reasoning does not
  /// carry over to this side: [remote] has already won the per-id LWW
  /// check at the call site by the time this runs, so it already reflects
  /// whatever the server's own CASE logic decided — including a genuine
  /// remote uncheck-then-recheck that lands back on the same boolean this
  /// device last saw, with a new actor and stamp. Re-deriving "did the
  /// check state transition" from the *local* row's boolean cannot tell
  /// that apart from a no-op push, so it kept the old device's stamp
  /// forever once two peers' booleans coincidentally matched. The
  /// authoritative stamp is always the one the already-validated remote
  /// row carries.
  ({String body, bool isChecked, String? checkedByUserId, DateTime? checkedAt})
      _visitPrepItemPayload(RemoteVisitPrepItemRow remote, bool tombstone) {
    if (tombstone) {
      return (body: '', isChecked: false, checkedByUserId: null, checkedAt: null);
    }
    return (
      body: remote.body,
      isChecked: remote.isChecked,
      checkedByUserId: remote.checkedByUserId,
      checkedAt: remote.checkedAt?.toUtc(),
    );
  }

  /// Issue #128: applies a server copy of a visit-prep item keyed by id —
  /// the same per-id LWW rule [_applyCareNote] uses. A tombstone clears
  /// `body` and resets the check state (mirroring the server's
  /// `visit_prep_items_tombstone_payload_check`).
  Future<bool> _applyVisitPrepItem(
    RemoteVisitPrepItemRow remote, {
    required bool onlyExisting,
    _PageLookup? cache,
  }) {
    final tombstone = remote.isTombstone;
    final updatedAt = remote.updatedAt.toUtc();
    final deletedAt = remote.deletedAt?.toUtc();
    return _applyKeyedRow<RemoteVisitPrepItemRow, VisitPrepItemData>(
      remote: remote,
      readLocal: () => _lookupCached(
        cache,
        (c) => c.visitPrepItems,
        remote.id,
        _visitPrepItemOrNull,
      ),
      onlyExisting: onlyExisting,
      remoteUpdatedAt: (r) => r.updatedAt,
      localUpdatedAt: (l) => l.updatedAt,
      parentProfileId: (r) => r.profileId,
      entityLabel: 'visit prep item',
      remoteId: remote.id,
      insert: (r) => _insertVisitPrepItem(
        r,
        _visitPrepItemPayload(r, tombstone),
        updatedAt,
        deletedAt,
        cache,
      ),
      update: (r, local) => _updateVisitPrepItem(
        r,
        local,
        _visitPrepItemPayload(r, tombstone),
        updatedAt,
        deletedAt,
        cache,
      ),
      cache: cache,
    );
  }

  /// The insert half of [_applyVisitPrepItem], split out so neither method
  /// exceeds the CRAP-gate complexity budget on its own.
  Future<void> _insertVisitPrepItem(
    RemoteVisitPrepItemRow remote,
    ({String body, bool isChecked, String? checkedByUserId, DateTime? checkedAt}) payload,
    DateTime updatedAt,
    DateTime? deletedAt,
    _PageLookup? cache,
  ) async {
    final written = await db
        .into(db.visitPrepItems)
        .insertReturning(
          VisitPrepItemsCompanion.insert(
            id: remote.id,
            profileId: remote.profileId,
            body: payload.body,
            isChecked: Value(payload.isChecked),
            checkedByUserId: Value(payload.checkedByUserId),
            checkedAt: Value(payload.checkedAt),
            updatedAt: updatedAt,
            deletedAt: Value(deletedAt),
            dirty: const Value(false),
            localRev: const Value(0),
            loggedByUserId: Value(remote.loggedByUserId),
            lastModifiedByUserId: Value(remote.lastModifiedByUserId),
          ),
        );
    cache?.visitPrepItems[written.id] = written;
  }

  /// The update half of [_applyVisitPrepItem], split out for the same
  /// reason. A null stamp on the remote copy never wipes a known local
  /// one (the _applyObservation precedent).
  Future<void> _updateVisitPrepItem(
    RemoteVisitPrepItemRow remote,
    VisitPrepItemData local,
    ({String body, bool isChecked, String? checkedByUserId, DateTime? checkedAt}) payload,
    DateTime updatedAt,
    DateTime? deletedAt,
    _PageLookup? cache,
  ) async {
    final written =
        await (db.update(
          db.visitPrepItems,
        )..where((t) => t.id.equals(remote.id))).writeReturning(
          VisitPrepItemsCompanion(
            body: Value(payload.body),
            isChecked: Value(payload.isChecked),
            checkedByUserId: Value(payload.checkedByUserId),
            checkedAt: Value(payload.checkedAt),
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            dirty: const Value(false),
            loggedByUserId: Value(
              remote.loggedByUserId ?? local.loggedByUserId,
            ),
            lastModifiedByUserId: Value(
              remote.lastModifiedByUserId ?? local.lastModifiedByUserId,
            ),
          ),
        );
    cache?.visitPrepItems[written.first.id] = written.first;
  }

  static bool _tagsEqual(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    final setA = a.toSet();
    final setB = b.toSet();
    if (setA.length != setB.length) return false;
    return setA.containsAll(setB);
  }

  /// Runs the same-date rule against every other live local row for
  /// [remote]'s (profile, date), starting from [updatedAt] (only called
  /// while [remote] itself is not already a tombstone). A local loser is
  /// tombstoned in place with the winner's timestamp and marked dirty so
  /// the resolution is pushed; a remote loser makes [remote] itself the
  /// tombstone, stamped with the local winner's timestamp (>=
  /// `remote.updatedAt` by the rule). Either way, R7/R11 (issue #3
  /// gap-closure plan, Unit U5): the loser's tags are unioned onto whichever
  /// row survives, mirroring the server's `sync_push` resolver exactly
  /// (KTD4/KTD6), rather than being discarded. Returns the `updated_at` /
  /// `deleted_at` / `tags` / `dirty` quadruple [remote] should be written
  /// with — when [remote] survives and absorbed tags from a local loser,
  /// [dirty] is true so the client-computed merge is pushed to the server
  /// (matching how the sibling branch marks its local survivor dirty). The
  /// `tags` value is meaningless when `deleted_at` is non-null, since
  /// tombstones are always written payload-free (R12) regardless — issue
  /// #224: `flow` is included in that payload-free guarantee too, cleared
  /// by the local-loser branch's own UPDATE below and by [_applyDayEntry]'s
  /// final write for a remote loser (both keyed off `tombstone`, not off
  /// this method's `tags` return value).
  ///
  /// Issue #124 (AC4): a branch that actually discards a `note`/`flow`
  /// value — the loser's copy differed from the winner's — also records a
  /// device-local [MergeEvent] in this same transaction, so the discard
  /// stays visible on the activity feed. Tags never record an event (they
  /// are unioned, not discarded) and identical payloads never do (nothing
  /// was lost).
  ///
  /// LLA-038 (issue #639): when [remote] survives with a real tag union
  /// (`dirty` true), the returned `updated_at` is `remote.updatedAt` plus
  /// one millisecond, never left tied to it — see the inline comment where
  /// that bump happens for why a tied stamp silently loses the merge to a
  /// replay or a declined equal-timestamp push.
  Future<(DateTime, DateTime?, List<String>, bool)> _resolveSameDateConflicts(
    RemoteDayEntryRow remote,
    DateTime updatedAt, {
    _PageLookup? cache,
  }) async {
    DateTime? deletedAt;
    var tags = remote.tags;
    final incoming = DayEntryCandidate(id: remote.id, updatedAt: updatedAt);
    final others = (await _livePeersCached(
      cache,
      remote.profileId,
      remote.localDate,
    )).where((row) => row.id != remote.id);
    for (final other in others) {
      final winner = sameDateWinner(
        incoming,
        DayEntryCandidate(id: other.id, updatedAt: other.updatedAt),
      )!;
      if (winner.id == remote.id) {
        // Local loser: tombstone with the winner's timestamp, dirty so the
        // resolution is pushed. R7: union its tags onto the incoming
        // (surviving) row instead of discarding them.
        await _recordMergeDiscardIfAny(
          profileId: remote.profileId,
          localDateIso: remote.localDate,
          resolutionStamp: updatedAt,
          winnerActorId: remote.lastModifiedByUserId ?? remote.loggedByUserId,
          loserActorId: other.lastModifiedByUserId ?? other.loggedByUserId,
          loserNote: other.note,
          winnerNote: remote.note,
          loserFlow: other.flow,
          winnerFlow: remote.flow,
          loserEntryId: other.id,
        );
        // Issue #130: the same discard, as a SYNCED row (the day sheet's
        // notice + the losing author's recovery text — visible on every
        // guardian's device once pushed, unlike the #124 device-local feed
        // event above).
        await _recordSyncedMergeEventIfAny(
          profileId: remote.profileId,
          localDateIso: remote.localDate,
          resolutionStamp: updatedAt,
          winnerRowId: remote.id,
          losingRowId: other.id,
          winnerLastModifiedByUserId: remote.lastModifiedByUserId,
          winnerLoggedByUserId: remote.loggedByUserId,
          loserLastModifiedByUserId: other.lastModifiedByUserId,
          loserLoggedByUserId: other.loggedByUserId,
          loserNote: other.note,
          winnerNote: remote.note,
          loserFlow: other.flow,
          winnerFlow: remote.flow,
        );
        tags = mergeTags(tags, other.tags);
        final written =
            await (db.update(
              db.dayEntries,
            )..where((t) => t.id.equals(other.id))).writeReturning(
              DayEntriesCompanion(
                flow: const Value(FlowLevel.none),
                note: const Value(null),
                tags: const Value(<String>[]),
                updatedAt: Value(updatedAt),
                deletedAt: Value(updatedAt),
                dirty: const Value(true),
                localRev: Value(other.localRev + 1),
              ),
            );
        cache?.storeDayEntry(written.first);
      } else {
        // Remote loser: store it as a tombstone stamped with the local
        // winner's timestamp (>= remote.updatedAt by the rule). R7/R11: the
        // union of both rows' tags is written onto the surviving local
        // winner in the same write that already touches it, and it is
        // marked dirty with a bumped localRev so the merge is pushed -
        // matching how the local-loser branch above already marks its
        // tombstone dirty.
        await _recordMergeDiscardIfAny(
          profileId: remote.profileId,
          localDateIso: remote.localDate,
          resolutionStamp: other.updatedAt,
          winnerActorId: other.lastModifiedByUserId ?? other.loggedByUserId,
          loserActorId: remote.lastModifiedByUserId ?? remote.loggedByUserId,
          loserNote: remote.note,
          winnerNote: other.note,
          loserFlow: remote.flow,
          winnerFlow: other.flow,
          loserEntryId: remote.id,
        );
        // Issue #130: the synced twin of the device-local event above —
        // the incoming (remote) row is the loser here.
        await _recordSyncedMergeEventIfAny(
          profileId: remote.profileId,
          localDateIso: remote.localDate,
          resolutionStamp: other.updatedAt,
          winnerRowId: other.id,
          losingRowId: remote.id,
          winnerLastModifiedByUserId: other.lastModifiedByUserId,
          winnerLoggedByUserId: other.loggedByUserId,
          loserLastModifiedByUserId: remote.lastModifiedByUserId,
          loserLoggedByUserId: remote.loggedByUserId,
          loserNote: remote.note,
          winnerNote: other.note,
          loserFlow: remote.flow,
          winnerFlow: other.flow,
        );
        final mergedOtherTags = mergeTags(other.tags, tags);
        // Issue #663 (LLA-038 mirror of the sibling branch's #662 fix
        // above): stamp the local survivor strictly after the incoming
        // remote loser's timestamp whenever it actually absorbs new tags.
        // `other`'s own write below never otherwise touches `updated_at`,
        // so a previously unmodified pulled copy (its stamp already tied
        // to what the server stores for `other`'s own id) would stay tied
        // even after gaining tags here. Untied, two failure modes match
        // the sibling branch exactly: (1) a later ordinary pull of
        // `other`'s own id — the merge never having reached the server —
        // ties `remoteWinsById`, and remote wins ties, so the union just
        // written is silently overwritten by the server's bare tags with
        // `dirty` cleared; (2) `sync_push`'s day_entries acceptance rule
        // only takes a row strictly newer than what it already has
        // stored, so an equal-timestamp push of the merged tags is
        // declined forever.
        final otherGainedTags = !_tagsEqual(mergedOtherTags, other.tags);
        final otherUpdatedAt = otherGainedTags
            ? other.updatedAt.toUtc().add(const Duration(milliseconds: 1))
            : other.updatedAt.toUtc();
        final written =
            await (db.update(
              db.dayEntries,
            )..where((t) => t.id.equals(other.id))).writeReturning(
              DayEntriesCompanion(
                tags: Value(mergedOtherTags),
                updatedAt: Value(otherUpdatedAt),
                dirty: const Value(true),
                localRev: Value(other.localRev + 1),
              ),
            );
        cache?.storeDayEntry(written.first);
        updatedAt = otherUpdatedAt;
        deletedAt = updatedAt;
      }
    }
    final hasNewTags = !_tagsEqual(tags, remote.tags);
    final dirty = hasNewTags && deletedAt == null;
    if (dirty) {
      // LLA-038 (issue #639): a merge that leaves [remote] itself the live
      // survivor must be stamped strictly after `remote.updatedAt` — the
      // value the server already has stored for this id — never left tied
      // to it. Tied, two failure modes converge: (1) a replay of the exact
      // same pre-merge row (a duplicate pull page, or the 24h reconcile's
      // lookback) ties `remoteWinsById` and re-runs this resolution, but by
      // then `other` is already tombstoned — no merge is recomputed, and
      // the union this branch just wrote is silently replaced by the
      // server's bare `remote.tags` with `dirty` cleared, discarding it for
      // good; (2) even without a replay, `sync_push`'s day_entries
      // acceptance rule (`v_accept`) only takes a *live* row strictly newer
      // than what it already has stored — an equal-timestamp push of the
      // merged tags is declined forever. The local-loser tombstone branch
      // above needs no such bump: a tombstone pushed at an equal timestamp
      // is the one case `sync_push` accepts on a tie (KTD5), and its own
      // stamped `updated_at` (the winner's) already sits at or after
      // anything the server holds for that loser id.
      updatedAt = updatedAt.add(const Duration(milliseconds: 1));
    }
    return (updatedAt, deletedAt, tags, dirty);
  }

  /// Records one device-local merge outcome (issue #124, AC4) when — and
  /// only when — the loser's `note` or `flow` actually differs from the
  /// winner's, i.e. the resolution really discarded a value. Called inside
  /// the caller's apply transaction, so the discard and its record commit
  /// or roll back together. Idempotent by `(loser entry id, resolution
  /// stamp)` via [appendMergeEvent], so a re-delivered row that re-applies
  /// (the per-id rule lets a tied remote copy re-apply) never duplicates an
  /// event. Stores actor ids and booleans only — never note text or tags.
  Future<void> _recordMergeDiscardIfAny({
    required String profileId,
    required String localDateIso,
    required DateTime resolutionStamp,
    required String? winnerActorId,
    required String? loserActorId,
    required String? loserNote,
    required String? winnerNote,
    required FlowLevel loserFlow,
    required FlowLevel winnerFlow,
    required String loserEntryId,
  }) async {
    final discardedNote = loserNote != winnerNote;
    final discardedFlow = loserFlow != winnerFlow;
    if (!discardedNote && !discardedFlow) return;
    final stamp = resolutionStamp.toUtc();
    final key = activityMergeEventsKey(profileId);
    final stored = await getSetting(key);
    final events = appendMergeEvent(decodeMergeEvents(stored), MergeEvent(
      id: '$loserEntryId@${stamp.toIso8601String()}',
      profileId: profileId,
      localDateIso: localDateIso,
      occurredAt: stamp,
      winnerActorId: winnerActorId,
      loserActorId: loserActorId,
      discardedNote: discardedNote,
      discardedFlow: discardedFlow,
    ));
    await setSetting(key: key, value: encodeMergeEvents(events), updatedAt: stamp);
  }

  /// Issue #130: the synced twin of [_recordMergeDiscardIfAny] — writes
  /// the same-date merge's discarded `flow`/`note` values as local
  /// `day_entry_merge_events` rows (dirty, so they ride the next push and
  /// reach every guardian's device), with the losing value's text retained
  /// for the losing author's recovery. Emitted ONLY from
  /// [_resolveSameDateConflicts] (the same-date, distinct-row-id path):
  /// the same-id convergence path never runs the resolver, so an ordinary
  /// edit of one row stays notice-free by construction (AC), and a
  /// tags-only merge records nothing (a set union loses nothing — AC).
  /// Called inside the caller's apply transaction, so the disclosure and
  /// the merge commit or roll back together. Deduplicated by the natural
  /// key (profileId, losingRowId, field) — a replayed resolution (the
  /// per-id rule lets a tied remote copy re-apply, though by then the
  /// loser is already tombstoned and no merge is recomputed) or the
  /// server's own emission of the same event collapse to one row.
  Future<void> _recordSyncedMergeEventIfAny({
    required String profileId,
    required String localDateIso,
    required DateTime resolutionStamp,
    required String winnerRowId,
    required String losingRowId,
    required String? winnerLastModifiedByUserId,
    required String? winnerLoggedByUserId,
    required String? loserLastModifiedByUserId,
    required String? loserLoggedByUserId,
    required String? loserNote,
    required String? winnerNote,
    required FlowLevel loserFlow,
    required FlowLevel winnerFlow,
  }) async {
    // Display attribution: the last writer if known, else the original
    // logger (the same coalesce the resolver's #124 call sites use).
    final winnerActorId =
        winnerLastModifiedByUserId ?? winnerLoggedByUserId;
    final loserActorId = loserLastModifiedByUserId ?? loserLoggedByUserId;
    if (loserNote != winnerNote) {
      await _insertMergeEventIfAbsent(
        profileId: profileId,
        localDateIso: localDateIso,
        resolutionStamp: resolutionStamp,
        winnerRowId: winnerRowId,
        losingRowId: losingRowId,
        field: 'note',
        losingValueText: loserNote ?? '',
        losingAuthorUserId: loserActorId,
        winningAuthorUserId: winnerActorId,
      );
    }
    if (loserFlow != winnerFlow) {
      await _insertMergeEventIfAbsent(
        profileId: profileId,
        localDateIso: localDateIso,
        resolutionStamp: resolutionStamp,
        winnerRowId: winnerRowId,
        losingRowId: losingRowId,
        field: 'flow',
        losingValueText: loserFlow.toDb(),
        losingAuthorUserId: loserActorId,
        winningAuthorUserId: winnerActorId,
      );
    }
  }

  /// [_recordSyncedMergeEventIfAny]'s insert half: a no-op when the
  /// natural key (profileId, losingRowId, field) is already recorded —
  /// the local mirror of the server's `day_entry_merge_events_discard_uq`
  /// + ON CONFLICT DO NOTHING. The retained text is clamped to the note
  /// bound defensively (a loser note is already bounded at write; this
  /// guards a hand-built row).
  Future<void> _insertMergeEventIfAbsent({
    required String profileId,
    required String localDateIso,
    required DateTime resolutionStamp,
    required String winnerRowId,
    required String losingRowId,
    required String field,
    required String losingValueText,
    required String? losingAuthorUserId,
    required String? winningAuthorUserId,
  }) async {
    final alreadyRecorded = await (db.select(db.dayEntryMergeEvents)
          ..where((t) =>
              t.profileId.equals(profileId) &
              t.losingRowId.equals(losingRowId) &
              t.field.equals(field)))
        .getSingleOrNull();
    if (alreadyRecorded != null) return;
    final stamp = resolutionStamp.toUtc();
    await db.into(db.dayEntryMergeEvents).insert(
          DayEntryMergeEventsCompanion.insert(
            id: _generator.next(),
            profileId: profileId,
            localDate: localDateIso,
            winningRowId: winnerRowId,
            losingRowId: losingRowId,
            field: field,
            losingValueText: losingValueText.length > kMaxNoteLength
                ? losingValueText.substring(0, kMaxNoteLength)
                : losingValueText,
            losingAuthorUserId: Value(losingAuthorUserId),
            winningAuthorUserId: Value(winningAuthorUserId),
            createdAt: stamp,
            updatedAt: stamp,
            dirty: const Value(true),
            localRev: const Value(1),
          ),
        );
  }

  /// Issue #130: applies a server copy of a merge event keyed by id — the
  /// per-id LWW rule the other profile-scoped tables use. The natural-key
  /// check comes FIRST: a locally-emitted row describing the same discard
  /// (a different id — this device's resolver and the server's both
  /// recorded it) already covers the event, and keeping the local id keeps
  /// any dismissal keyed on it stable; the pushed local row wins the
  /// server-side ON CONFLICT DO NOTHING, so both sides converge to one row
  /// per discard. Throws [RetryableSyncApplyError] when the profile is not
  /// held locally yet (checked up front so the failure is typed rather
  /// than a raw FK exception, mirroring [_ensureDayEntryProfileExists]).
  /// Issue #42: the own-row and parent-profile reads go through
  /// [_lookupCached] like every other applier; the natural-key check stays
  /// a live SELECT (keyed by (profile, losing row, field), not by id, so
  /// the id-keyed prefetch cannot serve it), and the write needs no
  /// RETURNING write-through — no later row in the same page can look a
  /// merge event up by an id that appeared earlier in it (ids are unique
  /// within a page, and the natural-key read above is live).
  Future<bool> _applyMergeEvent(RemoteDayEntryMergeEventRow remote,
      {required bool onlyExisting, _PageLookup? cache}) async {
    final local = await _lookupCached(
      cache,
      (c) => c.dayEntryMergeEvents,
      remote.id,
      _dayEntryMergeEventOrNull,
    );
    if (local == null && onlyExisting) return false;
    if (local != null &&
        !remoteWinsById(
            localUpdatedAt: local.updatedAt,
            remoteUpdatedAt: remote.updatedAt)) {
      return false;
    }
    if (await _lookupCached(
          cache,
          (c) => c.profiles,
          remote.profileId,
          _profileOrNull,
        ) ==
        null) {
      throw RetryableSyncApplyError(
          'merge event ${remote.id} references a profile not held locally');
    }
    final sameDiscard = await (db.select(db.dayEntryMergeEvents)
          ..where((t) =>
              t.profileId.equals(remote.profileId) &
              t.losingRowId.equals(remote.losingRowId) &
              t.field.equals(remote.field)))
        .getSingleOrNull();
    if (sameDiscard != null && sameDiscard.id != remote.id) return false;
    final updatedAt = remote.updatedAt.toUtc();
    await db.into(db.dayEntryMergeEvents).insertOnConflictUpdate(
          DayEntryMergeEventsCompanion.insert(
            id: remote.id,
            profileId: remote.profileId,
            localDate: remote.localDate,
            winningRowId: remote.winningRowId,
            losingRowId: remote.losingRowId,
            field: remote.field,
            losingValueText: remote.losingValueText,
            losingAuthorUserId: Value(remote.losingAuthorUserId),
            winningAuthorUserId: Value(remote.winningAuthorUserId),
            createdAt: remote.createdAt.toUtc(),
            updatedAt: updatedAt,
            dirty: const Value(false),
            localRev: const Value(0),
          ),
        );
    return true;
  }

  /// Issue #257: per-id LWW apply for a `profile_tag_registry` row, the
  /// care_notes shape via [_applyKeyedRow]. A tombstone's payload arrives
  /// already cleared server-side (the structural CHECK), so the local
  /// write stores what it was handed; `code` survives either way.
  Future<bool> _applyTagRegistryEntry(
    RemoteProfileTagRegistryRow remote, {
    required bool onlyExisting,
    _PageLookup? cache,
  }) {
    final tombstone = remote.isTombstone;
    final updatedAt = remote.updatedAt.toUtc();
    final deletedAt = remote.deletedAt?.toUtc();
    return _applyKeyedRow<RemoteProfileTagRegistryRow,
        ProfileTagRegistryEntry>(
      remote: remote,
      readLocal: () => _lookupCached(
          cache, (c) => c.profileTagRegistry, remote.id, _profileTagRegistryOrNull),
      onlyExisting: onlyExisting,
      remoteUpdatedAt: (r) => r.updatedAt,
      localUpdatedAt: (l) => l.updatedAt,
      parentProfileId: (r) => r.profileId,
      entityLabel: 'profile tag registry entry',
      remoteId: remote.id,
      insert: (r) =>
          _insertTagRegistryEntry(r, tombstone, updatedAt, deletedAt, cache),
      update: (r, local) => _updateTagRegistryEntry(
          r, local, tombstone, updatedAt, deletedAt, cache),
      cache: cache,
    );
  }

  Future<void> _insertTagRegistryEntry(
    RemoteProfileTagRegistryRow remote,
    bool tombstone,
    DateTime updatedAt,
    DateTime? deletedAt,
    _PageLookup? cache,
  ) async {
    final written = await db
        .into(db.profileTagRegistry)
        .insertReturning(
          ProfileTagRegistryCompanion.insert(
            id: remote.id,
            profileId: remote.profileId,
            code: remote.code,
            displayName: tombstone ? '' : remote.displayName,
            category: tombstone ? '' : remote.category,
            intensityEnabled:
                Value(tombstone ? false : remote.intensityEnabled),
            hiddenAt: Value(tombstone ? null : remote.hiddenAt),
            sortOrder: Value(tombstone ? null : remote.sortOrder),
            createdBy: Value(remote.createdBy),
            createdAt: remote.createdAt.toUtc(),
            updatedAt: updatedAt,
            deletedAt: Value(deletedAt),
            dirty: const Value(false),
            localRev: const Value(0),
          ),
        );
    cache?.profileTagRegistry[written.id] = written;
  }

  Future<void> _updateTagRegistryEntry(
    RemoteProfileTagRegistryRow remote,
    ProfileTagRegistryEntry local,
    bool tombstone,
    DateTime updatedAt,
    DateTime? deletedAt,
    _PageLookup? cache,
  ) async {
    final written =
        await (db.update(
          db.profileTagRegistry,
        )..where((t) => t.id.equals(remote.id))).writeReturning(
          ProfileTagRegistryCompanion(
            displayName: Value(tombstone ? '' : remote.displayName),
            category: Value(tombstone ? '' : remote.category),
            intensityEnabled:
                Value(tombstone ? false : remote.intensityEnabled),
            hiddenAt: Value(tombstone ? null : remote.hiddenAt),
            sortOrder: Value(tombstone ? null : remote.sortOrder),
            createdBy: Value(remote.createdBy ?? local.createdBy),
            updatedAt: Value(updatedAt),
            deletedAt: Value(deletedAt),
            dirty: const Value(false),
          ),
        );
    cache?.profileTagRegistry[written.first.id] = written.first;
  }

  /// The `flow` to write for a day entry row: cleared to [FlowLevel.none]
  /// for a tombstone (issue #224), whether [remote] already arrived
  /// tombstoned or [_resolveSameDateConflicts] made it one locally.
  FlowLevel _dayEntryFlow(bool tombstone, RemoteDayEntryRow remote) =>
      tombstone ? FlowLevel.none : remote.flow;

  /// The `tags` to write for a day entry row: cleared for a tombstone.
  List<String> _dayEntryTags(bool tombstone, List<String> tags) =>
      tombstone ? const <String>[] : tags;

  /// The `note` to write for a day entry row: cleared for a tombstone.
  String? _dayEntryNote(bool tombstone, RemoteDayEntryRow remote) =>
      tombstone ? null : remote.note;

  /// Issue #220: the `pms` to write for a day entry row — cleared for a
  /// tombstone like every other payload column (the server's
  /// `day_entries_tombstone_pms_check` enforces the same shape server-side).
  bool _dayEntryPms(bool tombstone, RemoteDayEntryRow remote) =>
      tombstone ? false : remote.pms;

}
