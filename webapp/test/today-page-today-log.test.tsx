import { QueryClientProvider } from '@tanstack/react-query';
import { cleanup, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { createAppQueryClient } from '../src/lib/queries';
import { TodayPage } from '../src/pages/TodayPage';
import { loadDomainModule } from './domain/load-module';

/**
 * The home's "Logged today" card and its Log today / Edit today button,
 * on the page (the browser version of the app's Today log card, issue
 * #1489).
 *
 * The domain module here is the real one: the compiled Dart, loaded the
 * way the parity suite loads it. So what these tests see on the page is
 * what the app's own rules say about the snapshot, end to end: the rows
 * the page picks, the call, and the card. The data-layer hooks are mocked
 * at the module boundary, as in today-page.test.tsx; nothing is fetched.
 *
 * "Today" is fixed at 30 September 2026, local time, so the day the page
 * reads from the clock is the day the rows are dated.
 */

vi.mock('../src/lib/queries', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../src/lib/queries')>();
  return {
    ...actual,
    useHasSyncSession: vi.fn(() => true),
    useSyncedData: vi.fn(),
    useCurrentUserId: vi.fn(),
    useSyncSignalsRefetch: vi.fn(),
  };
});

import { useCurrentUserId, useSyncedData } from '../src/lib/queries';
import { emptySyncedData, type SyncedData } from '../src/lib/domain';
import type {
  DayEntryRow,
  ObservationRow,
  ProfileGuardianRow,
  ProfileRow,
  ProfileTagRegistryRow,
} from '../src/lib/schemas';

const UID = '00000000-0000-4000-8000-0000000000u1';
const MAYA = '01M2FWKNG0ZMH2ANCH7R2CM2XZ';
const ADA = '01M2FWKNG0ZMH2ANCH7R2CM2YA';
const TODAY = '2026-09-30';
const YESTERDAY = '2026-09-29';
const NOTE = 'zebra crossing after the dentist';
const NOTE_WORDS = ['zebra', 'crossing', 'dentist'];

const realModule = loadDomainModule();

function profileRow(id: string, displayName: string, sortOrder: number): ProfileRow {
  return {
    id,
    user_id: UID,
    display_name: displayName,
    is_minor: false,
    mode: 'standard',
    relationship: 'self',
    birth_year: 1990,
    sort_order: sortOrder,
    archived_at: null,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    deleted_at: null,
    server_version: 1,
  };
}

/** The signed-in account's membership on a profile. */
function membership(
  profileId: string,
  overrides: Partial<ProfileGuardianRow> = {},
): ProfileGuardianRow {
  return {
    id: `g-${profileId}`,
    profile_id: profileId,
    user_id: UID,
    role: 'caregiver',
    status: 'accepted',
    is_subject: true,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    server_version: 2,
    ...overrides,
  };
}

function entryRow(overrides: Partial<DayEntryRow> = {}): DayEntryRow {
  return {
    id: '01M2FWKNG0ZMH2ANCH7R2CM2E1',
    user_id: UID,
    profile_id: MAYA,
    local_date: TODAY,
    tz: 'UTC',
    flow: 'none',
    tags: [],
    note: null,
    note_private: false,
    pms: false,
    source: 'manual',
    created_at: '2026-09-30T08:00:00Z',
    updated_at: '2026-09-30T08:00:00Z',
    deleted_at: null,
    server_version: 3,
    ...overrides,
  };
}

function observationRow(overrides: Partial<ObservationRow> = {}): ObservationRow {
  return {
    id: '01M2FWKNG0ZMH2ANCH7R2CM2B1',
    day_entry_id: '01M2FWKNG0ZMH2ANCH7R2CM2E1',
    profile_id: MAYA,
    local_date: TODAY,
    tz: 'UTC',
    observed_at: null,
    category: 'spotting',
    code: 'spotting',
    value_num: null,
    value_text: null,
    unit: null,
    intensity: null,
    excluded: false,
    source: 'manual',
    created_at: '2026-09-30T08:00:00Z',
    updated_at: '2026-09-30T08:00:00Z',
    deleted_at: null,
    server_version: 4,
    ...overrides,
  };
}

function tagRow(code: string, displayName: string): ProfileTagRegistryRow {
  return {
    id: '01M2FWKNG0ZMH2ANCH7R2CM2T1',
    profile_id: MAYA,
    code,
    display_name: displayName,
    category: 'custom',
    intensity_enabled: false,
    created_at: '2026-09-01T00:00:00Z',
    updated_at: '2026-09-01T00:00:00Z',
    deleted_at: null,
    server_version: 5,
  };
}

/** A snapshot with Maya and Ada, the signed-in account the subject of both. */
function snapshot(overrides: Partial<SyncedData> = {}): SyncedData {
  return {
    ...emptySyncedData(),
    profiles: [profileRow(MAYA, 'Maya', 0), profileRow(ADA, 'Ada', 1)],
    profile_guardians: [membership(MAYA), membership(ADA)],
    ...overrides,
  };
}

/** Something logged today for Maya: flow, a tag and a note. */
const loggedToday = entryRow({ flow: 'medium', tags: ['cramps'], note: NOTE });

function useSnapshot(data: SyncedData) {
  vi.mocked(useSyncedData).mockReturnValue({
    data,
    isError: false,
    isPending: false,
    isLoading: false,
  } as ReturnType<typeof useSyncedData>);
}

function renderHome(initialPath = '/') {
  return render(
    <AppIntlProvider>
      <QueryClientProvider client={createAppQueryClient()}>
        <MemoryRouter initialEntries={[initialPath]}>
          <TodayPage />
        </MemoryRouter>
      </QueryClientProvider>
    </AppIntlProvider>,
  );
}

/** Waits for the home to be drawn: the status card's heading is the profile's name. */
async function homeOf(name: string) {
  await screen.findByRole('heading', { level: 1, name });
}

function cardLines(): string[] {
  return within(screen.getByTestId('today-log-card'))
    .getAllByRole('listitem')
    .map((item) => item.textContent ?? '');
}

const logTodayButton = () =>
  screen.queryByRole('link', { name: messages['householdLogToday'] });
const editTodayButton = () => screen.queryByRole('link', { name: messages['todayLogFabEdit'] });

describe('the home: what is logged today', () => {
  beforeEach(() => {
    // Only the clock's reading is fixed; timers run, so the page's own
    // waits behave as they do in a browser.
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(2026, 8, 30, 12, 0, 0));
    vi.mocked(useCurrentUserId).mockReturnValue({ data: UID } as ReturnType<
      typeof useCurrentUserId
    >);
    (window as unknown as { lunarlogDomain?: unknown }).lunarlogDomain = realModule;
  });

  afterEach(() => {
    delete (window as unknown as { lunarlogDomain?: unknown }).lunarlogDomain;
    cleanup();
    vi.useRealTimers();
  });

  describe('something logged today', () => {
    it('says what, in the app\'s words, under the title "Logged today"', async () => {
      useSnapshot(snapshot({ day_entries: [loggedToday] }));
      renderHome();
      await homeOf('Maya');
      const card = screen.getByRole('region', { name: messages['todayLogTitle'] });
      expect(card).toBe(screen.getByTestId('today-log-card'));
      expect(cardLines()).toEqual(['Medium flow', 'Cramps', 'Note added']);
    });

    it("never shows the note's text, anywhere on the page", async () => {
      useSnapshot(snapshot({ day_entries: [loggedToday] }));
      renderHome();
      await homeOf('Maya');
      expect(cardLines()).toContain(messages['todayLogNoteAdded']);
      for (const word of NOTE_WORDS) {
        expect(document.body.innerHTML).not.toContain(word);
      }
    });

    it("links Edit to today's day page", async () => {
      useSnapshot(snapshot({ day_entries: [loggedToday] }));
      renderHome();
      await homeOf('Maya');
      const edit = within(screen.getByTestId('today-log-card')).getByRole('link', {
        name: messages['todayLogEdit'],
      });
      expect(edit).toHaveAttribute('href', `/day/${MAYA}`);
    });

    it('sits directly under the estimate card and above the calendar', async () => {
      useSnapshot(snapshot({ day_entries: [loggedToday] }));
      renderHome();
      await homeOf('Maya');
      const card = screen.getByTestId('today-log-card');
      const status = screen.getByRole('heading', { level: 1, name: 'Maya' }).closest('section');
      const calendar = screen.getByRole('grid').closest('section');
      expect(card.previousElementSibling).toBe(status);
      expect(card.nextElementSibling).toBe(calendar);
    });

    it('the button reads "Edit today"', async () => {
      useSnapshot(snapshot({ day_entries: [loggedToday] }));
      renderHome();
      await homeOf('Maya');
      const button = editTodayButton();
      expect(button).not.toBeNull();
      expect(button).toHaveAttribute('href', `/day/${MAYA}`);
      expect(button).toHaveClass('home-log-today');
      expect(logTodayButton()).toBeNull();
    });

    it('reads spotting and readings from the observations of the entry', async () => {
      useSnapshot(
        snapshot({
          profiles: [
            { ...profileRow(MAYA, 'Maya', 0), bbt_unit: 'fahrenheit', weight_unit: 'kg' },
            profileRow(ADA, 'Ada', 1),
          ],
          day_entries: [entryRow({ flow: 'not_bleeding' })],
          observations: [
            observationRow(),
            observationRow({
              id: '01M2FWKNG0ZMH2ANCH7R2CM2B2',
              category: 'bbt',
              code: null,
              value_num: 37,
              unit: 'celsius',
            }),
          ],
        }),
      );
      renderHome();
      await homeOf('Maya');
      expect(cardLines()).toEqual(['Spotting', 'BBT (°F): 98.6']);
      expect(editTodayButton()).not.toBeNull();
    });

    it("names the profile's own tag, and only counts the ones never named", async () => {
      useSnapshot(
        snapshot({
          day_entries: [
            entryRow({
              tags: ['back_cracking', 'unprotected_sex', 'pregnancy_positive', 'some_new_code'],
            }),
          ],
          profile_tag_registry: [tagRow('back_cracking', 'Back cracking')],
        }),
      );
      renderHome();
      await homeOf('Maya');
      expect(cardLines()).toEqual(['Back cracking and 3 more']);
      const cardHtml = screen.getByTestId('today-log-card').innerHTML;
      for (const hidden of ['sex', 'Sex', 'regnancy', 'some_new_code', 'back_cracking']) {
        expect(cardHtml).not.toContain(hidden);
      }
    });
  });

  describe('nothing logged today', () => {
    it('says so in one quiet line, and the button reads "Log today"', async () => {
      useSnapshot(snapshot());
      renderHome();
      await homeOf('Maya');
      const card = screen.getByTestId('today-log-card');
      expect(card.textContent).toBe(messages['todayLogEmpty']);
      expect(screen.queryByText(messages['todayLogTitle'])).toBeNull();
      expect(logTodayButton()).toHaveAttribute('href', `/day/${MAYA}`);
      expect(editTodayButton()).toBeNull();
    });

    it('an entry left with nothing on it is nothing logged', async () => {
      useSnapshot(snapshot({ day_entries: [entryRow()] }));
      renderHome();
      await homeOf('Maya');
      expect(screen.getByTestId('today-log-card').textContent).toBe(messages['todayLogEmpty']);
      expect(logTodayButton()).not.toBeNull();
      expect(editTodayButton()).toBeNull();
    });

    it('a deleted entry is nothing logged', async () => {
      useSnapshot(
        snapshot({
          day_entries: [{ ...loggedToday, deleted_at: '2026-09-30T09:00:00Z' }],
        }),
      );
      renderHome();
      await homeOf('Maya');
      expect(screen.getByTestId('today-log-card').textContent).toBe(messages['todayLogEmpty']);
      expect(logTodayButton()).not.toBeNull();
    });

    it("yesterday's entry is not today's", async () => {
      useSnapshot(snapshot({ day_entries: [{ ...loggedToday, local_date: YESTERDAY }] }));
      renderHome();
      await homeOf('Maya');
      expect(screen.getByTestId('today-log-card').textContent).toBe(messages['todayLogEmpty']);
      expect(logTodayButton()).not.toBeNull();
      expect(editTodayButton()).toBeNull();
    });
  });

  describe('the active profile only', () => {
    it("another profile's log for today is not shown on this one", async () => {
      useSnapshot(snapshot({ day_entries: [{ ...loggedToday, profile_id: ADA }] }));
      renderHome();
      await homeOf('Maya');
      expect(screen.getByTestId('today-log-card').textContent).toBe(messages['todayLogEmpty']);
      expect(logTodayButton()).not.toBeNull();
    });

    it('and is shown on its own', async () => {
      useSnapshot(snapshot({ day_entries: [{ ...loggedToday, profile_id: ADA }] }));
      renderHome(`/?profile=${ADA}`);
      await homeOf('Ada');
      expect(cardLines()).toEqual(['Medium flow', 'Cramps', 'Note added']);
      expect(editTodayButton()).toHaveAttribute('href', `/day/${ADA}`);
    });
  });

  describe('someone who cannot log', () => {
    const viewer = (data: Partial<SyncedData>) =>
      snapshot({
        profile_guardians: [membership(MAYA, { role: 'viewer' }), membership(ADA)],
        ...data,
      });

    it('sees the summary without Edit, and is offered no button', async () => {
      useSnapshot(viewer({ day_entries: [loggedToday] }));
      renderHome();
      await homeOf('Maya');
      expect(cardLines()).toEqual(['Medium flow', 'Cramps', 'Note added']);
      expect(within(screen.getByTestId('today-log-card')).queryByRole('link')).toBeNull();
      expect(logTodayButton()).toBeNull();
      expect(editTodayButton()).toBeNull();
    });

    it('sees no card at all when nothing is logged', async () => {
      useSnapshot(viewer({}));
      renderHome();
      await homeOf('Maya');
      expect(screen.queryByTestId('today-log-card')).toBeNull();
      expect(screen.queryByText(messages['todayLogEmpty'])).toBeNull();
      expect(logTodayButton()).toBeNull();
    });
  });

  // The app's lens rule (issue #850): an accepted member whose row does not
  // carry the server's subject marker is a guardian, and a guardian's front
  // page never says what was logged.
  describe('a guardian', () => {
    const guardian = (role: string, data: Partial<SyncedData>) =>
      snapshot({
        profile_guardians: [membership(MAYA, { role, is_subject: false }), membership(ADA)],
        ...data,
      });

    it.each(['primary_guardian', 'co_parent', 'caregiver', 'viewer'])(
      'a %s sees no card when something is logged',
      async (role) => {
        useSnapshot(guardian(role, { day_entries: [loggedToday] }));
        renderHome();
        await homeOf('Maya');
        expect(screen.queryByTestId('today-log-card')).toBeNull();
        expect(screen.queryByText(messages['todayLogTitle'])).toBeNull();
        expect(screen.queryByText(messages['todayLogNoteAdded'])).toBeNull();
        for (const word of NOTE_WORDS) {
          expect(document.body.innerHTML).not.toContain(word);
        }
      },
    );

    it('sees no card when nothing is logged either', async () => {
      useSnapshot(guardian('primary_guardian', {}));
      renderHome();
      await homeOf('Maya');
      expect(screen.queryByTestId('today-log-card')).toBeNull();
      expect(screen.queryByText(messages['todayLogEmpty'])).toBeNull();
    });

    it('a row with no subject marker at all is a guardian', async () => {
      const row = membership(MAYA, { role: 'primary_guardian' });
      delete row.is_subject;
      useSnapshot(
        snapshot({ profile_guardians: [row, membership(ADA)], day_entries: [loggedToday] }),
      );
      renderHome();
      await homeOf('Maya');
      expect(screen.queryByTestId('today-log-card')).toBeNull();
    });

    it('who can log still gets the button, with its two labels', async () => {
      useSnapshot(guardian('co_parent', { day_entries: [loggedToday] }));
      renderHome();
      await homeOf('Maya');
      expect(editTodayButton()).toHaveAttribute('href', `/day/${MAYA}`);
      cleanup();

      useSnapshot(guardian('co_parent', {}));
      renderHome();
      await homeOf('Maya');
      expect(logTodayButton()).toHaveAttribute('href', `/day/${MAYA}`);
      expect(editTodayButton()).toBeNull();
    });

    it("the subject of one profile is still a guardian of another's", async () => {
      useSnapshot(
        guardian('primary_guardian', {
          day_entries: [
            loggedToday,
            { ...loggedToday, id: '01M2FWKNG0ZMH2ANCH7R2CM2E2', profile_id: ADA },
          ],
        }),
      );
      renderHome();
      await homeOf('Maya');
      expect(screen.queryByTestId('today-log-card')).toBeNull();
      cleanup();

      renderHome(`/?profile=${ADA}`);
      await homeOf('Ada');
      expect(cardLines()).toEqual(['Medium flow', 'Cramps', 'Note added']);
    });
  });

  describe('before the page can tell who is looking', () => {
    it('shows no card while the account id has not loaded', async () => {
      vi.mocked(useCurrentUserId).mockReturnValue({ data: undefined } as ReturnType<
        typeof useCurrentUserId
      >);
      useSnapshot(snapshot({ day_entries: [loggedToday] }));
      renderHome();
      await homeOf('Maya');
      expect(screen.queryByTestId('today-log-card')).toBeNull();
      expect(screen.queryByText(messages['todayLogNoteAdded'])).toBeNull();
    });
  });

  describe('when the domain module cannot answer', () => {
    it('shows no card and keeps "Log today", rather than a wrong answer', async () => {
      delete (window as unknown as { lunarlogDomain?: unknown }).lunarlogDomain;
      useSnapshot(snapshot({ day_entries: [loggedToday] }));
      renderHome();
      await screen.findByText(messages['overviewEstimateLoadError']);
      expect(screen.queryByTestId('today-log-card')).toBeNull();
      expect(logTodayButton()).not.toBeNull();
      expect(editTodayButton()).toBeNull();
    });
  });
});
