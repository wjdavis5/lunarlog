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
///   preference decides rendering only. Pushed ONLY while
///   `Profiles.unitsUnconfirmed` is false (Issue #637, LLA-039) — the same
///   emit-only-when-confirmed shape as `tracking_preferences` above, so an
///   upgrade's local default never clobbers a real server value before a
///   pull hydrates it.
/// * `day_entries.pms` (Issue #220) gets the same LLA-039 treatment via
///   `DayEntries.pmsUnconfirmed`: pushed only once this device has
///   confirmed it against a real server value.
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

  /// A numeric field holds a non-finite value (NaN or +/-Infinity) — Issue
  /// #140 review, LLA-092: `dart:convert`'s `jsonEncode` cannot serialize
  /// one at all (it throws `UnsupportedError`), so this is the codec's own
  /// chance to fail with a typed, attributable error naming the offending
  /// row/field instead of a bare encoder crash surfacing far from — and
  /// long after — whatever local write actually let the value in.
  invalidNumber,
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
/// `cycle_overrides` / `care_notes` / `visit_prep_items` /
/// `day_entry_merge_events` / `profile_tag_registry` /
/// `deleted_profiles`).
String syncTableName(SyncTable table) => _syncTableNames[table]!;

/// The wire name per [SyncTable] — a const map rather than an exhaustive
/// switch since Issue #130's tenth SyncTable: an exhaustive switch over a
/// ten-member enum sits permanently over the quality gate's per-method
/// complexity ceiling no matter how well covered it is, while a lookup
/// stays flat as tables are added.
const Map<SyncTable, String> _syncTableNames = {
  SyncTable.profiles: 'profiles',
  SyncTable.dayEntries: 'day_entries',
  SyncTable.profileGuardians: 'profile_guardians',
  SyncTable.observations: 'observations',
  SyncTable.profileModes: 'profile_modes',
  SyncTable.cycleOverrides: 'cycle_overrides',
  SyncTable.careNotes: 'care_notes',
  SyncTable.visitPrepItems: 'visit_prep_items',
  SyncTable.dayEntryMergeEvents: 'day_entry_merge_events',
  SyncTable.profileTagRegistry: 'profile_tag_registry',
  SyncTable.deletedProfiles: 'deleted_profiles',
  SyncTable.dayEntryHistory: 'day_entry_history',
  SyncTable.guardianNotes: 'guardian_notes',
};

/// [syncTableName]'s inverse, precomputed once from it rather than
/// hand-duplicating the name/table pairing a second time (issue #525
/// review: a second 9-arm switch here pushed [syncTableFromName]'s CRAP
/// score over the gate as tables were added, on top of being one more
/// place a new [SyncTable] value could be forgotten).
final Map<String, SyncTable> _syncTableByName = {
  for (final table in SyncTable.values) syncTableName(table): table,
};

/// Inverse of [syncTableName]; null for anything else.
SyncTable? syncTableFromName(String name) => _syncTableByName[name];

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
    // Issue #255 / #637 LLA-039: already the raw `toDb()` string on the
    // drift row (the enum normalisation happens in
    // `mappers.dart`/`decodeProfile`, never here) — but emitted ONLY once
    // this device has confirmed it against a real server value at least
    // once (`Profiles.unitsUnconfirmed`'s doc comment). An upgrade
    // backfills both columns with a local default that may not match what
    // the server already has; the key's absence leaves the server's
    // stored value alone (its `?` containment guard, the same backstop
    // `trackingPreferences` below relies on) until a pull actually
    // confirms this device's copy.
    if (row.unitsUnconfirmed != true) ...{
      'bbt_unit': row.bbtUnit,
      'weight_unit': row.weightUnit,
    },
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
    // Issue #220 / #637 LLA-039: the first-class PMS marker rides the
    // payload like any other day-level field, emitted ONLY once this
    // device has confirmed it against a real server value at least once
    // (`DayEntries.pmsUnconfirmed`'s doc comment) — an upgrade backfills
    // the column with a local default that may not match what the server
    // already has. The server's sync_push update path already guards a
    // missing key with `v_row ? 'pms'`, so omitting it here is safe.
    if (row.pmsUnconfirmed != true) 'pms': row.pms,
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
    'estimated_due_date': row.estimatedDueDate,
    'postpartum_birth_date': row.postpartumBirthDate,
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

/// The `p_guardian_notes` element for [row] (Issue #801). `body` is
/// emitted as-is — free text, never validated against a closed set here.
/// `logged_by_user_id` is deliberately NOT emitted: the server stamps the
/// author on insert (and enforces author-ownership on update), so a client
/// can never forge or re-attribute an author. Emits exactly the keys
/// `sync_push`'s derived allowlist accepts.
JsonRow encodeGuardianNote(GuardianNoteData row) {
  const table = SyncTable.guardianNotes;
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
    'local_date': row.localDate,
    'tz': row.tz,
    'body': row.body,
    'updated_at': encodeTimestamp(row.updatedAt),
    'deleted_at': _encodeNullable(row.deletedAt),
  };
}

/// The `p_merge_events` element for [row] (Issue #130). `created_at` is
/// deliberately NOT emitted — the server stamps it, exactly as it stamps
/// `day_entries.created_at`; the local row's [DayEntryMergeEventData.createdAt]
/// rides along only for the display window. Emits exactly the keys
/// `sync_push`'s c_merge_event_keys allowlist accepts.
JsonRow encodeDayEntryMergeEvent(DayEntryMergeEventData row) {
  const table = SyncTable.dayEntryMergeEvents;
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
    'winning_row_id': row.winningRowId,
    'losing_row_id': row.losingRowId,
    'field': row.field,
    'losing_value_text': row.losingValueText,
    'losing_author_user_id': row.losingAuthorUserId,
    'winning_author_user_id': row.winningAuthorUserId,
    'updated_at': encodeTimestamp(row.updatedAt),
  };
}

/// The `p_tag_registry` element for [row] (Issue #257). `created_by` and
/// `created_at` are deliberately NOT emitted — the server stamps both
/// (created_by from the caller), and a row carrying either key would be
/// rejected as an unknown key. Emits exactly the keys `sync_push`'s
/// c_tag_registry_keys allowlist accepts.
JsonRow encodeProfileTagRegistryEntry(ProfileTagRegistryEntry row) {
  const table = SyncTable.profileTagRegistry;
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
    'code': row.code,
    'display_name': row.displayName,
    'category': row.category,
    'intensity_enabled': row.intensityEnabled,
    'hidden_at': _encodeNullable(row.hiddenAt),
    'sort_order': row.sortOrder,
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
  // Issue #140 review, LLA-092: a nonfinite value_num (NaN/Infinity) can
  // reach this far only if it slipped past every write-time guard — an
  // older row from before the storage-layer check landed, say — but
  // `jsonEncode`ing one for the push body below would throw an untyped
  // `UnsupportedError` instead of this codec's own typed [RowCodecError],
  // so it is checked explicitly rather than left to fail downstream.
  if (row.valueNum != null && !row.valueNum!.isFinite) {
    throw const RowCodecError(RowCodecErrorKind.invalidNumber,
        table: table, field: 'value_num');
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
    // Issue #186: the round-trip-write marker, synced like any other
    // observations column; the server's sync_push update path guards it
    // with `v_row ? 'exported_to_platform_at'`, so always emitting the key
    // is safe (an old client omitting it never clears a stored value).
    'exported_to_platform_at': _encodeNullable(row.exportedToPlatformAt),
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
    // Issue #186: absent key (a pre-#186 server) decodes to null rather
    // than failing the pull — the marker is optional round-trip metadata,
    // not an identity field.
    exportedToPlatformAt: r.timestampOrNull('exported_to_platform_at'),
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
    estimatedDueDate:
        _decodeIsoDate(r.stringOrNull('estimated_due_date'), r, 'estimated_due_date'),
    postpartumBirthDate: _decodeIsoDate(
        r.stringOrNull('postpartum_birth_date'), r, 'postpartum_birth_date'),
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

/// Decodes a `guardian_notes` row (Issue #801). `body` is read as-is —
/// free text, never validated against a closed set. `logged_by_user_id` is
/// the author-ownership key the client uses to decide editability.
RemoteGuardianNoteRow decodeGuardianNote(JsonRow json) {
  const table = SyncTable.guardianNotes;
  final r = _Reader(json, table);
  return RemoteGuardianNoteRow(
    id: r.ulid('id'),
    profileId: r.ulid('profile_id'),
    localDate: r.isoDate('local_date'),
    tz: r.string('tz'),
    body: r.string('body'),
    updatedAt: r.timestamp('updated_at'),
    deletedAt: r.timestampOrNull('deleted_at'),
    serverVersion: r.integerOr('server_version', 0),
    loggedByUserId: r.stringOrNull('logged_by_user_id'),
    lastModifiedByUserId: r.stringOrNull('last_modified_by_user_id'),
  );
}

/// Decodes a `day_entry_merge_events` row (Issue #130). `field` is
/// normalised against the closed set ('flow' | 'note') on decode — an
/// unrecognised value can only come from a broken writer, and degrades to
/// 'note' rather than crashing a pull over display metadata. `created_at`
/// falls back to `updated_at` when absent (only a hand-built row is ever
/// null there).
RemoteDayEntryMergeEventRow decodeDayEntryMergeEvent(JsonRow json) {
  const table = SyncTable.dayEntryMergeEvents;
  final r = _Reader(json, table);
  final updatedAt = r.timestamp('updated_at');
  return RemoteDayEntryMergeEventRow(
    id: r.ulid('id'),
    profileId: r.ulid('profile_id'),
    localDate: r.isoDate('local_date'),
    winningRowId: r.ulid('winning_row_id'),
    losingRowId: r.ulid('losing_row_id'),
    field: switch (r.string('field')) {
      'flow' => 'flow',
      _ => 'note',
    },
    losingValueText: r.string('losing_value_text'),
    losingAuthorUserId: r.stringOrNull('losing_author_user_id'),
    winningAuthorUserId: r.stringOrNull('winning_author_user_id'),
    createdAt: r.timestampOrNull('created_at') ?? updatedAt,
    updatedAt: updatedAt,
    serverVersion: r.integerOr('server_version', 0),
  );
}

/// Decodes a `deleted_profiles` row (issue #522): `deleted_at` is required
/// here, unlike every other decoder's `timestampOrNull` — this table's own
/// existence is the tombstone, so a row missing it is a codec failure, not
/// an absent-optional-field default.
RemoteDeletedProfileRow decodeDeletedProfile(JsonRow json) {
  const table = SyncTable.deletedProfiles;
  final r = _Reader(json, table);
  return RemoteDeletedProfileRow(
    profileId: r.ulid('profile_id'),
    deletedAt: r.timestamp('deleted_at'),
    serverVersion: r.integerOr('server_version', 0),
  );
}

/// Decodes a `profile_tag_registry` row (Issue #257). `code`/
/// `display_name`/`category` are read as-is — free text, never validated
/// against a closed set (the registry is display vocabulary, never an
/// allowlist). A tombstone renders with its payload already cleared
/// server-side (the structural CHECK), so no client-side clearing is
/// needed; `created_by`/`created_at` ride along for display only, with
/// `created_at` falling back to `updated_at` when absent (only a
/// hand-built row is ever null there).
RemoteProfileTagRegistryRow decodeProfileTagRegistryEntry(JsonRow json) {
  const table = SyncTable.profileTagRegistry;
  final r = _Reader(json, table);
  final updatedAt = r.timestamp('updated_at');
  return RemoteProfileTagRegistryRow(
    id: r.ulid('id'),
    profileId: r.ulid('profile_id'),
    code: r.string('code'),
    displayName: r.string('display_name'),
    category: r.string('category'),
    intensityEnabled: json['intensity_enabled'] == null
        ? false
        : r.boolean('intensity_enabled'),
    hiddenAt: r.timestampOrNull('hidden_at'),
    sortOrder: r.integerOrNull('sort_order'),
    createdBy: r.stringOrNull('created_by'),
    createdAt: r.timestampOrNull('created_at') ?? updatedAt,
    updatedAt: updatedAt,
    deletedAt: r.timestampOrNull('deleted_at'),
    serverVersion: r.integerOr('server_version', 0),
  );
}

/// Decodes a `day_entry_history` row (Issue #170). `change_kind` is
/// normalised against the closed set on decode — an unrecognised value can
/// only come from a broken writer and degrades to 'updated' (the generic
/// kind) rather than crashing a pull over display metadata. `entry_id` is
/// read as a plain string, NOT validated as a ULID the way `id` is: rows
/// arrive ordered and immutable, and a legacy-shaped entry id must not
/// fail an entire pull page over display metadata.
RemoteDayEntryHistoryRow decodeDayEntryHistory(JsonRow json) {
  const table = SyncTable.dayEntryHistory;
  final r = _Reader(json, table);
  return RemoteDayEntryHistoryRow(
    id: r.ulid('id'),
    entryId: r.string('entry_id'),
    profileId: r.ulid('profile_id'),
    changedByUserId: r.string('changed_by_user_id'),
    changedAt: r.timestamp('changed_at'),
    changeKind: switch (r.string('change_kind')) {
      'logged' => 'logged',
      'tombstoned' => 'tombstoned',
      'merged_discard' => 'merged_discard',
      _ => 'updated',
    },
    changedFields: r.tags('changed_fields'),
    serverVersion: r.integerOr('server_version', 0),
  );
}

/// Decodes a pull-page row of [table].
RemoteRow decodeRemoteRow(SyncTable table, JsonRow json) =>
    _remoteRowDecoders[table]!(json);

/// Same growth rationale as [_syncTableNames]: dispatch by const map of
/// decoder tear-offs rather than an exhaustive switch.
const Map<SyncTable, RemoteRow Function(JsonRow)> _remoteRowDecoders = {
  SyncTable.profiles: decodeProfile,
  SyncTable.dayEntries: decodeDayEntry,
  SyncTable.profileGuardians: decodeProfileGuardian,
  SyncTable.observations: decodeObservation,
  SyncTable.profileModes: decodeProfileMode,
  SyncTable.cycleOverrides: decodeCycleOverride,
  SyncTable.careNotes: decodeCareNote,
  SyncTable.visitPrepItems: decodeVisitPrepItem,
  SyncTable.dayEntryMergeEvents: decodeDayEntryMergeEvent,
  SyncTable.profileTagRegistry: decodeProfileTagRegistryEntry,
  SyncTable.deletedProfiles: decodeDeletedProfile,
  SyncTable.dayEntryHistory: decodeDayEntryHistory,
  SyncTable.guardianNotes: decodeGuardianNote,
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
