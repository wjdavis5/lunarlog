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

/// Parses a stored ISO `yyyy-MM-dd` civil date, once, into a [LocalDate]
/// (Issue #848). [LocalDate]'s own constructor is the shape validation — a
/// malformed string or an impossible calendar date cannot be represented —
/// so callers construct the value here and then validate *range* on the
/// resulting [LocalDate] via [DayEntryPolicy], rather than the old
/// `_validateLocalDate(String)` re-parse that checked shape only.
LocalDate _parseLocalDate(String localDate) {
  try {
    return LocalDate.fromIso(localDate);
  } on ArgumentError {
    throw ArgumentError.value(
        localDate, 'localDate', 'must be an ISO yyyy-MM-dd calendar date');
  }
}

/// Issue #848: takes an already-parsed [LocalDate], not the raw string. The
/// previous string signature re-parsed a value the caller already had as a
/// `LocalDate` and checked shape only, which is exactly how an out-of-range
/// date could pass every local write. Constructing the [LocalDate] (via
/// [_parseLocalDate]) is the shape check; this named seam now documents
/// that all stored civil dates flow through one parsed value, and the
/// day-entry paths pair it with [DayEntryPolicy.validateDate] for the
/// range rules.
void _validateLocalDate(LocalDate localDate) {}

/// Issue #848: throws [ArgumentError] when [date] violates
/// [DayEntryPolicy] — a date more than one day in the future (the +1
/// tolerance is for timezone travel), or one whose year precedes the
/// profile's known [birthYear]. Mirrors the server's `sync_push` day-entry
/// date bounds, so a row this layer accepts is not later rejected into
/// `rejected` at push time.
void _validateDayEntryDate(
  LocalDate date, {
  required LocalDate today,
  int? birthYear,
}) {
  final violation = DayEntryPolicy.validateDate(
    date,
    today: today,
    birthYear: birthYear,
  ).violation;
  switch (violation) {
    case DayEntryDateViolation.futureDate:
      throw ArgumentError.value(date.iso, 'localDate',
          'must not be more than one day in the future');
    case DayEntryDateViolation.beforeBirthYear:
      throw ArgumentError.value(date.iso, 'localDate',
          'must not be before the profile birth year');
    case null:
      break;
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

/// The `unitsUnconfirmed` write for a profile update (Issue #637,
/// LLA-039 review round 2): [upsertProfile]'s update branch is a
/// full-row write, so [bbtUnit]/[weightUnit] arrive on every call —
/// including an edit to some unrelated field that merely carries
/// [existing]'s own (possibly still-unconfirmed, still-default) value
/// through unchanged. Clearing the marker unconditionally there would
/// silently confirm a value nobody actually touched, letting that
/// unrelated edit push the stale default over the server's real
/// preference — the exact LLA-039 clobber, just reached through a
/// different edit. Cleared only when the write actually changes
/// [existing]'s stored value; otherwise left untouched
/// (`Value.absent()`) so a genuinely unconfirmed row stays protected
/// until something really sets it.
Value<bool?> _unitsUnconfirmedWrite(
  Profile existing,
  String bbtUnit,
  String weightUnit,
) =>
    (bbtUnit != existing.bbtUnit || weightUnit != existing.weightUnit)
        ? const Value(false)
        : const Value.absent();

/// The `pmsUnconfirmed` write for a day-entry update ([_writeDayEntry]'s
/// update branch) — the same reasoning as [_unitsUnconfirmedWrite], for
/// [pms] against [live]'s own stored value.
Value<bool?> _pmsUnconfirmedWrite(DayEntry live, bool pms) =>
    pms != live.pms ? const Value(false) : const Value.absent();

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

/// Issue #649 (CRAP-gate split): the document-level half of
/// [_validateTrackingPreferences] — the client-only entry-count bound that
/// mirrors nothing server-side (`kMaxTrackingPreferencesEntries`).
void _checkEntryCount(Map<String, dynamic> decoded) {
  if (decoded.length > kMaxTrackingPreferencesEntries) {
    throw ArgumentError.value(decoded.length, 'jsonText',
        'tracking preferences must have at most $kMaxTrackingPreferencesEntries entries');
  }
}

/// Issue #649 (CRAP-gate split): mirrors `is_valid_tracking_preferences`'s
/// key-length rule (`key = '' or length(key) > 64`).
void _checkKey(String key) {
  if (key.isEmpty || key.length > kMaxTrackingPreferencesKeyLength) {
    throw ArgumentError.value(key, 'jsonText',
        'tracking preference keys must be 1-$kMaxTrackingPreferencesKeyLength characters');
  }
}

/// Issue #649 (CRAP-gate split): mirrors `is_valid_tracking_preferences`'s
/// `jsonb_typeof(value) <> 'object'` and unknown-key checks.
void _checkEntryShape(String key, Object? value) {
  if (value is! Map) {
    throw ArgumentError.value(key, 'jsonText',
        'tracking preference "$key" must be an object');
  }
  for (final entryKey in value.keys) {
    if (entryKey != 'enabled' && entryKey != 'sort_order') {
      throw ArgumentError.value(key, 'jsonText',
          'tracking preference "$key" carries an unknown key "$entryKey"');
    }
  }
}

/// Issue #649 (CRAP-gate split): mirrors `is_valid_tracking_preferences`'s
/// `jsonb_typeof(value -> 'enabled') is distinct from 'boolean'` check.
/// [value] is already known to be a [Map] — [_checkEntryShape] ran first.
void _checkEnabled(String key, Map value) {
  if (value['enabled'] is! bool) {
    throw ArgumentError.value(key, 'jsonText',
        'tracking preference "$key" must have a boolean "enabled"');
  }
}

/// Issue #649 (CRAP-gate split): mirrors `is_valid_tracking_preferences`'s
/// `sort_order` regex/upper-bound checks (non-negative integer, <= 1000).
/// [value] is already known to be a [Map] — [_checkEntryShape] ran first.
void _checkSortOrder(String key, Map value) {
  final sortOrder = value['sort_order'];
  if (sortOrder is! int ||
      sortOrder < kMinTrackingPreferencesSortOrder ||
      sortOrder > kMaxTrackingPreferencesSortOrder) {
    throw ArgumentError.value(
        key,
        'jsonText',
        'tracking preference "$key" must have an integer "sort_order" in '
        '[$kMinTrackingPreferencesSortOrder, $kMaxTrackingPreferencesSortOrder]');
  }
}

/// Issue #649: mirrors `is_valid_tracking_preferences`
/// (`profiles_tracking_preferences_check`,
/// `supabase/migrations/20260915000000_profile_tracking_preferences.sql`)
/// exactly, plus the client-only entry-count bound that CHECK does not
/// (yet) enforce (`kMaxTrackingPreferencesEntries`). [decoded] is the
/// already-JSON-decoded document (an object — the caller has already
/// handled the null/empty-text "clear" case before this runs). A document
/// that would fail the server's CHECK is rejected here first, so it never
/// stores locally, goes dirty, and wedges the profile's sync row on every
/// push thereafter. Pure orchestration (CRAP-gate split): each rule lives
/// in its own small `_checkX` helper above.
void _validateTrackingPreferences(Map<String, dynamic> decoded) {
  _checkEntryCount(decoded);
  for (final mapEntry in decoded.entries) {
    final key = mapEntry.key;
    _checkKey(key);
    final value = mapEntry.value;
    _checkEntryShape(key, value);
    final entry = value as Map;
    _checkEnabled(key, entry);
    _checkSortOrder(key, entry);
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
  double? valueNum,
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
  // Issue #140 review, LLA-092: a NaN/Infinity value_num persists cleanly
  // here (sqlite has no numeric-range CHECK to catch it) and only fails
  // much later and far away, when `row_codec.dart`'s `encodeObservation`
  // tries to `jsonEncode` it for an unrelated sync push -- rejecting it at
  // the write boundary means a bad value can never reach storage in the
  // first place, from any writer (import, a future manual entry path, or
  // this store's own bulk seam), not only the one caught at parse time.
  if (valueNum != null && !valueNum.isFinite) {
    throw ArgumentError.value(valueNum, 'valueNum', 'must be a finite number');
  }
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
  String? estimatedDueDate,
  String? postpartumBirthDate,
  String? birthControlMethod,
  String? birthControlStartedOn,
  String? birthControlStoppedOn,
}) {
  if (modeStartedOn != null) _validateLocalDate(_parseLocalDate(modeStartedOn));
  if (estimatedDueDate != null) _validateLocalDate(_parseLocalDate(estimatedDueDate));
  if (postpartumBirthDate != null) {
    _validateLocalDate(_parseLocalDate(postpartumBirthDate));
  }
  _boundedOrThrow(
      birthControlMethod, kMaxBirthControlMethodLength, 'birthControlMethod');
  if (birthControlStartedOn != null) {
    _validateLocalDate(_parseLocalDate(birthControlStartedOn));
  }
  if (birthControlStoppedOn != null) {
    _validateLocalDate(_parseLocalDate(birthControlStoppedOn));
  }
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

/// Issue #801: mirrors `guardian_notes_body_length_check` (same max-only
/// shape as [_validateCareNoteBody]).
void _validateGuardianNoteBody(String body) {
  _boundedOrThrow(body, kMaxCareNoteLength, 'body');
}

/// Issue #257: mirrors `profile_tag_registry_code_length_check` — both the
/// min (a code is required; unlike a note body, an empty identifier could
/// never resolve) and the max (the same 64-char ceiling every tag-code
/// element carries).
void _validateRegistryCode(String code) {
  if (code.isEmpty || code.length > kMaxTagLength) {
    throw ArgumentError.value(code.length, 'code',
        'must be 1..$kMaxTagLength characters');
  }
}

/// Input payload for atomically upserting an observation alongside a day entry
/// in [LunarLogStorageLocalWrites.saveDayEntryWithObservations].
class UpsertObservationPayload {
  const UpsertObservationPayload({
    this.id,
    this.dayEntryId,
    required this.profileId,
    required this.localDate,
    this.observedAt,
    required this.tz,
    required this.category,
    this.code,
    this.valueNum,
    this.valueText,
    this.unit,
    this.intensity,
    this.excluded = false,
    this.source = 'manual',
    this.sourceId,
    this.importId,
    this.raw,
    this.updatedAt,
  });

  final String? id;
  final String? dayEntryId;
  final String profileId;
  final String localDate;
  final DateTime? observedAt;
  final String tz;
  final String category;
  final String? code;
  final double? valueNum;
  final String? valueText;
  final String? unit;
  final int? intensity;
  final bool excluded;
  final String source;
  final String? sourceId;
  final String? importId;
  final String? raw;
  final DateTime? updatedAt;
}

/// Local-write members mixed into [LunarLogStorage].
mixin LunarLogStorageLocalWrites on LunarLogStorageQueries {
  UlidGenerator get _generator;
  DateTime _now();

  /// Issue #848: the device's local civil date, supplied by the concrete
  /// store (defaulting to `LocalDate.today`), used only by the day-entry
  /// date-bounds policy — never for sync timestamps, which stay on the
  /// UTC [_now] clock.
  LocalDate _today();

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
  /// [bbtUnit] and [weightUnit] (Issue #255) are the raw `toDb()` strings
  /// of the per-profile display-unit preferences, same treatment as
  /// [mode]: presentation-only, synced like any other profile column.
  /// They are display preferences only — never a storage unit (each
  /// `observations` row carries its own `unit`).
  ///
  /// [trackingPreferences] (Issue #259) is the raw JSON text of the
  /// `{category: {enabled, sort_order}}` document
  /// (`TrackingPreferences.toJsonText`); null means never customized.
  /// Carried on every full-row write so an unrelated edit never clears
  /// the shared copy (the same full-row-overwrite discipline as
  /// [DriftProfilesRepository]'s update path documents).
  Future<Profile> upsertProfile({
    String? id,
    required String displayName,
    required bool isMinor,
    String mode = 'standard',
    String bbtUnit = 'celsius',
    String weightUnit = 'kg',
    String? trackingPreferences,
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
    if (lastPeriodStart != null) {
      _validateLocalDate(_parseLocalDate(lastPeriodStart));
    }
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
              bbtUnit: Value(bbtUnit),
              weightUnit: Value(weightUnit),
              // Issue #637, LLA-039: this call is the caller's real,
              // explicit value for bbtUnit/weightUnit (never a stale
              // upgrade-era default), so the row is confirmed from the
              // moment it exists.
              unitsUnconfirmed: const Value(false),
              trackingPreferences: Value(trackingPreferences),
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
          bbtUnit: Value(bbtUnit),
          weightUnit: Value(weightUnit),
          unitsUnconfirmed:
              _unitsUnconfirmedWrite(existing, bbtUnit, weightUnit),
          trackingPreferences: Value(trackingPreferences),
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

  /// Writes (or clears) the profile's tracking-preferences document
  /// (Issue #259): [jsonText] is the raw JSON text [TrackingPreferences]
  /// produces, or null to clear back to "never customized" (which resolves
  /// identically to an empty document). This is the column's *only*
  /// dedicated write path — everything else about the row is untouched —
  /// so curating the day sheet never restamps or clobbers any other
  /// profile metadata. Marks the row dirty and bumps `local_rev` (the
  /// document syncs to co-guardians, AC1/AC6); stamps `updated_at`
  /// strictly after the stored value like every local write. No-op when
  /// the row is not held locally or is tombstoned (curating a deleted
  /// profile is meaningless). Throws [ArgumentError] when [jsonText] is
  /// not null and not a JSON object, or when it fails
  /// [_validateTrackingPreferences] (Issue #649: mirrors the server's
  /// `profiles_tracking_preferences_check`/`is_valid_tracking_preferences`
  /// exactly — per-entry boolean `enabled`, integer `sort_order` in
  /// [0, 1000], 1-64 char keys, no extra keys — plus a client-only
  /// entry-count bound that CHECK does not enforce). A document that
  /// would fail the server's CHECK is rejected here first, so it never
  /// stores locally, goes dirty, and wedges the profile's entire sync row
  /// on every push. A null [jsonText] is stored as the
  /// explicitly empty document `'{}'`: a clear must be non-null to survive
  /// the codec's emit-only-when-non-null rule and actually propagate.
  Future<Profile?> setTrackingPreferences(
    String profileId,
    String? jsonText,
  ) async {
    jsonText ??= '{}';
    final String stored = jsonText;
    if (jsonText.isNotEmpty) {
      final Object? decoded;
      try {
        decoded = jsonDecode(jsonText);
      } on FormatException {
        throw ArgumentError.value(jsonText, 'jsonText',
            'tracking preferences must be valid JSON');
      }
      if (decoded is! Map<String, dynamic>) {
        throw ArgumentError.value(jsonText, 'jsonText',
            'tracking preferences must be a JSON object');
      }
      _validateTrackingPreferences(decoded);
    }
    return db.transaction(() async {
      final existing = await _profileOrNull(profileId);
      if (existing == null || existing.deletedAt != null) return null;
      await (db.update(db.profiles)..where((t) => t.id.equals(profileId)))
          .write(ProfilesCompanion(
        trackingPreferences: Value(stored),
        updatedAt: Value(_afterStored(_now(), existing.updatedAt)),
        dirty: const Value(true),
        localRev: Value(existing.localRev + 1),
      ));
      return _profileById(profileId);
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
  }) =>
      saveDayEntryWithObservations(
        id: id,
        profileId: profileId,
        localDate: localDate,
        tz: tz,
        flow: flow,
        tags: tags,
        note: note,
        pms: pms,
        updatedAt: updatedAt,
        source: source,
        sourceId: sourceId,
        importId: importId,
      );

  /// Atomically writes [entry] and its child [observationsToUpsert], and
  /// soft-deletes any observation IDs in [observationIdsToDelete] inside a
  /// single database transaction.
  ///
  /// Pre-validates all inputs before opening the transaction. If any validation
  /// or storage write fails, the entire transaction rolls back and neither the
  /// day entry nor observations are persisted or marked dirty.
  Future<DayEntry> saveDayEntryWithObservations({
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
    List<UpsertObservationPayload> observationsToUpsert = const [],
    List<String> observationIdsToDelete = const [],
  }) async {
    // Issue #848: construct the civil date once, then range-check it
    // against today and the profile's birth year (when known) before any
    // write. The profile read is the one extra lookup this adds; a missing
    // profile (birthYear null) defers to the insert's FK backstop exactly
    // as before.
    final entryDate = _parseLocalDate(localDate);
    _validateLocalDate(entryDate);
    _validateDayEntryDate(
      entryDate,
      today: _today(),
      birthYear: (await _profileOrNull(profileId))?.birthYear,
    );
    _validateNote(note);
    _validateTags(tags);
    _validateDayEntryProvenance(sourceId: sourceId);

    for (final obs in observationsToUpsert) {
      _validateLocalDate(_parseLocalDate(obs.localDate));
      _validateObservation(
        category: obs.category,
        code: obs.code,
        valueNum: obs.valueNum,
        valueText: obs.valueText,
        unit: obs.unit,
        sourceId: obs.sourceId,
        raw: obs.raw,
        intensity: obs.intensity,
      );
    }

    return db.transaction(() async {
      final savedEntry = await _writeDayEntry(
        id: id,
        profileId: profileId,
        localDate: localDate,
        tz: tz,
        flow: flow,
        tags: tags,
        note: note,
        pms: pms,
        updatedAt: updatedAt,
        source: source,
        sourceId: sourceId,
        importId: importId,
      );

      for (final deleteId in observationIdsToDelete) {
        await _softDeleteObservation(deleteId);
      }

      for (final obs in observationsToUpsert) {
        await _writeObservation(
          id: obs.id,
          dayEntryId: (obs.dayEntryId == null || obs.dayEntryId!.isEmpty)
              ? savedEntry.id
              : obs.dayEntryId!,
          profileId: obs.profileId,
          localDate: obs.localDate,
          observedAt: obs.observedAt,
          tz: obs.tz,
          category: obs.category,
          code: obs.code,
          valueNum: obs.valueNum,
          valueText: obs.valueText,
          unit: obs.unit,
          intensity: obs.intensity,
          excluded: obs.excluded,
          source: obs.source,
          sourceId: obs.sourceId,
          importId: obs.importId,
          raw: obs.raw,
          updatedAt: obs.updatedAt,
        );
      }

      return savedEntry;
    });
  }

  /// The per-row day-entry write behind [upsertDayEntry], minus the
  /// transaction wrapper: resolves the live row (by [id] when given, else
  /// by (profileId, localDate)), inserts or updates in place with the same
  /// stamping/dirty/local_rev/provenance rules, and reads the row back.
  /// [bulkUpsertDayEntries] calls this once per entry inside its single
  /// transaction instead of going through [upsertDayEntry] (which would
  /// open one transaction per row); [upsertDayEntry] itself delegates here
  /// too, so the single-entry behavior is defined exactly once.
  Future<DayEntry> _writeDayEntry({
    String? id,
    required String profileId,
    required String localDate,
    required String tz,
    required FlowLevel flow,
    required List<String> tags,
    required String? note,
    required bool pms,
    required DateTime? updatedAt,
    required String source,
    required String? sourceId,
    required String? importId,
  }) async {
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
              // Issue #637, LLA-039: this call is the caller's real,
              // explicit value for pms (never a stale upgrade-era
              // default), so the row is confirmed from the moment it
              // exists.
              pmsUnconfirmed: const Value(false),
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
          pmsUnconfirmed: _pmsUnconfirmedWrite(live, pms),
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
  }

  /// Bulk import seam (Issue #172): writes [entries] and [observations] in
  /// ONE [db.transaction] — one stream invalidation, not one per row — so
  /// importing a multi-year history (≈3,650 rows) is O(1) batches, not
  /// O(n) transactions each re-running a full-table SELECT. The future
  /// Clue importer (#190) drives imports exclusively through this method,
  /// never through the per-row [upsertDayEntry]/[upsertObservation].
  ///
  /// Each entry carries its own id (reused on insert, so two devices
  /// importing the same file converge on the same row ids instead of
  /// minting fresh ones) and its own `updated_at` stamp base (an update
  /// still bumps strictly after the stored value, the [_afterStored]
  /// rule). Entries resolve like [upsertDayEntry] plus one bulk-only
  /// fallback: an id matching no stored row falls back to the live row at
  /// (profileId, localDate) when one exists, so a re-import carrying new
  /// ids for already-imported dates updates in place instead of colliding
  /// on `uq_day_entries_profile_date_live`. Duplicate dates within one
  /// batch are last-wins in input order (each write sees the earlier ones
  /// in the same transaction, matching [upsertDayEntry]). Observations
  /// resolve by id alone, like [upsertObservation], and are written after
  /// their day entries so `day_entry_id` always resolves.
  ///
  /// Only live-row fields are read from the inputs: `dirty`/`local_rev`
  /// are restamped, `deleted_at` is ignored (bulk writes live rows — the
  /// update path clears it, like [upsertDayEntry]), and
  /// `logged_by_user_id`/`last_modified_by_user_id` are never written
  /// locally (the server stamps them). Every input is validated before
  /// anything is written, so a bad row fails the whole batch with nothing
  /// persisted. An empty call writes nothing and opens no transaction.
  /// Returns the persisted day entries in input order.
  Future<List<DayEntry>> bulkUpsertDayEntries(
    List<DayEntry> entries, {
    List<Observation> observations = const [],
  }) async {
    // Async so validation failures surface as failed futures, not sync
    // throws, for callers awaiting the result.
    // Issue #848: one profile read per distinct profile in the batch, so
    // each day entry can be range-checked against its subject's birth year
    // without an N-query fan-out on the import hot path.
    final birthYears = <String, int?>{
      for (final id in {for (final e in entries) e.profileId})
        id: (await _profileOrNull(id))?.birthYear,
    };
    for (final entry in entries) {
      _validateBulkDayEntry(entry, birthYear: birthYears[entry.profileId]);
    }
    for (final observation in observations) {
      _validateBulkObservation(observation);
    }
    if (entries.isEmpty && observations.isEmpty) return [];
    return db.transaction(() async {
      final written = <DayEntry>[];
      // Issue #140 review, LLA-044: incoming entry id -> the id it was
      // actually persisted under. Populated only when [_writeBulkDayEntry]'s
      // own local-parent fallback fires (an incoming id matching no stored
      // row, but a LIVE row already at (profileId, localDate) -- that live
      // row's id is reused instead) -- an entry written under its own id
      // never needs remapping.
      final parentIdRemap = <String, String>{};
      for (final entry in entries) {
        final row = await _writeBulkDayEntry(entry);
        if (row.id != entry.id) parentIdRemap[entry.id] = row.id;
        written.add(row);
      }
      for (final observation in observations) {
        // Issue #140 review, LLA-044: an observation's dayEntryId is
        // whatever the CALLER'S batch called its parent by -- remap it onto
        // the parent's actually-persisted id (above) before writing, or the
        // FK below would point at a row that was never inserted (the
        // fallback path wrote under a different, pre-existing row's id
        // instead) and this write would fail. A dayEntryId this batch never
        // remapped belongs to an entry outside it (already stored), so it
        // is used as-is.
        final dayEntryId =
            parentIdRemap[observation.dayEntryId] ?? observation.dayEntryId;
        // [_validateBulkObservation] already rejected a null/empty
        // category above, so this `!` never fails here.
        await _writeObservation(
          id: observation.id,
          dayEntryId: dayEntryId,
          profileId: observation.profileId,
          localDate: observation.localDate,
          observedAt: observation.observedAt,
          tz: observation.tz,
          category: observation.category!,
          code: observation.code,
          valueNum: observation.valueNum,
          valueText: observation.valueText,
          unit: observation.unit,
          intensity: observation.intensity,
          excluded: observation.excluded,
          source: observation.source,
          sourceId: observation.sourceId,
          importId: observation.importId,
          raw: observation.raw,
          updatedAt: observation.updatedAt,
        );
      }
      return written;
    });
  }

  /// Validates one bulk day-entry input with the same limits
  /// [upsertDayEntry] enforces, including the Issue #848 date bounds
  /// ([birthYear] is the entry profile's stored birth year, when known).
  void _validateBulkDayEntry(DayEntry entry, {int? birthYear}) {
    final date = _parseLocalDate(entry.localDate);
    _validateLocalDate(date);
    _validateDayEntryDate(date, today: _today(), birthYear: birthYear);
    _validateNote(entry.note);
    _validateTags(entry.tags);
    _validateDayEntryProvenance(sourceId: entry.sourceId);
  }

  /// Validates one bulk observation input with the same limits
  /// [upsertObservation] enforces. A null category reads as empty, which
  /// [_validateObservation] rejects (only a tombstone may carry a null
  /// category, and bulk writes live rows).
  void _validateBulkObservation(Observation observation) {
    _validateLocalDate(_parseLocalDate(observation.localDate));
    _validateObservation(
      category: observation.category ?? '',
      code: observation.code,
      valueNum: observation.valueNum,
      valueText: observation.valueText,
      unit: observation.unit,
      sourceId: observation.sourceId,
      raw: observation.raw,
      intensity: observation.intensity,
    );
  }

  /// One bulk day-entry row through [_writeDayEntry]: an id matching a
  /// stored row updates it; otherwise the live row at (profileId,
  /// localDate), when one exists, is updated in place (the bulk-only
  /// fallback); otherwise the entry's own id is inserted fresh.
  Future<DayEntry> _writeBulkDayEntry(DayEntry entry) async {
    var targetId = entry.id;
    if (await _dayEntryOrNull(targetId) == null) {
      targetId = (await _liveDayEntry(entry.profileId, entry.localDate))?.id ??
          entry.id;
    }
    return _writeDayEntry(
      id: targetId,
      profileId: entry.profileId,
      localDate: entry.localDate,
      tz: entry.tz,
      flow: entry.flow,
      tags: entry.tags,
      note: entry.note,
      pms: entry.pms,
      updatedAt: entry.updatedAt,
      source: entry.source,
      sourceId: entry.sourceId,
      importId: entry.importId,
    );
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
          // Issue #637, LLA-039: this write sets pms to a real,
          // deliberate value (the tombstone rule), not a stale
          // upgrade-era default.
          pmsUnconfirmed: const Value(false),
          updatedAt: Value(at),
          deletedAt: Value(at),
          dirty: const Value(true),
          localRev: Value(live.localRev + 1),
        ),
      );

      // Issue #470: cascade tombstone to all live observations attached
      // to this day entry. Payload fields are cleared, localRev is bumped,
      // and rows are marked dirty so sync pushes them.
      final liveObs = await (db.select(db.observations)
            ..where((t) =>
                (t.dayEntryId.equals(rowId) |
                    (t.profileId.equals(profileId) &
                        t.localDate.equals(localDate))) &
                t.deletedAt.isNull()))
          .get();
      for (final obs in liveObs) {
        final obsAt = _afterStored(at, obs.updatedAt);
        await (db.update(db.observations)..where((t) => t.id.equals(obs.id)))
            .write(
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
            // write) survive a tombstone.
            raw: const Value(null),
            updatedAt: Value(obsAt),
            deletedAt: Value(obsAt),
            dirty: const Value(true),
            localRev: Value(obs.localRev + 1),
          ),
        );
      }
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
    _validateLocalDate(_parseLocalDate(localDate));
    _validateObservation(
      category: category,
      code: code,
      valueNum: valueNum,
      valueText: valueText,
      unit: unit,
      sourceId: sourceId,
      raw: raw,
      intensity: intensity,
    );
    return db.transaction(() async {
      return _writeObservation(
        id: id,
        dayEntryId: dayEntryId,
        profileId: profileId,
        localDate: localDate,
        observedAt: observedAt,
        tz: tz,
        category: category,
        code: code,
        valueNum: valueNum,
        valueText: valueText,
        unit: unit,
        intensity: intensity,
        excluded: excluded,
        source: source,
        sourceId: sourceId,
        importId: importId,
        raw: raw,
        updatedAt: updatedAt,
      );
    });
  }

  /// The per-row observation write behind [upsertObservation], minus the
  /// transaction wrapper: inserts or updates by [id] with the same
  /// stamping/dirty/local_rev rules and reads the row back.
  /// [bulkUpsertDayEntries] calls this once per observation inside its
  /// single transaction instead of going through [upsertObservation]
  /// (which would open one transaction per row); [upsertObservation]
  /// itself delegates here too, so the single-entry behavior is defined
  /// exactly once.
  Future<Observation> _writeObservation({
    required String? id,
    required String dayEntryId,
    required String profileId,
    required String localDate,
    required DateTime? observedAt,
    required String tz,
    required String category,
    required String? code,
    required double? valueNum,
    required String? valueText,
    required String? unit,
    required int? intensity,
    required bool excluded,
    required String source,
    required String? sourceId,
    required String? importId,
    required String? raw,
    required DateTime? updatedAt,
  }) async {
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
    await db.transaction(() => _softDeleteObservation(id));
  }

  Future<void> _softDeleteObservation(String id) async {
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
    String? estimatedDueDate,
    String? postpartumBirthDate,
    String? birthControlMethod,
    String? birthControlStartedOn,
    String? birthControlStoppedOn,
    bool healthSyncConsent = false,
    DateTime? updatedAt,
  }) async {
    // Async so validation failures surface as failed futures.
    _validateProfileModePayload(
      modeStartedOn: modeStartedOn,
      estimatedDueDate: estimatedDueDate,
      postpartumBirthDate: postpartumBirthDate,
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
              estimatedDueDate: Value(estimatedDueDate),
              postpartumBirthDate: Value(postpartumBirthDate),
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
        estimatedDueDate: Value(estimatedDueDate),
        postpartumBirthDate: Value(postpartumBirthDate),
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
    _validateLocalDate(_parseLocalDate(cycleStartDate));
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

  // ------------------------------------------------------------ guardian notes

  /// Creates or updates one of the caller's own dated guardian notes (Issue
  /// #801), keyed by [id] (a fresh ULID is generated when omitted). Marks
  /// the row dirty and bumps `local_rev`; an update stamps `updated_at`
  /// strictly after the stored value and revives a tombstone (`deleted_at`
  /// cleared — under LWW a newer non-delete wins). Throws [ArgumentError]
  /// for a [body] over [kMaxCareNoteLength] or a malformed [localDate].
  ///
  /// Author scoping is a client-side contract too: callers pass the id of
  /// the caller's own note for that (profile, date); the repository's
  /// `findOwnNoteForDate` is what makes that possible. The storage layer
  /// itself is author-agnostic (it does not know the bound account here) —
  /// the server enforces ownership authoritatively.
  Future<GuardianNoteData> upsertGuardianNote({
    String? id,
    required String profileId,
    required String localDate,
    required String tz,
    required String body,
    String? loggedByUserId,
    DateTime? updatedAt,
  }) async {
    // Async so validation failures surface as failed futures.
    _validateGuardianNoteBody(body);
    _validateLocalDate(_parseLocalDate(localDate));
    return db.transaction(() async {
      final now = (updatedAt ?? _now()).toUtc();
      GuardianNoteData? existing;
      if (id != null) existing = await _guardianNoteOrNull(id);
      if (existing == null) {
        final rowId = id ?? _generator.next();
        await db.into(db.guardianNotes).insert(GuardianNotesCompanion.insert(
              id: rowId,
              profileId: profileId,
              localDate: localDate,
              tz: tz,
              body: body,
              updatedAt: now,
              dirty: const Value(true),
              localRev: const Value(1),
              loggedByUserId: Value(loggedByUserId),
            ));
        return _guardianNoteById(rowId);
      }
      final rowId = existing.id;
      await (db.update(db.guardianNotes)..where((t) => t.id.equals(rowId)))
          .write(
        GuardianNotesCompanion(
          localDate: Value(localDate),
          tz: Value(tz),
          body: Value(body),
          updatedAt: Value(_afterStored(now, existing.updatedAt)),
          deletedAt: const Value(null),
          dirty: const Value(true),
          localRev: Value(existing.localRev + 1),
          // Author is immutable: never re-stamp an existing row from a
          // later local write. The server is authoritative anyway.
        ),
      );
      return _guardianNoteById(rowId);
    });
  }

  /// Tombstones the guardian note [id]: sets `deleted_at` (and bumps
  /// `updated_at`), clears `body` (tombstones carry no payload — the
  /// server's `guardian_notes_tombstone_payload_check` mirror). Marks the
  /// row dirty. Idempotent: re-deleting a tombstone does nothing. No-op when
  /// the row is not held locally.
  Future<void> softDeleteGuardianNote(String id) async {
    await db.transaction(() async {
      final existing = await _guardianNoteOrNull(id);
      if (existing == null || existing.deletedAt != null) return;
      final at = _afterStored(_now(), existing.updatedAt);
      await (db.update(db.guardianNotes)..where((t) => t.id.equals(id))).write(
        GuardianNotesCompanion(
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

  // ------------------------------------------------- profile tag registry

  /// Issue #257: creates or updates a registry row keyed by [id] (a fresh
  /// ULID is generated when omitted). [code] is immutable on update — a
  /// rename rewrites [displayName] only, so stored day-entry references
  /// keep resolving. Throws [ArgumentError] for a [code] outside
  /// 1..[kMaxTagLength] or a [displayName] over
  /// [kMaxCustomTagLabelLength] (the server CHECKs' mirrors). [hiddenAt]
  /// is the retirement write: setting it removes the code from the
  /// day-sheet picker while stored rows keep rendering; passing null on a
  /// retired row un-retires it. Marks the row dirty and bumps `local_rev`.
  Future<ProfileTagRegistryEntry> upsertProfileTagRegistryEntry({
    String? id,
    required String profileId,
    required String code,
    required String displayName,
    String category = kCustomTagCategory,
    bool intensityEnabled = false,
    DateTime? hiddenAt,
    int? sortOrder,
    DateTime? updatedAt,
  }) async {
    // Async so validation failures surface as failed futures.
    _validateRegistryCode(code);
    _boundedOrThrow(displayName, kMaxCustomTagLabelLength, 'displayName');
    _boundedOrThrow(category, kMaxTagLength, 'category');
    return db.transaction(() async {
      final now = (updatedAt ?? _now()).toUtc();
      ProfileTagRegistryEntry? existing;
      if (id != null) existing = await _profileTagRegistryOrNull(id);
      existing ??= await findProfileTagByCode(profileId, code);
      if (existing == null) {
        final rowId = id ?? _generator.next();
        await db.into(db.profileTagRegistry)
            .insert(ProfileTagRegistryCompanion.insert(
          id: rowId,
          profileId: profileId,
          code: code,
          displayName: displayName,
          category: category,
          intensityEnabled: Value(intensityEnabled),
          hiddenAt: Value(hiddenAt),
          sortOrder: Value(sortOrder),
          createdAt: now,
          updatedAt: now,
          dirty: const Value(true),
          localRev: const Value(1),
        ));
        return _profileTagRegistryById(rowId);
      }
      final rowId = existing.id;
      await (db.update(db.profileTagRegistry)
            ..where((t) => t.id.equals(rowId)))
          .write(ProfileTagRegistryCompanion(
        displayName: Value(displayName),
        category: Value(category),
        intensityEnabled: Value(intensityEnabled),
        hiddenAt: Value(hiddenAt),
        sortOrder: Value(sortOrder),
        updatedAt: Value(_afterStored(now, existing.updatedAt)),
        deletedAt: const Value(null),
        dirty: const Value(true),
        localRev: Value(existing.localRev + 1),
      ));
      return _profileTagRegistryById(rowId);
    });
  }

  /// Issue #257: RETIRES a registry row — sets `hidden_at` and nothing
  /// else. Retirement removes the code from the day-sheet picker while
  /// every stored row referencing it keeps rendering; it never deletes
  /// anything. Returns false when [id] is unknown or already tombstoned.
  Future<bool> retireProfileTagRegistryEntry(String id) async {
    return db.transaction(() async {
      final existing = await _profileTagRegistryOrNull(id);
      if (existing == null || existing.deletedAt != null) return false;
      final at = _afterStored(_now(), existing.updatedAt);
      await (db.update(db.profileTagRegistry)
            ..where((t) => t.id.equals(id)))
          .write(ProfileTagRegistryCompanion(
        hiddenAt: Value(at),
        updatedAt: Value(at),
        dirty: const Value(true),
        localRev: Value(existing.localRev + 1),
      ));
      return true;
    });
  }

  /// Registry row by id (Issue #257), tombstones included — the local
  /// write path's own read-back.
  Future<ProfileTagRegistryEntry> _profileTagRegistryById(String id) async {
    final row = await _profileTagRegistryOrNull(id);
    if (row == null) {
      throw StateError('profile_tag_registry row $id missing after write');
    }
    return row;
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

  /// Issue #130: dismisses one merge notice on THIS device only — the
  /// event id joins the profile's device-local dismissal list and the day
  /// sheet stops showing it. Never synced and never a tombstone: the
  /// server row stays until its 30-day retention purge, so another
  /// guardian (or this guardian's other device) keeps their notice.
  Future<void> dismissDayEntryMergeEvent({
    required String profileId,
    required String eventId,
  }) async {
    final key = mergeNoticeDismissalsKey(profileId);
    final stored = await getSetting(key);
    final dismissed = appendMergeNoticeDismissal(
        decodeMergeNoticeDismissals(stored), eventId);
    await setSetting(key: key, value: encodeMergeNoticeDismissals(dismissed));
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
    // Issue #257: the eleventh SyncTable pushed this switch past the CRAP
    // gate's complexity ceiling (eleven arms — and like the batched path
    // before it at the tenth table, the two pull-only arms were unreachable
    // behind [_neverPushed] by construction), so the single-row path now
    // delegates to the same [_pushWriteTarget] map [markPushedBatch] uses:
    // one shared table/key/rev lookup, one shared chunk writer, the same
    // AE11 (id, local_rev-at-push) predicate either way. cycleOverrides'
    // composite-key note carried forward: ids are client-generated ULIDs —
    // globally unique in practice — so the id alone identifies at most one
    // row on every table here.
    final target = _pushWriteTarget(table);
    if (target == null) return false;
    final changed = await _markPushedChunk(target, [
      (id: id, localRevAtPush: localRevAtPush),
    ]);
    return changed > 0;
  }

  /// Issue #42: [markPushed] for a whole push batch's accepted rows in
  /// batched UPDATE statements — one statement per [kSyncBatchChunkSize]
  /// rows per table, instead of one statement per row (up to
  /// [PushBatch.maxRows] autocommit-by-autocommit UPDATEs per push batch
  /// before this; the single `db.transaction()` around them is issue #523's
  /// `applyPushResult`, which is also this method's only caller). The
  /// `local_rev` guard is preserved exactly: every chunked statement OR-folds
  /// the same per-row `key = ? AND local_rev = ?` predicate [markPushed]
  /// uses, so a row whose local revision changed while the push was in
  /// flight still matches no predicate and stays dirty (AE11) — its next
  /// push re-sends it. Returns how many rows were cleared.
  Future<int> markPushedBatch(
    List<({SyncTable table, String id, int localRevAtPush})> items,
  ) async {
    final byTable = <SyncTable, List<({String id, int localRevAtPush})>>{};
    for (final item in items) {
      byTable.putIfAbsent(item.table, () => []).add((
        id: item.id,
        localRevAtPush: item.localRevAtPush,
      ));
    }
    var cleared = 0;
    for (final entry in byTable.entries) {
      final target = _pushWriteTarget(entry.key);
      // profileGuardians / deletedProfiles never push: nothing to clear,
      // matching [markPushed]'s own no-op cases.
      if (target == null) continue;
      for (final chunk in chunkedBy(entry.value, kSyncBatchChunkSize)) {
        cleared += await _markPushedChunk(target, chunk);
      }
    }
    return cleared;
  }

  /// The drift table (and its key/revision column names, read off the typed
  /// schema so a rename cannot drift) one batched markPushed chunk writes
  /// for [table], or `null` for the two pull-only tables that never push.
  ({TableInfo<Table, dynamic> table, String keyColumn, String revColumn})?
  _pushWriteTarget(SyncTable table) {
    if (_neverPushed(table)) return null;
    return _pushedTableTargets[table]!();
  }

  /// The pull-only tables ([SyncTable.profileGuardians],
  /// [SyncTable.deletedProfiles], and Issue #170's
  /// [SyncTable.dayEntryHistory]): nothing is ever pushed for them, so
  /// there is no `dirty` flag for [markPushedBatch] to clear — the same
  /// no-op cases [markPushed] carries.
  static bool _neverPushed(SyncTable table) => switch (table) {
    SyncTable.profileGuardians ||
    SyncTable.deletedProfiles ||
    SyncTable.dayEntryHistory => true,
    _ => false,
  };

  /// [_pushWriteTarget]'s per-table targets — a map rather than an
  /// exhaustive switch since Issue #130's tenth SyncTable: the switch's
  /// pull-only arm was unreachable behind [_neverPushed] by construction
  /// (uncoverable, and with ten arms the method sat at the CRAP gate's
  /// complexity ceiling with no coverage headroom at all), while a lookup
  /// stays flat as tables are added — the same growth rationale as
  /// storage_remote_apply.dart's `_pageRowAppliers` and the sync
  /// engine's `_startingCursors`. The pull-only tables simply carry no
  /// entry; the `!` on the lookup preserves the old unreachable arm's
  /// fail-loud intent should the [_neverPushed] guard ever be bypassed.
  late final Map<
      SyncTable,
      ({TableInfo<Table, dynamic> table, String keyColumn, String revColumn})
          Function()> _pushedTableTargets = {
    SyncTable.profiles: () => (
      table: db.profiles,
      keyColumn: db.profiles.id.$name,
      revColumn: db.profiles.localRev.$name,
    ),
    SyncTable.dayEntries: () => (
      table: db.dayEntries,
      keyColumn: db.dayEntries.id.$name,
      revColumn: db.dayEntries.localRev.$name,
    ),
    SyncTable.observations: () => (
      table: db.observations,
      keyColumn: db.observations.id.$name,
      revColumn: db.observations.localRev.$name,
    ),
    SyncTable.profileModes: () => (
      table: db.profileModes,
      keyColumn: db.profileModes.profileId.$name,
      revColumn: db.profileModes.localRev.$name,
    ),
    SyncTable.cycleOverrides: () => (
      table: db.cycleOverrides,
      keyColumn: db.cycleOverrides.id.$name,
      revColumn: db.cycleOverrides.localRev.$name,
    ),
    SyncTable.careNotes: () => (
      table: db.careNotes,
      keyColumn: db.careNotes.id.$name,
      revColumn: db.careNotes.localRev.$name,
    ),
    SyncTable.visitPrepItems: () => (
      table: db.visitPrepItems,
      keyColumn: db.visitPrepItems.id.$name,
      revColumn: db.visitPrepItems.localRev.$name,
    ),
    // Issue #130: merge events push like every other synced table
    // (dirty rows ride the batch; [markPushed]'s own switch above clears
    // them the same way).
    SyncTable.dayEntryMergeEvents: () => (
      table: db.dayEntryMergeEvents,
      keyColumn: db.dayEntryMergeEvents.id.$name,
      revColumn: db.dayEntryMergeEvents.localRev.$name,
    ),
    // Issue #257: registry rows push like every other synced table
    // (dirty rows ride the batch; [markPushed]'s own switch above clears
    // them the same way).
    SyncTable.profileTagRegistry: () => (
      table: db.profileTagRegistry,
      keyColumn: db.profileTagRegistry.id.$name,
      revColumn: db.profileTagRegistry.localRev.$name,
    ),
    // Issue #801: guardian notes push like every other synced table
    // (dirty rows ride the batch; [markPushed]'s own switch above clears
    // them the same way).
    SyncTable.guardianNotes: () => (
      table: db.guardianNotes,
      keyColumn: db.guardianNotes.id.$name,
      revColumn: db.guardianNotes.localRev.$name,
    ),
  };

  /// One batched `UPDATE ... SET dirty = 0 WHERE (key = ? AND local_rev = ?)
  /// OR ...` statement covering [chunk] rows of [target] — semantically the
  /// per-row [markPushed] UPDATEs it replaces, folded into one statement.
  Future<int> _markPushedChunk(
    ({TableInfo<Table, dynamic> table, String keyColumn, String revColumn})
    target,
    List<({String id, int localRevAtPush})> chunk,
  ) {
    final predicates = [
      for (final _ in chunk)
        '(${target.keyColumn} = ? AND ${target.revColumn} = ?)',
    ].join(' OR ');
    return db.customUpdate(
      'UPDATE ${target.table.actualTableName} SET dirty = 0 WHERE '
      '$predicates',
      variables: [
        for (final item in chunk) ...[
          Variable(item.id),
          Variable(item.localRevAtPush),
        ],
      ],
      updates: {target.table},
    );
  }

  /// Issue #568: bumps `local_rev` on the row [id] of [table] and marks it
  /// dirty again — the retry affordance for a row the server rejected. A
  /// pure no-op write as far as content goes: no payload column changes,
  /// only the row's push eligibility (a rejected row is otherwise held out
  /// of every push until `local_rev` changes for an unrelated reason — see
  /// `SupabaseSyncApply.pushable`). Issue #257: the eleventh SyncTable
  /// pushed the per-table switch past the CRAP gate's complexity ceiling,
  /// so this writes through the same [_pushWriteTarget] map
  /// [markPushed]/[markPushedBatch] use — one raw UPDATE over the map's
  /// table and key column (the identical statement every arm wrote), with
  /// the pull-only tables ([SyncTable.profileGuardians],
  /// [SyncTable.deletedProfiles]) still a no-op ([_pushWriteTarget]
  /// answers null for them; nothing ever rejects a pull-only row anyway).
  Future<void> bumpLocalRevForRetry({
    required SyncTable table,
    required String id,
  }) async {
    final target = _pushWriteTarget(table);
    if (target == null) return;
    await db.customUpdate(
      'UPDATE ${target.table.actualTableName} '
      'SET dirty = 1, local_rev = local_rev + 1 '
      'WHERE ${target.keyColumn} = ?',
      variables: [Variable.withString(id)],
      updates: {target.table},
    );
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

  /// Replaces the `sync_state` singleton (the id is forced to 1).
  Future<void> writeSyncState(SyncStateRow state) async {
    await db
        .into(db.syncState)
        .insertOnConflictUpdate(state.copyWith(id: 1).toCompanion(false));
  }

  /// Upserts the device-local `health_sync_state` anchor for its platform
  /// (Issue #186 — never synced to the server; keyed by `platform`).
  Future<void> writeHealthSyncAnchor(HealthSyncStateRow anchor) async {
    await db
        .into(db.healthSyncState)
        .insertOnConflictUpdate(anchor.toCompanion(false));
  }

  /// Sweeps tombstoned rows older than [retentionHorizon] (or [olderThan] if
  /// specified) whose `dirty` flag is false (Issue #203).
  ///
  /// Deletes are performed in referential integrity order (child tables before
  /// parents). Only clean (already synced or never dirty) tombstones are removed;
  /// rows pending upload are never swept.
  /// Returns the total number of swept rows.
  Future<int> sweepTombstones({
    Duration retentionHorizon = kTombstoneRetentionHorizon,
    DateTime? olderThan,
  }) async {
    final cutoff = olderThan ?? _now().subtract(retentionHorizon);
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

  /// Runs periodic maintenance: sweeps tombstones and reclaims unused storage
  /// space via VACUUM (Issue #203).
  Future<int> runMaintenance({
    Duration retentionHorizon = kTombstoneRetentionHorizon,
    DateTime? olderThan,
  }) async {
    final swept = await sweepTombstones(
      retentionHorizon: retentionHorizon,
      olderThan: olderThan,
    );
    await db.vacuum();
    return swept;
  }
}
