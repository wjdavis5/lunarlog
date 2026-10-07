import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test, type Page, type Route } from '@playwright/test';

/**
 * Tap targets at phone width (issue #1562). On a 390 px screen every control
 * that stands on its own is at least 44 px tall and wide: the buttons, the
 * links that are not part of a sentence, the fields and the selects. They
 * used to be 38 px (buttons), 25 to 28 px (links) and 20 px (the links under
 * the sign-in form), which a thumb misses.
 *
 * The signed-out welcome and the main signed-in screens are measured in the
 * real built app, with the network answered at the fetch boundary the way
 * `profile-home.spec.ts` does it: a session from `/auth/session`, rows from
 * `sync_pull`, and the few tables the guardians and notes pages read
 * directly. No backend is reached.
 *
 * Three things are left out, each by what it is and not by a blanket
 * exemption:
 *
 *   - a link in a sentence, which is read as part of its line;
 *   - the calendar's day cells (`.cal-day-link`), which are sized by the
 *     seven-column grid and have their own rule;
 *   - tick boxes and radio buttons, which are tapped through their label.
 */

const messages = JSON.parse(
  readFileSync(join(import.meta.dirname, '..', 'src', 'i18n', 'messages.en.json'), 'utf8'),
) as Record<string, string>;

function message(id: string): string {
  const text = messages[id];
  if (text === undefined) throw new Error(`no message "${id}" in the catalogue`);
  return text;
}

/** The smallest height and width of a control that stands on its own, in px. */
const MIN_TARGET = 44;

test.use({
  viewport: { width: 390, height: 844 },
  // The served content security policy lets the page talk to one Supabase
  // host only. A build pointed at any other (a made-up host, which is how
  // this file is run locally, so that it cannot reach production data) has
  // every data call refused before the routes below can answer it, and the
  // signed-in tests would then skip themselves. Nothing in this file is
  // about the policy, which `smoke.spec.ts` holds, so it is off here.
  bypassCSP: true,
});

// ---------------------------------------------------------------------------
// Fixtures: one account, one profile with a few logged days, two guardians.
// ---------------------------------------------------------------------------

const UID = '00000000-0000-4000-8000-0000000000a1';
const OTHER_UID = '00000000-0000-4000-8000-0000000000b2';
const PROFILE_ID = '01M2FWKNG0ZMH2ANCH7R2CM2XZ';
/** The day the page's clock is fixed to: the fixtures have rows for it. */
const TODAY = '2026-09-30';

interface Row {
  [key: string]: unknown;
}

function entry(id: string, localDate: string, extra: Row = {}): Row {
  return {
    id,
    user_id: UID,
    profile_id: PROFILE_ID,
    local_date: localDate,
    tz: 'UTC',
    flow: 'medium',
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
    ...extra,
  };
}

function guardian(id: string, userId: string, role: string, displayName: string | null): Row {
  return {
    id,
    profile_id: PROFILE_ID,
    user_id: userId,
    role,
    status: 'accepted',
    display_name: displayName,
    invited_by: null,
    is_subject: userId === UID,
    revoked_at: null,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    server_version: 2,
  };
}

const guardians = [
  guardian('a0000000-0000-4000-8000-000000000001', UID, 'primary_guardian', null),
  guardian('a0000000-0000-4000-8000-000000000002', OTHER_UID, 'co_parent', 'Sam'),
];

/** What `sync_pull` answers with. */
const snapshot = {
  profiles: [
    {
      id: PROFILE_ID,
      user_id: UID,
      display_name: 'Maya',
      is_minor: false,
      sort_order: 0,
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
    },
  ],
  day_entries: [
    entry('01M2FWKNG0ZMH2ANCH7R2CM2E1', '2026-09-28'),
    entry('01M2FWKNG0ZMH2ANCH7R2CM2E2', '2026-09-29'),
    // Today has tags, so the home shows its "Logged today" card with the
    // Edit link, and the day editor opens two symptom sections.
    entry('01M2FWKNG0ZMH2ANCH7R2CM2E3', TODAY, { tags: ['cramps', 'fatigue'] }),
  ],
  observations: [],
  profile_modes: [],
  cycle_overrides: [],
  care_notes: [],
  visit_prep_items: [],
  profile_tag_registry: [],
  profile_guardians: guardians,
};

const pendingInvitations = [
  {
    id: 'b0000000-0000-4000-8000-000000000001',
    profile_id: PROFILE_ID,
    role: 'caregiver',
    invited_by: UID,
    recipient_label: 'Aunt Rosa',
    created_at: '2026-09-29T00:00:00Z',
    expires_at: '2026-10-06T00:00:00Z',
    is_subject: false,
  },
];

const guardianNotes = [
  {
    id: '01M2FWKNG0ZMH2ANCH7R2CM2G1',
    profile_id: PROFILE_ID,
    local_date: TODAY,
    tz: 'UTC',
    body: 'A note for the day.',
    logged_by_user_id: UID,
    updated_at: '2026-09-30T08:00:00Z',
  },
];

const careNotes = [
  {
    id: '01M2FWKNG0ZMH2ANCH7R2CM2N1',
    profile_id: PROFILE_ID,
    body: 'Ask about iron at the next visit.',
    logged_by_user_id: UID,
    last_modified_by_user_id: UID,
    updated_at: '2026-09-20T08:00:00Z',
  },
];

async function json(route: Route, body: unknown, status = 200): Promise<void> {
  await route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });
}

/** Every Supabase REST call the measured screens make, answered by path. */
async function answerRest(route: Route): Promise<void> {
  const path = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, '');
  switch (path) {
    case 'rpc/sync_pull':
      return json(route, snapshot);
    case 'rpc/sync_watermark':
      return json(route, 100_000);
    case 'profile_guardians':
      return json(route, guardians);
    case 'guardian_invitations':
      return json(route, pendingInvitations);
    case 'guardian_notes':
      return json(route, guardianNotes);
    case 'care_notes':
      return json(route, careNotes);
    default:
      // ownership_transfers, settings, account_consents: nothing there.
      return json(route, []);
  }
}

async function installSignedInFacade(page: Page): Promise<void> {
  await page.route('**/rest/v1/**', answerRest);
  // The data layer's wake-up socket (Realtime) is opened here and answered
  // by nobody. It only ever asks for a refetch, and with it held the built
  // app reaches no backend at all, whichever host it was built for.
  await page.routeWebSocket(/\/realtime\/v1\//, () => {});
  await page.route('**/auth/session', (route) =>
    json(route, {
      access_token: 'e2e-access-token',
      expires_in: 3600,
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      user: { id: UID, email: 'e2e@example.com' },
    }),
  );
  await page.route('**/auth/identities', (route) =>
    json(route, { email: 'e2e@example.com', providers: ['google'] }),
  );
  // Noon, local time: "today" is the day the fixtures were logged for.
  await page.clock.setFixedTime(new Date(2026, 8, 30, 12, 0, 0));
}

let configuredProbe: boolean | null = null;

/**
 * True when the build carries Supabase config, so the app signs in at all.
 * When `LUNARLOG_APP_CONFIGURED` is set, respect it without probing (issue #1662).
 * A fork's build does not, and never leaves the welcome: there the wait
 * runs out, once per worker, and the signed-in tests skip.
 */
async function buildIsConfigured(page: Page): Promise<boolean> {
  if (process.env.LUNARLOG_APP_CONFIGURED !== undefined) {
    return process.env.LUNARLOG_APP_CONFIGURED === 'true';
  }
  if (configuredProbe !== null) return configuredProbe;
  await page.goto('/');
  configuredProbe = await page
    .getByLabel(message('webHomeProfileSwitcherLabel'))
    .waitFor({ state: 'visible', timeout: 5_000 })
    .then(
      () => true,
      () => false,
    );
  return configuredProbe;
}

// ---------------------------------------------------------------------------
// The measure.
// ---------------------------------------------------------------------------

interface Measured {
  /** How many controls were held to the minimum. */
  held: number;
  /** The ones under it, as `tag.class "label" width x height`. */
  small: string[];
}

/**
 * Measures every control on the page that stands on its own and returns the
 * ones whose tap target is under `MIN_TARGET` in either direction.
 */
async function measureControls(page: Page): Promise<Measured> {
  await page.evaluate(() => document.fonts.ready);
  return page.evaluate((min) => {
    const CONTROLS = 'a[href], button, input, select, textarea, summary, [role="button"]';

    /**
     * True for a control that is part of a line of text: the block it sits
     * in also holds words that belong to no control. `<p>New here? <a>Create
     * an account</a></p>` is a sentence. `<p><a>Back to today</a></p>`, a
     * link in a row of links, and anything laid out as a flex or grid item
     * are not.
     */
    function inSentence(el: Element): boolean {
      if (!getComputedStyle(el).display.startsWith('inline')) return false;
      const parent = el.parentElement;
      if (parent === null) return false;
      if (/flex|grid/.test(getComputedStyle(parent).display)) return false;
      let block: Element = parent;
      while (block.parentElement !== null && getComputedStyle(block).display === 'inline') {
        block = block.parentElement;
      }
      const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node !== null; node = walker.nextNode()) {
        if (!/[\p{L}\p{N}]/u.test(node.textContent ?? '')) continue;
        // Count the text only when it runs in this block's own lines and
        // is not the label of a control.
        let host = node.parentElement;
        let running = true;
        while (host !== null && host !== block) {
          if (
            host.matches(`${CONTROLS}, label`) ||
            getComputedStyle(host).display !== 'inline'
          ) {
            running = false;
            break;
          }
          host = host.parentElement;
        }
        if (running) return true;
      }
      return false;
    }

    /**
     * What is tapped: the control's own box, or the larger box of a
     * `::before` or `::after` that is laid over it. A chip is drawn at
     * 30 px and tapped through such a box, which reaches above and below it.
     */
    function target(el: Element): { width: number; height: number } {
      let { width, height } = el.getBoundingClientRect();
      for (const pseudo of ['::before', '::after']) {
        const style = getComputedStyle(el, pseudo);
        if (style.content === 'none' || style.content === 'normal') continue;
        if (style.position !== 'absolute' || style.pointerEvents === 'none') continue;
        width = Math.max(width, Number.parseFloat(style.width) || 0);
        height = Math.max(height, Number.parseFloat(style.height) || 0);
      }
      return { width, height };
    }

    /** What to call the control in a failure: its label, or the field's name. */
    function nameOf(el: Element): string {
      const typed = el.matches('input, select, textarea');
      const text =
        el.getAttribute('aria-label') ??
        (typed ? (el.getAttribute('placeholder') ?? `#${el.id}`) : (el.textContent ?? ''));
      return text.replace(/\s+/g, ' ').trim().slice(0, 40);
    }

    const small: string[] = [];
    let held = 0;
    for (const el of document.querySelectorAll(CONTROLS)) {
      // The calendar's day cells: sized by the grid, under their own rule.
      if (el.matches('.cal-day-link')) continue;
      // Tick boxes and radio buttons are tapped through their label.
      if (el.matches('input[type="checkbox"], input[type="radio"]')) continue;
      // Not on screen: a hidden field, something kept for screen readers
      // only, or anything inside a part of the page that is not shown.
      if (el.matches('input[type="hidden"], .visually-hidden, .visually-hidden *')) continue;
      if (!el.checkVisibility({ visibilityProperty: true })) continue;
      if (inSentence(el)) continue;

      const { width, height } = target(el);
      held += 1;
      // Half a pixel of slack for sub-pixel layout.
      if (width >= min - 0.5 && height >= min - 0.5) continue;
      const classes = el.getAttribute('class') ?? '';
      small.push(
        `${el.tagName.toLowerCase()}${classes === '' ? '' : `.${classes.replace(/\s+/g, '.')}`} ` +
          `"${nameOf(el)}" ${Math.round(width)}x${Math.round(height)}`,
      );
    }
    return { held, small };
  }, MIN_TARGET);
}

// ---------------------------------------------------------------------------
// The tests.
// ---------------------------------------------------------------------------

// A measure that skips everything would pass on any page. Three elements
// are put on the welcome to show what it skips and what it catches.
test('the measure skips a link in a sentence and a day cell, and catches a small link', async ({
  page,
}) => {
  await page.route('**/auth/session', (route) => json(route, { error: 'unauthorized' }, 401));
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(message('webWelcomeTitle'));
  const before = await measureControls(page);

  await page.evaluate(() => {
    const link = (text: string, className: string): HTMLAnchorElement => {
      const a = document.createElement('a');
      a.href = '/';
      a.textContent = text;
      a.className = className;
      return a;
    };
    const main = document.querySelector('main');
    if (main === null) throw new Error('no main');
    const sentence = document.createElement('p');
    sentence.append('Words before ', link('a link in a sentence', ''), ' and words after.');
    const alone = document.createElement('p');
    alone.append(link('a small link on its own', ''));
    const dayCell = document.createElement('p');
    dayCell.append(link('7', 'cal-day-link'));
    main.append(sentence, alone, dayCell);
  });
  const after = await measureControls(page);

  // Only the link on its own was added to what is held to the minimum...
  expect(after.held).toBe(before.held + 1);
  // ...and it is the only new failure.
  const added = after.small.filter((line) => !before.small.includes(line));
  expect(added).toHaveLength(1);
  expect(added[0]).toContain('a small link on its own');
});

test('signed out: the welcome', async ({ page }) => {
  await page.route('**/auth/session', (route) => json(route, { error: 'unauthorized' }, 401));
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(message('webWelcomeTitle'));
  const measured = await measureControls(page);
  // The name, the header's "Sign in", the button and the link beside it.
  expect(measured.held).toBe(4);
  expect(measured.small).toEqual([]);
});

test.describe('signed in', () => {
  test.beforeEach(async ({ page }) => {
    await installSignedInFacade(page);
  });

  test('the home', async ({ page }) => {
    test.skip(!(await buildIsConfigured(page)), 'unconfigured build (fork); runs in CI');
    await page.goto('/');
    await expect(page.getByRole('grid')).toBeVisible();
    // The "Logged today" card, with its Edit link, is part of what is measured.
    await expect(page.getByTestId('today-log-edit')).toBeVisible();
    const measured = await measureControls(page);
    // Header (4), the switcher row (select, three links, the button), Edit,
    // three month buttons, and the two rows that open the legend and layers.
    expect(measured.held).toBeGreaterThanOrEqual(15);
    expect(measured.small).toEqual([]);
  });

  test('the day editor', async ({ page }) => {
    test.skip(!(await buildIsConfigured(page)), 'unconfigured build (fork); runs in CI');
    await page.goto(`/day/${PROFILE_ID}?date=${TODAY}`);
    await expect(page.getByRole('button', { name: message('webDaySave') })).toBeVisible();
    // A logged tag opens its section, so the chips are on show.
    await expect(page.getByRole('button', { name: 'Cramps', exact: true })).toBeVisible();
    const measured = await measureControls(page);
    expect(measured.held).toBeGreaterThanOrEqual(30);
    expect(measured.small).toEqual([]);
  });

  test('the profiles page, with the add form open', async ({ page }) => {
    test.skip(!(await buildIsConfigured(page)), 'unconfigured build (fork); runs in CI');
    await page.goto('/profiles');
    await page
      .getByRole('button', { name: message('profilePickerAddProfileTooltip'), exact: true })
      .click();
    await expect(page.locator('#profile-name')).toBeVisible();
    const measured = await measureControls(page);
    expect(measured.held).toBeGreaterThanOrEqual(12);
    expect(measured.small).toEqual([]);
  });

  test('the account page', async ({ page }) => {
    test.skip(!(await buildIsConfigured(page)), 'unconfigured build (fork); runs in CI');
    await page.goto('/account');
    await expect(
      page.getByRole('button', { name: message('accountSectionDelete'), exact: true }),
    ).toBeVisible();
    const measured = await measureControls(page);
    expect(measured.held).toBeGreaterThanOrEqual(10);
    expect(measured.small).toEqual([]);
  });

  test('the guardians page', async ({ page }) => {
    test.skip(!(await buildIsConfigured(page)), 'unconfigured build (fork); runs in CI');
    await page.goto(`/profile/${PROFILE_ID}/guardians`);
    await expect(
      page.getByRole('button', { name: message('sharingInviteGuardianCreateLink') }),
    ).toBeVisible();
    // The co-parent's row, with its role select beside the remove button.
    await expect(
      page.getByLabel(message('manageGuardiansChangeRoleTooltip')).first(),
    ).toBeVisible();
    const measured = await measureControls(page);
    expect(measured.held).toBeGreaterThanOrEqual(12);
    expect(measured.small).toEqual([]);
  });

  test('the notes page', async ({ page }) => {
    test.skip(!(await buildIsConfigured(page)), 'unconfigured build (fork); runs in CI');
    await page.goto(`/profile/${PROFILE_ID}/notes`);
    await expect(
      page
        .getByRole('region', { name: message('careNotesSectionTitle') })
        .getByRole('button', { name: message('careNotesAddButton'), exact: true }),
    ).toBeVisible();
    const measured = await measureControls(page);
    expect(measured.held).toBeGreaterThanOrEqual(10);
    expect(measured.small).toEqual([]);
  });
});
