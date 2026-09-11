part of 'storage.dart';

// Local writes for [LunarLogStorage] (part of `storage.dart`, mixed into
// the class below). Every local write stamps `updated_at` strictly after
// the stored value ([_afterStored]), enforces the payload limits mirroring
// the server's CHECK constraints, marks the row `dirty` and bumps
// `local_rev`. Deletes are tombstones; rows are never removed.
// Moved verbatim from `storage.dart` (#434); the validation helpers move
// with their callers.

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

/// Issue #128: mirrors `care_notes_body_length_check`. Only the max bound
/// — an empty note is meaningless but harmless, and the day-entry note
/// precedent (`_validateNote`) likewise bounds only the maximum.
void _validateCareNoteBody(String body) {
  _boundedOrThrow(body, kMaxCareNoteLength, 'body');
}

/// Issue #128: mirrors `visit_prep_items_body_length_check` (same
/// max-only shape as [_validateCareNoteBody]).
void _validateVisitPrepItemBody(String body) {
  _boundedOrThrow(body, kMaxVisitPrepItemLength, 'body');
}

/// Local-write members mixed into [LunarLogStorage].
mixin LunarLogStorageLocalWrites on LunarLogStorageQueries {
  UlidGenerator get _generator;
  DateTime _now();

  // ---------------------------------------------------------------- profiles

  /// Creates or updates a profile keyed by [id] (a fresh ULID is generated
  /// when omitted). A newer write to a tombstoned profile revives it
  /// (`deleted_at` cleared) — under LWW a newer non-delete must win.
  /// Marks the row dirty and bumps `local_rev`. An update stamps
  /// `updated_at` strictly after the stored value. Throws [ArgumentError]
  /// for a [displayName] over [kMaxDisplayNameLength].
  ///
  /// [birthYear] and [relationship] are optional subject metadata
  /// (Issue #4 R1, R3); [relationship] is the raw
  /// `toDb()` string, not validated here (the domain enum's closed set and
  /// the server's check constraint are the enforcement points). Neither is
  /// device-local bookkeeping: both sync like any other profile column.
  /// (`birthYear` is no longer display-only — it feeds the #153 health-sync
  /// minor gate's fail-closed year check; this method never writes the
  /// gate's server-owned `transferredToUserId` input.)
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
    bool pms = false,
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
              pms: Value(pms),
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
          pms: Value(pms),
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
  /// its payload (`flow = none`, `note = null`, `tags = []`, `pms = false`)
  /// and marking it dirty. Does nothing when there is no live entry
  /// (idempotent; never bumps `updated_at` without a change).
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
          // Issue #220: pms is health content like flow/tags/note — a
          // tombstone carries no payload (the server's
          // day_entries_tombstone_pms_check is the structural backstop).
          pms: const Value(false),
          updatedAt: Value(at),
          deletedAt: Value(at),
          dirty: const Value(true),
          localRev: Value(live.localRev + 1),
        ),
      );
    });
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

  // --------------------------------------------------------------- care notes

  /// Creates or updates a standing care note (Issue #128), keyed by [id]
  /// (a fresh ULID is generated when omitted). Marks the row dirty and
  /// bumps `local_rev`; an update stamps `updated_at` strictly after the
  /// stored value and revives a tombstone (`deleted_at` cleared — under
  /// LWW a newer non-delete wins). Throws [ArgumentError] for a [body]
  /// over [kMaxCareNoteLength].
  Future<CareNoteData> upsertCareNote({
    String? id,
    required String profileId,
    required String body,
    DateTime? updatedAt,
  }) async {
    // Async so validation failures surface as failed futures.
    _validateCareNoteBody(body);
    return db.transaction(() async {
      final now = (updatedAt ?? _now()).toUtc();
      CareNoteData? existing;
      if (id != null) existing = await _careNoteOrNull(id);
      if (existing == null) {
        final rowId = id ?? _generator.next();
        await db.into(db.careNotes).insert(CareNotesCompanion.insert(
              id: rowId,
              profileId: profileId,
              body: body,
              updatedAt: now,
              dirty: const Value(true),
              localRev: const Value(1),
            ));
        return _careNoteById(rowId);
      }
      final rowId = existing.id;
      await (db.update(db.careNotes)..where((t) => t.id.equals(rowId))).write(
        CareNotesCompanion(
          body: Value(body),
          updatedAt: Value(_afterStored(now, existing.updatedAt)),
          deletedAt: const Value(null),
          dirty: const Value(true),
          localRev: Value(existing.localRev + 1),
        ),
      );
      return _careNoteById(rowId);
    });
  }

  /// Tombstones the care note [id]: sets `deleted_at` (and bumps
  /// `updated_at`), clears `body` (tombstones carry no payload — the
  /// server's `care_notes_tombstone_payload_check` mirror). Marks the row
  /// dirty. Idempotent: re-deleting a tombstone does nothing. No-op when
  /// the row is not held locally.
  Future<void> softDeleteCareNote(String id) async {
    await db.transaction(() async {
      final existing = await _careNoteOrNull(id);
      if (existing == null || existing.deletedAt != null) return;
      final at = _afterStored(_now(), existing.updatedAt);
      await (db.update(db.careNotes)..where((t) => t.id.equals(id))).write(
        CareNotesCompanion(
          body: const Value(''),
          updatedAt: Value(at),
          deletedAt: Value(at),
          dirty: const Value(true),
          localRev: Value(existing.localRev + 1),
        ),
      );
    });
  }

  // ---------------------------------------------------------- visit prep list

  /// Adds a visit-prep item (Issue #128), keyed by [id] (a fresh ULID is
  /// generated when omitted). A new item always lands unchecked
  /// (`checked_by`/`checked_at` null) — checking is [setVisitPrepItemChecked]'s
  /// job, never this one's. Marks the row dirty and bumps `local_rev`.
  /// Throws [ArgumentError] for a [body] over [kMaxVisitPrepItemLength].
  Future<VisitPrepItemData> addVisitPrepItem({
    String? id,
    required String profileId,
    required String body,
    DateTime? updatedAt,
  }) async {
    // Async so validation failures surface as failed futures.
    _validateVisitPrepItemBody(body);
    return db.transaction(() async {
      final now = (updatedAt ?? _now()).toUtc();
      final rowId = id ?? _generator.next();
      await db.into(db.visitPrepItems).insert(VisitPrepItemsCompanion.insert(
            id: rowId,
            profileId: profileId,
            body: body,
            updatedAt: now,
            dirty: const Value(true),
            localRev: const Value(1),
          ));
      return _visitPrepItemById(rowId);
    });
  }

  /// Edits a prep item's text (Issue #128). The check state is identity,
  /// not payload, for this operation: the stored `is_checked`/
  /// `checked_by`/`checked_at` survive a text edit, and a tombstone is
  /// revived (`deleted_at` cleared). Marks the row dirty and bumps
  /// `local_rev`. Throws [ArgumentError] for a [body] over
  /// [kMaxVisitPrepItemLength]. No-op when the row is not held locally.
  Future<VisitPrepItemData?> editVisitPrepItem({
    required String id,
    required String body,
    DateTime? updatedAt,
  }) async {
    // Async so validation failures surface as failed futures.
    _validateVisitPrepItemBody(body);
    return db.transaction(() async {
      final existing = await _visitPrepItemOrNull(id);
      if (existing == null) return null;
      final now = (updatedAt ?? _now()).toUtc();
      await (db.update(db.visitPrepItems)..where((t) => t.id.equals(id)))
          .write(VisitPrepItemsCompanion(
        body: Value(body),
        updatedAt: Value(_afterStored(now, existing.updatedAt)),
        deletedAt: const Value(null),
        dirty: const Value(true),
        localRev: Value(existing.localRev + 1),
      ));
      return _visitPrepItemById(id);
    });
  }

  /// Checks (or unchecks) a prep item (Issue #128, AC3). Checking records
  /// who checked it ([checkedByUserId], the bound account — null for a
  /// never-synced local-only operator) and when; unchecking clears both.
  /// The item stays visible either way — checking never deletes. Marks the
  /// row dirty and bumps `local_rev`. No-op when the row is not held
  /// locally or is tombstoned.
  Future<VisitPrepItemData?> setVisitPrepItemChecked({
    required String id,
    required bool checked,
    String? checkedByUserId,
    DateTime? updatedAt,
  }) async {
    return db.transaction(() async {
      final existing = await _visitPrepItemOrNull(id);
      if (existing == null || existing.deletedAt != null) return null;
      final at = _afterStored((updatedAt ?? _now()).toUtc(), existing.updatedAt);
      await (db.update(db.visitPrepItems)..where((t) => t.id.equals(id)))
          .write(VisitPrepItemsCompanion(
        isChecked: Value(checked),
        checkedByUserId: Value(checked ? checkedByUserId : null),
        checkedAt: Value(checked ? at : null),
        updatedAt: Value(at),
        dirty: const Value(true),
        localRev: Value(existing.localRev + 1),
      ));
      return _visitPrepItemById(id);
    });
  }

  /// Tombstones the prep item [id]: sets `deleted_at` (and bumps
  /// `updated_at`), clears `body`, resets the check state (tombstones
  /// carry no payload — the server's
  /// `visit_prep_items_tombstone_payload_check` mirror). Marks the row
  /// dirty. Idempotent; no-op when the row is not held locally.
  Future<void> softDeleteVisitPrepItem(String id) async {
    await db.transaction(() async {
      final existing = await _visitPrepItemOrNull(id);
      if (existing == null || existing.deletedAt != null) return;
      final at = _afterStored(_now(), existing.updatedAt);
      await (db.update(db.visitPrepItems)..where((t) => t.id.equals(id)))
          .write(VisitPrepItemsCompanion(
        body: const Value(''),
        isChecked: const Value(false),
        checkedByUserId: const Value(null),
        checkedAt: const Value(null),
        updatedAt: Value(at),
        deletedAt: Value(at),
        dirty: const Value(true),
        localRev: Value(existing.localRev + 1),
      ));
    });
  }

  /// Clears a profile's visit-prep list (Issue #128): tombstones every
  /// *checked*, live item — unchecked items survive the clear, so clearing
  /// means "we covered these", not "drop the whole list". Returns the
  /// number of items cleared. Each tombstone is marked dirty (the clear
  /// itself syncs); already-tombstoned rows are untouched.
  Future<int> clearCheckedVisitPrepItems(String profileId) async {
    return db.transaction(() async {
      final checked = await (_carePrepCheckedQuery(profileId)).get();
      for (final row in checked) {
        final at = _afterStored(_now(), row.updatedAt);
        await (db.update(db.visitPrepItems)
              ..where((t) => t.id.equals(row.id)))
            .write(VisitPrepItemsCompanion(
          body: const Value(''),
          isChecked: const Value(false),
          checkedByUserId: const Value(null),
          checkedAt: const Value(null),
          updatedAt: Value(at),
          deletedAt: Value(at),
          dirty: const Value(true),
          localRev: Value(row.localRev + 1),
        ));
      }
      return checked.length;
    });
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
      case SyncTable.careNotes:
        changed = await (db.update(db.careNotes)
              ..where((t) =>
                  t.id.equals(id) & t.localRev.equals(localRevAtPush)))
            .write(const CareNotesCompanion(dirty: Value(false)));
      case SyncTable.visitPrepItems:
        changed = await (db.update(db.visitPrepItems)
              ..where((t) =>
                  t.id.equals(id) & t.localRev.equals(localRevAtPush)))
            .write(const VisitPrepItemsCompanion(dirty: Value(false)));
      case SyncTable.profileGuardians:
        changed = 0;
    }
    return changed > 0;
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
      await db.update(db.careNotes).write(CareNotesCompanion.custom(
            dirty: const Constant(true),
            localRev: db.careNotes.localRev + const Constant(1),
          ));
      await db.update(db.visitPrepItems).write(VisitPrepItemsCompanion.custom(
            dirty: const Constant(true),
            localRev: db.visitPrepItems.localRev + const Constant(1),
          ));
    });
  }

  /// Replaces the `sync_state` singleton (the id is forced to 1).
  Future<void> writeSyncState(SyncStateRow state) async {
    await db
        .into(db.syncState)
        .insertOnConflictUpdate(state.copyWith(id: 1).toCompanion(false));
  }

}
