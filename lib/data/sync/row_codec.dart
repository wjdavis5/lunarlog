/// Wire codec between drift rows and the remote JSON shape (U10; KTD2,
/// KTD3, KTD5): the `sync_push` request rows, the RPC's `resolved` rows and
/// PostgREST pull pages.
///
/// * Timestamps: drift stores ISO-8601 UTC text and hands us `DateTime`;
///   the server renders `timestamptz` as `2026-09-01T10:00:00.123+00:00`.
///   Decoding always yields a UTC `DateTime` with microsecond precision so
///   the conflict rules compare instants, never strings.
/// * `local_date` stays the `yyyy-MM-dd` string on both sides.
/// * `tags` is a JSON array of strings; `flow` is the enum name.
/// * `day_entries.created_at` is server-only: never emitted, never read.
/// * Failures are a typed [RowCodecError] naming the table and field and
///   the kind of problem — never the offending value, never the row.
///
/// Like `mappers.dart`, this is a place where storage types and another
/// representation meet; nothing under `lib/domain` imports it.
library;

import '../db/db.dart';
import '../db/tables.dart';
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

final RegExp _ulid = RegExp(r'^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$');
final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Postgres text rendering: `2026-09-01 10:00:00.123456+00` (space
/// separator, offset without minutes) — normalised before `DateTime.parse`.
final RegExp _shortOffset = RegExp(r'([+-]\d{2})$');

/// Whether [value] has the ULID shape the server's CHECK enforces.
bool isUlid(String value) => _ulid.hasMatch(value);

/// Remote table name for [table] (`profiles` / `day_entries`).
String syncTableName(SyncTable table) => switch (table) {
      SyncTable.profiles => 'profiles',
      SyncTable.dayEntries => 'day_entries',
    };

/// Inverse of [syncTableName]; null for anything else.
SyncTable? syncTableFromName(String name) => switch (name) {
      'profiles' => SyncTable.profiles,
      'day_entries' => SyncTable.dayEntries,
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
JsonRow encodeProfile(Profile row) {
  if (!isUlid(row.id)) {
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
  };
}

/// The `p_day_entries` element for [row]. No `created_at` (server-only).
JsonRow encodeDayEntry(DayEntry row) {
  const table = SyncTable.dayEntries;
  if (!isUlid(row.id)) {
    throw const RowCodecError(RowCodecErrorKind.invalidId,
        table: table, field: 'id');
  }
  if (!isUlid(row.profileId)) {
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
    'flow': row.flow.name,
    'tags': List<String>.of(row.tags),
    'note': row.note,
    'updated_at': encodeTimestamp(row.updatedAt),
    'deleted_at': _encodeNullable(row.deletedAt),
  };
}

String? _encodeNullable(DateTime? value) =>
    value == null ? null : encodeTimestamp(value);

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
  );
}

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
    updatedAt: r.timestamp('updated_at'),
    deletedAt: r.timestampOrNull('deleted_at'),
    serverVersion: r.integerOr('server_version', 0),
  );
}

/// Decodes a pull-page row of [table].
RemoteRow decodeRemoteRow(SyncTable table, JsonRow json) => switch (table) {
      SyncTable.profiles => decodeProfile(json),
      SyncTable.dayEntries => decodeDayEntry(json),
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
    if (!isUlid(value)) _fail(RowCodecErrorKind.invalidId, field);
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
      if (level.name == value) return level;
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
