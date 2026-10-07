import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

import {
  installSignedInFacade,
  json,
  loggedSnapshot,
  messages,
  PREGNANT_ID,
  RICH_ID,
  snapshot,
  UID,
} from './fixtures';

/**
 * The profile home's end-to-end slice (issue #1253): profile switching,
 * month navigation, and a profile whose life-stage mode suppresses
 * predictions — against the real built app and the real compiled domain
 * module, with the network mocked at the fetch boundary.
 *
 * The fabricated world and its fetch facade live in ./fixtures (shared
 * with the site's browser CTA capture, issue #1431). The interception
 * fulfils the Worker's `/auth/session` (a token in page memory, the #1250
 * contract) and every Supabase REST call the #1252 data layer makes
 * (`sync_pull`, `sync_watermark`), so no backend is reached. The one
 * uninterceptable surface is the `sync_signals` Realtime websocket
 * (Playwright cannot route WebSockets): with an unauthorised token the
 * server refuses the channel subscription and nothing is delivered — the
 * wake signal is only ever a refetch trigger (#1252), never data, so the
 * assertions below are unaffected.
 *
 * The suite self-skips on an unconfigured build (a fork's `VITE_SUPABASE_*`
 * are empty, so the app never creates a client and never signs in); this
 * repo's CI always builds configured.
 */

let configuredProbe: boolean | null = null;

/**
 * True when the build carries Supabase config (the app signs in at all).
 *
 * It waits for the signed-in home rather than reading the page once. The
 * signed-out welcome is also what a configured build shows for the moment
 * it takes the session to be restored, so a single look straight after
 * the load sometimes caught it and reported "unconfigured": the test was
 * then skipped, not failed, and nothing said so (about one run in three
 * skipped a test here). An unconfigured build never leaves the welcome,
 * so there the wait runs out, once per worker.
 */
async function buildIsConfigured(page: Page): Promise<boolean> {
  if (configuredProbe !== null) return configuredProbe;
  await installSignedInFacade(page);
  await page.goto('/');
  configuredProbe = await page
    .getByLabel(messages['webHomeProfileSwitcherLabel'] ?? 'Profile')
    .waitFor({ state: 'visible', timeout: 5_000 })
    .then(
      () => true,
      () => false,
    );
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

// What is logged today, on the home (the browser version of the app's
// Today log card, issue #1489): a card under the estimate that says what
// is logged for today, and a button that reads "Edit today" once something
// is. The rules are the app's own, asked of the real compiled domain
// module; the page's clock is fixed so "today" is a day the snapshot has
// rows for, or has none for.
test.describe('what is logged today, on the home', () => {
  /** Noon, local time, on the given day: the page reads this as its clock. */
  async function setToday(page: Page, year: number, month: number, day: number) {
    await page.clock.setFixedTime(new Date(year, month - 1, day, 12, 0, 0));
  }

  test.beforeEach(async ({ page }) => {
    await installSignedInFacade(page);
  });

  test('something logged: the card says what, and the button reads Edit today', async ({
    page,
  }) => {
    test.skip(!(await buildIsConfigured(page)), 'unconfigured build (fork); runs in CI');
    await page.route('**/rest/v1/rpc/sync_pull', (route) => json(route, loggedSnapshot(true)));
    await setToday(page, 2026, 9, 30);
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Maya' })).toBeVisible();

    const card = page.getByRole('region', { name: messages['todayLogTitle'] ?? 'missing' });
    await expect(card).toBeVisible();
    // The app's lines, in the app's order: flow, tags (the sex-life tag is
    // counted, never named), the PMS marker, the reading, the note.
    await expect(card.getByRole('listitem')).toHaveText([
      'Medium flow',
      'Cramps, Fatigue and 1 more',
      'PMS',
      'BBT (°C): 36.7',
      messages['todayLogNoteAdded'] ?? 'missing',
    ]);
    await expect(
      card.getByRole('link', { name: messages['todayLogEdit'] ?? 'missing' }),
    ).toHaveAttribute('href', `/day/${RICH_ID}`);
    await expect(
      page.getByRole('link', { name: messages['todayLogFabEdit'] ?? 'missing', exact: true }),
    ).toHaveAttribute('href', `/day/${RICH_ID}`);
    await expect(
      page.getByRole('link', { name: messages['householdLogToday'] ?? 'missing' }),
    ).toHaveCount(0);

    // It sits between the estimate card and the calendar.
    const order = await page.evaluate(() => {
      const sections = [...document.querySelectorAll('.home-stack > section')];
      return sections.map((section) => section.getAttribute('aria-labelledby'));
    });
    expect(order.slice(0, 3)).toEqual([
      'home-estimate-title',
      'home-today-log-title',
      'home-calendar-title',
    ]);

    // The note's text went into the domain call and came back as the one
    // fact that a note exists: it is nowhere in the page.
    const html = await page.content();
    for (const word of ['zebra', 'crossing', 'dentist']) {
      expect(html).not.toContain(word);
    }
    // And the card does not name the tag it only counted. (The calendar's
    // layer picker below lists every tag there is, logged or not, so this
    // is asked of the card alone.)
    const cardHtml = await card.innerHTML();
    for (const hidden of ['nprotected', 'sex', 'Sex']) {
      expect(cardHtml).not.toContain(hidden);
    }

    const axe = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze();
    expect(axe.violations).toEqual([]);
  });

  test('nothing logged: one quiet line, and the button reads Log today', async ({ page }) => {
    test.skip(!(await buildIsConfigured(page)), 'unconfigured build (fork); runs in CI');
    await page.route('**/rest/v1/rpc/sync_pull', (route) => json(route, loggedSnapshot(true)));
    // The day after: nothing is dated 1 October.
    await setToday(page, 2026, 10, 1);
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Maya' })).toBeVisible();

    await expect(page.getByText(messages['todayLogEmpty'] ?? 'missing')).toBeVisible();
    // Exact: "Nothing logged today yet" contains the title's words.
    await expect(
      page.getByText(messages['todayLogTitle'] ?? 'missing', { exact: true }),
    ).toHaveCount(0);
    await expect(page.getByTestId('today-log-card')).toHaveText(
      messages['todayLogEmpty'] ?? 'missing',
    );
    await expect(
      page.getByRole('link', { name: messages['householdLogToday'] ?? 'missing' }),
    ).toHaveAttribute('href', `/day/${RICH_ID}`);
    await expect(
      page.getByRole('link', { name: messages['todayLogFabEdit'] ?? 'missing', exact: true }),
    ).toHaveCount(0);

    const axe = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze();
    expect(axe.violations).toEqual([]);
  });

  // The app's lens rule (issue #850): a member whose row does not carry the
  // server's subject marker is a guardian, and a guardian's front page does
  // not say what was logged.
  test('a guardian sees no card, logged or not, and keeps the button', async ({ page }) => {
    test.skip(!(await buildIsConfigured(page)), 'unconfigured build (fork); runs in CI');
    await page.route('**/rest/v1/rpc/sync_pull', (route) => json(route, loggedSnapshot(false)));
    await setToday(page, 2026, 9, 30);
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Maya' })).toBeVisible();
    await expect(page.getByRole('grid')).toBeVisible();

    await expect(
      page.getByText(messages['todayLogTitle'] ?? 'missing', { exact: true }),
    ).toHaveCount(0);
    await expect(page.getByText(messages['todayLogNoteAdded'] ?? 'missing')).toHaveCount(0);
    await expect(page.getByText(messages['todayLogEmpty'] ?? 'missing')).toHaveCount(0);
    // A guardian who may log is still offered the button, with its label.
    await expect(
      page.getByRole('link', { name: messages['todayLogFabEdit'] ?? 'missing', exact: true }),
    ).toHaveAttribute('href', `/day/${RICH_ID}`);
    expect(await page.content()).not.toContain('zebra');
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
    // The day editor is axe-clean too, and has one navigation landmark:
    // its back link used to be a second, unnamed one beside the header's.
    const axe = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa'])
      .withRules(['landmark-unique'])
      .analyze();
    expect(axe.violations).toEqual([]);
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

// The header sits above every page and is never unmounted, so it has to
// follow the session on its own. Signing in on the page used to leave it
// offering "Sign in", with no "Today" or "Account", until a reload; and
// signing out left the signed-in links up. Both are checked here without a
// reload, against the Worker's routes as the page really calls them.
test.describe('the header follows the session without a reload', () => {
  test('signing in, then out, on the page', async ({ page }) => {
    let signedIn = false;
    const session = {
      access_token: 'e2e-access-token',
      expires_in: 3600,
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      user: { id: UID, email: 'e2e@example.com' },
    };
    await page.route('**/rest/v1/**', (route) => json(route, snapshot));
    await page.route('**/auth/session', (route) =>
      signedIn
        ? json(route, session)
        : route.fulfill({
            status: 401,
            contentType: 'application/json',
            body: JSON.stringify({ error: 'unauthorized' }),
          }),
    );
    await page.route('**/auth/password/sign-in', (route) => {
      signedIn = true;
      return json(route, session);
    });
    await page.route('**/auth/sign-out', (route) => {
      signedIn = false;
      return json(route, { ok: true });
    });

    const header = page.getByRole('banner');
    const signInLink = header.getByRole('link', {
      name: messages['accountSectionSignIn'] ?? 'missing',
    });
    const signOutLink = header.getByRole('link', {
      name: messages['webAuthSignOutAction'] ?? 'missing',
    });
    const accountLink = header.getByRole('link', {
      name: messages['accountSectionTitle'] ?? 'missing',
    });
    const todayLink = header.getByRole('link', {
      name: messages['calendarTodayTooltip'] ?? 'missing',
    });

    await page.goto('/sign-in');
    await expect(signInLink).toBeVisible();
    await expect(accountLink).toHaveCount(0);

    await page
      .getByLabel(messages['accountSignInEmailLabel'] ?? 'missing')
      .fill('e2e@example.com');
    await page
      .getByLabel(messages['accountSignInPasswordLabel'] ?? 'missing')
      .fill('a long enough password');
    await page
      .getByRole('button', { name: messages['accountSignInAction'] ?? 'missing', exact: true })
      .click();

    await expect(accountLink).toBeVisible();
    await expect(todayLink).toBeVisible();
    await expect(signOutLink).toBeVisible();
    await expect(signInLink).toHaveCount(0);

    // The sign-in page, signed in, is where the sign-out choices live.
    await page
      .getByRole('main')
      .getByRole('button', { name: messages['webAuthSignOutAction'] ?? 'missing', exact: true })
      .click();

    await expect(signInLink).toBeVisible();
    await expect(accountLink).toHaveCount(0);
    await expect(todayLink).toHaveCount(0);
  });
});
