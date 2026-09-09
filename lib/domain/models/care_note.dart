/// Domain model: one standing, non-date-bound care note on a profile
/// (Issue #128).
///
/// A care note belongs to the profile, not to a calendar date — the thing
/// the day-entry model (`day_entry.dart`) cannot express. Small by design:
/// a handful of standing notes per profile, each carrying who wrote it and
/// when (the same attribution treatment as day entries).
///
/// Concurrent-edit resolution (stated up front, per the issue's design
/// constraints): per-note last-writer-wins by `updatedAt` (the remote copy
/// wins ties, mirroring the day-entry KTD5 rule). Two guardians adding
/// notes concurrently offline mint distinct ULIDs, so both rows survive —
/// only an edit to the *same* note id races, and the later write wins.
/// There is no cross-note merge: this is not a chat feature.
///
/// Pure Dart with no drift/Flutter imports (R14/R16).
library;

class CareNote {
  CareNote({
    required this.id,
    required this.profileId,
    required this.body,
    required this.updatedAt,
    this.deletedAt,
    this.loggedByUserId,
    this.lastModifiedByUserId,
  });

  final String id;
  final String profileId;

  /// Free-text standing note (health content about a minor: length-bounded
  /// by `kMaxCareNoteLength`, scrubbed from crash reports, never in a
  /// notification payload).
  final String body;

  /// UTC instant of the last write (monotonic at the storage layer).
  final DateTime updatedAt;

  /// Null for live notes: repository reads filter tombstones.
  final DateTime? deletedAt;

  /// The Supabase auth user who originally wrote this note.
  final String? loggedByUserId;

  /// The Supabase auth user who last edited this note.
  final String? lastModifiedByUserId;

  static const Object _unset = Object();

  CareNote copyWith({
    String? id,
    String? profileId,
    String? body,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
    Object? loggedByUserId = _unset,
    Object? lastModifiedByUserId = _unset,
  }) =>
      CareNote(
        id: id ?? this.id,
        profileId: profileId ?? this.profileId,
        body: body ?? this.body,
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
      other is CareNote &&
          other.id == id &&
          other.profileId == profileId &&
          other.body == body &&
          other.updatedAt == updatedAt &&
          other.deletedAt == deletedAt &&
          other.loggedByUserId == loggedByUserId &&
          other.lastModifiedByUserId == lastModifiedByUserId;

  @override
  int get hashCode => Object.hash(
        id,
        profileId,
        body,
        updatedAt,
        deletedAt,
        loggedByUserId,
        lastModifiedByUserId,
      );

  @override
  String toString() => 'CareNote($profileId $id'
      '${deletedAt == null ? '' : ' [tombstoned]}'})';
}
