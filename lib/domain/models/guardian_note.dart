/// Domain model: one guardian's dated note on a profile's day (Issue #801).
///
/// The gap this closes: `DayEntry.note` is a single shared `String?` per day
/// with no author, so a parent writing about her daughter's day writes into
/// the daughter's note and two writers collide. A [GuardianNote] is both
/// date-bound *and* author-scoped — the mirror gap to [CareNote], which is
/// author-attributed but not bound to a date.
///
/// Concurrent-edit resolution (the care-note rules, restated here):
/// per-note last-writer-wins by [updatedAt] (the remote copy wins ties,
/// mirroring the day-entry KTD5 rule). Two guardians adding notes for the
/// same date concurrently offline mint distinct ULIDs, so both rows survive
/// — only an edit to the *same* note id races, and the later write wins.
/// There is no cross-author merge, ever: two authors on the same day are two
/// distinct rows, both live. A note is editable and removable only by its
/// original author, on both the client and the server.
///
/// Visibility (issue #800, decided): every accepted guardian — the child
/// included — reads every guardian note. There is no per-note visibility
/// flag. The writing surface states that audience at the point of writing.
///
/// Pure Dart with no drift/Flutter imports (R14/R16).
library;

import 'local_date.dart';

class GuardianNote {
  GuardianNote({
    required this.id,
    required this.profileId,
    required this.localDate,
    required this.tz,
    required this.body,
    required this.updatedAt,
    this.deletedAt,
    this.loggedByUserId,
    this.lastModifiedByUserId,
  });

  final String id;
  final String profileId;

  /// Civil calendar date the note is about (the date-bound half of the
  /// model).
  final LocalDate localDate;

  /// IANA time zone name the author's day was measured in.
  final String tz;

  /// Free-text note (health content about a minor: length-bounded by
  /// `kMaxCareNoteLength`, scrubbed from crash reports, never in a
  /// notification payload).
  final String body;

  /// UTC instant of the last write (monotonic at the storage layer).
  final DateTime updatedAt;

  /// Null for live notes: repository reads filter tombstones.
  final DateTime? deletedAt;

  /// The Supabase auth user who originally wrote this note. Author-immutable
  /// — the server refuses an edit or tombstone by anyone else.
  final String? loggedByUserId;

  /// The Supabase auth user who last edited this note.
  final String? lastModifiedByUserId;

  static const Object _unset = Object();

  GuardianNote copyWith({
    String? id,
    String? profileId,
    LocalDate? localDate,
    String? tz,
    String? body,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
    Object? loggedByUserId = _unset,
    Object? lastModifiedByUserId = _unset,
  }) =>
      GuardianNote(
        id: id ?? this.id,
        profileId: profileId ?? this.profileId,
        localDate: localDate ?? this.localDate,
        tz: tz ?? this.tz,
        body: body ?? this.body,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: _resolveNullable(deletedAt, this.deletedAt),
        loggedByUserId: _resolveNullable(loggedByUserId, this.loggedByUserId),
        lastModifiedByUserId:
            _resolveNullable(lastModifiedByUserId, this.lastModifiedByUserId),
      );

  static T? _resolveNullable<T>(Object? overrideValue, T? currentValue) =>
      identical(overrideValue, _unset) ? currentValue : overrideValue as T?;

  /// Every field as one structural value, so `==`/`hashCode` stay a single
  /// comparison each (nine field comparisons inline would put the method
  /// over the CRAP gate's complexity bound for a model this wide).
  Object get _equalityKey => (
        id,
        profileId,
        localDate,
        tz,
        body,
        updatedAt,
        deletedAt,
        loggedByUserId,
        lastModifiedByUserId,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuardianNote && _equalityKey == other._equalityKey;

  @override
  int get hashCode => _equalityKey.hashCode;

  @override
  String toString() => 'GuardianNote($profileId ${localDate.iso} $id'
      '${deletedAt == null ? '' : ' [tombstoned]}'})';
}
