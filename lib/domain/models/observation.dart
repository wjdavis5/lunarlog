/// Domain model: one logged option (Issue #240, the Clue tracking model's
/// `observations` child table) — a `dayEntryId`-scoped row per (category,
/// code), with an optional numeric/text value, unit, intensity, exclusion
/// flag, and source provenance.
///
/// Pure Dart with no drift/Flutter imports (R14/R16), mirroring
/// `lib/domain/models/day_entry.dart`'s shape. `category`/`code` are free
/// text — never validated here against a closed set (issue #240 D-10
/// companion note: unlike `flow`, the ~200 option codes are stored, never
/// rejected, so an unrecognised code from a newer client or an importer
/// always round-trips).
library;

import 'local_date.dart';

/// `manual` / `apple_health` / `health_connect` / `wearable` / `clue_import`.
enum ObservationSource {
  manual,
  appleHealth,
  healthConnect,
  wearable,
  clueImport;

  /// The raw string stored on the row and sent over the wire.
  String toDb() => switch (this) {
        ObservationSource.manual => 'manual',
        ObservationSource.appleHealth => 'apple_health',
        ObservationSource.healthConnect => 'health_connect',
        ObservationSource.wearable => 'wearable',
        ObservationSource.clueImport => 'clue_import',
      };

  /// Normalises a raw `source` string against the closed set: an
  /// unrecognised value (a future addition, a row from a newer client)
  /// degrades to [manual] rather than throwing — source provenance is
  /// informational, never a security- or authorization-relevant field.
  static ObservationSource fromDb(String? raw) => switch (raw) {
        'apple_health' => ObservationSource.appleHealth,
        'health_connect' => ObservationSource.healthConnect,
        'wearable' => ObservationSource.wearable,
        'clue_import' => ObservationSource.clueImport,
        _ => ObservationSource.manual,
      };
}

// TODO(#186): mirror the server's observations_derive_local_date trigger
// (supabase/migrations/20260908180000_timezone_contract.sql, issue #180)
// here on the client, so a locally-constructed Observation carrying
// observedAt always has a local_date consistent with the day-boundary
// contract in lib/domain/health/day_boundary.dart before it ever reaches
// sync_push. Not done in issue #180 itself: localDate is a required,
// independently-supplied constructor argument used by five call sites
// (lib/data/db/storage.dart, lib/data/repositories/mappers.dart,
// lib/data/sync/row_codec.dart, lib/data/sync/supabase_sync_engine.dart,
// lib/domain/export/account_export.dart) that read/write stored rows
// as-is, several of which must NOT recompute localDate from observedAt
// (a row read back from storage or the wire already carries the
// server-resolved value) — making derivation automatic here would need to
// distinguish "constructing a brand-new client-authored observation" from
// "rehydrating an already-resolved one," which is a bigger, call-site-aware
// change than this issue's scope, not a one-place constructor edit.
class Observation {
  Observation({
    required this.id,
    required this.dayEntryId,
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
    this.source = ObservationSource.manual,
    this.sourceId,
    this.importId,
    this.raw,
    required this.updatedAt,
    this.deletedAt,
    this.loggedByUserId,
    this.lastModifiedByUserId,
  });

  final String id;
  final String dayEntryId;
  final String profileId;

  /// Civil calendar date in the profile's local zone.
  final LocalDate localDate;

  /// Optional exact time-of-day; unused by the Clue importer (A1-40).
  final DateTime? observedAt;

  /// IANA time zone name the entry was logged in.
  final String tz;

  /// e.g. `pain`, `energy`, `bbt`. Free text, never a closed set.
  final String category;

  /// The selected option within [category] (e.g. `migraine`); null only
  /// for a purely-numeric category. Free text, never a closed set.
  final String? code;

  final double? valueNum;
  final String? valueText;

  /// `celsius` / `fahrenheit` / `kg` / `lb`.
  final String? unit;

  /// 1-5; null for legacy/ungraded rows.
  final int? intensity;

  /// BBT's per-point exclusion flag (A1-44).
  final bool excluded;

  final ObservationSource source;

  /// Import/device provenance key, for idempotent re-import.
  final String? sourceId;

  /// Placeholder FK to a future `import_jobs(id)` row (Issue #159,
  /// unconstrained server-side until #167 adds that table). Never cleared
  /// on a tombstone.
  final String? importId;

  /// Escape hatch for an unrecognised type/value shape (A1-45): the entire
  /// original datapoint, as a raw JSON string.
  final String? raw;

  /// UTC instant of the last write (monotonic at the storage layer).
  final DateTime updatedAt;

  /// Null for live rows: repository reads filter tombstones. Carried for
  /// full-fidelity sync reads.
  final DateTime? deletedAt;

  /// The Supabase auth user who originally recorded this observation.
  final String? loggedByUserId;

  /// The Supabase auth user who last edited this observation.
  final String? lastModifiedByUserId;

  static const Object _unset = Object();

  Observation copyWith({
    String? id,
    String? dayEntryId,
    String? profileId,
    LocalDate? localDate,
    Object? observedAt = _unset,
    String? tz,
    String? category,
    Object? code = _unset,
    Object? valueNum = _unset,
    Object? valueText = _unset,
    Object? unit = _unset,
    Object? intensity = _unset,
    bool? excluded,
    ObservationSource? source,
    Object? sourceId = _unset,
    Object? importId = _unset,
    Object? raw = _unset,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
    Object? loggedByUserId = _unset,
    Object? lastModifiedByUserId = _unset,
  }) =>
      Observation(
        id: id ?? this.id,
        dayEntryId: dayEntryId ?? this.dayEntryId,
        profileId: profileId ?? this.profileId,
        localDate: localDate ?? this.localDate,
        observedAt: _resolveNullable(observedAt, this.observedAt),
        tz: tz ?? this.tz,
        category: category ?? this.category,
        code: _resolveNullable(code, this.code),
        valueNum: _resolveNullable(valueNum, this.valueNum),
        valueText: _resolveNullable(valueText, this.valueText),
        unit: _resolveNullable(unit, this.unit),
        intensity: _resolveNullable(intensity, this.intensity),
        excluded: excluded ?? this.excluded,
        source: source ?? this.source,
        sourceId: _resolveNullable(sourceId, this.sourceId),
        importId: _resolveNullable(importId, this.importId),
        raw: _resolveNullable(raw, this.raw),
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: _resolveNullable(deletedAt, this.deletedAt),
        loggedByUserId: _resolveNullable(loggedByUserId, this.loggedByUserId),
        lastModifiedByUserId:
            _resolveNullable(lastModifiedByUserId, this.lastModifiedByUserId),
      );

  static T? _resolveNullable<T>(Object? overrideValue, T? currentValue) =>
      identical(overrideValue, _unset) ? currentValue : overrideValue as T?;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Observation && _sameIdentity(other) && _sameContent(other);

  bool _sameIdentity(Observation other) =>
      other.id == id &&
      other.dayEntryId == dayEntryId &&
      other.profileId == profileId &&
      other.localDate == localDate;

  // Split from a single ==, per-field chain, the same way DayEntry splits
  // _sameIdentity from _sameContent: a value half and a provenance half, so
  // neither exceeds the CRAP-gate complexity budget on its own. Same
  // fields, same order, no behavior change.
  bool _sameContent(Observation other) =>
      _sameValue(other) && _sameProvenance(other);

  bool _sameValue(Observation other) =>
      other.observedAt == observedAt &&
      other.tz == tz &&
      other.category == category &&
      other.code == code &&
      other.valueNum == valueNum &&
      other.valueText == valueText &&
      other.unit == unit &&
      other.intensity == intensity &&
      other.excluded == excluded;

  bool _sameProvenance(Observation other) =>
      other.source == source &&
      other.sourceId == sourceId &&
      other.importId == importId &&
      other.raw == raw &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.loggedByUserId == loggedByUserId &&
      other.lastModifiedByUserId == lastModifiedByUserId;

  @override
  int get hashCode => Object.hash(
        id,
        dayEntryId,
        profileId,
        localDate,
        observedAt,
        tz,
        category,
        code,
        valueNum,
        Object.hash(valueText, unit, intensity, excluded, source, sourceId),
        importId,
        raw,
        updatedAt,
        deletedAt,
        loggedByUserId,
        lastModifiedByUserId,
      );

  @override
  String toString() =>
      // `code` is the specific logged symptom (e.g. `migraine`) — elided the
      // way `DayEntry.toString()` elides note content, never the value
      // itself. `category` (e.g. `pain`) is coarser and kept.
      'Observation($profileId ${localDate.iso} $category'
      '${code == null ? '' : ' code'}'
      '${deletedAt == null ? '' : ' [tombstoned]'})';
}
