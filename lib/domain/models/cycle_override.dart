/// Domain model: one manually-flagged or manually-started cycle (Issue
/// #188), stored in `profile_modes`' sibling table `cycle_overrides` and
/// consumed by #132's omit-from-average and manual cycle-boundary
/// correction.
///
/// Pure Dart with no drift/Flutter imports (R14/R16) — `test/architecture/`
/// `layering_test.dart` enforces that.
library;

/// A manual correction to a profile's cycle history: either a boundary the
/// user started by hand (`manualStart`), an interval excluded from
/// averages (`excludedFromAverage` — e.g. the pregnancy-exit flow #192
/// offers), or both. [cycleStartDate] is the ISO calendar date
/// (`yyyy-MM-dd`) the boundary sits on.
///
/// Deletes are tombstones (`deletedAt` set, payload cleared): the
/// correction is withdrawn, not forgotten, so sync converges.
class CycleOverride {
  CycleOverride({
    required this.id,
    required this.profileId,
    required this.cycleStartDate,
    this.excludedFromAverage = false,
    this.manualStart = false,
    this.noteId,
    this.updatedAt,
    this.deletedAt,
  });

  /// Client-generated ULID (stable across devices/sync).
  final String id;

  /// The profile whose cycle history this corrects.
  final String profileId;

  /// ISO calendar date `yyyy-MM-dd` of the manual boundary.
  final String cycleStartDate;

  /// True when this interval is left out of cycle-length averages (#132).
  final bool excludedFromAverage;

  /// True when the user started this cycle by hand rather than the
  /// predictor deriving it from bleeding days.
  final bool manualStart;

  /// Placeholder id of a future notes-table row (#132); null when the
  /// correction carries no note.
  final String? noteId;

  /// UTC instant of the last write; null on unsaved, client-created
  /// models.
  final DateTime? updatedAt;

  /// Null for live rows; set when the correction is withdrawn (tombstone).
  final DateTime? deletedAt;

  bool get isTombstone => deletedAt != null;

  CycleOverride copyWith({
    String? id,
    String? profileId,
    String? cycleStartDate,
    bool? excludedFromAverage,
    bool? manualStart,
    Object? noteId = _unset,
    Object? updatedAt,
    Object? deletedAt = _unset,
  }) =>
      CycleOverride(
        id: id ?? this.id,
        profileId: profileId ?? this.profileId,
        cycleStartDate: cycleStartDate ?? this.cycleStartDate,
        excludedFromAverage: excludedFromAverage ?? this.excludedFromAverage,
        manualStart: manualStart ?? this.manualStart,
        noteId: _resolveNullable(noteId, this.noteId),
        updatedAt: updatedAt as DateTime? ?? this.updatedAt,
        deletedAt: _resolveNullable(deletedAt, this.deletedAt),
      );

  static const Object _unset = Object();

  /// Resolves a `copyWith` sentinel-typed parameter: an unpassed argument
  /// (still `_unset`) keeps [fallback]; anything else (including an
  /// explicit `null`) overrides it. Same shape as [Profile._resolveNullable].
  static T? _resolveNullable<T>(Object? value, T? fallback) =>
      identical(value, _unset) ? fallback : value as T?;

  bool _sameIdentity(CycleOverride other) =>
      other.id == id &&
      other.profileId == profileId &&
      other.cycleStartDate == cycleStartDate;

  bool _sameDetails(CycleOverride other) =>
      other.excludedFromAverage == excludedFromAverage &&
      other.manualStart == manualStart &&
      other.noteId == noteId &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CycleOverride && _sameIdentity(other) && _sameDetails(other);

  @override
  int get hashCode => Object.hash(
        id,
        profileId,
        cycleStartDate,
        excludedFromAverage,
        manualStart,
        noteId,
        updatedAt,
        deletedAt,
      );

  @override
  String toString() =>
      'CycleOverride($id $profileId $cycleStartDate'
      '${excludedFromAverage ? ' excluded' : ''}${manualStart ? ' manual' : ''}'
      '${deletedAt == null ? '' : ' [tombstoned]'})';
}
