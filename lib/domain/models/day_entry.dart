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

  bool _sameContent(DayEntry other) =>
      other.flow == flow &&
      listEquals(other.tags, tags) &&
      other.note == note &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.loggedByUserId == loggedByUserId &&
      other.lastModifiedByUserId == lastModifiedByUserId;

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
      );

  @override
  String toString() =>
      'DayEntry($profileId ${localDate.iso} ${flow.name}'
      '${note == null ? '' : ' note'}'
      '${deletedAt == null ? '' : ' [tombstoned]}'})';
}
