/// Domain model: one item on a profile's visit-prep checklist (Issue #128)
/// — a question or to-bring for an upcoming appointment.
///
/// Like care notes, a prep item belongs to the profile, not to a date. Any
/// guardian with write access can add, check off, and remove items. Checked
/// items stay visible until the list is explicitly cleared, so the other
/// parent can see what was covered; checking records who checked it and
/// when (AC3).
///
/// Concurrent-edit resolution (stated up front, per the issue's design
/// constraints): the checklist converges as a set of independent rows.
/// Add and remove are commutative on distinct ULIDs — two guardians adding
/// items concurrently offline both keep their items after sync (AC7). A
/// check-off or an edit races only against another write to the *same*
/// item id, resolved per-id last-writer-wins by `updatedAt` (remote wins
/// ties). There is no threading, no messaging, and no notification of its
/// own.
///
/// Pure Dart with no drift/Flutter imports (R14/R16).
library;

class VisitPrepItem {
  VisitPrepItem({
    required this.id,
    required this.profileId,
    required this.body,
    this.isChecked = false,
    this.checkedByUserId,
    this.checkedAt,
    required this.updatedAt,
    this.deletedAt,
    this.loggedByUserId,
    this.lastModifiedByUserId,
  });

  final String id;
  final String profileId;

  /// The item/question text (health content about a minor: length-bounded
  /// by `kMaxVisitPrepItemLength`, scrubbed from crash reports, never in a
  /// notification payload).
  final String body;

  /// Whether the item has been checked off. Checked items stay visible
  /// until cleared — checking never deletes.
  final bool isChecked;

  /// The Supabase auth user who checked the item, or null while unchecked.
  final String? checkedByUserId;

  /// UTC instant the item was checked, or null while unchecked.
  final DateTime? checkedAt;

  /// UTC instant of the last write (monotonic at the storage layer).
  final DateTime updatedAt;

  /// Null for live items: repository reads filter tombstones.
  final DateTime? deletedAt;

  /// The Supabase auth user who originally added this item.
  final String? loggedByUserId;

  /// The Supabase auth user who last edited this item.
  final String? lastModifiedByUserId;

  static const Object _unset = Object();

  VisitPrepItem copyWith({
    String? id,
    String? profileId,
    String? body,
    bool? isChecked,
    Object? checkedByUserId = _unset,
    Object? checkedAt = _unset,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
    Object? loggedByUserId = _unset,
    Object? lastModifiedByUserId = _unset,
  }) =>
      VisitPrepItem(
        id: id ?? this.id,
        profileId: profileId ?? this.profileId,
        body: body ?? this.body,
        isChecked: isChecked ?? this.isChecked,
        checkedByUserId:
            _resolveNullable(checkedByUserId, this.checkedByUserId),
        checkedAt: _resolveNullable(checkedAt, this.checkedAt),
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
      other is VisitPrepItem &&
          _sameIdentity(other) &&
          _sameBody(other) &&
          _sameSync(other);

  // Split into per-aspect halves so no single comparison chain exceeds the
  // CRAP-gate complexity budget on its own (the domain DayEntry
  // _sameIdentity/_sameContent precedent).
  bool _sameIdentity(VisitPrepItem other) =>
      other.id == id && other.profileId == profileId;

  bool _sameBody(VisitPrepItem other) =>
      other.body == body &&
      other.isChecked == isChecked &&
      other.checkedByUserId == checkedByUserId &&
      other.checkedAt == checkedAt;

  bool _sameSync(VisitPrepItem other) =>
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.loggedByUserId == loggedByUserId &&
      other.lastModifiedByUserId == lastModifiedByUserId;

  @override
  int get hashCode => Object.hash(
        id,
        profileId,
        body,
        isChecked,
        checkedByUserId,
        checkedAt,
        updatedAt,
        deletedAt,
        loggedByUserId,
        lastModifiedByUserId,
      );

  @override
  String toString() => 'VisitPrepItem($profileId $id'
      '${isChecked ? ' [checked]' : ''}'
      '${deletedAt == null ? '' : ' [tombstoned]}'})';
}
