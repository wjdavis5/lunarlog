/// Domain model: a tracked person (the operator or one of the minors).
///
/// Pure Dart with no drift/Flutter imports (R14/R16). Archiving is a soft
/// UI concern (profile stays in history); deleting is a tombstone.
library;

class Profile {
  Profile({
    required this.id,
    required this.displayName,
    required this.isMinor,
    this.sortOrder = 0,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  /// Storage-assigned ULID (empty on unsaved, client-created models).
  final String id;

  final String displayName;
  final bool isMinor;
  final int sortOrder;

  /// UTC instant when the profile was archived, or null when live.
  final DateTime? archivedAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Null for live profiles: repository reads filter tombstones.
  final DateTime? deletedAt;

  static const Object _unset = Object();

  Profile copyWith({
    String? id,
    String? displayName,
    bool? isMinor,
    int? sortOrder,
    Object? archivedAt = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
  }) =>
      Profile(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        isMinor: isMinor ?? this.isMinor,
        sortOrder: sortOrder ?? this.sortOrder,
        archivedAt:
            archivedAt == _unset ? this.archivedAt : archivedAt as DateTime?,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt:
            deletedAt == _unset ? this.deletedAt : deletedAt as DateTime?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Profile &&
          other.id == id &&
          other.displayName == displayName &&
          other.isMinor == isMinor &&
          other.sortOrder == sortOrder &&
          other.archivedAt == archivedAt &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(
        id,
        displayName,
        isMinor,
        sortOrder,
        archivedAt,
        createdAt,
        updatedAt,
        deletedAt,
      );

  @override
  String toString() =>
      'Profile($id $displayName${isMinor ? ' minor' : ''}'
      '${archivedAt == null ? '' : ' [archived]'}'
      '${deletedAt == null ? '' : ' [tombstoned]'})';
}
