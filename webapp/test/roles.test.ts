import { describe, expect, it } from 'vitest';

import {
  allowedNewRoles,
  canCancelInvitation,
  canRevokeGuardian,
  canUpdateGuardianRole,
  guardianRoleFromDb,
  guardianRoleFromDbOrViewer,
  guardianStatusFromDb,
  guardianStatusFromDbOrRevoked,
  roleCanEditProfile,
  roleCanInviteCoParent,
  roleCanLog,
  roleCanManageGuardians,
  roleCanTransferOwnership,
  type GuardianRowLike,
} from '../src/lib/roles';

function target(role: string, status = 'accepted', user_id = 'target-user'): GuardianRowLike {
  return {
    role: guardianRoleFromDbOrViewer(role),
    status: guardianStatusFromDbOrRevoked(status),
    user_id,
  };
}

describe('guardian role/status decoding (issue #540 posture)', () => {
  it('decodes every server value', () => {
    expect(guardianRoleFromDb('primary_guardian')).toBe('primary_guardian');
    expect(guardianRoleFromDb('co_parent')).toBe('co_parent');
    expect(guardianRoleFromDb('caregiver')).toBe('caregiver');
    expect(guardianRoleFromDb('viewer')).toBe('viewer');
    expect(guardianStatusFromDb('pending')).toBe('pending');
    expect(guardianStatusFromDb('accepted')).toBe('accepted');
    expect(guardianStatusFromDb('revoked')).toBe('revoked');
  });

  it('fails closed on unknown values', () => {
    expect(guardianRoleFromDb('owner')).toBeNull();
    expect(guardianRoleFromDbOrViewer('owner')).toBe('viewer');
    expect(guardianStatusFromDbOrRevoked('banned')).toBe('revoked');
  });
});

describe('capability flags', () => {
  it('mirror the app role ladder', () => {
    expect(roleCanLog('viewer')).toBe(false);
    expect(roleCanLog('caregiver')).toBe(true);
    expect(roleCanEditProfile('co_parent')).toBe(true);
    expect(roleCanEditProfile('caregiver')).toBe(false);
    expect(roleCanManageGuardians('primary_guardian')).toBe(true);
    expect(roleCanManageGuardians('co_parent')).toBe(true);
    expect(roleCanManageGuardians('viewer')).toBe(false);
  });
});

describe('canUpdateGuardianRole (the client mirror of the server ladder)', () => {
  it('a primary guardian may change anyone else to any non-primary role', () => {
    expect(
      canUpdateGuardianRole({
        callerRole: 'primary_guardian',
        target: target('viewer'),
        currentUserId: 'caller-user',
        newRole: 'caregiver',
      }),
    ).toBe(true);
    expect(
      canUpdateGuardianRole({
        callerRole: 'primary_guardian',
        target: target('caregiver'),
        currentUserId: 'caller-user',
        newRole: 'co_parent',
      }),
    ).toBe(true);
  });

  it('nobody changes their own row', () => {
    expect(
      canUpdateGuardianRole({
        callerRole: 'primary_guardian',
        target: target('viewer', 'accepted', 'caller-user'),
        currentUserId: 'caller-user',
        newRole: 'caregiver',
      }),
    ).toBe(false);
  });

  it('primary_guardian is never an assignable new role', () => {
    expect(
      canUpdateGuardianRole({
        callerRole: 'primary_guardian',
        target: target('viewer'),
        currentUserId: 'caller-user',
        newRole: 'primary_guardian',
      }),
    ).toBe(false);
  });

  it('re-applying the current role is not offered', () => {
    expect(
      canUpdateGuardianRole({
        callerRole: 'primary_guardian',
        target: target('viewer'),
        currentUserId: 'caller-user',
        newRole: 'viewer',
      }),
    ).toBe(false);
  });

  it('a co-parent may move caregiver/viewer to caregiver/viewer only', () => {
    expect(
      canUpdateGuardianRole({
        callerRole: 'co_parent',
        target: target('viewer'),
        currentUserId: 'caller-user',
        newRole: 'caregiver',
      }),
    ).toBe(true);
    expect(
      canUpdateGuardianRole({
        callerRole: 'co_parent',
        target: target('co_parent'),
        currentUserId: 'caller-user',
        newRole: 'caregiver',
      }),
    ).toBe(false);
    expect(
      canUpdateGuardianRole({
        callerRole: 'co_parent',
        target: target('primary_guardian'),
        currentUserId: 'caller-user',
        newRole: 'viewer',
      }),
    ).toBe(false);
    expect(
      canUpdateGuardianRole({
        callerRole: 'co_parent',
        target: target('caregiver'),
        currentUserId: 'caller-user',
        newRole: 'co_parent',
      }),
    ).toBe(false);
  });

  it('caregivers, viewers, and unknown callers change nothing', () => {
    for (const callerRole of ['caregiver', 'viewer', null] as const) {
      expect(
        canUpdateGuardianRole({
          callerRole,
          target: target('viewer'),
          currentUserId: 'caller-user',
          newRole: 'caregiver',
        }),
      ).toBe(false);
    }
  });

  it('a non-accepted target row never qualifies', () => {
    expect(
      canUpdateGuardianRole({
        callerRole: 'primary_guardian',
        target: target('viewer', 'pending'),
        currentUserId: 'caller-user',
        newRole: 'caregiver',
      }),
    ).toBe(false);
  });
});

describe('allowedNewRoles (the role control menu, ladder order)', () => {
  it('lists co_parent, caregiver, viewer for a primary guardian', () => {
    expect(
      allowedNewRoles({
        callerRole: 'primary_guardian',
        target: target('viewer'),
        currentUserId: 'caller-user',
      }),
    ).toEqual(['co_parent', 'caregiver']);
  });

  it('offers nothing when the caller may not manage', () => {
    expect(
      allowedNewRoles({
        callerRole: 'caregiver',
        target: target('viewer'),
        currentUserId: 'caller-user',
      }),
    ).toEqual([]);
  });
});

describe('roleCanTransferOwnership / roleCanInviteCoParent (issue #1285)', () => {
  it('both are primary-guardian-only', () => {
    expect(roleCanTransferOwnership('primary_guardian')).toBe(true);
    expect(roleCanTransferOwnership('co_parent')).toBe(false);
    expect(roleCanTransferOwnership('caregiver')).toBe(false);
    expect(roleCanTransferOwnership('viewer')).toBe(false);
    expect(roleCanTransferOwnership(null)).toBe(false);
    expect(roleCanInviteCoParent('primary_guardian')).toBe(true);
    expect(roleCanInviteCoParent('co_parent')).toBe(false);
    expect(roleCanInviteCoParent('caregiver')).toBe(false);
    expect(roleCanInviteCoParent('viewer')).toBe(false);
    expect(roleCanInviteCoParent(null)).toBe(false);
  });
});

describe('canRevokeGuardian (the client mirror of revoke_guardian, issue #1285)', () => {
  it('an unknown caller never qualifies', () => {
    expect(
      canRevokeGuardian({
        callerRole: null,
        target: target('caregiver'),
        currentUserId: 'caller-user',
        acceptedPrimaryGuardians: 2,
      }),
    ).toBe(false);
  });

  it('a non-primary guardian may always leave', () => {
    for (const callerRole of ['co_parent', 'caregiver', 'viewer'] as const) {
      expect(
        canRevokeGuardian({
          callerRole,
          target: target(callerRole, 'accepted', 'caller-user'),
          currentUserId: 'caller-user',
          acceptedPrimaryGuardians: 1,
        }),
      ).toBe(true);
    }
  });

  it('the sole accepted primary guardian may not leave', () => {
    expect(
      canRevokeGuardian({
        callerRole: 'primary_guardian',
        target: target('primary_guardian', 'accepted', 'caller-user'),
        currentUserId: 'caller-user',
        acceptedPrimaryGuardians: 1,
      }),
    ).toBe(false);
  });

  it('a primary guardian may leave when another accepted primary remains', () => {
    expect(
      canRevokeGuardian({
        callerRole: 'primary_guardian',
        target: target('primary_guardian', 'accepted', 'caller-user'),
        currentUserId: 'caller-user',
        acceptedPrimaryGuardians: 2,
      }),
    ).toBe(true);
  });

  it('a primary guardian may revoke anyone else', () => {
    for (const role of ['primary_guardian', 'co_parent', 'caregiver', 'viewer'] as const) {
      expect(
        canRevokeGuardian({
          callerRole: 'primary_guardian',
          target: target(role),
          currentUserId: 'caller-user',
          acceptedPrimaryGuardians: 1,
        }),
      ).toBe(true);
    }
  });

  it('a co-parent may revoke caregivers and viewers only', () => {
    expect(
      canRevokeGuardian({
        callerRole: 'co_parent',
        target: target('caregiver'),
        currentUserId: 'caller-user',
        acceptedPrimaryGuardians: 1,
      }),
    ).toBe(true);
    expect(
      canRevokeGuardian({
        callerRole: 'co_parent',
        target: target('viewer'),
        currentUserId: 'caller-user',
        acceptedPrimaryGuardians: 1,
      }),
    ).toBe(true);
    expect(
      canRevokeGuardian({
        callerRole: 'co_parent',
        target: target('co_parent'),
        currentUserId: 'caller-user',
        acceptedPrimaryGuardians: 1,
      }),
    ).toBe(false);
    expect(
      canRevokeGuardian({
        callerRole: 'co_parent',
        target: target('primary_guardian'),
        currentUserId: 'caller-user',
        acceptedPrimaryGuardians: 1,
      }),
    ).toBe(false);
  });

  it('caregivers and viewers revoke nobody else', () => {
    for (const callerRole of ['caregiver', 'viewer'] as const) {
      expect(
        canRevokeGuardian({
          callerRole,
          target: target('viewer'),
          currentUserId: 'caller-user',
          acceptedPrimaryGuardians: 1,
        }),
      ).toBe(false);
    }
  });
});

describe('canCancelInvitation (the client mirror of revoke_guardian_invitation, issue #1285)', () => {
  it('a primary guardian may cancel any invitation', () => {
    for (const inviteRole of ['co_parent', 'caregiver', 'viewer'] as const) {
      expect(
        canCancelInvitation({
          callerRole: 'primary_guardian',
          inviteRole,
          invitedBy: 'someone-else',
          currentUserId: 'caller-user',
        }),
      ).toBe(true);
    }
  });

  it('a co-parent may cancel caregiver and viewer invitations', () => {
    for (const inviteRole of ['caregiver', 'viewer'] as const) {
      expect(
        canCancelInvitation({
          callerRole: 'co_parent',
          inviteRole,
          invitedBy: 'someone-else',
          currentUserId: 'caller-user',
        }),
      ).toBe(true);
    }
  });

  it('a co-parent may not cancel a co_parent invitation someone else created', () => {
    expect(
      canCancelInvitation({
        callerRole: 'co_parent',
        inviteRole: 'co_parent',
        invitedBy: 'someone-else',
        currentUserId: 'caller-user',
      }),
    ).toBe(false);
  });

  it("a co-parent may cancel a co_parent invitation they created (the server's invited_by test)", () => {
    expect(
      canCancelInvitation({
        callerRole: 'co_parent',
        inviteRole: 'co_parent',
        invitedBy: 'caller-user',
        currentUserId: 'caller-user',
      }),
    ).toBe(true);
  });

  it('caregivers, viewers, and unknown callers cancel nothing', () => {
    for (const callerRole of ['caregiver', 'viewer', null] as const) {
      expect(
        canCancelInvitation({
          callerRole,
          inviteRole: 'viewer',
          invitedBy: 'someone-else',
          currentUserId: 'caller-user',
        }),
      ).toBe(false);
    }
  });
});
