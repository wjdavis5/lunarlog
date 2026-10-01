import { QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { AppIntlProvider } from '../src/i18n/i18n';
import { createAppQueryClient } from '../src/lib/queries';
import { getSyncedDataCache } from '../src/lib/domain';
import { DayPage } from '../src/pages/DayPage';
import type { AppSupabaseClient } from '../src/lib/supabase';
import type { ProfileGuardianRow, ProfileRow } from '../src/lib/schemas';

/**
 * The day editor page (issue #1254): the states a signed-in operator moves
 * through — read-only for a viewer, editable for a writer, the save button
 * driving one sync_push call through the data module, the retry banner
 * keeping a failed save on screen, and the unsaved-edits beforeunload
 * guard. The live-server behaviour is the integration test's; here the
 * client is a fake answering the masked sync_pull walk.
 */

const PROFILE_ID = '01M2FWKNG0ZMH2ANCH7R2CM2XZ';
const ENTRY_ID = '01M2FWKNG0ZMH2ANCH7R2CM2Y2';
const DATE = '2026-09-29';

const profile: ProfileRow = {
  id: PROFILE_ID,
  user_id: '00000000-0000-4000-8000-0000000000u1',
  display_name: 'Maya',
  is_minor: false,
  mode: 'standard',
  relationship: 'self',
  birth_year: 1990,
  sort_order: 0,
  archived_at: null,
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
  deleted_at: null,
  server_version: 1,
  bbt_unit: 'celsius',
  weight_unit: 'kg',
  tracking_preferences: null,
};

const entry = {
  id: ENTRY_ID,
  user_id: '00000000-0000-4000-8000-0000000000u1',
  profile_id: PROFILE_ID,
  local_date: DATE,
  tz: 'UTC',
  flow: 'none',
  tags: [],
  note: null,
  note_private: false,
  pms: false,
  source: 'manual',
  source_id: null,
  created_at: '2026-09-29T08:00:00.000Z',
  updated_at: '2026-09-29T08:00:00.000Z',
  deleted_at: null,
  server_version: 3,
};

function membership(role: string, isSubject = true): ProfileGuardianRow {
  return {
    id: '00000000-0000-4000-8000-0000000000e1',
    profile_id: PROFILE_ID,
    user_id: '00000000-0000-4000-8000-0000000000u1',
    role,
    status: 'accepted',
    is_subject: isSubject,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    server_version: 2,
  };
}

function fakeClient(options?: {
  membership?: ProfileGuardianRow | null;
  rpcResult?: { data: unknown; error: { message: string } | null };
  trackingPreferences?: unknown;
}) {
  const page = {
    profiles: [
      {
        ...profile,
        server_version: 3,
        ...(options?.trackingPreferences !== undefined
          ? { tracking_preferences: options.trackingPreferences }
          : {}),
      },
    ],
    day_entries: [{ ...entry, server_version: 7 }],
    observations: [],
    profile_modes: [],
    cycle_overrides: [],
    care_notes: [],
    visit_prep_items: [],
    profile_tag_registry: [],
    profile_guardians:
      options?.membership === undefined
        ? [membership('primary_guardian')]
        : options.membership === null
          ? []
          : [options.membership],
    day_entry_history: [],
  };
  const rpc = vi.fn().mockImplementation((name: string) => {
    if (name === 'sync_pull') {
      return Promise.resolve({ data: page, error: null });
    }
    return Promise.resolve(
      options?.rpcResult ?? {
        data: { resolved: [], rejected: [], server_now: '2026-09-30T08:00:00Z' },
        error: null,
      },
    );
  });
  const from = vi.fn().mockImplementation(() => {
    throw new Error('fakeClient: unexpected direct select');
  });
  return {
    client: {
      from,
      rpc,
      auth: {
        getSession: async () => ({
          data: { session: { user: { id: '00000000-0000-4000-8000-0000000000u1' } } },
        }),
      },
    } as unknown as AppSupabaseClient,
    rpc,
  };
}

function renderDay(client: AppSupabaseClient | null) {
  const queryClient = createAppQueryClient();
  return render(
    <AppIntlProvider>
      <QueryClientProvider client={queryClient}>
        <MemoryRouter initialEntries={[`/day/${PROFILE_ID}?date=${DATE}`]}>
          <Routes>
            <Route path="/day/:profileId" element={<DayPage client={client} />} />
          </Routes>
        </MemoryRouter>
      </QueryClientProvider>
    </AppIntlProvider>,
  );
}

describe('DayPage (issue #1254)', () => {
  beforeEach(() => {
    getSyncedDataCache().reset();
  });

  afterEach(cleanup);

  it('asks for sign-in on an unconfigured build', () => {
    renderDay(null);
    expect(screen.getByText('Sign in to log a day.')).toBeInTheDocument();
  });

  it('renders the heading and the flow chips for a writer', async () => {
    const { client } = fakeClient();
    renderDay(client);
    expect(await screen.findByText('Maya — 2026-09-29')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'None' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Heavy' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Save' })).toBeInTheDocument();
  });

  it('hides the metadata sections from a caregiver but keeps the day editable', async () => {
    const { client } = fakeClient({ membership: membership('caregiver', false) });
    renderDay(client);
    await screen.findByText('Maya — 2026-09-29');
    expect(screen.queryByText('Cycle corrections')).not.toBeInTheDocument();
    expect(screen.queryByText('Life stage')).not.toBeInTheDocument();
    const note = screen.getByLabelText('Notes');
    fireEvent.change(note, { target: { value: 'from the caregiver' } });
    await waitFor(() => expect(screen.getByRole('button', { name: 'Save' })).toBeEnabled());
  });

  it('is read-only for a viewer, with the banner', async () => {
    const { client } = fakeClient({ membership: membership('viewer', false) });
    renderDay(client);
    await screen.findByText('You have view-only access to this profile.');
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled();
    expect(screen.getByLabelText('Notes')).toHaveAttribute('readonly');
  });

  it('saves through the data module and shows the saved status', async () => {
    const { client, rpc } = fakeClient();
    renderDay(client);
    const note = await screen.findByLabelText('Notes');
    fireEvent.change(note, { target: { value: 'logged on the web' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));
    await waitFor(() => expect(screen.getByText('Saved')).toBeInTheDocument());
    expect(rpc).toHaveBeenCalledWith(
      'sync_push',
      expect.objectContaining({
        p_day_entries: [expect.objectContaining({ note: 'logged on the web', id: ENTRY_ID })],
      }),
    );
  });

  it('keeps a failed save on screen with the retry banner', async () => {
    const { client } = fakeClient({
      rpcResult: { data: null, error: { message: 'network unreachable' } },
    });
    renderDay(client);
    const note = await screen.findByLabelText('Notes');
    fireEvent.change(note, { target: { value: 'still here' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));
    expect(
      await screen.findByText(
        'Saving failed — your changes are still here, nothing was lost. Try again.',
      ),
    ).toBeInTheDocument();
    // The typed value is still on screen and Save (retry) is enabled.
    expect(screen.getByLabelText('Notes')).toHaveValue('still here');
    await waitFor(() => expect(screen.getByRole('button', { name: 'Save' })).toBeEnabled());
  });

  it('shows the inline rejection beside the field group the server refused', async () => {
    const { client } = fakeClient({
      rpcResult: {
        data: {
          resolved: [],
          rejected: [{ id: ENTRY_ID, rejected: true }],
          server_now: '2026-09-30T08:00:00Z',
        },
        error: null,
      },
    });
    renderDay(client);
    const note = await screen.findByLabelText('Notes');
    fireEvent.change(note, { target: { value: 'rejected day' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));
    expect(
      await screen.findByText('The server rejected this field — check it and try again.'),
    ).toBeInTheDocument();
  });

  it('keeps a partly-rejected save dirty: retry enabled, values kept, warning armed', async () => {
    const { client } = fakeClient({
      rpcResult: {
        data: {
          resolved: [],
          rejected: [{ id: ENTRY_ID, rejected: true }],
          server_now: '2026-09-30T08:00:00Z',
        },
        error: null,
      },
    });
    // The beforeunload listener is removed only by the effect's cleanup —
    // i.e. when `dirty` flips false. Zero removals after the save resolved
    // means the unsaved-edits warning stayed armed (issue #1290).
    const removeSpy = vi.spyOn(window, 'removeEventListener');
    try {
      renderDay(client);
      const note = await screen.findByLabelText('Notes');
      fireEvent.change(note, { target: { value: 'rejected day' } });
      fireEvent.click(screen.getByRole('button', { name: 'Save' }));
      expect(
        await screen.findByText('The server rejected this field — check it and try again.'),
      ).toBeInTheDocument();
      // The push resolved, but the baseline must not absorb what the
      // server rejected: the edit stays dirty — the typed value survives
      // the invalidation refetch, Save (retry) stays enabled, and no
      // saved status shows.
      expect(screen.getByLabelText('Notes')).toHaveValue('rejected day');
      await waitFor(() => expect(screen.getByRole('button', { name: 'Save' })).toBeEnabled());
      expect(screen.queryByText('Saved')).not.toBeInTheDocument();
      expect(removeSpy.mock.calls.filter(([type]) => type === 'beforeunload')).toHaveLength(0);
    } finally {
      removeSpy.mockRestore();
    }
  });

  it('keeps a declined (lost LWW) save dirty with the declined notice', async () => {
    const { client } = fakeClient({
      rpcResult: {
        data: {
          resolved: [
            {
              id: ENTRY_ID,
              table: 'day_entries',
              deleted_at: null,
              updated_at: '2026-09-29T23:00:00.000Z',
            },
          ],
          rejected: [],
          server_now: '2026-09-30T08:00:00Z',
        },
        error: null,
      },
    });
    renderDay(client);
    const note = await screen.findByLabelText('Notes');
    fireEvent.change(note, { target: { value: 'declined day' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));
    expect(
      await screen.findByText(
        'A newer save from another device won this day — your changes were not applied.',
      ),
    ).toBeInTheDocument();
    // A decline resolves the mutation too (issue #1290): the edit stays
    // dirty exactly like a partly-rejected save, so the declined banner's
    // values survive the refetch and Save stays available for retry.
    expect(screen.getByLabelText('Notes')).toHaveValue('declined day');
    await waitFor(() => expect(screen.getByRole('button', { name: 'Save' })).toBeEnabled());
    expect(screen.queryByText('Saved')).not.toBeInTheDocument();
  });

  it('warns beforeunload only while dirty', async () => {
    const { client } = fakeClient();
    const addSpy = vi.spyOn(window, 'addEventListener');
    try {
      renderDay(client);
      await screen.findByText('Maya — 2026-09-29');
      expect(addSpy.mock.calls.filter(([type]) => type === 'beforeunload')).toHaveLength(0);
      fireEvent.change(screen.getByLabelText('Notes'), { target: { value: 'unsaved' } });
      await waitFor(() =>
        expect(
          addSpy.mock.calls.filter(([type]) => type === 'beforeunload').length,
        ).toBeGreaterThan(0),
      );
    } finally {
      addSpy.mockRestore();
    }
  });

  it('renders the bounds banner and disables saving for a future day', async () => {
    const { client } = fakeClient();
    const queryClient = createAppQueryClient();
    render(
      <AppIntlProvider>
        <QueryClientProvider client={queryClient}>
          <MemoryRouter initialEntries={[`/day/${PROFILE_ID}?date=2026-10-05`]}>
            <Routes>
              <Route path="/day/:profileId" element={<DayPage client={client} />} />
            </Routes>
          </MemoryRouter>
        </QueryClientProvider>
      </AppIntlProvider>,
    );
    expect(
      await screen.findByText("You can't log a day more than one day ahead."),
    ).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled();
  });

  // Issue #1291: the ovulation/pregnancy test chips used to render twice —
  // once from the symptom picker's surfaced-category loop and again from a
  // dedicated Tests fieldset that ignored tracking_preferences.
  it('renders the test chips exactly once when the category is enabled', async () => {
    const { client } = fakeClient();
    renderDay(client);
    await screen.findByText('Maya — 2026-09-29');
    // The default (never-customized, non-minor) profile surfaces every
    // category, `tests` among them — but only through its own fieldset.
    expect(screen.getAllByRole('button', { name: 'Ovulation · positive' })).toHaveLength(1);
    expect(screen.getAllByRole('button', { name: 'Pregnancy · negative' })).toHaveLength(1);
    expect(screen.getAllByText('Tests')).toHaveLength(1);
  });

  it('renders no test chips when tracking_preferences disable the category', async () => {
    const { client } = fakeClient({
      trackingPreferences: { tests: { enabled: false, sort_order: 0 } },
    });
    renderDay(client);
    await screen.findByText('Maya — 2026-09-29');
    for (const chip of [
      'Ovulation · negative',
      'Ovulation · positive',
      'Ovulation · peak',
      'Pregnancy · negative',
      'Pregnancy · positive',
    ]) {
      expect(screen.queryByRole('button', { name: chip })).not.toBeInTheDocument();
    }
    expect(screen.queryByText('Tests')).not.toBeInTheDocument();
    // The rest of the symptom picker is untouched by the `tests` disable.
    expect(screen.getByRole('button', { name: 'Cramps' })).toBeInTheDocument();
  });
});
