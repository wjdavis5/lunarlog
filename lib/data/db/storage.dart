/// Storage-level persistence API for the drift database (the domain
/// repositories and the sync engine build on this).
///
/// Invariants enforced here (settled data model, KTD4, KTD5):
/// * `updated_at` strictly increases on local edits: a local write stamps
///   the clock when it is later than the stored value, otherwise the stored
///   value plus one millisecond — never equal, because the server declines
///   an edit stamped equal to the copy it already holds (the remote wins
///   ties) and would revert it. Remote applies compare *before* writing
///   (LWW per id; the remote copy wins ties) and only ever write a
///   timestamp that is at least the stored one, so `updated_at` never
///   regresses for them by construction.
/// * Payload limits mirror the server's CHECK constraints
///   (`lib/domain/limits.dart`): a local write past them throws rather than
///   persisting a row the server would reject forever.
/// * The storage clock is the injected clock plus [clockOffset]
///   (`server_now - device_now`, learned by the sync engine), so a device
///   whose clock trails the server does not lose every LWW race.
/// * Every local write sets `dirty = true` and bumps `local_rev`; remote
///   applies write `dirty = false` and leave `local_rev` alone.
/// * Deletes are tombstones: `deleted_at` is set, `updated_at` bumped, the
///   payload cleared (`note = null`, `tags = []`, `display_name = ''`); rows
///   are never removed.
/// * At most one *live* day entry per (profile, date): local writes update
///   the live row in place, remote applies run the same-date rule and
///   tombstone the loser with the winner's timestamp.
/// * UI reads filter tombstones; full-fidelity reads (tombstones included)
///   exist for sync.
library;

import 'package:drift/drift.dart';
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/sync/local_row_counts.dart';

import '../sync/conflict_rules.dart';
import '../sync/remote_rows.dart';
import 'db.dart';
import 'tables.dart';
import 'ulid.dart';

export 'package:lunarlog/domain/sync/local_row_counts.dart' show LocalRowCounts;

export '../sync/remote_rows.dart'
    show RemoteDayEntryRow, RemoteProfileRow, RemoteRow, RetryableSyncApplyError, SyncTable;

/// Default ULID generator for new records (per-isolate monotonic).
final UlidGenerator _ulid = UlidGenerator();

final RegExp _isoLocalDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

void _validateLocalDate(String localDate) {
  if (!_isoLocalDate.hasMatch(localDate)) {
    throw ArgumentError.value(
        localDate, 'localDate', 'must be an ISO yyyy-MM-dd string');
  }
  final parsed = DateTime.tryParse('${localDate}T00:00:00Z');
  if (parsed == null ||
      parsed.year.toString().padLeft(4, '0') != localDate.substring(0, 4) ||
      parsed.month.toString().padLeft(2, '0') != localDate.substring(5, 7) ||
      parsed.day.toString().padLeft(2, '0') != localDate.substring(8, 10)) {
    throw ArgumentError.value(localDate, 'localDate', 'not a valid calendar date');
  }
}

/// Returns [next] clamped so it is never earlier than [floor] (device-local
/// settings, which are not synced and need no strict bump).
DateTime _notBefore(DateTime next, DateTime floor) =>
    next.toUtc().isBefore(floor.toUtc()) ? floor.toUtc() : next.toUtc();

/// The `updated_at` for a local edit of a synced row stored at [stored]:
/// [next] when it is strictly later, otherwise [stored] plus one
/// millisecond (milliseconds, not microseconds, so the bump survives web's
/// millisecond `DateTime` precision). Never equal to [stored]: an edit
/// stamped equal to the server's copy is declined and reverted.
DateTime _afterStored(DateTime next, DateTime stored) {
  final n = next.toUtc();
  final s = stored.toUtc();
  return n.isAfter(s) ? n : s.add(const Duration(milliseconds: 1));
}

void _validateDisplayName(String displayName) {
  if (displayName.length > kMaxDisplayNameLength) {
    throw ArgumentError.value(displayName.length, 'displayName',
        'must be at most $kMaxDisplayNameLength characters');
  }
}

void _validateNote(String? note) {
  if (note != null && note.length > kMaxNoteLength) {
    throw ArgumentError.value(
        note.length, 'note', 'must be at most $kMaxNoteLength characters');
  }
}

/// The `sync_state` row as read when none has been written yet.
const SyncStateRow kDefaultSyncState = SyncStateRow(
  id: 1,
  deviceId: '',
  cursorProfiles: 0,
  cursorDayEntries: 0,
);

class LunarLogStorage {
  LunarLogStorage(this.db, {DateTime Function()? clock, UlidGenerator? ulid})
      : _clock = clock ?? (() => DateTime.now().toUtc()),
        _generator = ulid ?? _ulid;

  final LunarLogDatabase db;
  final DateTime Function() _clock;
  final UlidGenerator _generator;
  Duration _clockOffset = Duration.zero;

  /// `server_now - device_now`, added to the clock when stamping local
  /// writes (KTD4). Zero until the sync engine learns it.
  Duration get clockOffset => _clockOffset;

  /// Sets [clockOffset]. In-memory only; the engine persists the learned
  /// value in `sync_state.server_clock_offset_ms` and restores it on open.
  void setClockOffset(Duration offset) {
    _clockOffset = offset;
  }

  /// The instant a local write is stamped with: injected clock + offset.
  DateTime _now() => _clock().toUtc().add(_clockOffset);

  // ---------------------------------------------------------------- profiles

  /// Creates or updates a profile keyed by [id] (a fresh ULID is generated
  /// when omitted). A newer write to a tombstoned profile revives it
  /// (`deleted_at` cleared) — under LWW a newer non-delete must win.
  /// Marks the row dirty and bumps `local_rev`. An update stamps
  /// `updated_at` strictly after the stored value. Throws [ArgumentError]
  /// for a [displayName] over [kMaxDisplayNameLength].
  ///
  /// [birthYear] and [relationship] are optional, display/context-only
  /// subject metadata (Issue #4 R1, R3); [relationship] is the raw
  /// `toDb()` string, not validated here (the domain enum's closed set and
  /// the server's check constraint are the enforcement points). Neither is
  /// device-local bookkeeping: both sync like any other profile column.
  Future<Profile> upsertProfile({
    String? id,
    required String displayName,
    required bool isMinor,
    int sortOrder = 0,
    DateTime? archivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? birthYear,
    String? relationship,
  }) async {
    // Async so validation failures surface as failed futures.
    _validateDisplayName(displayName);
    return db.transaction(() async {
      final now = (updatedAt ?? _now()).toUtc();
      Profile? existing;
      if (id != null) {
        existing = await _profileOrNull(id);
      }
      if (existing == null) {
        final rowId = id ?? _generator.next();
        await db.into(db.profiles).insert(ProfilesCompanion.insert(
              id: rowId,
              displayName: displayName,
              isMinor: isMinor,
              sortOrder: Value(sortOrder),
              archivedAt: Value(archivedAt),
              createdAt: createdAt ?? now,
              updatedAt: now,
              dirty: const Value(true),
              localRev: const Value(1),
              birthYear: Value(birthYear),
              relationship: Value(relationship),
            ));
        return _profileById(rowId);
      }
      final rowId = existing.id;
      await (db.update(db.profiles)..where((t) => t.id.equals(rowId))).write(
        ProfilesCompanion(
          displayName: Value(displayName),
          isMinor: Value(isMinor),
          sortOrder: Value(sortOrder),
          archivedAt: Value(archivedAt),
          updatedAt: Value(_afterStored(now, existing.updatedAt)),
          deletedAt: const Value(null),
          dirty: const Value(true),
          localRev: Value(existing.localRev + 1),
          birthYear: Value(birthYear),
          relationship: Value(relationship),
        ),
      );
      return _profileById(rowId);
    });
  }

  /// Tombstones a profile: sets `deleted_at` (and bumps `updated_at`),
  /// clears `display_name` (KTD5: tombstones carry no payload), marks the
  /// row dirty. The row is never removed. Idempotent: re-deleting a
  /// tombstone does not bump `updated_at` again.
  Future<void> softDeleteProfile(String id) async {
    await db.transaction(() async {
      final existing = await _profileOrNull(id);
      if (existing == null || existing.deletedAt != null) return;
      final at = _afterStored(_now(), existing.updatedAt);
      await (db.update(db.profiles)..where((t) => t.id.equals(id))).write(
        ProfilesCompanion(
          displayName: const Value(''),
          updatedAt: Value(at),
          deletedAt: Value(at),
          dirty: const Value(true),
          localRev: Value(existing.localRev + 1),
        ),
      );
    });
  }

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

  // ------------------------------------------------------------- day entries

  /// Creates or updates the *live* day entry for (profileId, localDate).
  ///
  /// * If a live entry exists, it is updated in place (same ULID) with
  ///   `updated_at` strictly after the stored value (`now` when later,
  ///   otherwise `stored + 1ms`).
  /// * If none exists (including when only a tombstone exists for that date),
  ///   a new row with a fresh ULID is inserted. The old tombstone remains in
  ///   full-fidelity reads for sync; the new ULID row wins UI reads.
  ///
  /// Marks the row dirty and bumps `local_rev`. Throws [ArgumentError] for
  /// a [note] over [kMaxNoteLength].
  Future<DayEntry> upsertDayEntry({
    required String profileId,
    required String localDate,
    required String tz,
    required FlowLevel flow,
    List<String> tags = const [],
    String? note,
    DateTime? updatedAt,
  }) async {
    // Async so validation failures surface as failed futures, not sync
    // throws, for callers awaiting the result.
    _validateLocalDate(localDate);
    _validateNote(note);
    return db.transaction(() async {
      final now = (updatedAt ?? _now()).toUtc();
      final live = await _liveDayEntry(profileId, localDate);
      if (live == null) {
        await db.into(db.dayEntries).insert(DayEntriesCompanion.insert(
              id: _generator.next(),
              profileId: profileId,
              localDate: localDate,
              tz: tz,
              flow: flow,
              tags: Value(tags),
              note: Value(note),
              updatedAt: now,
              dirty: const Value(true),
              localRev: const Value(1),
            ));
      } else {
        final rowId = live.id;
        await (db.update(db.dayEntries)..where((t) => t.id.equals(rowId)))
            .write(DayEntriesCompanion(
          tz: Value(tz),
          flow: Value(flow),
          tags: Value(tags),
          note: Value(note),
          updatedAt: Value(_afterStored(now, live.updatedAt)),
          deletedAt: const Value(null),
          dirty: const Value(true),
          localRev: Value(live.localRev + 1),
        ));
      }
      final rows = await _liveDayEntries(profileId, localDate);
      if (rows.isEmpty) {
        throw StateError('day entry disappeared: $profileId $localDate');
      }
      return rows.last;
    });
  }

  /// Tombstones the live entry for (profileId, localDate), if any, clearing
  /// its payload (`note = null`, `tags = []`) and marking it dirty. Does
  /// nothing when there is no live entry (idempotent; never bumps
  /// `updated_at` without a change).
  Future<void> softDeleteDayEntry({
    required String profileId,
    required String localDate,
  }) async {
    await db.transaction(() async {
      final live = await _liveDayEntry(profileId, localDate);
      if (live == null) return;
      final at = _afterStored(_now(), live.updatedAt);
      final rowId = live.id;
      await (db.update(db.dayEntries)..where((t) => t.id.equals(rowId))).write(
        DayEntriesCompanion(
          note: const Value(null),
          tags: const Value(<String>[]),
          updatedAt: Value(at),
          deletedAt: Value(at),
          dirty: const Value(true),
          localRev: Value(live.localRev + 1),
        ),
      );
    });
  }

  /// Day entries for one profile — UI reads (default) filter tombstones;
  /// `includeTombstones: true` gives full-fidelity reads for sync.
  /// [updatedAfter] narrows to rows changed after that instant
  /// (incremental-sync support). Per-profile isolation (R3) is structural:
  /// every query is scoped to exactly one profileId.
  Future<List<DayEntry>> getDayEntries({
    required String profileId,
    bool includeTombstones = false,
    DateTime? updatedAfter,
  }) {
    return _dayEntryQuery(
      profileId: profileId,
      includeTombstones: includeTombstones,
      updatedAfter: updatedAfter,
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

  /// Stream variant of [getDayEntries] for reactive UI.
  Stream<List<DayEntry>> watchDayEntries({
    required String profileId,
    bool includeTombstones = false,
    DateTime? updatedAfter,
  }) {
    return _dayEntryQuery(
      profileId: profileId,
      includeTombstones: includeTombstones,
      updatedAfter: updatedAfter,
    ).watch();
  }

  // ------------------------------------------------------------- app settings

  /// Device-local key-value state. Not part of the sync model (open design
  /// question); `updated_at` kept for uniform change tracking.
  Future<void> setSetting({
    required String key,
    required String value,
    DateTime? updatedAt,
  }) async {
    await db.transaction(() async {
      final now = (updatedAt ?? _now()).toUtc();
      final existing = await (db.select(db.appSettings)
            ..where((t) => t.key.equals(key)))
          .getSingleOrNull();
      await db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: key,
              value: value,
              updatedAt:
                  existing == null ? now : _notBefore(now, existing.updatedAt),
            ),
          );
    });
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

  /// Profiles with unpushed local changes, tombstones included, by id.
  Future<List<Profile>> readDirtyProfiles() => (db.select(db.profiles)
        ..where((t) => t.dirty.equals(true))
        ..orderBy([(t) => OrderingTerm(expression: t.id)]))
      .get();

  /// Day entries with unpushed local changes, tombstones included, by id.
  Future<List<DayEntry>> readDirtyDayEntries() => (db.select(db.dayEntries)
        ..where((t) => t.dirty.equals(true))
        ..orderBy([(t) => OrderingTerm(expression: t.id)]))
      .get();

  /// Clears `dirty` on the row [id] of [table] only when its `local_rev`
  /// still equals [localRevAtPush] (the value read when the push was
  /// assembled). Returns whether the flag was cleared; `false` means a
  /// local write landed while the push was in flight and the row must be
  /// pushed again (AE11).
  Future<bool> markPushed({
    required SyncTable table,
    required String id,
    required int localRevAtPush,
  }) async {
    final int changed;
    switch (table) {
      case SyncTable.profiles:
        changed = await (db.update(db.profiles)
              ..where((t) =>
                  t.id.equals(id) & t.localRev.equals(localRevAtPush)))
            .write(const ProfilesCompanion(dirty: Value(false)));
      case SyncTable.dayEntries:
        changed = await (db.update(db.dayEntries)
              ..where((t) =>
                  t.id.equals(id) & t.localRev.equals(localRevAtPush)))
            .write(const DayEntriesCompanion(dirty: Value(false)));
      case SyncTable.profileGuardians:
        changed = 0;
    }
    return changed > 0;
  }

  /// Number of rows, live and tombstoned, in both synced tables that still
  /// need pushing.
  Future<int> dirtyCount() async {
    final p = await _count(db.profiles, db.profiles.id,
        db.profiles.dirty.equals(true));
    final d = await _count(db.dayEntries, db.dayEntries.id,
        db.dayEntries.dirty.equals(true));
    return p + d;
  }

  /// Flags every row, live and tombstoned, in both synced tables for push
  /// (first sign-in upload, R14). Bumps `local_rev` like any local write.
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
    });
  }

  /// Row counts, live and tombstoned, of both synced tables — what the
  /// upload-consent step shows before the first push (R14, AS4).
  Future<LocalRowCounts> countAllRows() async {
    final [p, d] = await Future.wait([
      _count(db.profiles, db.profiles.id),
      _count(db.dayEntries, db.dayEntries.id),
    ]);
    return (profiles: p, dayEntries: d);
  }

  /// True only when both synced tables hold no row of any kind — a
  /// tombstone-only database is not empty (it has deletions to push).
  Future<bool> isEmpty() async {
    final counts = await countAllRows();
    return counts.profiles == 0 && counts.dayEntries == 0;
  }

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
  /// local winner is pushed). The partial unique index is therefore never
  /// violated. Throws [RetryableSyncApplyError] when the entry's profile is
  /// not held locally yet.
  Future<bool> applyRemoteDayEntry(RemoteDayEntryRow remote) =>
      db.transaction(() => _applyDayEntry(remote, onlyExisting: false));

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
        SyncTable.profileGuardians =>
          const SyncStateCompanion(),
      },
    );
  }

  /// Applies one full-reconcile page (rows of one or both tables) in ONE
  /// transaction without touching any cursor (KTD2). Same per-row rules as
  /// [applyRemoteProfile] / [applyRemoteDayEntry]; profiles first. A
  /// throwing row rolls the page back — callers that need per-row
  /// independence fall back to the single-row applies.
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
    });
  }

  /// Applies the server's `resolved` copies returned by a push (rows the
  /// server tombstoned by resolution or declined as older): same rules as
  /// [applyRemoteProfile] / [applyRemoteDayEntry], written with
  /// `dirty = false`, profiles before day entries. Ids not held locally are
  /// no-ops — a resolution never inserts. One transaction for the batch.
  Future<void> applyResolved(List<RemoteRow> rows) async {
    await db.transaction(() async {
      for (final row in rows.whereType<RemoteProfileRow>()) {
        await _applyProfile(row, onlyExisting: true);
      }
      for (final row in rows.whereType<RemoteDayEntryRow>()) {
        await _applyDayEntry(row, onlyExisting: true);
      }
    });
  }

  // --------------------------------------------------------- sync: state row

  /// The `sync_state` singleton, or [kDefaultSyncState] when never written.
  Future<SyncStateRow> readSyncState() async {
    final row = await (db.select(db.syncState)..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    return row ?? kDefaultSyncState;
  }

  /// Replaces the `sync_state` singleton (the id is forced to 1).
  Future<void> writeSyncState(SyncStateRow state) async {
    await db
        .into(db.syncState)
        .insertOnConflictUpdate(state.copyWith(id: 1).toCompanion(false));
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
            birthYear: Value(remote.birthYear),
            relationship: Value(remote.relationship),
            transferredAt: Value(remote.transferredAt?.toUtc()),
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
        birthYear: Value(remote.birthYear),
        relationship: Value(remote.relationship),
        transferredAt: Value(remote.transferredAt?.toUtc()),
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
  /// payload and are marked not dirty - the server already knows, so the
  /// wipe must never be pushed back. Rows with unpushed local edits are
  /// wiped too: once revoked, the server rejects those pushes regardless.
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
          note: const Value(null),
          tags: const Value(<String>[]),
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

  Future<List<ProfileGuardianData>> getGuardiansForProfile(String profileId) =>
      (db.select(db.profileGuardians)..where((t) => t.profileId.equals(profileId)))
          .get();

  Stream<List<ProfileGuardianData>> watchGuardiansForProfile(String profileId) =>
      (db.select(db.profileGuardians)..where((t) => t.profileId.equals(profileId)))
          .watch();

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

    var updatedAt = remote.updatedAt.toUtc();
    var deletedAt = remote.deletedAt?.toUtc();
    if (deletedAt == null) {
      (updatedAt, deletedAt) = await _resolveSameDateConflicts(remote, updatedAt);
    }
    final tombstone = deletedAt != null;
    if (local == null) {
      await db.into(db.dayEntries).insert(DayEntriesCompanion.insert(
            id: remote.id,
            profileId: remote.profileId,
            localDate: remote.localDate,
            tz: remote.tz,
            flow: remote.flow,
            tags: Value(_dayEntryTags(tombstone, remote)),
            note: Value(_dayEntryNote(tombstone, remote)),
            updatedAt: updatedAt,
            deletedAt: Value(deletedAt),
            dirty: const Value(false),
            localRev: const Value(0),
            loggedByUserId: Value(remote.loggedByUserId),
            lastModifiedByUserId: Value(remote.lastModifiedByUserId),
          ));
      return true;
    }
    await (db.update(db.dayEntries)..where((t) => t.id.equals(remote.id)))
        .write(DayEntriesCompanion(
      profileId: Value(remote.profileId),
      localDate: Value(remote.localDate),
      tz: Value(remote.tz),
      flow: Value(remote.flow),
      tags: Value(_dayEntryTags(tombstone, remote)),
      note: Value(_dayEntryNote(tombstone, remote)),
      updatedAt: Value(updatedAt),
      deletedAt: Value(deletedAt),
      dirty: const Value(false),
      loggedByUserId: Value(remote.loggedByUserId ?? local.loggedByUserId),
      lastModifiedByUserId: Value(remote.lastModifiedByUserId ?? local.lastModifiedByUserId),
    ));
    return true;
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

  /// Runs the same-date rule against every other live local row for
  /// [remote]'s (profile, date), starting from [updatedAt] (only called
  /// while [remote] itself is not already a tombstone). A local loser is
  /// tombstoned in place with the winner's timestamp and marked dirty so
  /// the resolution is pushed; a remote loser makes [remote] itself the
  /// tombstone, stamped with the local winner's timestamp (>=
  /// `remote.updatedAt` by the rule). Returns the `updated_at` /
  /// `deleted_at` pair [remote] should be written with.
  Future<(DateTime, DateTime?)> _resolveSameDateConflicts(
      RemoteDayEntryRow remote, DateTime updatedAt) async {
    DateTime? deletedAt;
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
        // resolution is pushed.
        await (db.update(db.dayEntries)..where((t) => t.id.equals(other.id)))
            .write(DayEntriesCompanion(
          note: const Value(null),
          tags: const Value(<String>[]),
          updatedAt: Value(updatedAt),
          deletedAt: Value(updatedAt),
          dirty: const Value(true),
          localRev: Value(other.localRev + 1),
        ));
      } else {
        // Remote loser: store it as a tombstone stamped with the local
        // winner's timestamp (>= remote.updatedAt by the rule).
        updatedAt = other.updatedAt.toUtc();
        deletedAt = updatedAt;
      }
    }
    return (updatedAt, deletedAt);
  }

  /// The `tags` to write for a day entry row: cleared for a tombstone.
  List<String> _dayEntryTags(bool tombstone, RemoteDayEntryRow remote) =>
      tombstone ? const <String>[] : remote.tags;

  /// The `note` to write for a day entry row: cleared for a tombstone.
  String? _dayEntryNote(bool tombstone, RemoteDayEntryRow remote) =>
      tombstone ? null : remote.note;

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
  Selectable<DayEntry> _dayEntryQuery({
    required String profileId,
    required bool includeTombstones,
    String? localDate,
    DateTime? updatedAfter,
  }) {
    final query = db.select(db.dayEntries)
      ..where((row) {
        var condition = row.profileId.equals(profileId);
        if (localDate != null) {
          condition = condition & row.localDate.equals(localDate);
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
}
