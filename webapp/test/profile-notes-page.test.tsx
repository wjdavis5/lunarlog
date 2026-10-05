import { QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { QueryClient } from '@tanstack/react-query';
import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { ProfileNotesPage } from '../src/pages/ProfileNotesPage';

/**
 * Notes-page tests (issue #1255): the author rules (#867/#868) — every
 * accepted guardian reads both note kinds, the editor adopts only the
 * operator's own guardian note, and writes go through the sync_push
 * wrappers with the exact payload shapes.
 */

const ULID = '01ARZ3NDEKTSV4RRFFQ69G5FAV';
const ULID2 = '01ARZ3NDEKTSV4RRFFQ69G5FAW';
// profile_guardians row ids are uuid (gen_random_uuid, 20260904010000),
// unlike the profile's and the notes' client-generated ULIDs (issue #1284).
const GUARDIAN_ROW_ID = '2f2f2f2f-2f2f-4f2f-8f2f-2f2f2f2f2f2f';
const GUARDIAN_ROW_ID_2 = '3f3f3f3f-3f3f-4f3f-8f3f-3f3f3f3f3f3f';
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
 * #1252) — `onAuthStateChange` included, or the effect throws. The synced
 * profile list is seeded into the query cache by `renderPage`. */
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

const sharingMocks = vi.hoisted(() => ({
  fetchGuardians: vi.fn(),
  fetchGuardianNotesForDate: vi.fn(),
  fetchCareNotes: vi.fn(),
  currentUserId: vi.fn(() => ME),
  pushGuardianNotes: vi.fn(),
  pushCareNotes: vi.fn(),
}));

vi.mock('../src/lib/sharing', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  ...sharingMocks,
}));

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

function noteRow(overrides: Record<string, unknown> = {}) {
  return {
    id: ULID2,
    profile_id: ULID,
    local_date: '2026-09-30',
    tz: 'America/Chicago',
    body: 'Felt better after lunch.',
    logged_by_user_id: OTHER,
    updated_at: '2026-09-30T18:00:00Z',
    ...overrides,
  };
}

function renderPage() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  // Seed the synced-data cache (issue #1252's `useLiveProfiles` reads
  // `['synced-data']`, never a table) instead of the retired profiles read.
  domainMocks.refresh.mockResolvedValue({ profiles: [profileRow] });
  queryClient.setQueryData(['synced-data'], { profiles: [profileRow] } as never);
  return render(
    <AppIntlProvider>
      <QueryClientProvider client={queryClient}>
        <MemoryRouter initialEntries={[`/profile/${ULID}/notes`]}>
          <Routes>
            <Route path="/profile/:profileId/notes" element={<ProfileNotesPage />} />
          </Routes>
        </MemoryRouter>
      </QueryClientProvider>
    </AppIntlProvider>,
  );
}

function defaultMocks() {
  sharingMocks.fetchGuardians.mockResolvedValue([
    guardianRow(),
    guardianRow({
      id: GUARDIAN_ROW_ID_2,
      user_id: OTHER,
      role: 'caregiver',
      display_name: 'Grandma',
    }),
  ]);
  sharingMocks.fetchGuardianNotesForDate.mockResolvedValue([]);
  sharingMocks.fetchCareNotes.mockResolvedValue([]);
  sharingMocks.pushGuardianNotes.mockResolvedValue([]);
  sharingMocks.pushCareNotes.mockResolvedValue([]);
}

beforeEach(defaultMocks);

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe('ProfileNotesPage (issue #1255)', () => {
  it('renders both note sections and the date picker', async () => {
    renderPage();
    expect(screen.getByText(messages['guardianNotesSectionTitle'] ?? '')).toBeInTheDocument();
    expect(
      await screen.findByText(messages['careNotesSectionTitle'] ?? ''),
    ).toBeInTheDocument();
    // The chosen day is written out, never as an ISO string.
    expect(screen.getByLabelText(/^for \w+day, \w+ \d{1,2}, \d{4}$/)).toBeInTheDocument();
    expect(screen.queryByLabelText(/\d{4}-\d{2}-\d{2}/)).toBeNull();
  });

  // The page is reached by its own address and holds two kinds of note. It
  // used to be titled "Notes from guardians" whoever it was about.
  it("is titled with the profile's name, and that is the only top-level heading", async () => {
    renderPage();
    const headings = await screen.findAllByRole('heading', { level: 1 });
    expect(headings).toHaveLength(1);
    expect(headings[0]).toHaveTextContent(
      (messages['webNotesTitle'] ?? '').replace('{profileName}', 'Maya'),
    );
    expect(
      screen.getByRole('heading', { level: 2, name: messages['guardianNotesSectionTitle'] }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole('heading', { level: 2, name: messages['careNotesSectionTitle'] }),
    ).toBeInTheDocument();
  });

  it("leads back to this profile's home, not to whichever profile is first", () => {
    renderPage();
    expect(screen.getByRole('link', { name: messages['webDayBackToToday'] })).toHaveAttribute(
      'href',
      `/?profile=${ULID}`,
    );
    // One link back is not a navigation landmark of its own.
    expect(screen.queryByRole('navigation')).toBeNull();
  });

  it("prints the editor's label once", async () => {
    renderPage();
    await screen.findByLabelText(messages['guardianNotesFieldLabel'] ?? '');
    expect(screen.getAllByText(messages['guardianNotesFieldLabel'] ?? '')).toHaveLength(1);
  });

  it('credits a care note to its author above the note, "You" for your own', async () => {
    sharingMocks.fetchCareNotes.mockResolvedValue([
      {
        id: ULID,
        profile_id: ULID,
        body: 'Refill the heat pad.',
        logged_by_user_id: ME,
        last_modified_by_user_id: null,
        updated_at: '2026-09-30T18:00:00Z',
      },
      {
        id: ULID2,
        profile_id: ULID,
        body: 'Bring the pain diary.',
        logged_by_user_id: OTHER,
        last_modified_by_user_id: null,
        updated_at: '2026-09-30T19:00:00Z',
      },
    ]);
    renderPage();
    const mine = (await screen.findByText('Refill the heat pad.')).closest('li') as HTMLElement;
    expect(within(mine).getByText(messages['guardianNotesYou'] ?? 'missing')).toHaveClass(
      'row-title',
    );
    expect(within(mine).getByText('Refill the heat pad.')).toHaveClass('row-sub');
    const theirs = screen.getByText('Bring the pain diary.').closest('li') as HTMLElement;
    expect(within(theirs).getByText('Grandma')).toHaveClass('row-title');
  });

  it("another guardian's note is read-only and attributed", async () => {
    sharingMocks.fetchGuardianNotesForDate.mockResolvedValue([noteRow()]);
    renderPage();
    expect(await screen.findByText('Felt better after lunch.')).toBeInTheDocument();
    expect(screen.getByText('Grandma')).toBeInTheDocument();
    // One editor exists (the operator's own), and the other's note has no
    // remove control of its own — the editor's textarea is the only one.
    const editors = screen.getAllByLabelText(messages['guardianNotesFieldLabel'] ?? '');
    expect(editors).toHaveLength(1);
  });

  // Issue #1464: an empty name is no name. `??` kept it, so the note was
  // signed by nobody at all.
  it.each([
    ['no', null],
    ['an empty', ''],
  ])('a note from a guardian with %s name is signed "Guardian"', async (_described, name) => {
    sharingMocks.fetchGuardians.mockResolvedValue([
      guardianRow(),
      guardianRow({
        id: GUARDIAN_ROW_ID_2,
        user_id: OTHER,
        role: 'caregiver',
        display_name: name,
      }),
    ]);
    sharingMocks.fetchGuardianNotesForDate.mockResolvedValue([noteRow()]);
    renderPage();
    const note = (await screen.findByText('Felt better after lunch.')).closest(
      'li',
    ) as HTMLElement;
    expect(
      within(note).getByText(messages['guardianNotesGuardianFallback'] ?? 'missing'),
    ).toHaveClass('row-title');
  });

  it("the operator's own note adopts the editor with an update button", async () => {
    sharingMocks.fetchGuardianNotesForDate.mockResolvedValue([
      noteRow({ id: ULID, logged_by_user_id: ME, body: 'My note.' }),
      noteRow(),
    ]);
    renderPage();
    const editor = await screen.findByLabelText(messages['guardianNotesFieldLabel'] ?? '');
    expect((editor as HTMLTextAreaElement).value).toBe('My note.');
    const editorSection = within(editor.closest('section') as HTMLElement);
    expect(editorSection.getByText(messages['guardianNotesUpdate'] ?? '')).toBeInTheDocument();
    expect(editorSection.getByText(messages['guardianNotesRemove'] ?? '')).toBeInTheDocument();
  });

  it('saving writes through sync_push with the date-bound payload', async () => {
    sharingMocks.fetchGuardianNotesForDate.mockResolvedValue([]);
    renderPage();
    const editor = await screen.findByLabelText(messages['guardianNotesFieldLabel'] ?? '');
    const editorSection = within(editor.closest('section') as HTMLElement);
    fireEvent.change(editor, { target: { value: 'Slept great.' } });
    fireEvent.click(editorSection.getByText(messages['guardianNotesAdd'] ?? ''));
    await waitFor(() => {
      expect(sharingMocks.pushGuardianNotes).toHaveBeenCalledTimes(1);
    });
    const [client, rows] = sharingMocks.pushGuardianNotes.mock.calls[0] ?? [];
    expect(client).toBe(fakeClient);
    const row = (rows as Array<Record<string, unknown>>)[0] ?? {};
    expect(row['profileId']).toBe(ULID);
    expect(row['body']).toBe('Slept great.');
    expect(row['tz']).toBeTruthy();
    expect(String(row['localDate'])).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(row['deleted']).toBe(false);
  });

  it("removing the operator's own note tombstones it", async () => {
    sharingMocks.fetchGuardianNotesForDate.mockResolvedValue([
      noteRow({ id: ULID, logged_by_user_id: ME, body: 'My note.' }),
    ]);
    renderPage();
    const editor = await screen.findByLabelText(messages['guardianNotesFieldLabel'] ?? '');
    fireEvent.click(
      within(editor.closest('section') as HTMLElement).getByText(
        messages['guardianNotesRemove'] ?? '',
      ),
    );
    await waitFor(() => {
      expect(sharingMocks.pushGuardianNotes).toHaveBeenCalledTimes(1);
    });
    const row =
      (
        sharingMocks.pushGuardianNotes.mock.calls[0]?.[1] as Array<Record<string, unknown>>
      )[0] ?? {};
    expect(row['id']).toBe(ULID);
    expect(row['deleted']).toBe(true);
    expect(row['body']).toBe('My note.');
  });

  it('a viewer reads notes but has no editor and no composer', async () => {
    sharingMocks.fetchGuardians.mockResolvedValue([guardianRow({ role: 'viewer' })]);
    renderPage();
    await screen.findByText(messages['careNotesSectionTitle'] ?? '');
    expect(
      screen.queryByLabelText(messages['guardianNotesFieldLabel'] ?? ''),
    ).not.toBeInTheDocument();
    expect(screen.queryByText(messages['careNotesAddButton'] ?? '')).not.toBeInTheDocument();
  });

  it('care notes list, add, and confirm-before-remove', async () => {
    sharingMocks.fetchCareNotes.mockResolvedValue([
      {
        id: ULID,
        profile_id: ULID,
        body: 'Refill the heat pad.',
        logged_by_user_id: OTHER,
        last_modified_by_user_id: null,
        updated_at: '2026-09-30T18:00:00Z',
      },
    ]);
    renderPage();
    expect(await screen.findByText('Refill the heat pad.')).toBeInTheDocument();
    const careSection = within(
      screen
        .getByText(messages['careNotesSectionTitle'] ?? '')
        .closest('section') as HTMLElement,
    );

    fireEvent.change(careSection.getByLabelText(messages['careNotesAddLabel'] ?? ''), {
      target: { value: 'New care note.' },
    });
    fireEvent.click(careSection.getByText(messages['careNotesAddButton'] ?? ''));
    await waitFor(() => {
      expect(sharingMocks.pushCareNotes).toHaveBeenCalledTimes(1);
    });
    const added =
      (sharingMocks.pushCareNotes.mock.calls[0]?.[1] as Array<Record<string, unknown>>)[0] ??
      {};
    expect(added['body']).toBe('New care note.');
    expect(added['deleted']).toBe(false);

    fireEvent.click(careSection.getByLabelText(messages['careNotesRemoveNoteTooltip'] ?? ''));
    fireEvent.click(screen.getByText(messages['careNotesDeleteConfirm'] ?? ''));
    await waitFor(() => {
      expect(sharingMocks.pushCareNotes).toHaveBeenCalledTimes(2);
    });
    const removed =
      (sharingMocks.pushCareNotes.mock.calls[1]?.[1] as Array<Record<string, unknown>>)[0] ??
      {};
    expect(removed['id']).toBe(ULID);
    expect(removed['deleted']).toBe(true);
    expect(removed['body']).toBe('');
  });
});
