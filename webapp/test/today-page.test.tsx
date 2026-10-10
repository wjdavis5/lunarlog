import { QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { createAppQueryClient } from '../src/lib/queries';
import { resetFirstRunForTests } from '../src/lib/first-run';
import { AppIntlProvider } from '../src/i18n/i18n';
import messages from '../src/i18n/messages.en.json';
import { TodayPage } from '../src/pages/TodayPage';

/**
 * The profile home (issue #1253). The #1252 data-layer hooks are mocked at
 * the module boundary (the integration suite owns the live pull); the
 * domain module is a fake `window.lunarlogDomain` serving the committed
 * parity fixtures, so the page renders exactly the outputs the compiled
 * Dart engine produces for those request shapes.
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
    useSyncSignalsRefetch: vi.fn(),
  };
});

import { useHasSyncSession, useSyncedData } from '../src/lib/queries';
import { mergeSyncedData, emptySyncedData } from '../src/lib/domain';
import type { SyncedData } from '../src/lib/domain';
import type {
  CycleOverrideRow,
  DayEntryRow,
  ProfileGuardianRow,
  ProfileModeRow,
  ProfileRow,
} from '../src/lib/schemas';
import fixtures from './domain/fixtures.json';

const UID = '00000000-0000-4000-8000-0000000000u1';
const RICH_ID = '01M2FWKNG0ZMH2ANCH7R2CM2XZ';
const TEEN_ID = '01M2FWKNG0ZMH2ANCH7R2CM2YA';
const PREGNANT_ID = '01M2FWKNG0ZMH2ANCH7R2CM2YC';

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

function modeRow(profileId: string, mode: string): ProfileModeRow {
  return {
    profile_id: profileId,
    mode,
    mode_started_on: null,
    health_sync_consent: false,
    updated_at: '2026-01-01T00:00:00Z',
    server_version: 2,
  };
}

function guardianRow(profileId: string, isSubject = false): ProfileGuardianRow {
  return {
    // One membership row per profile. A shared id collapsed the three rows
    // into one when merged, leaving two profiles with no membership.
    id: `g-${profileId}`,
    profile_id: profileId,
    user_id: UID,
    role: 'primary_guardian',
    status: 'accepted',
    // The server's subject marker (issue #1818): rows without it read as
    // the guardian lens, as the phone's guardianLensFor does.
    is_subject: isSubject,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    server_version: 2,
  };
}

function entryRow(profileId: string, localDate: string, flow: string): DayEntryRow {
  return {
    id: `01M2FWKNG0ZMH2ANCH7R2CM2${localDate.replaceAll('-', '').slice(-4)}`,
    user_id: UID,
    profile_id: profileId,
    local_date: localDate,
    tz: 'UTC',
    flow,
    tags: [],
    note: null,
    note_private: false,
    pms: false,
    source: 'manual',
    created_at: '2026-09-01T00:00:00Z',
    updated_at: '2026-09-01T00:00:00Z',
    deleted_at: null,
    server_version: 3,
  };
}

function overrideRow(profileId: string, date: string): CycleOverrideRow {
  return {
    id: `01M2FWKNG0ZMH2ANCH7R2CM2${date.replaceAll('-', '').slice(-4)}X`,
    profile_id: profileId,
    cycle_start_date: date,
    excluded_from_average: true,
    manual_start: false,
    updated_at: '2026-09-01T00:00:00Z',
    deleted_at: null,
    server_version: 3,
  };
}

const syncedFixture = (): SyncedData =>
  mergeSyncedData(emptySyncedData(), {
    profiles: [
      profileRow(RICH_ID, 'Maya', 0),
      profileRow(PREGNANT_ID, 'Priya', 1),
      profileRow(TEEN_ID, 'Ada', 2),
    ],
    day_entries: [
      entryRow(RICH_ID, '2026-09-28', 'medium'),
      entryRow(RICH_ID, '2026-09-29', 'light'),
      entryRow(RICH_ID, '2026-09-30', 'medium'),
    ],
    observations: [],
    profile_modes: [modeRow(PREGNANT_ID, 'pregnancy')],
    cycle_overrides: [overrideRow(RICH_ID, '2026-08-15')],
    care_notes: [],
    visit_prep_items: [],
    profile_tag_registry: [],
    profile_guardians: [
      guardianRow(RICH_ID, true),
      guardianRow(PREGNANT_ID),
      guardianRow(TEEN_ID),
    ],
  });

// The shape the module mock answers with; the real hook carries more query
// fields, and the page reads only these four.
function syncedResult(data: SyncedData): ReturnType<typeof useSyncedData> {
  return {
    data,
    isError: false,
    isPending: false,
    isLoading: false,
  } as unknown as ReturnType<typeof useSyncedData>;
}

// The fake module answers with the committed parity fixtures - the exact
// envelopes the compiled Dart engine produces. A pregnancy life-stage
// request resolves to the suppressed fixture, the way the real engine
// branches; the recap, phase and BBT chart pin their cases by name (the
// BBT chart pins the empty case: the parity suite owns the populated ones);
// everything else resolves to that method's richest fixture.
interface FixtureCase {
  name: string;
  method: string;
  request: Record<string, unknown>;
  expected: { ok: boolean; data?: unknown; error?: string };
}

const fixtureCases = fixtures as FixtureCase[];

function fixtureEnvelope(method: string, request: Record<string, unknown>): unknown {
  const suppressed = method === 'predict' && request['lifecycleMode'] === 'pregnancy';
  // "What is logged today" follows the request too: this snapshot's entries
  // are dated in September, so on any real today the page asks about no
  // entry, and the engine's answer to that is "nothing logged". (The card
  // and the button's two labels are tested against the real compiled
  // module in today-page-today-log.test.tsx.)
  const nothingToday = method === 'todayLog' && (request['entry'] ?? null) === null;
  const wanted =
    method === 'cycleRecap'
      ? 'cycleRecap.completed-cycle'
      : method === 'bbtChart'
        ? 'bbtChart.empty'
        : method === 'phaseInsights'
          ? 'phaseInsights.statistical-cycle'
          : suppressed
            ? 'predict.suppressed-lifecycle'
            : nothingToday
              ? 'todayLog.no-entry'
              : undefined;
  const candidates = fixtureCases.filter((fixture) => fixture.method === method);
  const match =
    (wanted !== undefined
      ? fixtureCases.find((fixture) => fixture.name === wanted)
      : undefined) ?? candidates[candidates.length - 1];
  if (match === undefined) {
    return { ok: false, error: `no fixture for ${method}` };
  }
  return match.expected;
}

const fakeDomainModule = {
  version: '1',
  invoke: (method: string, requestJson: string) => {
    let request: Record<string, unknown> = {};
    try {
      request = JSON.parse(requestJson) as Record<string, unknown>;
    } catch {
      request = {};
    }
    return JSON.stringify(fixtureEnvelope(method, request));
  },
};

function renderHome(initialPath = '/') {
  const queryClient = createAppQueryClient();
  return render(
    <AppIntlProvider>
      <QueryClientProvider client={queryClient}>
        <MemoryRouter initialEntries={[initialPath]}>
          <TodayPage />
        </MemoryRouter>
      </QueryClientProvider>
    </AppIntlProvider>,
  );
}

describe('TodayPage — the profile home (issue #1253)', () => {
  beforeEach(() => {
    vi.mocked(useHasSyncSession).mockReturnValue(true);
    // Re-establish the default snapshot every case: a case that swaps in
    // emptySyncedData() must not leak into the next one (mockClear clears
    // calls, not the implementation).
    vi.mocked(useSyncedData).mockImplementation(() => syncedResult(syncedFixture()));
    resetFirstRunForTests();
    (window as unknown as { lunarlogDomain?: unknown }).lunarlogDomain = fakeDomainModule;
  });

  afterEach(() => {
    delete (window as unknown as { lunarlogDomain?: unknown }).lunarlogDomain;
    cleanup();
  });

  it('shows the welcome while signed out, not an empty Profiles page', () => {
    vi.mocked(useHasSyncSession).mockReturnValue(false);
    renderHome();
    expect(screen.getByText(messages['webHomeNeedsSignIn'] ?? 'missing')).toBeInTheDocument();
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      messages['webWelcomeTitle'] ?? 'missing',
    );
  });

  // The BBT chart section rides the same domain call pattern as the
  // estimate and history (issue #1796).
  it('renders the BBT chart section from the domain module', async () => {
    renderHome();
    await screen.findByRole('heading', { name: 'Maya' });
    expect(screen.getByText(messages['bbtChartEmptyTitle'] ?? 'missing')).toBeInTheDocument();
  });

  // The recap card rides the same domain call pattern as the estimate and
  // history (issue #1796); the fake module answers the completed-cycle case.
  it('renders the recap card from the domain module', async () => {
    renderHome();
    await screen.findByRole('heading', { name: 'Maya' });
    expect(screen.getByTestId('cycle-recap-card')).toBeInTheDocument();
  });

  // Issue #1818: the phone hides the recap from guardians entirely
  // (`_recapSection` returns nothing under the guardian lens); the web used
  // to show it to whoever was viewing. Priya's membership carries no
  // is_subject marker, so this account sees her profile as a guardian.
  it('hides the recap from a guardian', async () => {
    renderHome();
    await screen.findByRole('heading', { name: 'Maya' });
    expect(screen.getByTestId('cycle-recap-card')).toBeInTheDocument();

    fireEvent.change(
      screen.getByLabelText(messages['webHomeProfileSwitcherLabel'] ?? 'missing'),
      { target: { value: PREGNANT_ID } },
    );
    await screen.findByRole('heading', { name: 'Priya' });
    expect(screen.queryByTestId('cycle-recap-card')).not.toBeInTheDocument();
  });

  // Issue #1819: a dismissal is scoped to its profile and cycle. This
  // fixture's two subject profiles share one cycle start (the fake module
  // answers the same completed-cycle recap for both), which used to share
  // one dismissal.
  it('scopes a recap dismissal to its profile', async () => {
    vi.mocked(useSyncedData).mockImplementation(() =>
      syncedResult(
        mergeSyncedData(emptySyncedData(), {
          profiles: [profileRow(RICH_ID, 'Maya', 0), profileRow(PREGNANT_ID, 'Priya', 1)],
          day_entries: [],
          observations: [],
          profile_modes: [modeRow(PREGNANT_ID, 'pregnancy')],
          cycle_overrides: [],
          care_notes: [],
          visit_prep_items: [],
          profile_tag_registry: [],
          profile_guardians: [guardianRow(RICH_ID, true), guardianRow(PREGNANT_ID, true)],
        }),
      ),
    );
    renderHome();
    await screen.findByRole('heading', { name: 'Maya' });
    fireEvent.click(
      screen.getByRole('button', { name: messages['cycleRecapDismissLabel'] ?? 'missing' }),
    );
    expect(screen.queryByTestId('cycle-recap-card')).not.toBeInTheDocument();

    const switcher = screen.getByLabelText(
      messages['webHomeProfileSwitcherLabel'] ?? 'missing',
    );
    fireEvent.change(switcher, { target: { value: PREGNANT_ID } });
    await screen.findByRole('heading', { name: 'Priya' });
    expect(screen.getByTestId('cycle-recap-card')).toBeInTheDocument();

    fireEvent.change(switcher, { target: { value: RICH_ID } });
    await screen.findByRole('heading', { name: 'Maya' });
    expect(screen.queryByTestId('cycle-recap-card')).not.toBeInTheDocument();
  });

  // First-run orientation (issue #1795): a signed-in account with no
  // profiles gets one short welcome before the compact empty state.
  describe('first-run orientation (issue #1795)', () => {
    beforeEach(() => {
      vi.mocked(useSyncedData).mockReturnValue(syncedResult(emptySyncedData()));
    });

    it('orients a new account and links to the profile picker', () => {
      renderHome();
      expect(screen.getByText(messages['webFirstRunTitle'] ?? 'missing')).toBeInTheDocument();
      expect(screen.getByText(messages['webFirstRunBody'] ?? 'missing')).toBeInTheDocument();
      expect(
        screen.getByText(messages['webFirstRunDataLine'] ?? 'missing'),
      ).toBeInTheDocument();
      expect(
        screen.getByRole('link', { name: messages['webFirstRunCreateAction'] ?? 'missing' }),
      ).toHaveAttribute('href', '/profiles');
    });

    it('Continue dismisses to the compact empty state', () => {
      renderHome();
      fireEvent.click(
        screen.getByRole('button', {
          name: messages['webFirstRunContinueAction'] ?? 'missing',
        }),
      );
      expect(
        screen.queryByText(messages['webFirstRunTitle'] ?? 'missing'),
      ).not.toBeInTheDocument();
      expect(
        screen.getByText(messages['profilePickerEmptyTitle'] ?? 'missing'),
      ).toBeInTheDocument();
    });

    it('a dismissed card stays dismissed when the page mounts again in the session', () => {
      renderHome();
      fireEvent.click(
        screen.getByRole('button', {
          name: messages['webFirstRunContinueAction'] ?? 'missing',
        }),
      );
      cleanup();
      renderHome();
      expect(
        screen.queryByText(messages['webFirstRunTitle'] ?? 'missing'),
      ).not.toBeInTheDocument();
      expect(
        screen.getByText(messages['profilePickerEmptyTitle'] ?? 'missing'),
      ).toBeInTheDocument();
    });

    // Issue #1806: `live` is empty while the snapshot pulls, which must not
    // read as "no profiles" - the welcome card flashed at returning users.
    it('shows neither card while the snapshot is still loading', () => {
      vi.mocked(useSyncedData).mockReturnValue({
        data: undefined,
        isError: false,
        isPending: true,
        isLoading: true,
      } as unknown as ReturnType<typeof useSyncedData>);
      renderHome();
      expect(
        screen.queryByText(messages['webFirstRunTitle'] ?? 'missing'),
      ).not.toBeInTheDocument();
      expect(
        screen.queryByText(messages['profilePickerEmptyTitle'] ?? 'missing'),
      ).not.toBeInTheDocument();
    });
  });

  // The symptom-trends section rides the same domain call pattern as the
  // estimate and history (issue #1796).
  it('renders the symptom-trends section from the domain module', async () => {
    renderHome();
    await screen.findByRole('heading', { name: 'Maya' });
    expect(screen.getByText(messages['symptomTrendsTitle'] ?? 'missing')).toBeInTheDocument();
  });

  // The phase card rides the same domain call pattern (issue #1796); the
  // fake module answers the statistical-cycle case.
  it('renders the phase card from the domain module', async () => {
    renderHome();
    await screen.findByRole('heading', { name: 'Maya' });
    expect(screen.getByTestId('phase-range')).toBeInTheDocument();
  });

  it('renders the estimate card from the domain module for the first profile', async () => {
    renderHome();
    // The status card carries the active profile's name as its heading and
    // the domain's own output (the committed active-prediction fixture).
    expect(await screen.findByRole('heading', { name: 'Maya' })).toBeInTheDocument();
    expect(
      screen.getByText(messages['webHomeNextEstimateLabel'] ?? 'missing'),
    ).toBeInTheDocument();
    expect(
      screen.getByText(messages['webHomeEstimateDisclaimer'] ?? 'missing'),
    ).toBeInTheDocument();
  });

  // The page exists so someone can log today. That action used to be a
  // text link under everything else, labelled "Today" like the header link
  // that goes home.
  it('offers Log today for the active profile, at the top', async () => {
    renderHome();
    const logToday = await screen.findByRole('link', {
      name: messages['householdLogToday'] ?? 'missing',
    });
    expect(logToday).toHaveAttribute('href', `/day/${RICH_ID}`);
    // It sits in the switcher row, ahead of the cards.
    expect(logToday.closest('.home-switcher')).not.toBeNull();
  });

  it('has no second link called "Today"', async () => {
    renderHome();
    await screen.findByRole('link', { name: messages['householdLogToday'] ?? 'missing' });
    // The calendar keeps its "Today" button (jump to this month). No link
    // on the page carries that name: the header owns it.
    expect(
      screen.queryAllByRole('link', { name: messages['calendarTodayTooltip'] ?? 'missing' }),
    ).toHaveLength(0);
  });

  it('links to the guardians of the active profile from the switcher row', async () => {
    renderHome();
    const guardians = await screen.findByRole('link', {
      name: messages['profilePickerMenuGuardians'] ?? 'missing',
    });
    expect(guardians).toHaveAttribute('href', `/profile/${RICH_ID}/guardians`);
    expect(guardians.closest('.home-switcher')).not.toBeNull();
  });

  // Guardian notes and care notes had a page and nothing that linked to it.
  it('links to the notes of the active profile from the switcher row', async () => {
    renderHome();
    const notes = await screen.findByRole('link', {
      name: messages['webDayNotesSection'] ?? 'missing',
    });
    expect(notes).toHaveAttribute('href', `/profile/${RICH_ID}/notes`);
    expect(notes.closest('.home-switcher')).not.toBeNull();
  });

  it('does not offer Log today to a viewer, who cannot log', async () => {
    const fixture = syncedFixture();
    vi.mocked(useSyncedData).mockReturnValue({
      data: {
        ...fixture,
        profile_guardians: fixture.profile_guardians.map((row) => ({
          ...row,
          role: 'viewer',
        })),
      },
      isError: false,
      isPending: false,
      isLoading: false,
    } as ReturnType<typeof useSyncedData>);
    renderHome();
    // The page has rendered (the guardians link is there) and the button
    // is not.
    await screen.findByRole('link', {
      name: messages['profilePickerMenuGuardians'] ?? 'missing',
    });
    expect(
      screen.queryByRole('link', { name: messages['householdLogToday'] ?? 'missing' }),
    ).toBeNull();
  });

  it('renders the month header and grid for the current month', async () => {
    renderHome();
    const month = new Intl.DateTimeFormat('en', { month: 'long' }).format(new Date());
    const year = String(new Date().getFullYear());
    const expectedHeader = (messages['calendarMonthYearLabel'] ?? '')
      .replace('{month}', month)
      .replace('{year}', year);
    expect(await screen.findByText(expectedHeader)).toBeInTheDocument();
    expect(screen.getByRole('grid')).toBeInTheDocument();
    // Every rendered day links into the day editor for the active profile.
    const dayLinks = screen
      .getAllByRole('link')
      .filter((link) => link.getAttribute('href')?.includes(`/day/${RICH_ID}?date=`));
    expect(dayLinks.length).toBeGreaterThanOrEqual(28);
  });

  it('renders the month calendar and history for the whole history, not just the estimate', async () => {
    renderHome();
    // The cycle history section renders the domain's own view statistics.
    expect(
      await screen.findByText(messages['cycleHistoryTitle'] ?? 'missing'),
    ).toBeInTheDocument();
    expect(
      screen.getByText(messages['cycleComparisonScreenTitle'] ?? 'missing'),
    ).toBeInTheDocument();
  });

  it('renders suppression copy for a pregnancy-mode profile (mode suppresses predictions)', async () => {
    renderHome('/?profile=01M2FWKNG0ZMH2ANCH7R2CM2YC');
    expect(await screen.findByRole('heading', { name: 'Priya' })).toBeInTheDocument();
    expect(
      screen.getByText(messages['predictionsSuppressedTitle'] ?? 'missing'),
    ).toBeInTheDocument();
    expect(
      screen.getByText(
        (messages['predictionsSuppressedByModeBody'] ?? '').replace(
          '{mode}',
          messages['webDayModePregnancy'] ?? 'missing',
        ),
      ),
    ).toBeInTheDocument();
  });

  it('switches profiles from the switcher and keeps the URL in step', async () => {
    renderHome();
    const switcher = await screen.findByLabelText(
      messages['webHomeProfileSwitcherLabel'] ?? 'missing',
    );
    expect((switcher as HTMLSelectElement).value).toBe(RICH_ID);
    fireEvent.change(switcher, { target: { value: PREGNANT_ID } });
    // The selection re-renders the home for Priya (suppression copy) and
    // the address bar names what is on screen.
    expect(await screen.findByRole('heading', { name: 'Priya' })).toBeInTheDocument();
    await waitFor(() => {
      expect((switcher as HTMLSelectElement).value).toBe(PREGNANT_ID);
    });
  });
});
