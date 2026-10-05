import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page, type Route } from '@playwright/test';

/**
 * The profile home's end-to-end slice (issue #1253): profile switching,
 * month navigation, and a profile whose life-stage mode suppresses
 * predictions — against the real built app and the real compiled domain
 * module, with the network mocked at the fetch boundary.
 *
 * The interception fulfils the Worker's `/auth/session` (a token in page
 * memory, the #1250 contract) and every Supabase REST call the #1252 data
 * layer makes (`sync_pull`, `sync_watermark`), so no backend is reached.
 * The one uninterceptable surface is the `sync_signals` Realtime
 * websocket (Playwright cannot route WebSockets): with an unauthorised
 * token the server refuses the channel subscription and nothing is
 * delivered — the wake signal is only ever a refetch trigger (#1252),
 * never data, so the assertions below are unaffected.
 *
 * The suite self-skips on an unconfigured build (a fork's `VITE_SUPABASE_*`
 * are empty, so the app never creates a client and never signs in); this
 * repo's CI always builds configured.
 */

const messages = JSON.parse(
  readFileSync(join(import.meta.dirname, '..', 'src', 'i18n', 'messages.en.json'), 'utf8'),
) as Record<string, string>;

const UID = '00000000-0000-4000-8000-00000000000u1';
const RICH_ID = '01M2FWKNG0ZMH2ANCH7R2CM2XZ';
const PREGNANT_ID = '01M2FWKNG0ZMH2ANCH7R2CM2YC';

interface Row {
  [key: string]: unknown;
}

function profile(id: string, displayName: string, sortOrder: number): Row {
  return {
    id,
    user_id: UID,
    display_name: displayName,
    is_minor: false,
    sort_order: sortOrder,
    archived_at: null,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    deleted_at: null,
    server_version: 1,
    mode: 'standard',
    irregular_framing: null,
    birth_year: 1990,
    relationship: 'self',
    last_period_start: null,
    typical_cycle_length_days: null,
    typical_period_length_days: null,
    bbt_unit: 'celsius',
    weight_unit: 'kg',
    tracking_preferences: null,
  };
}

function entry(id: string, profileId: string, localDate: string, flow: string): Row {
  return {
    id,
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
    source_id: null,
    import_id: null,
    created_at: '2026-09-01T00:00:00Z',
    updated_at: '2026-09-01T00:00:00Z',
    deleted_at: null,
    server_version: 3,
  };
}

/** The snapshot `sync_pull` answers with — deterministic, ULID ids. */
const snapshot = {
  profiles: [profile(RICH_ID, 'Maya', 0), profile(PREGNANT_ID, 'Priya', 1)],
  day_entries: [
    entry('01M2FWKNG0ZMH2ANCH7R2CM2E1', RICH_ID, '2026-09-28', 'medium'),
    entry('01M2FWKNG0ZMH2ANCH7R2CM2E2', RICH_ID, '2026-09-29', 'light'),
    entry('01M2FWKNG0ZMH2ANCH7R2CM2E3', RICH_ID, '2026-09-30', 'medium'),
  ],
  observations: [],
  profile_modes: [
    {
      profile_id: PREGNANT_ID,
      mode: 'pregnancy',
      mode_started_on: null,
      estimated_due_date: null,
      postpartum_birth_date: null,
      birth_control_method: null,
      birth_control_started_on: null,
      birth_control_stopped_on: null,
      health_sync_consent: false,
      updated_at: '2026-01-01T00:00:00Z',
      server_version: 2,
    },
  ],
  cycle_overrides: [],
  care_notes: [],
  visit_prep_items: [],
  profile_tag_registry: [],
  profile_guardians: [
    {
      id: 'a0000000-0000-4000-8000-000000000001',
      profile_id: RICH_ID,
      user_id: UID,
      role: 'primary_guardian',
      status: 'accepted',
      display_name: null,
      invited_by: null,
      is_subject: true,
      revoked_at: null,
      created_at: '2026-01-01T00:00:00Z',
      updated_at: '2026-01-01T00:00:00Z',
      server_version: 2,
    },
    {
      id: 'a0000000-0000-4000-8000-000000000002',
      profile_id: PREGNANT_ID,
      user_id: UID,
      role: 'primary_guardian',
      status: 'accepted',
      display_name: null,
      invited_by: null,
      is_subject: true,
      revoked_at: null,
      created_at: '2026-01-01T00:00:00Z',
      updated_at: '2026-01-01T00:00:00Z',
      server_version: 2,
    },
  ],
};

async function json(route: Route, body: unknown): Promise<void> {
  await route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify(body),
  });
}

/**
 * Installs the signed-in fetch facade. Registration order matters: the
 * catch-all goes first so Playwright matches the specific routes after
 * it (later registrations win).
 */
async function installSignedInFacade(page: Page): Promise<void> {
  await page.route('**/rest/v1/**', (route) =>
    json(route, { message: 'e2e: unmocked rest call', details: route.request().url() }),
  );
  await page.route('**/rest/v1/rpc/sync_pull', (route) => json(route, snapshot));
  await page.route('**/rest/v1/rpc/sync_watermark', (route) => json(route, 100_000));
  await page.route('**/auth/session', (route) =>
    json(route, {
      access_token: 'e2e-access-token',
      expires_in: 3600,
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      user: { id: UID, email: 'e2e@example.com' },
    }),
  );
}

let configuredProbe: boolean | null = null;

/** True when the build carries Supabase config (the app signs in at all). */
async function buildIsConfigured(page: Page): Promise<boolean> {
  if (configuredProbe !== null) return configuredProbe;
  await installSignedInFacade(page);
  await page.goto('/');
  const signInCopy = page.getByText(messages['webHomeNeedsSignIn'] ?? 'missing');
  configuredProbe = !(await signInCopy.isVisible().catch(() => false));
  return configuredProbe;
}

test.describe('the profile home (issue #1253)', () => {
  test.beforeEach(async ({ page }) => {
    await installSignedInFacade(page);
  });

  test('switching profiles swaps the home content and the address bar', async ({ page }) => {
    test.skip(!(await buildIsConfigured(page)), 'unconfigured build (fork); runs in CI');
    await page.goto('/');
    // Maya first (lowest sort order): the status card carries her name.
    await expect(page.getByRole('heading', { name: 'Maya' })).toBeVisible();
    const switcher = page.getByLabel(messages['webHomeProfileSwitcherLabel'] ?? 'Profile');
    await expect(switcher).toHaveValue(RICH_ID);
    // A signed-in home is axe-clean (WCAG 2.2 AA is the issue's bar).
    const axe = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze();
    expect(axe.violations).toEqual([]);

    await switcher.selectOption(PREGNANT_ID);
    await expect(page).toHaveURL(new RegExp(`profile=${PREGNANT_ID}`));
    await expect(page.getByRole('heading', { name: 'Priya' })).toBeVisible();
    // The switch shows Priya's suppression card (pregnancy mode) instead
    // of an estimate — see the dedicated test below for its copy.
    await expect(page.getByText(messages['predictionsSuppressedTitle'] ?? '')).toBeVisible();
    // And the address bar names what is on screen.
    await expect(page).toHaveURL(new RegExp(`profile=${PREGNANT_ID}`));
  });

  test('month navigation walks the grid and Today returns', async ({ page }) => {
    test.skip(!(await buildIsConfigured(page)), 'unconfigured build (fork); runs in CI');
    await page.goto('/');
    const grid = page.getByRole('grid');
    await expect(grid).toBeVisible();
    const currentTitle = await page.locator('#home-calendar-title').textContent();
    expect(currentTitle).not.toBeNull();

    const now = new Date();
    const monthName = (offset: number): string => {
      const d = new Date(Date.UTC(now.getFullYear(), now.getMonth() + offset, 1));
      return new Intl.DateTimeFormat('en', { month: 'long', timeZone: 'UTC' }).format(d);
    };
    const yearOf = (offset: number): number => {
      const d = new Date(Date.UTC(now.getFullYear(), now.getMonth() + offset, 1));
      return d.getUTCFullYear();
    };

    // Next month: the header names it.
    await page
      .getByRole('button', { name: messages['calendarNextMonthTooltip'] ?? '' })
      .click();
    await expect(page.locator('#home-calendar-title')).toHaveText(
      `${monthName(1)} ${yearOf(1)}`,
    );

    // Previous month: back to the current one.
    await page
      .getByRole('button', { name: messages['calendarPreviousMonthTooltip'] ?? '' })
      .click();
    await expect(page.locator('#home-calendar-title')).toHaveText(
      `${monthName(0)} ${yearOf(0)}`,
    );

    // From a month away, Today snaps back to the current month.
    await page
      .getByRole('button', { name: messages['calendarNextMonthTooltip'] ?? '' })
      .click();
    await page.getByRole('button', { name: messages['calendarTodayTooltip'] ?? '' }).click();
    await expect(page.locator('#home-calendar-title')).toHaveText(
      `${monthName(0)} ${yearOf(0)}`,
    );
  });

  test('a pregnancy-mode profile shows suppression copy, never an estimate', async ({
    page,
  }) => {
    test.skip(!(await buildIsConfigured(page)), 'unconfigured build (fork); runs in CI');
    await page.goto(`/?profile=${PREGNANT_ID}`);
    await expect(page.getByRole('heading', { name: 'Priya' })).toBeVisible();
    const mode = messages['webDayModePregnancy'] ?? 'Pregnancy';
    await expect(
      page.getByText(
        (messages['predictionsSuppressedByModeBody'] ?? '').replace('{mode}', mode),
      ),
    ).toBeVisible();
    // No estimate heading anywhere on the page.
    expect(page.getByText(messages['webHomeNextEstimateLabel'] ?? '')).toHaveCount(0);
    // The calendar itself still renders (logged days only, no forecast bands).
    await expect(page.getByRole('grid')).toBeVisible();
    // And the suppressed home is axe-clean too.
    const axe = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze();
    expect(axe.violations).toEqual([]);
  });
});

// The day editor on a cold load: a reload, a bookmark, a link opened in a
// new tab. This client keeps nothing at rest, so every one of those starts
// with no session in memory. The page used to start its pull straight
// away; the pull restored the session part-way through, the cache then
// discarded it as having changed account, and the editor reported "You
// don't have access to this profile" for a profile the reader owns.
test.describe('the day editor on a cold load', () => {
  test.beforeEach(async ({ page }) => {
    await installSignedInFacade(page);
  });

  test('opens the profile, not a no-access error', async ({ page }) => {
    test.skip(!(await buildIsConfigured(page)), 'unconfigured build (fork); runs in CI');
    // A full navigation: a new document, nothing carried over in memory.
    await page.goto(`/day/${RICH_ID}?date=2026-09-30`);
    await expect(page.getByRole('heading', { level: 1 })).toContainText('Maya');
    await expect(
      page.getByRole('button', { name: messages['webDaySave'] ?? 'Save' }),
    ).toBeVisible();
    await expect(page.getByText(messages['webDayNoAccess'] ?? 'missing')).toHaveCount(0);
  });

  test('still opens after a reload', async ({ page }) => {
    test.skip(!(await buildIsConfigured(page)), 'unconfigured build (fork); runs in CI');
    await page.goto(`/day/${RICH_ID}?date=2026-09-30`);
    await expect(page.getByRole('heading', { level: 1 })).toContainText('Maya');
    await page.reload();
    await expect(page.getByRole('heading', { level: 1 })).toContainText('Maya');
    await expect(page.getByText(messages['webDayNoAccess'] ?? 'missing')).toHaveCount(0);
  });
});
