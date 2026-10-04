import { QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { createAppQueryClient } from '../src/lib/queries';
import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { ProfilesPage } from '../src/pages/ProfilesPage';

/**
 * The profiles page (issue #1253): list / create / edit / archive /
 * delete over the #1252 data layer. The TanStack hooks are mocked at the
 * module boundary; the writes run for real against a fake Supabase client
 * whose `rpc` capture asserts each action rides the same server path the
 * app uses (`sync_push` for metadata and archive stamps,
 * `delete_profile_data` for the purge, `record_minimum_age_acknowledgement`
 * for the #845 acknowledgement).
 */

vi.mock('../src/lib/queries', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../src/lib/queries')>();
  return {
    ...actual,
    useHasSyncSession: vi.fn(() => true),
    useSyncedData: vi.fn(() => ({
      data: syncedFixture(),
      isError: false,
      isPending: false,
      isLoading: false,
    })),
    useCurrentUserId: vi.fn(() => ({ data: UID })),
  };
});

import { useHasSyncSession } from '../src/lib/queries';
import { mergeSyncedData, emptySyncedData } from '../src/lib/domain';
import type { SyncedData } from '../src/lib/domain';
import type { ProfileGuardianRow, ProfileRow } from '../src/lib/schemas';
import { getSupabaseClient } from '../src/lib/supabase';

vi.mock('../src/lib/supabase', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../src/lib/supabase')>();
  return { ...actual, getSupabaseClient: vi.fn(() => null) };
});

const UID = '00000000-0000-4000-8000-0000000000u1';
const MINE_ID = '01M2FWKNG0ZMH2ANCH7R2CM2XZ';
const SHARED_ID = '01M2FWKNG0ZMH2ANCH7R2CM2SB';
const ARCHIVED_ID = '01M2FWKNG0ZMH2ANCH7R2CM2AR';

function profileRow(overrides: Partial<ProfileRow> = {}): ProfileRow {
  return {
    id: MINE_ID,
    user_id: UID,
    display_name: 'Maya',
    is_minor: false,
    mode: 'standard',
    relationship: 'self',
    birth_year: 1990,
    sort_order: 0,
    archived_at: null,
    created_at: '2026-01-05T00:00:00Z',
    updated_at: '2026-01-05T00:00:00Z',
    deleted_at: null,
    server_version: 1,
    ...overrides,
  };
}

let guardianSeq = 0;
function guardianRow(profileId: string, role: string): ProfileGuardianRow {
  guardianSeq += 1;
  return {
    id: `00000000-0000-4000-8000-0000000000g${guardianSeq}`,
    profile_id: profileId,
    user_id: UID,
    role,
    status: 'accepted',
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    server_version: 2,
  };
}

const syncedFixture = (): SyncedData =>
  mergeSyncedData(emptySyncedData(), {
    profiles: [
      profileRow(),
      profileRow({
        id: SHARED_ID,
        user_id: '00000000-0000-4000-8000-0000000000u2',
        display_name: 'Zoe',
        sort_order: 1,
      }),
      profileRow({
        id: ARCHIVED_ID,
        display_name: 'Old',
        archived_at: '2026-09-01T00:00:00Z',
        sort_order: 2,
      }),
    ],
    day_entries: [],
    observations: [],
    profile_modes: [],
    cycle_overrides: [],
    care_notes: [],
    visit_prep_items: [],
    profile_tag_registry: [],
    profile_guardians: [
      guardianRow(MINE_ID, 'primary_guardian'),
      guardianRow(SHARED_ID, 'viewer'),
      guardianRow(ARCHIVED_ID, 'primary_guardian'),
    ],
    guardian_notes: [],
  });

/** The fake client: captures every rpc, answers the consent read with no record. */
function fakeClient(options: { consentRecord?: Record<string, string> | null } = {}) {
  const rpc = vi.fn(async (name: string, _args: Record<string, unknown> = {}) => {
    if (name === 'sync_watermark') {
      return { data: 100_000, error: null };
    }
    return {
      data: { resolved: [], rejected: [], server_now: '2026-10-03T12:00:00Z' },
      error: null,
    };
  });
  const from = vi.fn((table: string) => {
    if (table === 'account_consents') {
      return {
        select: () => ({
          maybeSingle: async () => ({
            data: options.consentRecord ?? null,
            error: null,
          }),
        }),
      };
    }
    throw new Error(`fakeClient: unexpected select on ${table}`);
  });
  const client = { from, rpc };
  vi.mocked(getSupabaseClient).mockReturnValue(client as never);
  return { rpc, from, client };
}

function renderPage() {
  const queryClient = createAppQueryClient();
  return render(
    <AppIntlProvider>
      <QueryClientProvider client={queryClient}>
        <MemoryRouter initialEntries={['/profiles']}>
          <ProfilesPage />
        </MemoryRouter>
      </QueryClientProvider>
    </AppIntlProvider>,
  );
}

describe('ProfilesPage (issue #1253)', () => {
  beforeEach(() => {
    vi.mocked(useHasSyncSession).mockReturnValue(true);
    vi.mocked(getSupabaseClient).mockReturnValue(null);
  });

  afterEach(cleanup);

  it('asks for sign-in while signed out', () => {
    vi.mocked(useHasSyncSession).mockReturnValue(false);
    renderPage();
    expect(screen.getByText(messages['webHomeNeedsSignIn'] ?? 'missing')).toBeInTheDocument();
  });

  it('renders mine, shared-with-me, and archived sections', () => {
    renderPage();
    expect(
      screen.getByText(messages['profilePickerMyProfilesHeader'] ?? 'missing'),
    ).toBeInTheDocument();
    expect(
      screen.getByText(messages['profilePickerSharedWithMeHeader'] ?? 'missing'),
    ).toBeInTheDocument();
    expect(
      screen.getByText((messages['profilePickerArchivedHeader'] ?? '').replace('{count}', '1')),
    ).toBeInTheDocument();
    expect(screen.getByText('Maya')).toBeInTheDocument();
    expect(screen.getByText('Zoe')).toBeInTheDocument();
    expect(screen.getByText('Old')).toBeInTheDocument();
  });

  it('gates the actions on the caller role: a viewer sees none, a primary sees all', () => {
    renderPage();
    const mine = screen.getByText('Maya').closest('li') as HTMLElement;
    expect(
      within(mine).queryByRole('button', { name: messages['webProfilesEditAction'] ?? '' }),
    ).not.toBeNull();
    const shared = screen.getByText('Zoe').closest('li') as HTMLElement;
    expect(
      within(shared).queryByRole('button', { name: messages['webProfilesEditAction'] ?? '' }),
    ).toBeNull();
    expect(
      within(shared).queryByRole('button', { name: messages['webProfilesDeleteAction'] ?? '' }),
    ).toBeNull();
  });

  it('validates the create form before pushing anything', async () => {
    const { rpc } = fakeClient();
    renderPage();
    fireEvent.click(
      screen.getByRole('button', { name: messages['profilePickerAddProfileTooltip'] ?? '' }),
    );
    fireEvent.submit(
      screen.getByRole('button', { name: messages['profileDialogCreate'] ?? '' }),
    );
    expect(
      await screen.findByText(messages['profileDialogNameEmpty'] ?? 'missing'),
    ).toBeInTheDocument();
    expect(rpc).not.toHaveBeenCalled();
  });

  it('requires the minimum-age acknowledgement when the account has none', async () => {
    const { rpc } = fakeClient({ consentRecord: null });
    renderPage();
    fireEvent.click(
      screen.getByRole('button', { name: messages['profilePickerAddProfileTooltip'] ?? '' }),
    );
    fireEvent.change(screen.getByLabelText(messages['firstRunNameLabel'] ?? ''), {
      target: { value: 'Noor' },
    });
    fireEvent.submit(
      screen.getByRole('button', { name: messages['profileDialogCreate'] ?? '' }),
    );
    expect(
      await screen.findByText(messages['firstRunAgeAcknowledgementRequired'] ?? 'missing'),
    ).toBeInTheDocument();
    expect(rpc).not.toHaveBeenCalled();
  });

  it('creates the profile and records the acknowledgement best-effort', async () => {
    const { rpc } = fakeClient({ consentRecord: null });
    renderPage();
    fireEvent.click(
      screen.getByRole('button', { name: messages['profilePickerAddProfileTooltip'] ?? '' }),
    );
    fireEvent.change(screen.getByLabelText(messages['firstRunNameLabel'] ?? ''), {
      target: { value: 'Noor' },
    });
    fireEvent.click(screen.getByLabelText(messages['firstRunAgeAcknowledgementLabel'] ?? ''));
    fireEvent.submit(
      screen.getByRole('button', { name: messages['profileDialogCreate'] ?? '' }),
    );
    await waitFor(() => expect(rpc).toHaveBeenCalledWith('sync_push', expect.anything()));
    expect(rpc).toHaveBeenCalledWith(
      'record_minimum_age_acknowledgement',
      expect.objectContaining({
        p_consent_via: 'self_13_plus',
        p_policy_version: messages['webHomeNeedsSignIn'] !== undefined ? '2026-09-21' : '',
      }),
    );
    const pushArg = rpc.mock.calls.find((call) => call[0] === 'sync_push')?.[1] as unknown as {
      p_profiles: { display_name: string; mode: string }[];
    };
    expect(pushArg.p_profiles[0]).toMatchObject({ display_name: 'Noor', mode: 'standard' });
  });

  it('skips the acknowledgement statement when the account already carries a current one', async () => {
    const { rpc } = fakeClient({
      consentRecord: {
        consent_via: 'self_13_plus',
        acknowledged_at: '2026-09-21T00:00:00Z',
        app_version: '1.0.0',
        policy_version: '2026-09-21',
      },
    });
    renderPage();
    fireEvent.click(
      screen.getByRole('button', { name: messages['profilePickerAddProfileTooltip'] ?? '' }),
    );
    await waitFor(() =>
      expect(
        screen.queryByLabelText(messages['firstRunAgeAcknowledgementLabel'] ?? ''),
      ).toBeNull(),
    );
    fireEvent.change(screen.getByLabelText(messages['firstRunNameLabel'] ?? ''), {
      target: { value: 'Noor' },
    });
    fireEvent.submit(
      screen.getByRole('button', { name: messages['profileDialogCreate'] ?? '' }),
    );
    await waitFor(() => expect(rpc).toHaveBeenCalledWith('sync_push', expect.anything()));
    expect(rpc.mock.calls.some(([name]) => name === 'record_minimum_age_acknowledgement')).toBe(
      false,
    );
  });

  it('archives through a confirm step that pushes an archived_at stamp', async () => {
    const { rpc } = fakeClient();
    renderPage();
    const row = screen.getByText('Maya').closest('li') as HTMLElement;
    fireEvent.click(
      within(row).getByRole('button', { name: messages['profileArchive'] ?? '' }),
    );
    // The confirm carries the app's own copy, as a labelled dialog.
    expect(
      await within(row).findByRole('alertdialog', {
        name: (messages['profileArchiveConfirmTitle'] ?? '').replace('{name}', 'Maya'),
      }),
    ).toBeInTheDocument();
    fireEvent.click(
      within(row).getByRole('button', { name: messages['profileArchiveConfirmButton'] ?? '' }),
    );
    await waitFor(() => expect(rpc).toHaveBeenCalledWith('sync_push', expect.anything()));
    const pushArg = rpc.mock.calls.find((call) => call[0] === 'sync_push')?.[1] as unknown as {
      p_profiles: { id: string; archived_at: string | null }[];
    };
    expect(pushArg.p_profiles[0].id).toBe(MINE_ID);
    expect(pushArg.p_profiles[0].archived_at).not.toBeNull();
  });

  it('deletes through the two-step confirm on delete_profile_data', async () => {
    const { rpc } = fakeClient();
    renderPage();
    const row = screen.getByText('Maya').closest('li') as HTMLElement;
    fireEvent.click(
      within(row).getByRole('button', { name: messages['webProfilesDeleteAction'] ?? '' }),
    );
    // Step 1 carries the erasure scope; the action advances to step 2.
    fireEvent.click(
      within(row).getByRole('button', {
        name: messages['sharingManageGuardiansDeleteProfileAction'] ?? '',
      }),
    );
    expect(
      await within(row).findByRole('alertdialog', {
        name: messages['sharingManageGuardiansDeleteProfileStep2Title'] ?? 'missing',
      }),
    ).toBeInTheDocument();
    fireEvent.click(
      within(row).getByRole('button', {
        name: messages['sharingManageGuardiansDeleteProfileAction'] ?? '',
      }),
    );
    await waitFor(() =>
      expect(rpc).toHaveBeenCalledWith(
        'delete_profile_data',
        expect.objectContaining({ p_profile_id: MINE_ID }),
      ),
    );
    expect(
      await screen.findByText(messages['webProfilesDeleted'] ?? 'missing'),
    ).toBeInTheDocument();
  });

  it('edits a profile: name and irregular framing ride sync_push', async () => {
    const { rpc } = fakeClient();
    renderPage();
    const row = screen.getByText('Maya').closest('li') as HTMLElement;
    fireEvent.click(
      within(row).getByRole('button', { name: messages['webProfilesEditAction'] ?? '' }),
    );
    const name = screen.getByLabelText(messages['firstRunNameLabel'] ?? '');
    fireEvent.change(name, { target: { value: 'Maya B' } });
    fireEvent.submit(screen.getByRole('button', { name: messages['profileDialogSave'] ?? '' }));
    await waitFor(() => expect(rpc).toHaveBeenCalledWith('sync_push', expect.anything()));
    const pushArg = rpc.mock.calls.find((call) => call[0] === 'sync_push')?.[1] as unknown as {
      p_profiles: Record<string, unknown>[];
    };
    expect(pushArg.p_profiles[0]).toMatchObject({ id: MINE_ID, display_name: 'Maya B' });
    // The untouched framing control preserves the stored tri-state: the
    // payload omits the key entirely (the server's containment guard).
    expect('irregular_framing' in pushArg.p_profiles[0]).toBe(false);
  });
});

import { within } from '@testing-library/react';
