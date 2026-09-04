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
