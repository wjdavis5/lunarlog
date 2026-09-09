/// Discoverability helpers for family sharing (Issue #126).
///
/// Pure Dart: which bucket a profile falls into for the current operator,
/// whether it reads as co-managed, and whether an outstanding-invitation
/// badge may be shown. No Flutter, no storage, no network — the widgets in
/// `lib/ui/sharing/` and the settings section own all I/O.
library;

import '../models/profile_guardian.dart';

/// Where a profile is listed for the current operator: profiles they hold
/// as primary guardian versus profiles held via membership.
enum ProfileSharingGroup {
  owned,
  sharedWithMe,
}

/// Local view of one profile's sharing state, derived from its synced
/// guardian rows. Unknown (no rows yet, signed out, local-only) reads as
/// owned with zero co-managers — fail open, never label someone's own
/// profile as shared (the #13 null-vs-empty discipline).
class SharingProfileInfo {
  const SharingProfileInfo({
    required this.myRole,
    required this.acceptedCount,
  });

  const SharingProfileInfo.unknown() : myRole = null, acceptedCount = 0;

  /// The operator's own accepted role, or null when unknown.
  final GuardianRole? myRole;

  /// How many accepted guardians the profile has locally.
  final int acceptedCount;

  ProfileSharingGroup get group {
    if (myRole == null || myRole == GuardianRole.primaryGuardian) {
      return ProfileSharingGroup.owned;
    }
    return ProfileSharingGroup.sharedWithMe;
  }

  /// More than one accepted guardian: a second guardian exists, so the
  /// profile reads as co-managed without opening any menu.
  bool get isCoManaged => acceptedCount > 1;

  /// Builds the info from synced [rows] for [currentUserId].
  static SharingProfileInfo fromGuardians(
    List<ProfileGuardian> rows,
    String? currentUserId,
  ) {
    final accepted = [
      for (final row in rows)
        if (row.status == GuardianStatus.accepted) row,
    ];
    return SharingProfileInfo(
      myRole: acceptedGuardianFor(accepted, currentUserId)?.role,
      acceptedCount: accepted.length,
    );
  }

  /// Whether an outstanding-invitation badge may be fetched for a caller
  /// with [role]. Managers (and the not-yet-known caller, matching Manage
  /// Guardians' pre-sync discipline) may see it; a viewer or caregiver
  /// sees shared state but no invite affordance, so no badge is fetched
  /// for them at all.
  static bool canShowPendingBadge(GuardianRole? role) =>
      role == null || role.canManageGuardians;

  /// The role line for a profile row: shared profiles name the group and
  /// the role; owned profiles name the role only when known, otherwise
  /// null so the caller falls back to its own subtitle (e.g. created
  /// date) instead of guessing.
  static String? roleSubtitle(SharingProfileInfo info) {
    final role = info.myRole;
    if (info.group == ProfileSharingGroup.sharedWithMe) {
      return 'Shared with me · ${role!.label}';
    }
    return role?.label;
  }
}
