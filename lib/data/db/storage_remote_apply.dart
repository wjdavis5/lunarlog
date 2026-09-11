part of 'storage.dart';

// Remote applies for [LunarLogStorage] (part of `storage.dart`, mixed into
// the class below). Every remote apply compares *before* writing (LWW per
// id; the remote copy wins ties), writes `dirty = false`, and never
// regresses `updated_at`. Same-date conflicts tombstone the loser with the
// winner's timestamp.
// Moved verbatim from `storage.dart` (#434).

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

  /// Applies one pull page: every row (all of [table]) and the table's new
  /// cursor in ONE transaction, so a crash can only re-fetch rows, never
  /// skip them (KTD2). A throwing row rolls the whole page back, cursor
  /// included.
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
      for (final row in rows) {
        await _applyPageRow(row);
      }
      await _updateTableCursor(table, newCursor);
    });
  }

  Future<void> _applyPageRow(RemoteRow row) async {
    switch (row) {
      case RemoteProfileRow():
        await _applyProfile(row, onlyExisting: false);
      case RemoteDayEntryRow():
        await _applyDayEntry(row, onlyExisting: false);
      case RemoteProfileGuardianRow():
        await _applyProfileGuardian(row);
      case RemoteObservationRow():
        await _applyObservation(row, onlyExisting: false);
      case RemoteProfileModeRow():
        await _applyProfileMode(row, onlyExisting: false);
      case RemoteCycleOverrideRow():
        await _applyCycleOverride(row, onlyExisting: false);
      case RemoteCareNoteRow():
        await _applyCareNote(row, onlyExisting: false);
      case RemoteVisitPrepItemRow():
        await _applyVisitPrepItem(row, onlyExisting: false);
    }
  }

  Future<void> _updateTableCursor(SyncTable table, int newCursor) async {
    await _ensureSyncStateRow();
    await (db.update(db.syncState)..where((t) => t.id.equals(1))).write(
      switch (table) {
        SyncTable.profiles =>
          SyncStateCompanion(cursorProfiles: Value(newCursor)),
        SyncTable.dayEntries =>
          SyncStateCompanion(cursorDayEntries: Value(newCursor)),
        SyncTable.observations =>
          SyncStateCompanion(cursorObservations: Value(newCursor)),
        SyncTable.profileModes =>
          SyncStateCompanion(cursorProfileModes: Value(newCursor)),
        SyncTable.cycleOverrides =>
          SyncStateCompanion(cursorCycleOverrides: Value(newCursor)),
        SyncTable.careNotes =>
          SyncStateCompanion(cursorCareNotes: Value(newCursor)),
        SyncTable.visitPrepItems =>
          SyncStateCompanion(cursorVisitPrepItems: Value(newCursor)),
        SyncTable.profileGuardians =>
          const SyncStateCompanion(),
      },
    );
  }

  /// Applies one full-reconcile page (rows of one or more tables) in ONE
  /// transaction without touching any cursor (KTD2). Same per-row rules as
  /// [applyRemoteProfile] / [applyRemoteDayEntry] / [applyRemoteObservation];
  /// profiles, then day entries, then observations, then the two Issue
  /// #188 tables (both reference only a profile, which is already applied
  /// by the time their turns come). A throwing row rolls the page back —
  /// callers that need per-row independence fall back to the single-row
  /// applies.
  Future<void> applyRemoteRows(List<RemoteRow> rows) async {
    await db.transaction(() async {
      for (final row in rows.whereType<RemoteProfileRow>()) {
        await _applyProfile(row, onlyExisting: false);
      }
      for (final row in rows.whereType<RemoteProfileGuardianRow>()) {
        await _applyProfileGuardian(row);
      }
      for (final row in rows.whereType<RemoteDayEntryRow>()) {
        await _applyDayEntry(row, onlyExisting: false);
      }
      for (final row in rows.whereType<RemoteObservationRow>()) {
        await _applyObservation(row, onlyExisting: false);
      }
      for (final row in rows.whereType<RemoteProfileModeRow>()) {
        await _applyProfileMode(row, onlyExisting: false);
      }
      for (final row in rows.whereType<RemoteCycleOverrideRow>()) {
        await _applyCycleOverride(row, onlyExisting: false);
      }
      for (final row in rows.whereType<RemoteCareNoteRow>()) {
        await _applyCareNote(row, onlyExisting: false);
      }
      for (final row in rows.whereType<RemoteVisitPrepItemRow>()) {
        await _applyVisitPrepItem(row, onlyExisting: false);
      }
    });
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
    });
  }

  // ---------------------------------------------------------------- internal

  Future<bool> _applyProfile(RemoteProfileRow remote,
      {required bool onlyExisting}) async {
    final local = await _profileOrNull(remote.id);
    if (local == null && onlyExisting) return false;
    if (local != null &&
        !remoteWinsById(
            localUpdatedAt: local.updatedAt,
            remoteUpdatedAt: remote.updatedAt)) {
      return false;
    }
    final tombstone = remote.isTombstone;
    final updatedAt = remote.updatedAt.toUtc();
    final deletedAt = remote.deletedAt?.toUtc();
    if (local == null) {
      await db.into(db.profiles).insert(ProfilesCompanion.insert(
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
            birthYear: Value(remote.birthYear),
            relationship: Value(remote.relationship),
            transferredAt: Value(remote.transferredAt?.toUtc()),
            transferredToUserId: Value(remote.transferredToUserId),
            lastPeriodStart: Value(remote.lastPeriodStart),
            typicalCycleLengthDays: Value(remote.typicalCycleLengthDays),
            typicalPeriodLengthDays: Value(remote.typicalPeriodLengthDays),
          ));
      return true;
    }
    await (db.update(db.profiles)..where((t) => t.id.equals(remote.id))).write(
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
        birthYear: Value(remote.birthYear),
        relationship: Value(remote.relationship),
        transferredAt: Value(remote.transferredAt?.toUtc()),
        transferredToUserId: Value(remote.transferredToUserId),
        lastPeriodStart: Value(remote.lastPeriodStart),
        typicalCycleLengthDays: Value(remote.typicalCycleLengthDays),
        typicalPeriodLengthDays: Value(remote.typicalPeriodLengthDays),
      ),
    );
    return true;
  }

  Future<bool> _applyProfileGuardian(RemoteProfileGuardianRow remote) async {
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
    if (await _profileOrNull(remote.profileId) == null) {
      if (remote.status != 'accepted') return false;
      throw RetryableSyncApplyError(
          'profile_guardian ${remote.id} references a profile not held locally');
    }

    final existing = await (db.select(db.profileGuardians)
          ..where((t) => t.id.equals(remote.id)))
        .getSingleOrNull();

    if (existing != null &&
        !remoteWinsById(
            localUpdatedAt: existing.updatedAt,
            remoteUpdatedAt: remote.updatedAt)) {
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
      await _tombstoneRevokedSharedProfile(remote.profileId, remote.updatedAt);
    }

    await db.into(db.profileGuardians).insertOnConflictUpdate(
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
          ),
        );
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
  /// `updated_at` is deliberately left untouched (finding #9): neither
  /// `revoke_guardian` nor `accept_guardian_invitation` bumps the server's
  /// `profiles.updated_at`, so stamping the tombstone with `revokedAt` would
  /// make it permanently newer than any row a later re-share can ever
  /// deliver - `remoteWinsById` (KTD5) would then keep the tombstone forever
  /// and the profile could never come back. Leaving `updated_at` where it
  /// was means a later server row (even one carrying its original,
  /// never-touched timestamp) ties or wins normally and un-tombstones it.
  Future<void> _tombstoneRevokedSharedProfile(
      String profileId, DateTime revokedAt) async {
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
    await (db.update(db.profiles)
          ..where((t) => t.id.equals(profileId) & t.deletedAt.isNull()))
        .write(ProfilesCompanion(
          displayName: const Value(''),
          deletedAt: Value(stamp),
          dirty: const Value(false),
        ));
  }

  Future<bool> _applyDayEntry(RemoteDayEntryRow remote,
      {required bool onlyExisting}) async {
    final local = await _dayEntryOrNull(remote.id);
    if (_shouldSkipDayEntryApply(
        local: local, onlyExisting: onlyExisting, remote: remote)) {
      return false;
    }
    // Referential integrity is checked up front so the failure is a typed,
    // retryable one rather than a raw constraint exception from sqlite.
    await _ensureDayEntryProfileExists(remote);
    await _recordResolvedOverwriteIfAny(remote,
        local: local, onlyExisting: onlyExisting);

    var updatedAt = remote.updatedAt.toUtc();
    var deletedAt = remote.deletedAt?.toUtc();
    var tags = remote.tags;
    var dirty = false;
    if (deletedAt == null) {
      (updatedAt, deletedAt, tags, dirty) =
          await _resolveSameDateConflicts(remote, updatedAt);
    }
    final tombstone = deletedAt != null;
    if (local == null) {
      await db.into(db.dayEntries).insert(DayEntriesCompanion.insert(
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
          ));
      return true;
    }
    await (db.update(db.dayEntries)..where((t) => t.id.equals(remote.id)))
        .write(DayEntriesCompanion(
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
      loggedByUserId: Value(remote.loggedByUserId ?? local.loggedByUserId),
      lastModifiedByUserId: Value(remote.lastModifiedByUserId ?? local.lastModifiedByUserId),
      source: Value(remote.source),
      sourceId: Value(remote.sourceId),
      importId: Value(remote.importId),
    ));
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
  Future<void> _ensureDayEntryProfileExists(RemoteDayEntryRow remote) async {
    if (await _profileOrNull(remote.profileId) == null) {
      throw RetryableSyncApplyError(
          'day entry ${remote.id} references a profile not held locally');
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
  Future<bool> _applyObservation(RemoteObservationRow remote,
      {required bool onlyExisting}) async {
    final local = await _observationOrNull(remote.id);
    if (local == null && onlyExisting) return false;
    if (local != null &&
        !remoteWinsById(
            localUpdatedAt: local.updatedAt,
            remoteUpdatedAt: remote.updatedAt)) {
      return false;
    }
    // Referential integrity up front, mirroring [_ensureDayEntryProfileExists]:
    // a typed, retryable failure rather than a raw constraint exception.
    if (await _dayEntryOrNull(remote.dayEntryId) == null) {
      throw RetryableSyncApplyError(
          'observation ${remote.id} references a day entry not held locally');
    }
    final tombstone = remote.isTombstone;
    final updatedAt = remote.updatedAt.toUtc();
    final deletedAt = remote.deletedAt?.toUtc();
    final payload = _observationPayload(remote, tombstone);
    if (local == null) {
      await db.into(db.observations).insert(ObservationsCompanion.insert(
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
            raw: Value(payload.raw),
            updatedAt: updatedAt,
            deletedAt: Value(deletedAt),
            dirty: const Value(false),
            localRev: const Value(0),
            loggedByUserId: Value(remote.loggedByUserId),
            lastModifiedByUserId: Value(remote.lastModifiedByUserId),
          ));
      return true;
    }
    await (db.update(db.observations)..where((t) => t.id.equals(remote.id)))
        .write(ObservationsCompanion(
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
      raw: Value(payload.raw),
      updatedAt: Value(updatedAt),
      deletedAt: Value(deletedAt),
      dirty: const Value(false),
      loggedByUserId: Value(remote.loggedByUserId ?? local.loggedByUserId),
      lastModifiedByUserId:
          Value(remote.lastModifiedByUserId ?? local.lastModifiedByUserId),
    ));
    return true;
  }

  /// Issue #188: applies a server copy of a profile mode row keyed by
  /// profile id — the same per-id LWW rule [_applyProfile] uses. No
  /// tombstone exists on this table. Throws [RetryableSyncApplyError] when
  /// the profile is not held locally yet (checked up front so the failure
  /// is typed rather than a raw constraint exception, mirroring
  /// [_ensureDayEntryProfileExists]).
  Future<bool> _applyProfileMode(RemoteProfileModeRow remote,
      {required bool onlyExisting}) async {
    final local = await _profileModeOrNull(remote.profileId);
    if (local == null && onlyExisting) return false;
    if (local != null &&
        !remoteWinsById(
            localUpdatedAt: local.updatedAt,
            remoteUpdatedAt: remote.updatedAt)) {
      return false;
    }
    if (await _profileOrNull(remote.profileId) == null) {
      throw RetryableSyncApplyError(
          'profile mode ${remote.profileId} references a profile not held locally');
    }
    final updatedAt = remote.updatedAt.toUtc();
    if (local == null) {
      await db.into(db.profileModes).insert(ProfileModesCompanion.insert(
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
          ));
      return true;
    }
    await (db.update(db.profileModes)
          ..where((t) => t.profileId.equals(remote.profileId)))
        .write(ProfileModesCompanion(
      mode: Value(remote.mode),
      modeStartedOn: Value(remote.modeStartedOn),
      birthControlMethod: Value(remote.birthControlMethod),
      birthControlStartedOn: Value(remote.birthControlStartedOn),
      birthControlStoppedOn: Value(remote.birthControlStoppedOn),
      healthSyncConsent: Value(remote.healthSyncConsent),
      updatedAt: Value(updatedAt),
      dirty: const Value(false),
    ));
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
  Future<bool> _applyCycleOverride(RemoteCycleOverrideRow remote,
      {required bool onlyExisting}) async {
    final local = await _cycleOverrideOrNull(remote.id, remote.profileId);
    if (local == null && onlyExisting) return false;
    if (local != null &&
        !remoteWinsById(
            localUpdatedAt: local.updatedAt,
            remoteUpdatedAt: remote.updatedAt)) {
      return false;
    }
    if (await _profileOrNull(remote.profileId) == null) {
      throw RetryableSyncApplyError(
          'cycle override ${remote.id} references a profile not held locally');
    }
    final tombstone = remote.isTombstone;
    final updatedAt = remote.updatedAt.toUtc();
    final deletedAt = remote.deletedAt?.toUtc();
    final payload = _cycleOverridePayload(remote, tombstone);
    if (local == null) {
      await db.into(db.cycleOverrides).insert(CycleOverridesCompanion.insert(
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
          ));
      return true;
    }
    await (db.update(db.cycleOverrides)
          ..where((t) =>
              t.id.equals(remote.id) & t.profileId.equals(remote.profileId)))
        .write(CycleOverridesCompanion(
      cycleStartDate: Value(remote.cycleStartDate),
      excludedFromAverage: Value(payload.excludedFromAverage),
      manualStart: Value(payload.manualStart),
      noteId: Value(payload.noteId),
      updatedAt: Value(updatedAt),
      deletedAt: Value(deletedAt),
      dirty: const Value(false),
    ));
    return true;
  }

  /// Issue #128: applies a server copy of a care note keyed by id — the
  /// same per-id LWW rule [_applyCycleOverride] uses, with no resolver. A
  /// tombstone clears `body` (mirroring the server's
  /// `care_notes_tombstone_payload_check`).
  Future<bool> _applyCareNote(RemoteCareNoteRow remote,
      {required bool onlyExisting}) async {
    final local = await _careNoteOrNull(remote.id);
    if (local == null && onlyExisting) return false;
    if (local != null &&
        !remoteWinsById(
            localUpdatedAt: local.updatedAt,
            remoteUpdatedAt: remote.updatedAt)) {
      return false;
    }
    if (await _profileOrNull(remote.profileId) == null) {
      throw RetryableSyncApplyError(
          'care note ${remote.id} references a profile not held locally');
    }
    final tombstone = remote.isTombstone;
    final updatedAt = remote.updatedAt.toUtc();
    final deletedAt = remote.deletedAt?.toUtc();
    if (local == null) {
      await _insertCareNote(remote, tombstone, updatedAt, deletedAt);
      return true;
    }
    await _updateCareNote(remote, local, tombstone, updatedAt, deletedAt);
    return true;
  }

  /// The insert half of [_applyCareNote], split out so neither method
  /// exceeds the CRAP-gate complexity budget on its own.
  Future<void> _insertCareNote(
    RemoteCareNoteRow remote,
    bool tombstone,
    DateTime updatedAt,
    DateTime? deletedAt,
  ) async {
    await db.into(db.careNotes).insert(CareNotesCompanion.insert(
          id: remote.id,
          profileId: remote.profileId,
          body: tombstone ? '' : remote.body,
          updatedAt: updatedAt,
          deletedAt: Value(deletedAt),
          dirty: const Value(false),
          localRev: const Value(0),
          loggedByUserId: Value(remote.loggedByUserId),
          lastModifiedByUserId: Value(remote.lastModifiedByUserId),
        ));
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
  ) async {
    await (db.update(db.careNotes)..where((t) => t.id.equals(remote.id)))
        .write(CareNotesCompanion(
      body: Value(tombstone ? '' : remote.body),
      updatedAt: Value(updatedAt),
      deletedAt: Value(deletedAt),
      dirty: const Value(false),
      loggedByUserId: Value(remote.loggedByUserId ?? local.loggedByUserId),
      lastModifiedByUserId: Value(
          remote.lastModifiedByUserId ?? local.lastModifiedByUserId),
    ));
  }

  /// The redacted payload columns for a visit-prep item row: the cleared
  /// state for a tombstone (mirroring the server's
  /// `visit_prep_items_tombstone_payload_check`); the remote values as-is
  /// for a live row whose check state transitioned; the *stored* check
  /// stamp for a live row whose check state did not transition (a text
  /// edit on a co-guardian's checked item must not silently re-stamp who
  /// checked it — the sync_push CASE mirror).
  ({String body, bool isChecked, String? checkedByUserId, DateTime? checkedAt})
      _visitPrepItemPayload(
          RemoteVisitPrepItemRow remote, bool tombstone, VisitPrepItemData? local) {
    if (tombstone) {
      return (body: '', isChecked: false, checkedByUserId: null, checkedAt: null);
    }
    if (local != null && remote.isChecked == local.isChecked) {
      return (
        body: remote.body,
        isChecked: remote.isChecked,
        checkedByUserId: local.checkedByUserId,
        checkedAt: local.checkedAt,
      );
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
  Future<bool> _applyVisitPrepItem(RemoteVisitPrepItemRow remote,
      {required bool onlyExisting}) async {
    final local = await _visitPrepItemOrNull(remote.id);
    if (local == null && onlyExisting) return false;
    if (local != null &&
        !remoteWinsById(
            localUpdatedAt: local.updatedAt,
            remoteUpdatedAt: remote.updatedAt)) {
      return false;
    }
    if (await _profileOrNull(remote.profileId) == null) {
      throw RetryableSyncApplyError(
          'visit prep item ${remote.id} references a profile not held locally');
    }
    final tombstone = remote.isTombstone;
    final updatedAt = remote.updatedAt.toUtc();
    final deletedAt = remote.deletedAt?.toUtc();
    final payload = _visitPrepItemPayload(remote, tombstone, local);
    if (local == null) {
      await _insertVisitPrepItem(remote, payload, updatedAt, deletedAt);
      return true;
    }
    await _updateVisitPrepItem(remote, local, payload, updatedAt, deletedAt);
    return true;
  }

  /// The insert half of [_applyVisitPrepItem], split out so neither method
  /// exceeds the CRAP-gate complexity budget on its own.
  Future<void> _insertVisitPrepItem(
    RemoteVisitPrepItemRow remote,
    ({String body, bool isChecked, String? checkedByUserId, DateTime? checkedAt}) payload,
    DateTime updatedAt,
    DateTime? deletedAt,
  ) async {
    await db.into(db.visitPrepItems).insert(VisitPrepItemsCompanion.insert(
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
        ));
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
  ) async {
    await (db.update(db.visitPrepItems)
          ..where((t) => t.id.equals(remote.id)))
        .write(VisitPrepItemsCompanion(
      body: Value(payload.body),
      isChecked: Value(payload.isChecked),
      checkedByUserId: Value(payload.checkedByUserId),
      checkedAt: Value(payload.checkedAt),
      updatedAt: Value(updatedAt),
      deletedAt: Value(deletedAt),
      dirty: const Value(false),
      loggedByUserId: Value(remote.loggedByUserId ?? local.loggedByUserId),
      lastModifiedByUserId: Value(
          remote.lastModifiedByUserId ?? local.lastModifiedByUserId),
    ));
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
  Future<(DateTime, DateTime?, List<String>, bool)> _resolveSameDateConflicts(
      RemoteDayEntryRow remote, DateTime updatedAt) async {
    DateTime? deletedAt;
    var tags = remote.tags;
    final incoming = DayEntryCandidate(id: remote.id, updatedAt: updatedAt);
    final others = (await _liveDayEntries(remote.profileId, remote.localDate))
        .where((row) => row.id != remote.id);
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
        tags = mergeTags(tags, other.tags);
        await (db.update(db.dayEntries)..where((t) => t.id.equals(other.id)))
            .write(DayEntriesCompanion(
          flow: const Value(FlowLevel.none),
          note: const Value(null),
          tags: const Value(<String>[]),
          updatedAt: Value(updatedAt),
          deletedAt: Value(updatedAt),
          dirty: const Value(true),
          localRev: Value(other.localRev + 1),
        ));
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
        await (db.update(db.dayEntries)..where((t) => t.id.equals(other.id)))
            .write(DayEntriesCompanion(
          tags: Value(mergeTags(other.tags, tags)),
          dirty: const Value(true),
          localRev: Value(other.localRev + 1),
        ));
        updatedAt = other.updatedAt.toUtc();
        deletedAt = updatedAt;
      }
    }
    final hasNewTags = !_tagsEqual(tags, remote.tags);
    return (updatedAt, deletedAt, tags, hasNewTags && deletedAt == null);
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
