/**
 * Guardian roles, statuses, and the role-change ladder (issue #1255).
 *
 * A TypeScript mirror of `lib/domain/models/profile_guardian.dart`'s enums
 * and `lib/domain/sharing/sharing_service.dart`'s `canUpdateGuardianRole` /
 * `allowedNewRoles` — the client-side copy of `update_guardian_role`'s
 * server-side ladder. The server re-checks everything; this only decides
 * what the Manage-guardians UI offers, exactly as the app's copy does.
 */

/** The four roles the server's `profile_guardians_role_check` accepts. */
export type GuardianRole = 'primary_guardian' | 'co_parent' | 'caregiver' | 'viewer';

/** The three membership statuses the server's check accepts. */
export type GuardianStatus = 'pending' | 'accepted' | 'revoked';

/** The server's wire spelling for a role, or null for an unknown value. */
export function guardianRoleFromDb(value: string): GuardianRole | null {
  switch (value) {
    case 'primary_guardian':
    case 'co_parent':
    case 'caregiver':
    case 'viewer':
      return value;
    default:
      return null;
  }
}

/** Fails closed to the least-privileged role, matching the app (#540). */
export function guardianRoleFromDbOrViewer(value: string): GuardianRole {
  return guardianRoleFromDb(value) ?? 'viewer';
}

/** The server's wire spelling for a status, or null for an unknown value. */
export function guardianStatusFromDb(value: string): GuardianStatus | null {
  switch (value) {
    case 'pending':
    case 'accepted':
    case 'revoked':
      return value;
    default:
      return null;
  }
}

/** Fails closed to `revoked` (least privilege), matching the app (#540). */
export function guardianStatusFromDbOrRevoked(value: string): GuardianStatus {
  return guardianStatusFromDb(value) ?? 'revoked';
}

/** Whether `role` may log entries (day sheets, notes). */
export function roleCanLog(role: GuardianRole): boolean {
  return role !== 'viewer';
}

/** Whether `role` may edit profile details. */
export function roleCanEditProfile(role: GuardianRole): boolean {
  return role === 'primary_guardian' || role === 'co_parent';
}

/** Whether `role` may manage guardians (invite, change roles, revoke). */
export function roleCanManageGuardians(role: GuardianRole): boolean {
  return role === 'primary_guardian' || role === 'co_parent';
}

/** The catalogue message id for `role`'s human label. */
export function guardianRoleLabelId(role: GuardianRole) {
  switch (role) {
    case 'primary_guardian':
      return 'guardianRoleLabelPrimaryGuardian' as const;
    case 'co_parent':
      return 'guardianRoleLabelCoParent' as const;
    case 'caregiver':
      return 'guardianRoleLabelCaregiver' as const;
    case 'viewer':
      return 'guardianRoleLabelViewer' as const;
  }
}

export interface GuardianRowLike {
  status: GuardianStatus;
  /** The wire key (`profile_guardians.user_id`), matching the parsed rows. */
  user_id: string;
  role: GuardianRole;
}

/**
 * Whether `callerRole` may change `target`'s role to `newRole` — the client
 * mirror of `canUpdateGuardianRole` (issue #127):
 *
 * - Unknown callers (`callerRole` null), non-accepted targets, and
 *   self-changes never qualify — nobody escalates themselves.
 * - `primary_guardian` is never an assignable new role; re-applying the
 *   target's current role is not offered either.
 * - A primary guardian may change anyone else's role; a co-parent may move
 *   a caregiver/viewer to caregiver/viewer only.
 */
export function canUpdateGuardianRole(options: {
  callerRole: GuardianRole | null;
  target: GuardianRowLike;
  currentUserId: string | null;
  newRole: GuardianRole;
}): boolean {
  const { callerRole, target, currentUserId, newRole } = options;
  if (callerRole === null) return false;
  if (target.status !== 'accepted') return false;
  if (currentUserId !== null && target.user_id === currentUserId) return false;
  if (newRole === 'primary_guardian') return false;
  if (newRole === target.role) return false;
  if (callerRole === 'primary_guardian') return true;
  if (callerRole === 'co_parent') {
    const assignable: readonly GuardianRole[] = ['caregiver', 'viewer'];
    return assignable.includes(target.role) && assignable.includes(newRole);
  }
  return false;
}

/**
 * Every role the caller may move `target` to — the menu items for the role
 * control, in ladder order. Empty means no control is shown.
 */
export function allowedNewRoles(options: {
  callerRole: GuardianRole | null;
  target: GuardianRowLike;
  currentUserId: string | null;
}): GuardianRole[] {
  const candidates: GuardianRole[] = ['co_parent', 'caregiver', 'viewer'];
  return candidates.filter((newRole) => canUpdateGuardianRole({ ...options, newRole }));
}
