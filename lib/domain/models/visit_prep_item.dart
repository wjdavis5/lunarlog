/// Domain model: one item on a profile's visit-prep checklist (Issue #128)
/// — a question or to-bring for an upcoming appointment — or, as of Issue
/// #851, one item on the profile's household supplies list. The two share
/// this model and its storage/sync/RLS substrate; [VisitPrepItemKind]
/// discriminates. A supply item lives on the profile, visible to every
/// guardian including the subject: #800 already established that guardian
/// notes are visible to the subject, and a supplies list a teen cannot see
/// would be a list about her she is excluded from.
///
/// Like care notes, a prep item belongs to the profile, not to a date. Any
/// guardian with write access can add, check off, and remove items. Checked
/// items stay visible until the list is explicitly cleared, so the other
/// parent can see what was covered; checking records who checked it and
/// when (AC3). For a supply item, "checked" reads as "stocked".
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

/// Issue #851: the row's kind. `visitPrep` is the Issue #128 visit-prep
/// checklist item (a question or to-bring for an appointment); `supply` is
/// a household-logistics stock item, where [VisitPrepItem.isChecked] reads
/// as "stocked". The two share one table, one sync path, one RLS posture,
/// and one model because a supply item is structurally identical to a prep
/// item — a synced, attributed, tombstoned checklist row — so a second
/// table would have been a copy with the same invariants.
enum VisitPrepItemKind {
  visitPrep,
  supply;

  /// Server wire string — mirrors `visit_prep_items_kind_check`.
  String toDb() => switch (this) {
        VisitPrepItemKind.visitPrep => 'visit_prep',
        VisitPrepItemKind.supply => 'supply',
      };

  /// Never throws: an unrecognised value (only reachable from a broken
  /// writer) degrades to [visitPrep], the column default.
  static VisitPrepItemKind fromDb(String value) => switch (value) {
        'supply' => VisitPrepItemKind.supply,
        _ => VisitPrepItemKind.visitPrep,
      };
}

class VisitPrepItem {
  VisitPrepItem({
    required this.id,
    required this.profileId,
    required this.body,
    this.kind = VisitPrepItemKind.visitPrep,
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

  /// Which list this row belongs to (Issue #851): a visit-prep question or
  /// a household supply item, where [isChecked] reads as "stocked".
  final VisitPrepItemKind kind;

  /// Whether the item has been checked off (or, for a supply item,
  /// stocked). Checked items stay visible until cleared — checking never
  /// deletes.
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
    VisitPrepItemKind? kind,
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
        kind: kind ?? this.kind,
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
      other.kind == kind &&
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
        kind,
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
