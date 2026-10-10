import { describe, expect, it } from 'vitest';

import { subjectInviteAvailable, type ProfileRow } from '../src/lib/schemas';

/**
 * The "her own profile" invitation is offered for a child's profile or a
 * minor's, and never for the profile someone keeps for herself: she is its
 * subject from the moment she creates it, and the server refuses a subject
 * invitation for a profile that already has one. The app's rule is
 * `Profile.subjectInviteAvailableAt` (lib/domain/models/profile.dart).
 */

const today = new Date('2026-10-05T12:00:00Z');

function profile(overrides: Partial<ProfileRow>): ProfileRow {
  return {
    id: '01ARZ3NDEKTSV4RRFFQ69G5FAV',
    user_id: '00000000-0000-4000-8000-000000000001',
    display_name: 'Riley',
    is_minor: false,
    mode: 'standard',
    relationship: null,
    birth_year: null,
    sort_order: 0,
    archived_at: null,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    deleted_at: null,
    server_version: 1,
    bbt_unit: 'celsius',
    weight_unit: 'kg',
    tracking_preferences: null,
    ...overrides,
  };
}

describe('subjectInviteAvailable', () => {
  it("is offered for a child's profile and for a minor's", () => {
    expect(subjectInviteAvailable(profile({ relationship: 'daughter' }), today)).toBe(true);
    expect(subjectInviteAvailable(profile({ relationship: 'son' }), today)).toBe(true);
    expect(subjectInviteAvailable(profile({ relationship: 'child' }), today)).toBe(true);
    expect(subjectInviteAvailable(profile({ is_minor: true }), today)).toBe(true);
    expect(subjectInviteAvailable(profile({ birth_year: 2012 }), today)).toBe(true);
  });

  it('is not offered for an adult with no child relationship', () => {
    expect(subjectInviteAvailable(profile({}), today)).toBe(false);
    expect(subjectInviteAvailable(profile({ relationship: 'partner' }), today)).toBe(false);
  });

  it('counts the calendar year locally, the way the app does (issue #1835 review item)', () => {
    // Both moments are local-calendar facts by construction, so the case is
    // real in every runner zone: 2027-01-01 00:30 local is 19 local years
    // after 2008, and 2026-12-31 23:30 local is 18. The UTC-year arithmetic
    // this replaced read one of them the other way in any non-UTC zone.
    const localNewYear = new Date(2027, 0, 1, 0, 30);
    expect(subjectInviteAvailable(profile({ birth_year: 2008 }), localNewYear)).toBe(false);

    const localOldYearEnd = new Date(2026, 11, 31, 23, 30);
    expect(subjectInviteAvailable(profile({ birth_year: 2008 }), localOldYearEnd)).toBe(true);
  });

  it('is never offered for the profile someone keeps for herself, minor or not', () => {
    expect(subjectInviteAvailable(profile({ relationship: 'self' }), today)).toBe(false);
    expect(
      subjectInviteAvailable(profile({ relationship: 'self', is_minor: true }), today),
    ).toBe(false);
    expect(
      subjectInviteAvailable(profile({ relationship: 'self', birth_year: 2012 }), today),
    ).toBe(false);
  });
});
