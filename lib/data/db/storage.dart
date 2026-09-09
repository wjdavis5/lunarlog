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
///   payload cleared (`flow = none`, `note = null`, `tags = []`,
///   `display_name = ''`); rows are never removed.
/// * At most one *live* day entry per (profile, date): local writes update
///   the live row in place, remote applies run the same-date rule and
///   tombstone the loser with the winner's timestamp.
/// * Observations (Issue #240) are keyed by id alone, like profiles — there
///   is no same-date uniqueness to resolve: multiple live rows per
///   (profile, date, category) are the whole point of this child table.
///   Their tombstone clears every payload column, `category` included —
///   only `local_date`/`tz`/`source`/`source_id`/`import_id` survive a
///   delete (Issue #159: provenance is not health content, and a deleted
///   row must stay recognisable to a future re-import; see
///   `supabase/migrations/20260908170000_import_provenance.sql`'s
///   `observations_tombstone_payload_check`). `day_entries.source`/
///   `source_id`/`import_id` (Issue #159) get the same treatment.
/// * Profile modes (Issue #188) are one row per profile keyed by
///   `profile_id`, with NO tombstone (the server table has none either) —
///   an absent row means `tracking`, and rows are created lazily on first
///   write. Cycle overrides (Issue #188) tombstone like day entries:
///   `excluded_from_average`/`manual_start` reset to false and `note_id`
///   clears, while `cycle_start_date` (identity) survives — mirroring the
///   server's `cycle_overrides_tombstone_payload_check` exactly.
/// * UI reads filter tombstones; full-fidelity reads (tombstones included)
///   exist for sync.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lunarlog/domain/activity/merge_events.dart';
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/sync/local_row_counts.dart';

import '../sync/conflict_rules.dart';
import '../sync/remote_rows.dart';
import 'db.dart';
import 'tables.dart';
import 'ulid.dart';

export 'package:lunarlog/domain/sync/local_row_counts.dart' show LocalRowCounts;

export '../sync/remote_rows.dart'
    show
        RemoteCycleOverrideRow,
        RemoteDayEntryRow,
        RemoteObservationRow,
        RemoteProfileModeRow,
        RemoteProfileRow,
        RemoteRow,
        RetryableSyncApplyError,
        SyncTable;

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

void _validateTags(List<String> tags) {
  if (tags.length > kMaxTagCount) {
    throw ArgumentError.value(tags.length, 'tags',
        'must have at most $kMaxTagCount elements');
  }
  for (final tag in tags) {
    if (tag.length > kMaxTagLength) {
      throw ArgumentError.value(tag.length, 'tags',
          'must be at most $kMaxTagLength characters');
    }
  }
}

/// Issue #240: mirrors the server's `observations` CHECK constraints
/// (`supabase/migrations/20260908160000_observations.sql`). `category`/
/// `code` are bounded but never validated against a closed set — see
/// `lib/domain/models/observation.dart`'s doc comment.
/// Throws if [value] is non-null and longer than [max] UTF-16 code units.
/// Shared by the observation payload columns that are bounded by
/// `String.length` (the server's CHECK constraints on those columns count
/// characters, not bytes — see `_boundedUtf8BytesOrThrow` for the one
/// column, `raw`, that isn't).
void _boundedOrThrow(String? value, int max, String name) {
  if (value != null && value.length > max) {
    throw ArgumentError.value(value.length, name, 'must be at most $max characters');
  }
}

/// Throws if [value] is non-null and its UTF-8 encoding is longer than
/// [max] bytes.
///
/// Issue #240 review finding: bound UTF-8 *bytes* (`kMaxObservationRawLength`'s
/// own doc comment), not `String.length` (UTF-16 code units) — a non-ASCII
/// payload can encode to more UTF-8 bytes than code units, which is the unit
/// the server's `pg_column_size` check ultimately cares about.
void _boundedUtf8BytesOrThrow(String? value, int max, String name) {
  if (value == null) return;
  final byteLength = utf8.encode(value).length;
  if (byteLength > max) {
    throw ArgumentError.value(byteLength, name, 'must be at most $max UTF-8 bytes');
  }
}

/// Issue #159: mirrors `day_entries_source_id_length_check`
/// (`supabase/migrations/20260908170000_import_provenance.sql`).
void _validateDayEntryProvenance({String? sourceId}) {
  _boundedOrThrow(sourceId, kMaxDayEntrySourceIdLength, 'sourceId');
}

/// The `source`/`sourceId`/`importId` to write on an [upsertDayEntry]
/// update, one column set at a time (`this` fixed, `other` varies).
typedef _DayEntryProvenance = ({
  String source,
  String? sourceId,
  String? importId,
});

/// Issue #159 review finding: [DayEntry] domain objects built without an
/// explicit provenance default to the `manual`/null/null triple
/// (`domain.DayEntry`'s constructor), so a plain save of an *imported* day
/// — e.g. the day sheet re-saving an entry it loaded — must not be read as
/// "reset this back to manual". A caller-supplied `manual`/null/null triple
/// against an existing **non-manual** [live] row is therefore treated as
/// "provenance unspecified" and the stored provenance is kept; any other
/// combination (a real reset to manual, an explicit re-import, a `live`
/// that was already manual) writes exactly what the caller passed, as
/// before. `day_sheet.dart` no longer relies on this — it forwards the
/// loaded entry's own provenance — but the storage layer stays defensive
/// for any other caller that does the same as it once did.
_DayEntryProvenance _resolvedProvenanceForUpdate({
  required DayEntry live,
  required String source,
  required String? sourceId,
  required String? importId,
}) {
  final callerUnspecified =
      source == 'manual' && sourceId == null && importId == null;
  final liveIsNonManual =
      live.source != 'manual' || live.sourceId != null || live.importId != null;
  if (callerUnspecified && liveIsNonManual) {
    return (source: live.source, sourceId: live.sourceId, importId: live.importId);
  }
  return (source: source, sourceId: sourceId, importId: importId);
}

void _validateObservation({
  required String category,
  String? code,
  String? valueText,
  String? unit,
  String? sourceId,
  String? raw,
  int? intensity,
}) {
  if (category.isEmpty || category.length > kMaxObservationCategoryLength) {
    throw ArgumentError.value(category, 'category',
        'must be 1-$kMaxObservationCategoryLength characters');
  }
  _boundedOrThrow(code, kMaxObservationCodeLength, 'code');
  _boundedOrThrow(valueText, kMaxObservationValueTextLength, 'valueText');
  _boundedOrThrow(unit, kMaxObservationUnitLength, 'unit');
  _boundedOrThrow(sourceId, kMaxObservationSourceIdLength, 'sourceId');
  _boundedUtf8BytesOrThrow(raw, kMaxObservationRawLength, 'raw');
  if (intensity != null &&
      (intensity < kMinObservationIntensity || intensity > kMaxObservationIntensity)) {
    throw ArgumentError.value(intensity, 'intensity',
        'must be between $kMinObservationIntensity and $kMaxObservationIntensity');
  }
}

/// Issue #188: mirrors `profile_modes`' CHECK constraints
/// (`profile_modes_birth_control_method_length_check`) and validates the
/// three optional date fields as ISO calendar dates (the server validates
/// the same shape with a `^\d{4}-\d{2}-\d{2}$` check in `sync_push`).
void _validateProfileModePayload({
  String? modeStartedOn,
  String? birthControlMethod,
  String? birthControlStartedOn,
  String? birthControlStoppedOn,
}) {
  if (modeStartedOn != null) _validateLocalDate(modeStartedOn);
  _boundedOrThrow(
      birthControlMethod, kMaxBirthControlMethodLength, 'birthControlMethod');
  if (birthControlStartedOn != null) _validateLocalDate(birthControlStartedOn);
  if (birthControlStoppedOn != null) _validateLocalDate(birthControlStoppedOn);
}

/// Issue #188: mirrors `cycle_overrides`' CHECK constraints
/// (`cycle_overrides_note_id_length_check`).
void _validateCycleOverridePayload({String? noteId}) {
  _boundedOrThrow(noteId, kMaxCycleOverrideNoteIdLength, 'noteId');
}

/// The `sync_state` row as read when none has been written yet.
const SyncStateRow kDefaultSyncState = SyncStateRow(
  id: 1,
  deviceId: '',
  cursorProfiles: 0,
  cursorDayEntries: 0,
  cursorObservations: 0,
  cursorProfileModes: 0,
  cursorCycleOverrides: 0,
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
  /// [mode] (Issue #131) is the raw `toDb()` care-mode string, same
  /// treatment: presentation-only, synced like any other profile column.
  /// The three cycle-fact parameters (Issue #218) are the onboarding
  /// answers: [lastPeriodStart] as an ISO `yyyy-MM-dd` string (validated
  /// like every other stored civil date) and the two typical lengths as
  /// plain ints, stored as supplied and synced like any other profile
  /// column — the prediction domain's `CycleFacts.canSeed` is the gate on
  /// which values can seed an estimate, not this method.
  Future<Profile> upsertProfile({
    String? id,
    required String displayName,
    required bool isMinor,
    String mode = 'standard',
    int sortOrder = 0,
    DateTime? archivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? birthYear,
    String? relationship,
    String? lastPeriodStart,
    int? typicalCycleLengthDays,
    int? typicalPeriodLengthDays,
  }) async {
    // Async so validation failures surface as failed futures.
    _validateDisplayName(displayName);
    if (lastPeriodStart != null) _validateLocalDate(lastPeriodStart);
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
              mode: Value(mode),
              birthYear: Value(birthYear),
              relationship: Value(relationship),
              lastPeriodStart: Value(lastPeriodStart),
              typicalCycleLengthDays: Value(typicalCycleLengthDays),
              typicalPeriodLengthDays: Value(typicalPeriodLengthDays),
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
          mode: Value(mode),
          birthYear: Value(birthYear),
          relationship: Value(relationship),
          lastPeriodStart: Value(lastPeriodStart),
          typicalCycleLengthDays: Value(typicalCycleLengthDays),
          typicalPeriodLengthDays: Value(typicalPeriodLengthDays),
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

  /// Un-tombstones profile [id] in place — clears `deleted_at`, bumps
  /// `updated_at` (strictly after the stored value) and `local_rev`, marks
  /// the row dirty — without touching any other column (Issue #140 review
  /// round 2, item 6). Unlike [upsertProfile], which always overwrites
  /// every metadata column with the caller's values, restoring an
  /// account-import file's profile onto a tombstoned local one must keep
  /// what is actually stored (a `softDeleteProfile`'d row's own
  /// `isMinor`/`mode`/`sortOrder`/`birthYear`/`relationship` all survive a
  /// tombstone unchanged — only `displayName` was cleared, per
  /// [softDeleteProfile]'s own doc comment) rather than let the file's
  /// copy of that metadata silently win. A no-op — returns the row as-is —
  /// when [id] is already live; throws [StateError] when [id] does not
  /// exist at all (this should only ever be called for a profile already
  /// confirmed tombstoned).
  Future<Profile> reviveTombstonedProfile(String id) async {
    return db.transaction(() async {
      final existing = await _profileOrNull(id);
      if (existing == null) {
        throw StateError('profile not found: $id');
      }
      if (existing.deletedAt == null) return existing;
      final at = _afterStored(_now(), existing.updatedAt);
      await (db.update(db.profiles)..where((t) => t.id.equals(id))).write(
        ProfilesCompanion(
          updatedAt: Value(at),
          deletedAt: const Value(null),
          dirty: const Value(true),
          localRev: Value(existing.localRev + 1),
        ),
      );
      return _profileById(id);
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
  /// [id], when given, targets that exact row by id instead of the ordinary
  /// live-by-date lookup above — Issue #140 review, item 5: the partial
  /// unique index `day_entries_profile_source_source_id_uq` is not scoped
  /// to live rows, so an importer that finds an existing (live OR
  /// tombstoned) row for the same (profileId, source, sourceId) triple
  /// (`LunarLogStorage.findDayEntryBySource`) must revive that row by id
  /// rather than let the ordinary live-only lookup miss it and insert a
  /// second, colliding row. Reviving a tombstone this way is safe against
  /// the live-uniqueness index (`uq_day_entries_profile_date_live`): the
  /// only caller of this path (`AccountImporter`) only does so when
  /// [_planDayEntry] in `lib/domain/import/account_import.dart` has already
  /// established there is no live row at [localDate] to collide with.
  ///
  /// Marks the row dirty and bumps `local_rev`. Throws [ArgumentError] for
  /// a [note] over [kMaxNoteLength], a [tags] list over [kMaxTagCount]
  /// elements, or a [tags] element over [kMaxTagLength].
  Future<DayEntry> upsertDayEntry({
    String? id,
    required String profileId,
    required String localDate,
    required String tz,
    required FlowLevel flow,
    List<String> tags = const [],
    String? note,
    DateTime? updatedAt,
    String source = 'manual',
    String? sourceId,
    String? importId,
  }) async {
    // Async so validation failures surface as failed futures, not sync
    // throws, for callers awaiting the result.
    _validateLocalDate(localDate);
    _validateNote(note);
    _validateTags(tags);
    _validateDayEntryProvenance(sourceId: sourceId);
    return db.transaction(() async {
      final now = (updatedAt ?? _now()).toUtc();
      final live =
          id == null ? await _liveDayEntry(profileId, localDate) : await _dayEntryOrNull(id);
      if (live == null) {
        await db.into(db.dayEntries).insert(DayEntriesCompanion.insert(
              id: id ?? _generator.next(),
              profileId: profileId,
              localDate: localDate,
              tz: tz,
              flow: flow,
              tags: Value(tags),
              note: Value(note),
              updatedAt: now,
              dirty: const Value(true),
              localRev: const Value(1),
              source: Value(source),
              sourceId: Value(sourceId),
              importId: Value(importId),
            ));
      } else {
        final rowId = live.id;
        final provenance = _resolvedProvenanceForUpdate(
          live: live,
          source: source,
          sourceId: sourceId,
          importId: importId,
        );
        await (db.update(db.dayEntries)..where((t) => t.id.equals(rowId)))
            .write(DayEntriesCompanion(
          // Issue #140 review round 2, item 2: `localDate` must be written
          // here too, not just on the ordinary (id == null) path above —
          // the `id:` revival path (this branch) can target a row whose
          // stored `local_date` differs from [localDate] (a tombstone
          // found by (profileId, source, sourceId) rather than by date).
          // Leaving it out silently kept the stale date, so the read below
          // (`_liveDayEntries(profileId, localDate)`, which queries by the
          // NEW date) found nothing and threw `StateError('day entry
          // disappeared')`.
          localDate: Value(localDate),
          tz: Value(tz),
          flow: Value(flow),
          tags: Value(tags),
          note: Value(note),
          updatedAt: Value(_afterStored(now, live.updatedAt)),
          deletedAt: const Value(null),
          dirty: const Value(true),
          localRev: Value(live.localRev + 1),
          source: Value(provenance.source),
          sourceId: Value(provenance.sourceId),
          importId: Value(provenance.importId),
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
  /// its payload (`flow = none`, `note = null`, `tags = []`) and marking it
  /// dirty. Does nothing when there is no live entry (idempotent; never
  /// bumps `updated_at` without a change).
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
          flow: const Value(FlowLevel.none),
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

  // -------------------------------------------------------------- observations

  /// Creates or updates an observation keyed by [id] (a fresh ULID is
  /// generated when omitted); unlike [upsertDayEntry], identity is by [id]
  /// alone — multiple live rows per (profileId, localDate, category) are
  /// the whole point of this child table (Issue #240), so there is no
  /// same-date uniqueness to resolve against the way day entries have.
  /// Marks the row dirty and bumps `local_rev`. An update stamps
  /// `updated_at` strictly after the stored value. Throws [ArgumentError]
  /// for a [category]/[code]/[unit]/[sourceId]/[valueText]/[raw] over its
  /// bound (see `lib/domain/limits.dart`) or an [intensity] outside 1-5.
  Future<Observation> upsertObservation({
    String? id,
    required String dayEntryId,
    required String profileId,
    required String localDate,
    DateTime? observedAt,
    required String tz,
    required String category,
    String? code,
    double? valueNum,
    String? valueText,
    String? unit,
    int? intensity,
    bool excluded = false,
    String source = 'manual',
    String? sourceId,
    String? importId,
    String? raw,
    DateTime? updatedAt,
  }) async {
    // Async so validation failures surface as failed futures, not sync
    // throws, for callers awaiting the result.
    _validateLocalDate(localDate);
    _validateObservation(
      category: category,
      code: code,
      valueText: valueText,
      unit: unit,
      sourceId: sourceId,
      raw: raw,
      intensity: intensity,
    );
    return db.transaction(() async {
      final now = (updatedAt ?? _now()).toUtc();
      Observation? existing;
      if (id != null) existing = await _observationOrNull(id);
      if (existing == null) {
        final rowId = id ?? _generator.next();
        await db.into(db.observations).insert(ObservationsCompanion.insert(
              id: rowId,
              dayEntryId: dayEntryId,
              profileId: profileId,
              localDate: localDate,
              observedAt: Value(observedAt),
              tz: tz,
              category: Value(category),
              code: Value(code),
              valueNum: Value(valueNum),
              valueText: Value(valueText),
              unit: Value(unit),
              intensity: Value(intensity),
              excluded: Value(excluded),
              source: Value(source),
              sourceId: Value(sourceId),
              importId: Value(importId),
              raw: Value(raw),
              updatedAt: now,
              dirty: const Value(true),
              localRev: const Value(1),
            ));
        return _observationById(rowId);
      }
      final rowId = existing.id;
      await (db.update(db.observations)..where((t) => t.id.equals(rowId)))
          .write(ObservationsCompanion(
        dayEntryId: Value(dayEntryId),
        profileId: Value(profileId),
        localDate: Value(localDate),
        observedAt: Value(observedAt),
        tz: Value(tz),
        category: Value(category),
        code: Value(code),
        valueNum: Value(valueNum),
        valueText: Value(valueText),
        unit: Value(unit),
        intensity: Value(intensity),
        excluded: Value(excluded),
        source: Value(source),
        sourceId: Value(sourceId),
        importId: Value(importId),
        raw: Value(raw),
        updatedAt: Value(_afterStored(now, existing.updatedAt)),
        deletedAt: const Value(null),
        dirty: const Value(true),
        localRev: Value(existing.localRev + 1),
      ));
      return _observationById(rowId);
    });
  }

  /// Tombstones the observation [id]: sets `deleted_at` (and bumps
  /// `updated_at`), clears every payload column (`category` included —
  /// review finding: no longer the exception to this list — `code`,
  /// `value_num`, `value_text`, `unit`, `intensity`, `excluded` reset to
  /// false, `source_id`, `raw`, `observed_at`) — `local_date`/`tz` are
  /// kept, mirroring the server's `observations_tombstone_payload_check`
  /// exactly. Marks the row dirty. Idempotent: re-deleting a tombstone does
  /// nothing. No-op when [id] is not held locally.
  Future<void> softDeleteObservation(String id) async {
    await db.transaction(() async {
      final existing = await _observationOrNull(id);
      if (existing == null || existing.deletedAt != null) return;
      final at = _afterStored(_now(), existing.updatedAt);
      await (db.update(db.observations)..where((t) => t.id.equals(id))).write(
        ObservationsCompanion(
          category: const Value(null),
          observedAt: const Value(null),
          code: const Value(null),
          valueNum: const Value(null),
          valueText: const Value(null),
          unit: const Value(null),
          intensity: const Value(null),
          excluded: const Value(false),
          // Issue #159: sourceId (and importId, never touched by this
          // write) survive a tombstone -- a deleted row must stay
          // recognisable to a future re-import (reverses #240's original
          // "sourceId: const Value(null)" here; see the server-side
          // decision in supabase/migrations/20260908170000_import_provenance.sql).
          raw: const Value(null),
          updatedAt: Value(at),
          deletedAt: Value(at),
          dirty: const Value(true),
          localRev: Value(existing.localRev + 1),
        ),
      );
    });
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

  // ------------------------------------------------------------- profile modes

  /// Creates or updates the profile's single life-stage mode row (Issue
  /// #188), keyed by [profileId] — exactly one row per profile, no
  /// tombstone. Creates the row lazily on first write (the server's
  /// contract: an absent row means `tracking`). Marks the row dirty and
  /// bumps `local_rev`; an update stamps `updated_at` strictly after the
  /// stored value. [mode] is the raw `LifecycleMode` `toDb()` string, not
  /// validated here (the domain enum and the server's
  /// `profile_modes_mode_check` are the enforcement points — the
  /// `upsertProfile` care-mode precedent). Throws [ArgumentError] for a
  /// non-ISO date field or a [birthControlMethod] over
  /// [kMaxBirthControlMethodLength].
  Future<ProfileModeData> upsertProfileMode({
    required String profileId,
    required String mode,
    String? modeStartedOn,
    String? birthControlMethod,
    String? birthControlStartedOn,
    String? birthControlStoppedOn,
    bool healthSyncConsent = false,
    DateTime? updatedAt,
  }) async {
    // Async so validation failures surface as failed futures.
    _validateProfileModePayload(
      modeStartedOn: modeStartedOn,
      birthControlMethod: birthControlMethod,
      birthControlStartedOn: birthControlStartedOn,
      birthControlStoppedOn: birthControlStoppedOn,
    );
    return db.transaction(() async {
      final now = (updatedAt ?? _now()).toUtc();
      final existing = await _profileModeOrNull(profileId);
      if (existing == null) {
        await db.into(db.profileModes).insert(ProfileModesCompanion.insert(
              profileId: profileId,
              mode: Value(mode),
              modeStartedOn: Value(modeStartedOn),
              birthControlMethod: Value(birthControlMethod),
              birthControlStartedOn: Value(birthControlStartedOn),
              birthControlStoppedOn: Value(birthControlStoppedOn),
              healthSyncConsent: Value(healthSyncConsent),
              updatedAt: now,
              dirty: const Value(true),
              localRev: const Value(1),
            ));
        return _profileModeById(profileId);
      }
      await (db.update(db.profileModes)
            ..where((t) => t.profileId.equals(profileId)))
          .write(ProfileModesCompanion(
        mode: Value(mode),
        modeStartedOn: Value(modeStartedOn),
        birthControlMethod: Value(birthControlMethod),
        birthControlStartedOn: Value(birthControlStartedOn),
        birthControlStoppedOn: Value(birthControlStoppedOn),
        healthSyncConsent: Value(healthSyncConsent),
        updatedAt: Value(_afterStored(now, existing.updatedAt)),
        dirty: const Value(true),
        localRev: Value(existing.localRev + 1),
      ));
      return _profileModeById(profileId);
    });
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

  // ----------------------------------------------------------- cycle overrides

  /// Creates or updates a manual cycle correction (Issue #188), keyed by
  /// [id] within [profileId] (a fresh ULID is generated when omitted).
  /// Marks the row dirty and bumps `local_rev`; an update stamps
  /// `updated_at` strictly after the stored value. Throws
  /// [ArgumentError] for a non-ISO [cycleStartDate] or a [noteId] over
  /// [kMaxCycleOverrideNoteIdLength].
  Future<CycleOverrideData> upsertCycleOverride({
    String? id,
    required String profileId,
    required String cycleStartDate,
    bool excludedFromAverage = false,
    bool manualStart = false,
    String? noteId,
    DateTime? updatedAt,
  }) async {
    // Async so validation failures surface as failed futures.
    _validateLocalDate(cycleStartDate);
    _validateCycleOverridePayload(noteId: noteId);
    return db.transaction(() async {
      final now = (updatedAt ?? _now()).toUtc();
      CycleOverrideData? existing;
      if (id != null) existing = await _cycleOverrideOrNull(id, profileId);
      if (existing == null) {
        final rowId = id ?? _generator.next();
        await db.into(db.cycleOverrides).insert(CycleOverridesCompanion.insert(
              id: rowId,
              profileId: profileId,
              cycleStartDate: cycleStartDate,
              excludedFromAverage: Value(excludedFromAverage),
              manualStart: Value(manualStart),
              noteId: Value(noteId),
              updatedAt: now,
              dirty: const Value(true),
              localRev: const Value(1),
            ));
        return _cycleOverrideById(rowId, profileId);
      }
      final rowId = existing.id;
      await (db.update(db.cycleOverrides)
            ..where((t) =>
                t.id.equals(rowId) & t.profileId.equals(profileId)))
          .write(CycleOverridesCompanion(
        cycleStartDate: Value(cycleStartDate),
        excludedFromAverage: Value(excludedFromAverage),
        manualStart: Value(manualStart),
        noteId: Value(noteId),
        updatedAt: Value(_afterStored(now, existing.updatedAt)),
        deletedAt: const Value(null),
        dirty: const Value(true),
        localRev: Value(existing.localRev + 1),
      ));
      return _cycleOverrideById(rowId, profileId);
    });
  }

  /// Tombstones the cycle override [id] within [profileId]: sets
  /// `deleted_at` (and bumps `updated_at`), clears every payload column
  /// (`excluded_from_average`/`manual_start` reset to false, `note_id`
  /// nulled — mirroring the server's
  /// `cycle_overrides_tombstone_payload_check` exactly), keeps
  /// `cycle_start_date` (identity). Marks the row dirty. Idempotent:
  /// re-deleting a tombstone does nothing. No-op when the row is not held
  /// locally.
  Future<void> softDeleteCycleOverride({
    required String id,
    required String profileId,
  }) async {
    await db.transaction(() async {
      final existing = await _cycleOverrideOrNull(id, profileId);
      if (existing == null || existing.deletedAt != null) return;
      final at = _afterStored(_now(), existing.updatedAt);
      await (db.update(db.cycleOverrides)
            ..where((t) => t.id.equals(id) & t.profileId.equals(profileId)))
          .write(CycleOverridesCompanion(
        excludedFromAverage: const Value(false),
        manualStart: const Value(false),
        noteId: const Value(null),
        updatedAt: Value(at),
        deletedAt: Value(at),
        dirty: const Value(true),
        localRev: Value(existing.localRev + 1),
      ));
    });
  }

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
      case SyncTable.observations:
        changed = await (db.update(db.observations)
              ..where((t) =>
                  t.id.equals(id) & t.localRev.equals(localRevAtPush)))
            .write(const ObservationsCompanion(dirty: Value(false)));
      case SyncTable.profileModes:
        changed = await (db.update(db.profileModes)
              ..where((t) =>
                  t.profileId.equals(id) & t.localRev.equals(localRevAtPush)))
            .write(const ProfileModesCompanion(dirty: Value(false)));
      case SyncTable.cycleOverrides:
        // The table's key is composite (id, profile_id), but ids are
        // client-generated ULIDs — globally unique in practice — so the id
        // alone identifies at most one row; matching on it keeps
        // [markPushed]'s table-agnostic signature.
        changed = await (db.update(db.cycleOverrides)
              ..where((t) =>
                  t.id.equals(id) & t.localRev.equals(localRevAtPush)))
            .write(const CycleOverridesCompanion(dirty: Value(false)));
      case SyncTable.profileGuardians:
        changed = 0;
    }
    return changed > 0;
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
    return p + d + o + pm + co;
  }

  /// Flags every row, live and tombstoned, in every synced table for push
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
    });
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
    return await _count(db.cycleOverrides, db.cycleOverrides.id) == 0;
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
            mode: Value(remote.mode),
            birthYear: Value(remote.birthYear),
            relationship: Value(remote.relationship),
            transferredAt: Value(remote.transferredAt?.toUtc()),
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
}
