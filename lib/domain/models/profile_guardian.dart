/// Domain model: a caregiver or viewer linked to a profile (Issue #8).
///
/// Pure Dart with no drift/Flutter imports (R14/R16).
library;

/// Guardian roles matching the database check constraints.
enum GuardianRole {
  primaryGuardian,
  coParent,
  caregiver,
  viewer;

  String toDb() => switch (this) {
        primaryGuardian => 'primary_guardian',
        coParent => 'co_parent',
        caregiver => 'caregiver',
        viewer => 'viewer',
      };

  static GuardianRole fromDb(String value) => switch (value) {
        'primary_guardian' => primaryGuardian,
        'co_parent' => coParent,
        'caregiver' => caregiver,
        'viewer' => viewer,
        _ => throw ArgumentError.value(value, 'value', 'unknown guardian role'),
      };

  String get label => switch (this) {
        primaryGuardian => 'Primary Guardian',
        coParent => 'Co-Parent',
        caregiver => 'Caregiver',
        viewer => 'Viewer',
      };

  bool get canLog => this != viewer;
  bool get canEditProfile => this == primaryGuardian || this == coParent;
  bool get canManageGuardians => this == primaryGuardian || this == coParent;
  bool get canDeleteProfile => this == primaryGuardian;

  /// Copy explaining why a role's day sheet is read-only (Issue #3
  /// gap-closure plan, Unit U6; R13). Null for every role that [canLog] -
  /// only a role that cannot log has a reason to surface, and it must read
  /// distinctly from the archived-profile reason so a viewer session is
  /// never mistaken for an archived one.
  String? get readOnlyReason => switch (this) {
        viewer => 'You have view-only access to this profile.',
        _ => null,
      };
}

enum GuardianStatus {
  pending,
  accepted,
  revoked;

  String toDb() => name;

  static GuardianStatus fromDb(String value) => switch (value) {
        'pending' => pending,
        'accepted' => accepted,
        'revoked' => revoked,
        _ => throw ArgumentError.value(value, 'value', 'unknown guardian status'),
      };
}

class ProfileGuardian {
  const ProfileGuardian({
    required this.id,
    required this.profileId,
    required this.userId,
    required this.role,
    this.status = GuardianStatus.accepted,
    this.displayName,
    this.invitedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String profileId;
  final String userId;
  final GuardianRole role;
  final GuardianStatus status;
  final String? displayName;
  final String? invitedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProfileGuardian copyWith({
    String? id,
    String? profileId,
    String? userId,
    GuardianRole? role,
    GuardianStatus? status,
    String? displayName,
    String? invitedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      ProfileGuardian(
        id: id ?? this.id,
        profileId: profileId ?? this.profileId,
        userId: userId ?? this.userId,
        role: role ?? this.role,
        status: status ?? this.status,
        displayName: displayName ?? this.displayName,
        invitedBy: invitedBy ?? this.invitedBy,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileGuardian &&
          _sameProfileIdentity(other) &&
          _sameProfileDetails(other);

  bool _sameProfileIdentity(ProfileGuardian other) =>
      other.id == id &&
      other.profileId == profileId &&
      other.userId == userId;

  bool _sameProfileDetails(ProfileGuardian other) =>
      other.role == role &&
      other.status == status &&
      other.displayName == displayName &&
      other.invitedBy == invitedBy &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        profileId,
        userId,
        role,
        status,
        displayName,
        invitedBy,
        createdAt,
        updatedAt,
      );

  @override
  String toString() =>
      'ProfileGuardian($profileId $userId ${role.name} ${status.name}'
      '${displayName == null ? '' : ' $displayName'})';
}

/// The accepted guardian row for [currentUserId] among [guardians], or null
/// when [currentUserId] is null, the rows haven't synced, or none match
/// (Issue #3 gap-closure plan, Unit U6). Fails open by construction: every
/// caller of this function must treat a null result as "not known to be
/// anything in particular" - never as "known to be read-only" - since a
/// local-only operator or a freshly created, not-yet-synced profile both
/// pass no rows here.
ProfileGuardian? acceptedGuardianFor(
  List<ProfileGuardian> guardians,
  String? currentUserId,
) {
  if (currentUserId == null) return null;
  for (final g in guardians) {
    if (g.userId == currentUserId && g.status == GuardianStatus.accepted) {
      return g;
    }
  }
  return null;
}
