/// Domain model: one profile's tracked day.
///
/// Identity in the domain is (profileId, localDate) — saving always upserts
/// the live entry for that pair. [id] is the storage-assigned ULID (stable
/// for sync); it is populated on reads and ignored on save.
///
/// Pure Dart with no drift/Flutter imports (R14/R16).
library;

import '../util/list_equals.dart';
import 'flow_level.dart';
import 'local_date.dart';

/// `manual` / `clue_import` / `healthkit` / `health_connect` / `file_import`
/// (Issue #159, `day_entries_source_check`). Deliberately a different closed
/// set from `ObservationSource` — the two tables' provenance domains are
/// genuinely different (a whole day's flow/tag import source vs. one logged
/// option's device/source), mirrored independently server-side too.
enum DayEntrySource {
  manual,
  clueImport,
  healthkit,
  healthConnect,
  fileImport;

  /// The raw string stored on the row and sent over the wire.
  String toDb() => switch (this) {
        DayEntrySource.manual => 'manual',
        DayEntrySource.clueImport => 'clue_import',
        DayEntrySource.healthkit => 'healthkit',
        DayEntrySource.healthConnect => 'health_connect',
        DayEntrySource.fileImport => 'file_import',
      };

  /// Normalises a raw `source` string against the closed set: an
  /// unrecognised value (a future addition, a row from a newer client)
  /// degrades to [manual] rather than throwing — source provenance is
  /// informational, never a security- or authorization-relevant field
  /// (mirrors [ObservationSource.fromDb]'s precedent).
  static DayEntrySource fromDb(String? raw) => switch (raw) {
        'clue_import' => DayEntrySource.clueImport,
        'healthkit' => DayEntrySource.healthkit,
        'health_connect' => DayEntrySource.healthConnect,
        'file_import' => DayEntrySource.fileImport,
        _ => DayEntrySource.manual,
      };
}

class DayEntry {
  DayEntry({
    required this.id,
    required this.profileId,
    required this.localDate,
    required this.tz,
    required this.flow,
    this.tags = const [],
    this.note,
    required this.updatedAt,
    this.deletedAt,
    this.loggedByUserId,
    this.lastModifiedByUserId,
    this.source = DayEntrySource.manual,
    this.sourceId,
    this.importId,
  });

  final String id;
  final String profileId;

  /// Civil calendar date in the profile's local zone.
  final LocalDate localDate;

  /// IANA time zone name the date was recorded in.
  final String tz;

  final FlowLevel flow;

  /// Tag codes from the domain taxonomy (`lib/domain/tags.dart`).
  final List<String> tags;

  final String? note;

  /// UTC instant of the last write (monotonic at the storage layer).
  final DateTime updatedAt;

  /// Null for live entries: repository reads filter tombstones. Carried for
  /// full-fidelity sync reads in later units.
  final DateTime? deletedAt;

  /// The Supabase auth user who originally recorded this day entry (Issue #8).
  final String? loggedByUserId;

  /// The Supabase auth user who last edited this day entry (Issue #8).
  final String? lastModifiedByUserId;

  /// Import/device provenance (Issue #159). Defaults to [DayEntrySource.manual]
  /// for every entry logged directly in the app.
  final DayEntrySource source;

  /// Import/device provenance key, for idempotent re-import — paired with
  /// [source] in the server's partial unique index. Null for a manually
  /// logged entry.
  final String? sourceId;

  /// Placeholder FK to a future `import_jobs(id)` row (Issue #159,
  /// unconstrained server-side until #167 adds that table). Null for a
  /// manually logged entry.
  final String? importId;

  static const Object _unset = Object();

  DayEntry copyWith({
    String? id,
    String? profileId,
    LocalDate? localDate,
    String? tz,
    FlowLevel? flow,
    List<String>? tags,
    Object? note = _unset,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
    Object? loggedByUserId = _unset,
    Object? lastModifiedByUserId = _unset,
    DayEntrySource? source,
    Object? sourceId = _unset,
    Object? importId = _unset,
  }) =>
      DayEntry(
        id: id ?? this.id,
        profileId: profileId ?? this.profileId,
        localDate: localDate ?? this.localDate,
        tz: tz ?? this.tz,
        flow: flow ?? this.flow,
        tags: tags ?? this.tags,
        note: _resolveNullable(note, this.note),
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: _resolveNullable(deletedAt, this.deletedAt),
        loggedByUserId: _resolveNullable(loggedByUserId, this.loggedByUserId),
        lastModifiedByUserId:
            _resolveNullable(lastModifiedByUserId, this.lastModifiedByUserId),
        source: source ?? this.source,
        sourceId: _resolveNullable(sourceId, this.sourceId),
        importId: _resolveNullable(importId, this.importId),
      );

  static T? _resolveNullable<T>(Object? overrideValue, T? currentValue) =>
      identical(overrideValue, _unset) ? currentValue : overrideValue as T?;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DayEntry && _sameIdentity(other) && _sameContent(other);

  // Split from a single ==, per-field chain into an identity half and a
  // content half — same fields, same order, no behavior change.
  bool _sameIdentity(DayEntry other) =>
      other.id == id &&
      other.profileId == profileId &&
      other.localDate == localDate &&
      other.tz == tz;

  // Split from a single ==, per-field chain, the same way
  // Observation._sameContent splits into a value half and a provenance half
  // (Issue #159 adds a third provenance field here too), so neither half
  // exceeds the CRAP-gate complexity budget on its own.
  bool _sameContent(DayEntry other) =>
      _sameValue(other) && _sameProvenance(other);

  bool _sameValue(DayEntry other) =>
      other.flow == flow &&
      listEquals(other.tags, tags) &&
      other.note == note &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  bool _sameProvenance(DayEntry other) =>
      other.loggedByUserId == loggedByUserId &&
      other.lastModifiedByUserId == lastModifiedByUserId &&
      other.source == source &&
      other.sourceId == sourceId &&
      other.importId == importId;

  @override
  int get hashCode => Object.hash(
        id,
        profileId,
        localDate,
        tz,
        flow,
        Object.hashAll(tags),
        note,
        updatedAt,
        deletedAt,
        loggedByUserId,
        lastModifiedByUserId,
        Object.hash(source, sourceId, importId),
      );

  @override
  String toString() =>
      'DayEntry($profileId ${localDate.iso} ${flow.name}'
      '${note == null ? '' : ' note'}'
      '${deletedAt == null ? '' : ' [tombstoned]}'})';
}
