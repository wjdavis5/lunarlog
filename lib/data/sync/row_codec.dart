/// Wire codec between drift rows and the remote JSON shape (U10; KTD2,
/// KTD3, KTD5): the `sync_push` request rows, the RPC's `resolved` rows and
/// PostgREST pull pages.
///
/// * Timestamps: drift stores ISO-8601 UTC text and hands us `DateTime`;
///   the server renders `timestamptz` as `2026-09-01T10:00:00.123+00:00`.
///   Decoding always yields a UTC `DateTime` with microsecond precision so
///   the conflict rules compare instants, never strings.
/// * `local_date` stays the `yyyy-MM-dd` string on both sides.
/// * `tags` is a JSON array of strings; `flow` is `FlowLevel.toDb()`'s wire
///   string (Issue #247: no longer always the enum's Dart name --
///   `superHeavy`/`notBleeding` encode as `super_heavy`/`not_bleeding`).
/// * `day_entries.created_at` is server-only: never emitted, never read.
/// * `profiles.relationship` (Issue #4 R3) is validated against the closed
///   set on decode: an unrecognised value normalises to null rather than
///   surfacing garbage the app never asked for, since it is optional
///   display metadata, not a security-relevant field like a guardian role.
///   `profiles.mode` (Issue #131) gets the same closed-set treatment except
///   that it is non-null by default: an absent or unrecognised value
///   normalises to `standard` (presentation-only, never a security field).
///   `profiles.transferred_at` (R5) and
///   `profiles.transferred_to_user_id` (Issue #296) are pulled but never
///   pushed — server-owned, written only by `accept_ownership_transfer`.
/// * `profiles.last_period_start` / `typical_cycle_length_days` /
///   `typical_period_length_days` (Issue #218, onboarding cycle facts) are
///   pulled *and* pushed like any other profile column; the date stays a
///   `yyyy-MM-dd` string, same as `profile_modes.mode_started_on`.
/// * `profiles.tracking_preferences` (Issue #259) is a JSON object on the
///   wire and JSON text locally (the `observations.raw` precedent). It is
///   pulled like any other column but pushed ONLY when locally non-null —
///   a null means "not customized on this device", and emitting it would
///   clear a co-guardian's curated document; the server's `?` containment
///   guard backstops the same rule for old clients.
/// * `profiles.bbt_unit` / `weight_unit` (Issue #255, display-unit
///   preferences) get `mode`'s closed-set treatment exactly: non-null by
///   default, an absent or unrecognised value normalises to the column
///   default (`celsius`/`kg`) — presentation-only, never a security field.
///   An `observations` value's own `unit` is untouched by this: the
///   preference decides rendering only.
/// * `observations.category`/`code` (Issue #240) are free text and
///   deliberately NOT validated against a closed set here — unlike
///   `flow`/`mode`, an unrecognised value round-trips unchanged (the D-10
///   companion note: the ~200 option codes are stored, never rejected).
///   `observations.raw` is a JSON value on the wire but a JSON-text column
///   client-side, matching `tags`' `TagsConverter` precedent.
/// * `profile_modes.mode` (Issue #188 — the life-stage axis, NOT #131's
///   care mode) is normalised against the `LifecycleMode` closed set on
///   decode exactly like `profiles.mode`: an absent or unrecognised value
///   degrades to `tracking` rather than throwing. Its date fields stay
///   `yyyy-MM-dd` strings, like `local_date`.
/// * Failures are a typed [RowCodecError] naming the table and field and
///   the kind of problem — never the offending value, never the row.
///
/// Like `mappers.dart`, this is a place where storage types and another
/// representation meet; nothing under `lib/domain` imports it (the reverse
/// import below, of the small closed-set `ProfileRelationship` enum, is the
/// normal data-depends-on-domain direction and does not violate that).
library;

import 'dart:convert';

import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';

import '../db/db.dart';
import '../db/tables.dart';
import '../db/ulid.dart';
import 'remote_rows.dart';

/// A JSON object as `dart:convert` produces and consumes it.
typedef JsonRow = Map<String, Object?>;

/// What went wrong while encoding or decoding a row.
enum RowCodecErrorKind {
  /// A required key is absent or null.
  missing,

  /// A key holds a value of the wrong JSON type.
  wrongType,

  /// `id` / `profile_id` is not a 26-character Crockford ULID.
  invalidId,

  /// A timestamp string does not parse.
  invalidTimestamp,

  /// `local_date` is not `yyyy-MM-dd`.
  invalidDate,

  /// `flow` is not a known [FlowLevel] name.
  unknownFlow,

  /// `tags` is not a JSON array of strings.
  invalidTags,

  /// A resolved row's `table` key is absent or not a synced table.
  unknownTable,

  /// `observations.raw` (Issue #240) does not parse as JSON.
  invalidRaw,

  /// `profiles.tracking_preferences` (Issue #259) does not parse as a JSON
  /// object on either direction of the codec.
  invalidTrackingPreferences,
}

/// Typed codec failure. Deliberately carries no payload: the table, the
/// field and the kind are all a log or a crash report may see (R18).
class RowCodecError implements Exception {
  const RowCodecError(this.kind, {required this.table, required this.field});

  final RowCodecErrorKind kind;
  final SyncTable table;
  final String field;

  @override
  String toString() =>
      'RowCodecError(${kind.name}: ${syncTableName(table)}.$field)';
}

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Postgres text rendering: `2026-09-01 10:00:00.123456+00` (space
/// separator, offset without minutes) — normalised before `DateTime.parse`.
final RegExp _shortOffset = RegExp(r'([+-]\d{2})$');


/// Remote table name for [table] (`profiles` / `day_entries` /
/// `profile_guardians` / `observations` / `profile_modes` /
/// `cycle_overrides` / `care_notes` / `visit_prep_items`).
String syncTableName(SyncTable table) => switch (table) {
      SyncTable.profiles => 'profiles',
      SyncTable.dayEntries => 'day_entries',
      SyncTable.profileGuardians => 'profile_guardians',
      SyncTable.observations => 'observations',
      SyncTable.profileModes => 'profile_modes',
      SyncTable.cycleOverrides => 'cycle_overrides',
      SyncTable.careNotes => 'care_notes',
      SyncTable.visitPrepItems => 'visit_prep_items',
    };

/// Inverse of [syncTableName]; null for anything else.
SyncTable? syncTableFromName(String name) => switch (name) {
      'profiles' => SyncTable.profiles,
      'day_entries' => SyncTable.dayEntries,
      'profile_guardians' => SyncTable.profileGuardians,
      'observations' => SyncTable.observations,
      'profile_modes' => SyncTable.profileModes,
      'cycle_overrides' => SyncTable.cycleOverrides,
      'care_notes' => SyncTable.careNotes,
      'visit_prep_items' => SyncTable.visitPrepItems,
      _ => null,
    };

// ---------------------------------------------------------------------------
// timestamps
// ---------------------------------------------------------------------------

/// Renders [value] as UTC ISO-8601 (`…Z`), microseconds included.
String encodeTimestamp(DateTime value) => value.toUtc().toIso8601String();

/// Parses a `timestamptz` rendering (`+00:00`, `Z`, `-05:00`, or the
/// Postgres text form with a space and a short offset) to a UTC instant.
/// Throws [RowCodecError] ([RowCodecErrorKind.invalidTimestamp]) — never a
/// `FormatException` — attributing the failure to [table].[field].
DateTime decodeTimestamp(
  String text, {
  SyncTable table = SyncTable.profiles,
  String field = 'timestamp',
}) {
  var normalised = text.trim();
  if (normalised.length > 10 && normalised[10] == ' ') {
    normalised = '${normalised.substring(0, 10)}T${normalised.substring(11)}';
  }
  if (_shortOffset.hasMatch(normalised)) {
    // `+00` → `+00:00` (a full `+00:00` ends in `:00` and never matches).
    normalised = '$normalised:00';
  }
  final parsed = DateTime.tryParse(normalised);
  if (parsed == null) {
    throw RowCodecError(RowCodecErrorKind.invalidTimestamp,
        table: table, field: field);
  }
  return parsed.toUtc();
}

// ---------------------------------------------------------------------------
// encode (drift row → RPC JSON)
// ---------------------------------------------------------------------------

/// The `p_profiles` element for [row]. Emits exactly the keys `sync_push`
/// accepts; `dirty` and `local_rev` are device-local and never leave.
/// `transferred_at` and `transferred_to_user_id` are deliberately omitted
/// (Issue #4 R5/R21; Issue #296): they are server-owned, written only by
/// `accept_ownership_transfer`, and `sync_push` tolerates but never reads
/// them, so the client keeps the payload honest by never sending them.
JsonRow encodeProfile(Profile row) {
  if (!isValidUlid(row.id)) {
    throw const RowCodecError(RowCodecErrorKind.invalidId,
        table: SyncTable.profiles, field: 'id');
  }
  return {
    'id': row.id,
    'display_name': row.displayName,
    'is_minor': row.isMinor,
    'sort_order': row.sortOrder,
    'archived_at': _encodeNullable(row.archivedAt),
    'created_at': encodeTimestamp(row.createdAt),
    'updated_at': encodeTimestamp(row.updatedAt),
    'deleted_at': _encodeNullable(row.deletedAt),
    'mode': row.mode,
    // Issue #255: already the raw `toDb()` string on the drift row (the
    // enum normalisation happens in `mappers.dart`/`decodeProfile`, never
    // here).
    'bbt_unit': row.bbtUnit,
    'weight_unit': row.weightUnit,
    'birth_year': row.birthYear,
    'relationship': row.relationship,
    'last_period_start': row.lastPeriodStart,
    'typical_cycle_length_days': row.typicalCycleLengthDays,
    'typical_period_length_days': row.typicalPeriodLengthDays,
    // Issue #259: emitted ONLY when locally non-null — unlike the columns
    // above, a null here is "never customized on this device", not an
    // instruction to clear. Emitting an explicit null from a device that
    // had simply not pulled yet would wipe a co-guardian's curated
    // document server-side; the key's absence leaves the stored value
    // alone (the server's `?` containment guard) and the next pull
    // converges this device onto it. "Clear back to defaults" is a
    // deliberate write of an empty document, not a null.
    if (row.trackingPreferences != null)
      'tracking_preferences':
          _decodeTrackingPreferencesForWire(row.trackingPreferences),
  };
}

/// The `p_day_entries` element for [row]. No `created_at` (server-only).
JsonRow encodeDayEntry(DayEntry row) {
  const table = SyncTable.dayEntries;
  if (!isValidUlid(row.id)) {
    throw const RowCodecError(RowCodecErrorKind.invalidId,
        table: table, field: 'id');
  }
  if (!isValidUlid(row.profileId)) {
    throw const RowCodecError(RowCodecErrorKind.invalidId,
        table: table, field: 'profile_id');
  }
  if (!_isoDate.hasMatch(row.localDate)) {
    throw const RowCodecError(RowCodecErrorKind.invalidDate,
        table: table, field: 'local_date');
  }
  return {
    'id': row.id,
    'profile_id': row.profileId,
    'local_date': row.localDate,
    'tz': row.tz,
    'flow': row.flow.toDb(),
    'tags': List<String>.of(row.tags),
    'note': row.note,
    // Issue #220: the first-class PMS marker rides the payload like any
    // other day-level field; the server's sync_push update path guards it
    // with `v_row ? 'pms'`, so always emitting the key is safe.
    'pms': row.pms,
    'source': row.source,
    'source_id': row.sourceId,
    'import_id': row.importId,
    'updated_at': encodeTimestamp(row.updatedAt),
    'deleted_at': _encodeNullable(row.deletedAt),
  };
}

/// The `p_cycle_overrides` element for [row] (Issue #188).
JsonRow encodeCycleOverride(CycleOverrideData row) {
  const table = SyncTable.cycleOverrides;
  if (!isValidUlid(row.id)) {
    throw const RowCodecError(RowCodecErrorKind.invalidId,
        table: table, field: 'id');
  }
  if (!isValidUlid(row.profileId)) {
    throw const RowCodecError(RowCodecErrorKind.invalidId,
        table: table, field: 'profile_id');
  }
  if (!_isoDate.hasMatch(row.cycleStartDate)) {
    throw const RowCodecError(RowCodecErrorKind.invalidDate,
        table: table, field: 'cycle_start_date');
  }
  return {
    'id': row.id,
    'profile_id': row.profileId,
    'cycle_start_date': row.cycleStartDate,
    'excluded_from_average': row.excludedFromAverage,
    'manual_start': row.manualStart,
    'note_id': row.noteId,
    'updated_at': encodeTimestamp(row.updatedAt),
    'deleted_at': _encodeNullable(row.deletedAt),
  };
}

/// The `p_profile_modes` element for [row] (Issue #188). Emits every key
/// this client knows; the server's update path applies its own `v_row ?
/// 'key'` containment guards, so a full-key payload is always safe.
JsonRow encodeProfileMode(ProfileModeData row) {
  const table = SyncTable.profileModes;
  if (!isValidUlid(row.profileId)) {
    throw const RowCodecError(RowCodecErrorKind.invalidId,
        table: table, field: 'profile_id');
  }
  return {
    'profile_id': row.profileId,
    'mode': row.mode,
    'mode_started_on': row.modeStartedOn,
    'birth_control_method': row.birthControlMethod,
    'birth_control_started_on': row.birthControlStartedOn,
    'birth_control_stopped_on': row.birthControlStoppedOn,
    'health_sync_consent': row.healthSyncConsent,
    'updated_at': encodeTimestamp(row.updatedAt),
  };
}

/// The `p_care_notes` element for [row] (Issue #128). `body` is emitted
/// as-is — free text, never validated against a closed set here (the
/// storage layer bounds it and the server's CHECK is the enforcement
/// point). `checked_by`/`checked_at` have no care-note analogue; the
/// server stamps `logged_by`/`last_modified_by` itself, like day entries.
JsonRow encodeCareNote(CareNoteData row) {
  const table = SyncTable.careNotes;
  if (!isValidUlid(row.id)) {
    throw const RowCodecError(RowCodecErrorKind.invalidId,
        table: table, field: 'id');
  }
  if (!isValidUlid(row.profileId)) {
    throw const RowCodecError(RowCodecErrorKind.invalidId,
        table: table, field: 'profile_id');
  }
  return {
    'id': row.id,
    'profile_id': row.profileId,
    'body': row.body,
    'updated_at': encodeTimestamp(row.updatedAt),
    'deleted_at': _encodeNullable(row.deletedAt),
  };
}

/// The `p_visit_prep_items` element for [row] (Issue #128).
/// `checked_by_user_id`/`checked_at` are deliberately *not* emitted: the
/// server stamps them from the caller when `is_checked` is set (the
/// attribution-stamping precedent), so a client can never forge "who
/// checked it".
JsonRow encodeVisitPrepItem(VisitPrepItemData row) {
  const table = SyncTable.visitPrepItems;
  if (!isValidUlid(row.id)) {
    throw const RowCodecError(RowCodecErrorKind.invalidId,
        table: table, field: 'id');
  }
  if (!isValidUlid(row.profileId)) {
    throw const RowCodecError(RowCodecErrorKind.invalidId,
        table: table, field: 'profile_id');
  }
  return {
    'id': row.id,
    'profile_id': row.profileId,
    'body': row.body,
    'is_checked': row.isChecked,
    'updated_at': encodeTimestamp(row.updatedAt),
    'deleted_at': _encodeNullable(row.deletedAt),
  };
}

String? _encodeNullable(DateTime? value) =>
    value == null ? null : encodeTimestamp(value);

/// [Observations.raw] is stored client-side as JSON text (mirroring
/// [TagsConverter]'s approach for `tags`); the wire payload wants the
/// decoded JSON value, not a doubly-encoded string.
Object? _decodeRawForWire(String? raw) {
  if (raw == null) return null;
  try {
    return jsonDecode(raw);
  } on FormatException {
    throw const RowCodecError(RowCodecErrorKind.invalidRaw,
        table: SyncTable.observations, field: 'raw');
  }
}

/// Issue #259: same wire shape as [_decodeRawForWire] (local JSON text ->
/// decoded JSON object), with the codec failure attributed to
/// `profiles.tracking_preferences`.
Object? _decodeTrackingPreferencesForWire(String? text) {
  if (text == null) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    throw const RowCodecError(RowCodecErrorKind.invalidTrackingPreferences,
        table: SyncTable.profiles, field: 'tracking_preferences');
  }
}

/// The `p_observations` element for [row] (Issue #240). `category`/`code`
/// are emitted as-is — free text, never validated against a closed set
/// here (the write RPC is the validation point per the issue's D-10
/// companion note).
JsonRow encodeObservation(Observation row) {
  const table = SyncTable.observations;
  if (!isValidUlid(row.id)) {
    throw const RowCodecError(RowCodecErrorKind.invalidId,
        table: table, field: 'id');
  }
  if (!isValidUlid(row.dayEntryId)) {
    throw const RowCodecError(RowCodecErrorKind.invalidId,
        table: table, field: 'day_entry_id');
  }
  if (!isValidUlid(row.profileId)) {
    throw const RowCodecError(RowCodecErrorKind.invalidId,
        table: table, field: 'profile_id');
  }
  if (!_isoDate.hasMatch(row.localDate)) {
    throw const RowCodecError(RowCodecErrorKind.invalidDate,
        table: table, field: 'local_date');
  }
  return {
    'id': row.id,
    'day_entry_id': row.dayEntryId,
    'profile_id': row.profileId,
    'local_date': row.localDate,
    'observed_at': _encodeNullable(row.observedAt),
    'tz': row.tz,
    'category': row.category,
    'code': row.code,
    'value_num': row.valueNum,
    'value_text': row.valueText,
    'unit': row.unit,
    'intensity': row.intensity,
    'excluded': row.excluded,
    'source': row.source,
    'source_id': row.sourceId,
    'import_id': row.importId,
    'raw': _decodeRawForWire(row.raw),
    'updated_at': encodeTimestamp(row.updatedAt),
    'deleted_at': _encodeNullable(row.deletedAt),
  };
}

// ---------------------------------------------------------------------------
// decode (server JSON → RemoteRow)
// ---------------------------------------------------------------------------

/// Decodes a `profiles` row as PostgREST or `sync_push` renders it. Extra
/// keys (`user_id`, `table`) are ignored; `server_version` defaults to 0
/// when absent.
RemoteProfileRow decodeProfile(JsonRow json) {
  const table = SyncTable.profiles;
  final r = _Reader(json, table);
  return RemoteProfileRow(
    id: r.ulid('id'),
    displayName: r.string('display_name'),
    isMinor: r.boolean('is_minor'),
    sortOrder: r.integer('sort_order'),
    archivedAt: r.timestampOrNull('archived_at'),
    createdAt: r.timestamp('created_at'),
    updatedAt: r.timestamp('updated_at'),
    deletedAt: r.timestampOrNull('deleted_at'),
    serverVersion: r.integerOr('server_version', 0),
    mode: ProfileMode.fromDb(r.stringOrNull('mode')).toDb(),
    // Issue #255: same closed-set normalisation as `mode` above — an
    // absent or unrecognised value degrades to the column default rather
    // than surfacing garbage (or crashing a pull) for a presentation-only
    // preference.
    bbtUnit: BbtUnit.fromDb(r.stringOrNull('bbt_unit')).toDb(),
    weightUnit: WeightUnit.fromDb(r.stringOrNull('weight_unit')).toDb(),
    birthYear: r.integerOrNull('birth_year'),
    relationship: _decodeRelationship(r.stringOrNull('relationship')),
    transferredAt: r.timestampOrNull('transferred_at'),
    transferredToUserId: r.stringOrNull('transferred_to_user_id'),
    lastPeriodStart:
        _decodeIsoDate(r.stringOrNull('last_period_start'), r, 'last_period_start'),
    typicalCycleLengthDays: r.integerOrNull('typical_cycle_length_days'),
    typicalPeriodLengthDays: r.integerOrNull('typical_period_length_days'),
    // Issue #259: the wire carries a JSON object (or an absent/null key for
    // a never-customized profile); it is stored locally as JSON text, the
    // `observations.raw` precedent. A key present with a non-object value
    // is a typed codec failure — that shape can only come from a broken
    // writer, and silently dropping it would present a curated profile as
    // a default one.
    trackingPreferences: _decodeTrackingPreferencesFromWire(json, r),
  );
}

/// Issue #259: `profiles.tracking_preferences` off the wire. Absent or
/// JSON-null -> null (never customized); a JSON object -> its text form;
/// anything else -> a typed failure attributed to the field.
String? _decodeTrackingPreferencesFromWire(JsonRow json, _Reader r) {
  final value = json['tracking_preferences'];
  if (value == null) return null;
  if (value is Map<String, dynamic>) return jsonEncode(value);
  if (value is Map) return jsonEncode(value);
  r._fail(RowCodecErrorKind.invalidTrackingPreferences,
      'tracking_preferences');
}

/// Normalises a raw `relationship` string against the closed set: an
/// unrecognised value (a future addition, a row from a newer client) comes
/// back null rather than being passed through as garbage.
String? _decodeRelationship(String? raw) =>
    raw == null ? null : ProfileRelationship.fromDb(raw)?.toDb();

/// Decodes a `day_entries` row. `created_at` and `user_id` are ignored;
/// `server_version` defaults to 0 when absent.
RemoteDayEntryRow decodeDayEntry(JsonRow json) {
  const table = SyncTable.dayEntries;
  final r = _Reader(json, table);
  return RemoteDayEntryRow(
    id: r.ulid('id'),
    profileId: r.ulid('profile_id'),
    localDate: r.isoDate('local_date'),
    tz: r.string('tz'),
    flow: r.flow('flow'),
    tags: r.tags('tags'),
    note: r.stringOrNull('note'),
    // Issue #220: absent key (an old peer, a pre-#220 server row) decodes
    // to `false` rather than failing the pull — the marker is optional
    // day-level content, not an identity field.
    pms: json['pms'] == null ? false : r.boolean('pms'),
    updatedAt: r.timestamp('updated_at'),
    deletedAt: r.timestampOrNull('deleted_at'),
    serverVersion: r.integerOr('server_version', 0),
    loggedByUserId: r.stringOrNull('logged_by_user_id'),
    lastModifiedByUserId: r.stringOrNull('last_modified_by_user_id'),
    // Issue #159: read as-is, never validated against a closed set here
    // (mirrors observations.source/source_id's precedent above) —
    // `mappers.dart`'s `DayEntrySource.fromDb` normalises on the way to
    // the domain model.
    source: r.stringOrNull('source') ?? 'manual',
    sourceId: r.stringOrNull('source_id'),
    importId: r.stringOrNull('import_id'),
  );
}

/// Decodes a `profile_guardians` row.
RemoteProfileGuardianRow decodeProfileGuardian(JsonRow json) {
  const table = SyncTable.profileGuardians;
  final r = _Reader(json, table);
  return RemoteProfileGuardianRow(
    id: r.string('id'),
    profileId: r.ulid('profile_id'),
    userId: r.string('user_id'),
    role: r.string('role'),
    status: r.string('status'),
    displayName: r.stringOrNull('display_name'),
    invitedBy: r.stringOrNull('invited_by'),
    createdAt: r.timestamp('created_at'),
    updatedAt: r.timestamp('updated_at'),
    serverVersion: r.integerOr('server_version', 0),
  );
}

/// Decodes an `observations` row (Issue #240). `category`/`code` are read
/// as-is — never validated against a closed set (see this file's doc
/// comment on `profiles.mode`/`relationship` for the contrasting cases that
/// do have one). `category` is read nullable (review finding: the server
/// clears it on a tombstone too, like every other payload column — see
/// `RemoteObservationRow.category`'s own doc comment). `raw` is re-encoded
/// to JSON text for client-side storage (mirroring [Observations.raw]'s
/// text-column shape).
RemoteObservationRow decodeObservation(JsonRow json) {
  const table = SyncTable.observations;
  final r = _Reader(json, table);
  return RemoteObservationRow(
    id: r.ulid('id'),
    dayEntryId: r.ulid('day_entry_id'),
    profileId: r.ulid('profile_id'),
    localDate: r.isoDate('local_date'),
    observedAt: r.timestampOrNull('observed_at'),
    tz: r.string('tz'),
    category: r.stringOrNull('category'),
    code: r.stringOrNull('code'),
    valueNum: r.doubleOrNull('value_num'),
    valueText: r.stringOrNull('value_text'),
    unit: r.stringOrNull('unit'),
    intensity: r.integerOrNull('intensity'),
    excluded: json['excluded'] == null ? false : r.boolean('excluded'),
    source: r.stringOrNull('source') ?? 'manual',
    sourceId: r.stringOrNull('source_id'),
    importId: r.stringOrNull('import_id'),
    raw: json['raw'] == null ? null : jsonEncode(json['raw']),
    updatedAt: r.timestamp('updated_at'),
    deletedAt: r.timestampOrNull('deleted_at'),
    serverVersion: r.integerOr('server_version', 0),
    loggedByUserId: r.stringOrNull('logged_by_user_id'),
    lastModifiedByUserId: r.stringOrNull('last_modified_by_user_id'),
  );
}

/// Decodes a `profile_modes` row (Issue #188). `mode` is normalised
/// against the [LifecycleMode] closed set (an absent or unrecognised value
/// degrades to `tracking`, never throws a pull — the `profiles.mode`
/// precedent). Dates stay `yyyy-MM-dd` strings, like `local_date`.
RemoteProfileModeRow decodeProfileMode(JsonRow json) {
  const table = SyncTable.profileModes;
  final r = _Reader(json, table);
  return RemoteProfileModeRow(
    profileId: r.ulid('profile_id'),
    mode: LifecycleMode.fromDb(r.stringOrNull('mode')).toDb(),
    modeStartedOn: _decodeIsoDate(r.stringOrNull('mode_started_on'), r, 'mode_started_on'),
    birthControlMethod: r.stringOrNull('birth_control_method'),
    birthControlStartedOn:
        _decodeIsoDate(r.stringOrNull('birth_control_started_on'), r, 'birth_control_started_on'),
    birthControlStoppedOn:
        _decodeIsoDate(r.stringOrNull('birth_control_stopped_on'), r, 'birth_control_stopped_on'),
    healthSyncConsent:
        json['health_sync_consent'] == null ? false : r.boolean('health_sync_consent'),
    updatedAt: r.timestamp('updated_at'),
    serverVersion: r.integerOr('server_version', 0),
  );
}

/// Normalises an optional date field against the `yyyy-MM-dd` shape: null
/// stays null, a well-formed value passes through, anything else is a typed
/// codec failure attributed to [field] (never a silently-mangled date).
String? _decodeIsoDate(String? raw, _Reader r, String field) {
  if (raw == null) return null;
  if (!_isoDate.hasMatch(raw)) {
    r._fail(RowCodecErrorKind.invalidDate, field);
  }
  return raw;
}

/// Decodes a `cycle_overrides` row (Issue #188).
RemoteCycleOverrideRow decodeCycleOverride(JsonRow json) {
  const table = SyncTable.cycleOverrides;
  final r = _Reader(json, table);
  return RemoteCycleOverrideRow(
    id: r.ulid('id'),
    profileId: r.ulid('profile_id'),
    cycleStartDate: r.isoDate('cycle_start_date'),
    excludedFromAverage:
        json['excluded_from_average'] == null ? false : r.boolean('excluded_from_average'),
    manualStart: json['manual_start'] == null ? false : r.boolean('manual_start'),
    noteId: r.stringOrNull('note_id'),
    updatedAt: r.timestamp('updated_at'),
    deletedAt: r.timestampOrNull('deleted_at'),
    serverVersion: r.integerOr('server_version', 0),
  );
}

/// Decodes a `care_notes` row (Issue #128). `body` is read as-is — free
/// text, never validated against a closed set.
RemoteCareNoteRow decodeCareNote(JsonRow json) {
  const table = SyncTable.careNotes;
  final r = _Reader(json, table);
  return RemoteCareNoteRow(
    id: r.ulid('id'),
    profileId: r.ulid('profile_id'),
    body: r.string('body'),
    updatedAt: r.timestamp('updated_at'),
    deletedAt: r.timestampOrNull('deleted_at'),
    serverVersion: r.integerOr('server_version', 0),
    loggedByUserId: r.stringOrNull('logged_by_user_id'),
    lastModifiedByUserId: r.stringOrNull('last_modified_by_user_id'),
  );
}

/// Decodes a `visit_prep_items` row (Issue #128). `body` is read as-is —
/// free text, never validated against a closed set.
RemoteVisitPrepItemRow decodeVisitPrepItem(JsonRow json) {
  const table = SyncTable.visitPrepItems;
  final r = _Reader(json, table);
  return RemoteVisitPrepItemRow(
    id: r.ulid('id'),
    profileId: r.ulid('profile_id'),
    body: r.string('body'),
    isChecked: json['is_checked'] == null ? false : r.boolean('is_checked'),
    checkedByUserId: r.stringOrNull('checked_by_user_id'),
    checkedAt: r.timestampOrNull('checked_at'),
    updatedAt: r.timestamp('updated_at'),
    deletedAt: r.timestampOrNull('deleted_at'),
    serverVersion: r.integerOr('server_version', 0),
    loggedByUserId: r.stringOrNull('logged_by_user_id'),
    lastModifiedByUserId: r.stringOrNull('last_modified_by_user_id'),
  );
}

/// Decodes a pull-page row of [table].
RemoteRow decodeRemoteRow(SyncTable table, JsonRow json) => switch (table) {
      SyncTable.profiles => decodeProfile(json),
      SyncTable.dayEntries => decodeDayEntry(json),
      SyncTable.profileGuardians => decodeProfileGuardian(json),
      SyncTable.observations => decodeObservation(json),
      SyncTable.profileModes => decodeProfileMode(json),
      SyncTable.cycleOverrides => decodeCycleOverride(json),
      SyncTable.careNotes => decodeCareNote(json),
      SyncTable.visitPrepItems => decodeVisitPrepItem(json),
    };

/// Decodes a `sync_push` `resolved` element, dispatching on its `table`
/// key. Throws [RowCodecErrorKind.unknownTable] when the key is absent or
/// names a table that is not synced.
RemoteRow decodeResolvedRow(JsonRow json) {
  final name = json['table'];
  final table = name is String ? syncTableFromName(name) : null;
  if (table == null) {
    throw const RowCodecError(RowCodecErrorKind.unknownTable,
        table: SyncTable.profiles, field: 'table');
  }
  return decodeRemoteRow(table, json);
}

/// Typed field access over one JSON object, attributing every failure to
/// the table and field being read.
class _Reader {
  _Reader(this.json, this.table);

  final JsonRow json;
  final SyncTable table;

  Never _fail(RowCodecErrorKind kind, String field) =>
      throw RowCodecError(kind, table: table, field: field);

  Object _required(String field) {
    final value = json[field];
    if (value == null) _fail(RowCodecErrorKind.missing, field);
    return value;
  }

  String string(String field) {
    final value = _required(field);
    if (value is! String) _fail(RowCodecErrorKind.wrongType, field);
    return value;
  }

  String? stringOrNull(String field) {
    final value = json[field];
    if (value == null) return null;
    if (value is! String) _fail(RowCodecErrorKind.wrongType, field);
    return value;
  }

  bool boolean(String field) {
    final value = _required(field);
    if (value is! bool) _fail(RowCodecErrorKind.wrongType, field);
    return value;
  }

  int integer(String field) {
    final value = _required(field);
    return _asInt(value, field);
  }

  int integerOr(String field, int fallback) {
    final value = json[field];
    if (value == null) return fallback;
    return _asInt(value, field);
  }

  int? integerOrNull(String field) {
    final value = json[field];
    if (value == null) return null;
    return _asInt(value, field);
  }

  /// `observations.value_num` (Issue #240): PostgREST/`sync_push` may
  /// render a `numeric` as a JSON number or, for values it cannot represent
  /// exactly, a numeric string — accept either.
  double? doubleOrNull(String field) {
    final value = json[field];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    _fail(RowCodecErrorKind.wrongType, field);
  }

  int _asInt(Object value, String field) {
    if (value is int) return value;
    // JSON numbers may arrive as doubles (e.g. from a lenient decoder).
    if (value is double && value == value.truncateToDouble()) {
      return value.toInt();
    }
    _fail(RowCodecErrorKind.wrongType, field);
  }

  String ulid(String field) {
    final value = string(field);
    if (!isValidUlid(value)) _fail(RowCodecErrorKind.invalidId, field);
    return value;
  }

  String isoDate(String field) {
    final value = string(field);
    if (!_isoDate.hasMatch(value)) _fail(RowCodecErrorKind.invalidDate, field);
    return value;
  }

  DateTime timestamp(String field) =>
      decodeTimestamp(string(field), table: table, field: field);

  DateTime? timestampOrNull(String field) {
    final value = stringOrNull(field);
    if (value == null) return null;
    return decodeTimestamp(value, table: table, field: field);
  }

  FlowLevel flow(String field) {
    final value = string(field);
    for (final level in FlowLevel.values) {
      if (level.toDb() == value) return level;
    }
    _fail(RowCodecErrorKind.unknownFlow, field);
  }

  List<String> tags(String field) {
    final value = _required(field);
    if (value is! List) _fail(RowCodecErrorKind.invalidTags, field);
    final out = <String>[];
    for (final item in value) {
      if (item is! String) _fail(RowCodecErrorKind.invalidTags, field);
      out.add(item);
    }
    return out;
  }
}
