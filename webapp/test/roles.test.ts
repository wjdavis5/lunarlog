import { describe, expect, it } from 'vitest';

import {
  allowedNewRoles,
  canUpdateGuardianRole,
  guardianRoleFromDb,
  guardianRoleFromDbOrViewer,
  guardianStatusFromDb,
  guardianStatusFromDbOrRevoked,
  roleCanEditProfile,
  roleCanLog,
  roleCanManageGuardians,
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
