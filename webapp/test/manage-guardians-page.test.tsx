import { QueryClientProvider } from '@tanstack/react-query';
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { QueryClient } from '@tanstack/react-query';
import { SYNCED_DATA_QUERY_KEY } from '../src/lib/queries';
import { SharingError } from '../src/lib/sharing';
import { ManageGuardiansPage } from '../src/pages/ManageGuardiansPage';

/**
 * Page tests for the web Manage-guardians surface (issue #1255). The
 * supabase and sharing modules are partially mocked — the RPC wrappers
 * become spies, everything else (the role ladder, the Zod boundaries, the
 * catalogue) runs for real.
 */

const ULID = '01ARZ3NDEKTSV4RRFFQ69G5FAV';
// Sharing-table row ids are uuid (gen_random_uuid, 20260904010000 /
// 20260906170000), unlike the profile's client-generated ULID — the
// fixtures keep the two apart (issue #1284).
const GUARDIAN_ROW_ID = '2f2f2f2f-2f2f-4f2f-8f2f-2f2f2f2f2f2f';
const INVITE_ROW_ID = '3f3f3f3f-3f3f-4f3f-8f3f-3f3f3f3f3f3f';
const ME = '0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f';
const OTHER = '1f1f1f1f-1f1f-4f1f-8f1f-1f1f1f1f1f1f';

const profileRow = {
  id: ULID,
  display_name: 'Maya',
  is_minor: true,
  mode: 'cycle',
  relationship: 'daughter',
  birth_year: 2013,
  sort_order: 0,
  deleted_at: null,
  archived_at: null,
  server_version: 1,
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
};

/** The fake client answers the session gate (`useHasSyncSession`, issue
 * #1252) — `onAuthStateChange` included, or the effect throws; the synced
 * profile list itself is seeded into the query cache by `renderPage`
 * (`useLiveProfiles` reads the ['synced-data'] cache, not a table read);
 * sharing-table reads and every RPC come from the sharing-module spies. */
const fakeClient = {
  auth: {
    currentUser: { id: ME },
    getSession: async () => ({ data: { session: { user: { id: ME } } } }),
    onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }),
  },
};

vi.mock('../src/lib/supabase', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  getSupabaseClient: () => fakeClient,
}));

// The synced-data query's queryFn runs the domain cache refresh (issue
// #1252) — serve the seeded profiles through that seam so the query
// resolves instead of rejecting against the fake client.
const domainMocks = vi.hoisted(() => ({ refresh: vi.fn() }));
vi.mock('../src/lib/domain', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  getSyncedDataCache: () => ({ refresh: domainMocks.refresh }),
}));

// Issue #1282: the leave flow's from-zero re-pull runs through this one
// queries-module helper — mocked here so the page tests pin *that* the
// mutation triggers it (the helper's own behavior is unit-tested in
// domain.test.ts through SyncedDataCache.repullAll).
const queriesMocks = vi.hoisted(() => ({
  repullMembershipData: vi.fn(() => Promise.resolve()),
}));

vi.mock('../src/lib/queries', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  repullMembershipData: queriesMocks.repullMembershipData,
}));

const sharingMocks = vi.hoisted(() => ({
  fetchGuardians: vi.fn(),
  fetchPendingInvites: vi.fn(),
  fetchActiveTransfer: vi.fn(),
  currentUserId: vi.fn(() => '0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f'),
  createGuardianInvitation: vi.fn(),
  createOwnershipTransfer: vi.fn(),
  cancelOwnershipTransfer: vi.fn(),
  revokeGuardian: vi.fn(),
  revokeGuardianInvitation: vi.fn(),
  updateGuardianRole: vi.fn(),
}));

vi.mock('../src/lib/sharing', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  ...sharingMocks,
}));

/** Matches an element whose full normalized text equals `expected` — the
 * row copy composes several message fragments into one <p>. */
function exactText(expected: string) {
  return (_content: string, element: Element | null) => element?.textContent === expected;
}

function guardianRow(overrides: Record<string, unknown> = {}) {
  return {
    id: GUARDIAN_ROW_ID,
    profile_id: ULID,
    user_id: ME,
    role: 'primary_guardian',
    status: 'accepted',
    display_name: 'Mom',
    invited_by: null,
    is_subject: false,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    ...overrides,
  };
}

function pendingRow(overrides: Record<string, unknown> = {}) {
  return {
    id: INVITE_ROW_ID,
    profile_id: ULID,
    role: 'viewer',
    // Read since issue #1285 for the cancel ladder; the fixture's default
    // creator is the signed-in primary guardian.
    invited_by: ME,
    recipient_label: 'Nurse',
    created_at: '2026-09-01T00:00:00Z',
    expires_at: '2026-09-03T00:00:00Z',
    is_subject: false,
    ...overrides,
  };
}

function renderPage() {
  // Retry-free: a rejected query settles on its first failure, so failure-
  // copy assertions do not wait out TanStack's exponential retry delay.
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  // Seed the synced-data cache (issue #1252's `useLiveProfiles` reads
  // `['synced-data']`, never a table) instead of the retired profiles read.
  domainMocks.refresh.mockResolvedValue({ profiles: [profileRow] });
  queryClient.setQueryData(['synced-data'], { profiles: [profileRow] } as never);
  const view = render(
    <AppIntlProvider>
      <QueryClientProvider client={queryClient}>
        <MemoryRouter initialEntries={[`/profile/${ULID}/guardians`]}>
          <Routes>
            <Route path="/" element={<div>home</div>} />
            <Route path="/profile/:profileId/guardians" element={<ManageGuardiansPage />} />
          </Routes>
        </MemoryRouter>
      </QueryClientProvider>
    </AppIntlProvider>,
  );
  return { queryClient, view };
}

function defaultMocks() {
  sharingMocks.fetchGuardians.mockResolvedValue([
    guardianRow(),
    guardianRow({
      id: INVITE_ROW_ID,
      user_id: OTHER,
      role: 'caregiver',
      display_name: 'Grandma',
    }),
  ]);
  sharingMocks.fetchPendingInvites.mockResolvedValue([]);
  sharingMocks.fetchActiveTransfer.mockResolvedValue(null);
}

beforeEach(() => {
  defaultMocks();
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe('ManageGuardiansPage (issue #1255)', () => {
  it("leads back to this profile's home", () => {
    renderPage();
    expect(screen.getByRole('link', { name: messages['webDayBackToToday'] })).toHaveAttribute(
      'href',
      `/?profile=${ULID}`,
    );
  });

  it('renders the screen title and both guardian rows with role labels', async () => {
    renderPage();
    expect(
      await screen.findByRole('heading', {
        name: (messages['sharingManageGuardiansScreenTitle'] ?? '').replace(
          '{profileName}',
          'Maya',
        ),
      }),
    ).toBeInTheDocument();
    expect(
      await screen.findByText(
        exactText(`Mom ${messages['sharingManageGuardiansYouSuffix'] ?? ''}`.trimEnd()),
      ),
    ).toBeInTheDocument();
    expect(await screen.findByText('Grandma')).toBeInTheDocument();
    expect(
      screen.getByText((messages['guardianRoleLabelCaregiver'] ?? '') as string),
    ).toBeInTheDocument();
  });

  it('shows the subject badge on a subject membership', async () => {
    sharingMocks.fetchGuardians.mockResolvedValue([guardianRow({ is_subject: true })]);
    renderPage();
    expect(
      await screen.findByText(
        exactText(
          `${messages['guardianRoleLabelPrimaryGuardian']} · ${messages['manageGuardiansSubjectBadge']}`,
        ),
      ),
    ).toBeInTheDocument();
  });

  it('offers only ladder-legal roles in the change-role control', async () => {
    renderPage();
    const selects = await screen.findAllByLabelText(
      messages['manageGuardiansChangeRoleTooltip'] ?? '',
    );
    // The caregiver row's select (the primary's own row has none).
    const caregiverSelect = selects[1] ?? selects[0];
    const options = Array.from(caregiverSelect.querySelectorAll('option')).map(
      (option) => option.textContent,
    );
    expect(options).toContain(messages['guardianRoleLabelCoParent']);
    expect(options).toContain(messages['guardianRoleLabelViewer']);
    expect(options).not.toContain(messages['guardianRoleLabelPrimaryGuardian']);
    fireEvent.change(caregiverSelect, { target: { value: 'co_parent' } });
    await waitFor(() => {
      expect(sharingMocks.updateGuardianRole).toHaveBeenCalledWith(
        fakeClient,
        ULID,
        OTHER,
        'co_parent',
      );
    });
  });

  it('creates an invitation and shows the share link panel', async () => {
    sharingMocks.createGuardianInvitation.mockResolvedValue({
      invitation: {
        id: INVITE_ROW_ID,
        profile_id: ULID,
        role: 'caregiver',
        expires_at: '2026-10-02T00:00:00Z',
      },
      rawToken: 'T0KEN123',
    });
    renderPage();
    fireEvent.click(await screen.findByText(messages['sharingInviteGuardianCreateLink'] ?? ''));
    expect(
      await screen.findByText(messages['sharingInviteGuardianCreatedTitle'] ?? ''),
    ).toBeInTheDocument();
    const link = await screen.findByText(
      (content, element) =>
        element?.className === 'link-display' && content.includes('/invite?code=T0KEN123'),
    );
    expect(link.textContent).toContain(`profile=${ULID}`);
  });

  it('renders pending invitations with expiry copy and cancels one', async () => {
    sharingMocks.fetchPendingInvites.mockResolvedValue([
      pendingRow({ expires_at: '2020-01-01T00:00:00Z', recipient_label: null }),
    ]);
    sharingMocks.revokeGuardianInvitation.mockResolvedValue('revoked');
    renderPage();
    expect(
      await screen.findByText(
        exactText(
          `${messages['guardianRoleLabelViewer']} · ${messages['sharingManageGuardiansExpiryExpired']}`,
        ),
      ),
    ).toBeInTheDocument();
    expect(
      screen.getByText(messages['manageGuardiansWaitingForRedemption'] ?? ''),
    ).toBeInTheDocument();

    fireEvent.click(screen.getByText(messages['sharingManageGuardiansCancel'] ?? ''));
    fireEvent.click(screen.getByText(messages['sharingManageGuardiansCancelInvitation'] ?? ''));
    await waitFor(() => {
      expect(sharingMocks.revokeGuardianInvitation).toHaveBeenCalledWith(
        fakeClient,
        INVITE_ROW_ID,
      );
    });
    expect(
      await screen.findByText(messages['inviteCancellationRevoked'] ?? ''),
    ).toBeInTheDocument();
  });

  it('an armed transfer replaces the arm form with the pending card', async () => {
    sharingMocks.fetchActiveTransfer.mockResolvedValue({
      id: INVITE_ROW_ID,
      profile_id: ULID,
      parent_post_transfer_role: 'co_parent',
      recipient_label: null,
      expires_at: '2026-10-03T00:00:00Z',
    });
    renderPage();
    expect(
      await screen.findByText(messages['sharingTransferOwnershipPendingTitle'] ?? ''),
    ).toBeInTheDocument();
    expect(
      screen.getByText(messages['sharingTransferOwnershipCancelPending'] ?? ''),
    ).toBeInTheDocument();
    expect(
      screen.queryByText(messages['sharingTransferOwnershipAction'] ?? ''),
    ).not.toBeInTheDocument();
  });

  it('cancelling the live transfer calls the RPC', async () => {
    sharingMocks.fetchActiveTransfer.mockResolvedValue({
      id: INVITE_ROW_ID,
      profile_id: ULID,
      parent_post_transfer_role: 'viewer',
      recipient_label: null,
      expires_at: '2026-10-03T00:00:00Z',
    });
    sharingMocks.cancelOwnershipTransfer.mockResolvedValue(undefined);
    // The post-cancel readback sees the transfer gone (the invalidate
    // refetch), so the form branch — and its cancelled copy — renders.
    sharingMocks.fetchActiveTransfer
      .mockResolvedValueOnce({
        id: INVITE_ROW_ID,
        profile_id: ULID,
        parent_post_transfer_role: 'viewer',
        recipient_label: null,
        expires_at: '2026-10-03T00:00:00Z',
      })
      .mockResolvedValue(null);
    renderPage();
    fireEvent.click(
      await screen.findByText(messages['sharingTransferOwnershipCancelPending'] ?? ''),
    );
    await waitFor(() => {
      expect(sharingMocks.cancelOwnershipTransfer).toHaveBeenCalledWith(
        fakeClient,
        INVITE_ROW_ID,
      );
    });
    expect(
      await screen.findByText(messages['sharingTransferOwnershipCancelled'] ?? ''),
    ).toBeInTheDocument();
  });

  it('the transfer link survives the post-arm active-transfer readback (issue #1286)', async () => {
    const transferId = '4f4f4f4f-4f4f-4f4f-8f4f-4f4f4f4f4f4f';
    const liveRow = {
      id: transferId,
      profile_id: ULID,
      parent_post_transfer_role: 'co_parent',
      recipient_label: null,
      expires_at: '2026-10-03T00:00:00Z',
    };
    // Pre-arm readback: nothing live yet. The invalidate inside
    // `arm.onSuccess` then refetches, and that readback resolves with the
    // just-created transfer as the live row.
    sharingMocks.fetchActiveTransfer.mockResolvedValueOnce(null).mockResolvedValue(liveRow);
    sharingMocks.createOwnershipTransfer.mockResolvedValue({
      transfer: { id: transferId, expires_at: '2026-10-03T00:00:00Z' },
      rawToken: 'T0KEN123',
    });
    const { queryClient } = renderPage();
    fireEvent.click(await screen.findByText(messages['sharingTransferOwnershipAction'] ?? ''));
    expect(
      await screen.findByText(messages['sharingTransferOwnershipReadyTitle'] ?? ''),
    ).toBeInTheDocument();

    // Wait out the post-arm readback: the query cache must already hold the
    // live row, or the assertions below would not prove anything.
    await waitFor(() => {
      expect(queryClient.getQueryData(['activeTransfer', ULID])).toEqual(liveRow);
    });
    await act(async () => {}); // flush the cache-to-DOM propagation

    // The link panel is still up once the readback has landed — the server
    // stores only the token hash, so the pending card swallowing the panel
    // here would strand the one-time token (issue #1286).
    expect(
      screen.getByText(messages['sharingTransferOwnershipReadyTitle'] ?? ''),
    ).toBeInTheDocument();
    const link = screen.getByText(
      (content, element) =>
        element?.className === 'link-display' && content.includes('/invite?code=T0KEN123'),
    );
    expect(link.textContent).toContain('kind=claim');
    // The invite panel shares the "Copy Link" string, but it never entered
    // its created state in this test — exactly one copy button is up.
    expect(
      screen.getAllByText(messages['sharingTransferOwnershipCopyLink'] ?? ''),
    ).toHaveLength(1);
    expect(
      screen.getByText(messages['sharingTransferOwnershipCancelTransfer'] ?? ''),
    ).toBeInTheDocument();
    expect(
      screen.queryByText(messages['sharingTransferOwnershipPendingTitle'] ?? ''),
    ).not.toBeInTheDocument();
  });

  it('a not-signed-in failure renders the sign-in copy (issue #885 posture)', async () => {
    sharingMocks.fetchGuardians.mockRejectedValue(new SharingError('notSignedIn'));
    renderPage();
    expect(
      await screen.findByText(messages['sharingFailureNotSignedIn'] ?? ''),
    ).toBeInTheDocument();
  });

  it('a revoked membership row is never listed', async () => {
    sharingMocks.fetchGuardians.mockResolvedValue([guardianRow({ status: 'revoked' })]);
    renderPage();
    await screen.findByRole('heading', {
      name: (messages['sharingManageGuardiansScreenTitle'] ?? '').replace(
        '{profileName}',
        'Maya',
      ),
    });
    expect(screen.queryByText('Mom')).not.toBeInTheDocument();
  });

  it('leaving re-pulls membership data and lands home (issue #1282)', async () => {
    sharingMocks.fetchGuardians.mockResolvedValue([
      guardianRow({ role: 'co_parent', display_name: 'Dad' }),
      guardianRow({
        id: '4f4f4f4f-4f4f-4f4f-8f4f-4f4f4f4f4f4f',
        user_id: OTHER,
        role: 'primary_guardian',
        display_name: 'Mom',
      }),
    ]);
    sharingMocks.revokeGuardian.mockResolvedValue(undefined);
    renderPage();
    fireEvent.click(
      await screen.findByText(messages['manageGuardiansLeaveProfileTooltip'] ?? ''),
    );
    fireEvent.click(screen.getByText(messages['manageGuardiansLeaveProfileConfirm'] ?? ''));
    await waitFor(() => {
      expect(sharingMocks.revokeGuardian).toHaveBeenCalledWith(fakeClient, ULID, ME);
    });
    // sync_pull stops returning the left profile with no tombstone (issue
    // #1282) — the from-zero re-pull is what drops it, and the navigation
    // waits for it.
    await waitFor(() => {
      expect(queriesMocks.repullMembershipData).toHaveBeenCalledTimes(1);
    });
    await screen.findByText('home');
  });

  it('removing another guardian refreshes the guardians list only — no membership re-pull', async () => {
    sharingMocks.fetchGuardians.mockResolvedValue([
      guardianRow(),
      guardianRow({
        id: '4f4f4f4f-4f4f-4f4f-8f4f-4f4f4f4f4f4f',
        user_id: OTHER,
        role: 'co_parent',
        display_name: 'Uncle',
      }),
    ]);
    sharingMocks.revokeGuardian.mockResolvedValue(undefined);
    renderPage();
    fireEvent.click(
      await screen.findByText(messages['manageGuardiansRemoveCaregiverTooltip'] ?? ''),
    );
    fireEvent.click(screen.getByText(messages['sharingManageGuardiansRemove'] ?? ''));
    await waitFor(() => {
      expect(sharingMocks.revokeGuardian).toHaveBeenCalledWith(fakeClient, ULID, OTHER);
    });
    // The revoked account is the one whose view must converge; this
    // operator's own membership set is unchanged (issue #1282).
    expect(queriesMocks.repullMembershipData).not.toHaveBeenCalled();
  });

  it('arming a transfer invalidates the synced-data query (the dead profiles key is gone, issue #1282)', async () => {
    sharingMocks.createOwnershipTransfer.mockResolvedValue({
      transfer: { id: INVITE_ROW_ID, expires_at: '2026-10-03T00:00:00Z' },
      rawToken: 'T0KEN123',
    });
    const { queryClient } = renderPage();
    await screen.findByText(messages['sharingTransferOwnershipAction'] ?? '');
    expect(queryClient.getQueryState(SYNCED_DATA_QUERY_KEY)?.isInvalidated ?? false).toBe(
      false,
    );
    fireEvent.click(screen.getByText(messages['sharingTransferOwnershipAction'] ?? ''));
    // The invalidation lands on the one key any screen reads — the
    // mounted-but-idle synced-data query is marked stale and refetches the
    // moment a session holds (the profiles key this used to touch is read
    // by no query at all).
    await waitFor(() => {
      expect(queryClient.getQueryState(SYNCED_DATA_QUERY_KEY)?.isInvalidated).toBe(true);
    });
  });
});

/**
 * The role-laddered controls (issue #1285): the server refuses a co-parent's
 * ownership transfer, co_parent invitation, co_parent/primary removals, and
 * another co-parent's invite cancellation — and a sole primary guardian's
 * self-leave — so the page never offers them.
 */
describe('ManageGuardiansPage role ladder (issue #1285)', () => {
  it('a co-parent sees no transfer section but keeps the invite form', async () => {
    sharingMocks.fetchGuardians.mockResolvedValue([
      guardianRow({ role: 'co_parent', display_name: 'Dad' }),
      guardianRow({
        id: '4f4f4f4f-4f4f-4f4f-8f4f-4f4f4f4f4f4f',
        user_id: OTHER,
        role: 'primary_guardian',
        display_name: 'Mom',
      }),
    ]);
    renderPage();
    expect(await screen.findByText('Mom')).toBeInTheDocument();
    // canManage still holds for a co-parent: the invite form is on offer…
    expect(
      screen.getByText(messages['sharingInviteGuardianCreateLink'] ?? ''),
    ).toBeInTheDocument();
    // …but the transfer arm form is not — `create_ownership_transfer`
    // answers a co-parent with 42501.
    expect(
      screen.queryByText(messages['sharingTransferOwnershipAction'] ?? ''),
    ).not.toBeInTheDocument();
  });

  it("a co-parent's invite form neither defaults to nor offers the co_parent preset", async () => {
    sharingMocks.fetchGuardians.mockResolvedValue([
      guardianRow({ role: 'co_parent', display_name: 'Dad' }),
      guardianRow({
        id: '4f4f4f4f-4f4f-4f4f-8f4f-4f4f4f4f4f4f',
        user_id: OTHER,
        role: 'primary_guardian',
        display_name: 'Mom',
      }),
    ]);
    sharingMocks.createGuardianInvitation.mockResolvedValue({
      invitation: {
        id: INVITE_ROW_ID,
        profile_id: ULID,
        role: 'caregiver',
        expires_at: '2026-10-02T00:00:00Z',
      },
      rawToken: 'T0KEN123',
    });
    renderPage();
    const inviteSelect = (await screen.findByLabelText(
      messages['sharingInviteGuardianRoleLabel'] ?? '',
    )) as HTMLSelectElement;
    const options = Array.from(inviteSelect.querySelectorAll('option')).map(
      (option) => option.textContent,
    );
    expect(options).not.toContain(messages['sharingInviteGuardianPresetCoParent']);
    expect(options).toContain(messages['sharingInviteGuardianPresetCaregiver']);
    // The default falls back to caregiver — the submit the server accepts.
    expect(inviteSelect.value).toBe('caregiver');
    fireEvent.click(screen.getByText(messages['sharingInviteGuardianCreateLink'] ?? ''));
    await waitFor(() => {
      expect(sharingMocks.createGuardianInvitation).toHaveBeenCalledWith(
        fakeClient,
        expect.objectContaining({ role: 'caregiver', subject: false }),
      );
    });
  });

  it("a primary guardian's invite form still offers the co_parent preset by default", async () => {
    renderPage();
    const inviteSelect = (await screen.findByLabelText(
      messages['sharingInviteGuardianRoleLabel'] ?? '',
    )) as HTMLSelectElement;
    const options = Array.from(inviteSelect.querySelectorAll('option')).map(
      (option) => option.textContent,
    );
    expect(options).toContain(messages['sharingInviteGuardianPresetCoParent']);
    expect(inviteSelect.value).toBe('co_parent');
  });

  it('a co-parent may remove caregivers and viewers, never co-parents or primaries', async () => {
    sharingMocks.fetchGuardians.mockResolvedValue([
      guardianRow({ role: 'co_parent', display_name: 'Dad' }),
      guardianRow({
        id: '4f4f4f4f-4f4f-4f4f-8f4f-4f4f4f4f4f4f',
        user_id: OTHER,
        role: 'primary_guardian',
        display_name: 'Mom',
      }),
      guardianRow({
        id: '5f5f5f5f-5f5f-5f5f-8f5f-5f5f5f5f5f5f',
        user_id: '6f6f6f6f-6f6f-4f6f-8f6f-6f6f6f6f6f6f',
        role: 'co_parent',
        display_name: 'Uncle',
      }),
      guardianRow({
        id: '7f7f7f7f-7f7f-7f7f-8f7f-7f7f7f7f7f7f',
        user_id: '8f8f8f8f-8f8f-4f8f-8f8f-8f8f8f8f8f8f',
        role: 'caregiver',
        display_name: 'Grandma',
      }),
    ]);
    renderPage();
    expect(await screen.findByText('Grandma')).toBeInTheDocument();
    // Exactly one Remove control: the caregiver's. The server refuses a
    // co-parent revoking a co_parent or primary_guardian with 42501.
    expect(
      screen.getAllByText(messages['manageGuardiansRemoveCaregiverTooltip'] ?? ''),
    ).toHaveLength(1);
  });

  it('a primary guardian may still remove a co-parent row', async () => {
    sharingMocks.fetchGuardians.mockResolvedValue([
      guardianRow(),
      guardianRow({
        id: '4f4f4f4f-4f4f-4f4f-8f4f-4f4f4f4f4f4f',
        user_id: OTHER,
        role: 'co_parent',
        display_name: 'Uncle',
      }),
    ]);
    renderPage();
    expect(await screen.findByText('Uncle')).toBeInTheDocument();
    expect(
      screen.getAllByText(messages['manageGuardiansRemoveCaregiverTooltip'] ?? ''),
    ).toHaveLength(1);
  });

  it('a sole accepted primary guardian is not offered Leave', async () => {
    // defaultMocks: the primary plus one accepted caregiver — counting every
    // accepted role (the pre-#1285 bug) made soleAccepted false and offered
    // a Leave the server answers with `object_not_in_prerequisite_state`.
    renderPage();
    await screen.findByText('Grandma');
    expect(
      screen.queryByText(messages['manageGuardiansLeaveProfileTooltip'] ?? ''),
    ).not.toBeInTheDocument();
  });

  it('a primary guardian with a co-primary is offered Leave', async () => {
    sharingMocks.fetchGuardians.mockResolvedValue([
      guardianRow(),
      guardianRow({
        id: '4f4f4f4f-4f4f-4f4f-8f4f-4f4f4f4f4f4f',
        user_id: OTHER,
        role: 'primary_guardian',
        display_name: 'Mom',
      }),
    ]);
    renderPage();
    expect(await screen.findByText('Mom')).toBeInTheDocument();
    expect(
      screen.getByText(messages['manageGuardiansLeaveProfileTooltip'] ?? ''),
    ).toBeInTheDocument();
  });

  it('a co-parent is offered Leave for their own row', async () => {
    sharingMocks.fetchGuardians.mockResolvedValue([
      guardianRow({ role: 'co_parent', display_name: 'Dad' }),
      guardianRow({
        id: '4f4f4f4f-4f4f-4f4f-8f4f-4f4f4f4f4f4f',
        user_id: OTHER,
        role: 'primary_guardian',
        display_name: 'Mom',
      }),
    ]);
    renderPage();
    // The signed-in co-parent's own row carries the "you" suffix.
    expect(
      await screen.findByText(
        exactText(`Dad ${messages['sharingManageGuardiansYouSuffix'] ?? ''}`.trimEnd()),
      ),
    ).toBeInTheDocument();
    expect(
      screen.getByText(messages['manageGuardiansLeaveProfileTooltip'] ?? ''),
    ).toBeInTheDocument();
  });

  it('a co-parent cannot cancel a co_parent invitation someone else created', async () => {
    sharingMocks.fetchGuardians.mockResolvedValue([
      guardianRow({ role: 'co_parent', display_name: 'Dad' }),
      guardianRow({
        id: '4f4f4f4f-4f4f-4f4f-8f4f-4f4f4f4f4f4f',
        user_id: OTHER,
        role: 'primary_guardian',
        display_name: 'Mom',
      }),
    ]);
    sharingMocks.fetchPendingInvites.mockResolvedValue([
      pendingRow({ role: 'co_parent', invited_by: OTHER, recipient_label: null }),
    ]);
    renderPage();
    expect(
      await screen.findByText(
        exactText(
          `${messages['guardianRoleLabelCoParent']} · ${messages['sharingManageGuardiansExpiryExpired']}`,
        ),
      ),
    ).toBeInTheDocument();
    // The control hides rather than ending in the server's 42501 refusal.
    expect(
      screen.queryByText(messages['sharingManageGuardiansCancel'] ?? ''),
    ).not.toBeInTheDocument();
    expect(sharingMocks.revokeGuardianInvitation).not.toHaveBeenCalled();
  });

  it('a co-parent can still cancel a caregiver invitation', async () => {
    sharingMocks.fetchGuardians.mockResolvedValue([
      guardianRow({ role: 'co_parent', display_name: 'Dad' }),
      guardianRow({
        id: '4f4f4f4f-4f4f-4f4f-8f4f-4f4f4f4f4f4f',
        user_id: OTHER,
        role: 'primary_guardian',
        display_name: 'Mom',
      }),
    ]);
    sharingMocks.fetchPendingInvites.mockResolvedValue([
      pendingRow({ role: 'caregiver', invited_by: OTHER, recipient_label: 'Nurse' }),
    ]);
    sharingMocks.revokeGuardianInvitation.mockResolvedValue('revoked');
    renderPage();
    fireEvent.click(await screen.findByText(messages['sharingManageGuardiansCancel'] ?? ''));
    fireEvent.click(screen.getByText(messages['sharingManageGuardiansCancelInvitation'] ?? ''));
    await waitFor(() => {
      expect(sharingMocks.revokeGuardianInvitation).toHaveBeenCalledWith(
        fakeClient,
        INVITE_ROW_ID,
      );
    });
  });
});
