import { expect, test, type Page } from '@playwright/test';

import { buildIsConfigured, installSignedInFacade } from './fixtures';

/** The six at-rest surfaces the guard measures (issue #1249). */
async function emptiness(page: Page) {
  return page.evaluate(async () => {
    const databases = await indexedDB.databases();
    const cacheNames = await caches.keys();
    const registrations = await navigator.serviceWorker.getRegistrations();
    return {
      localStorage: window.localStorage.length,
      sessionStorage: window.sessionStorage.length,
      indexedDB: databases.length,
      caches: cacheNames.length,
      serviceWorkers: registrations.length,
      cookies: document.cookie,
    };
  });
}

/** Every one of the six must be empty. */
const empty = {
  localStorage: 0,
  sessionStorage: 0,
  indexedDB: 0,
  caches: 0,
  serviceWorkers: 0,
  cookies: '',
};

/**
 * The nothing-stored guard (issue #1249): after exercising the app, every
 * at-rest surface the browser offers is empty. Later slices extend this
 * test as the client grows; it fails the day anything — the app, a
 * dependency, an injected script — persists so much as a cookie.
 *
 * Issue #1252 extends what this page loads: the data layer (synced-data
 * hooks, ULID generator, the sync_signals wiring) is now part of the
 * bundle TodayPage mounts, so this session exercises it — the hooks wire
 * up, find no configured client, and idle — and the emptiness assertions
 * prove the module left nothing behind either.
 */
test('a session leaves every browser store empty', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();

  // Exercise the shell: the reserved auth route and back, like a session
  // that did something.
  await page.goto('/auth/callback?code=smoke');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
  await page.goBack();
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();

  // Exercise the day editor (issue #1254): unconfigured, it renders its
  // sign-in prompt — a page the editor owns, holding only in-memory state.
  await page.goto('/day/01ARZ3NDEKTSV4RRFFQ69G5FAV');
  await expect(page.getByText('Sign in to log a day.')).toBeVisible();

  // Exercise the invite redemption surface (issue #1255): a link-shaped
  // visit — preview fails closed without a session — must still store
  // nothing, especially not the code.
  await page.goto('/invite?code=e2e-no-storage-check&profile=&kind=');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();

  // Exercise the account surface (issue #1256): unconfigured, it renders
  // its signed-out prompt; signed in, its state lives in page memory and
  // the only cookie it touches is the Worker's HttpOnly one — neither
  // readable here, both asserted by the emptiness table below.
  await page.goto('/account?code=smoke&state=smoke');
  await expect(page.getByRole('main').getByRole('link', { name: 'Sign in' })).toBeVisible();

  expect(await emptiness(page)).toEqual(empty);
});

// Issue #1250's extension: the auth screens leave the browser just as
// empty. The refresh token only ever travels in the Worker's HttpOnly
// cookie (invisible to document.cookie and asserted in worker/auth.test.ts),
// and the access token lives in page memory — so even a signed-in session
// has nothing for a script to read back from storage. Here every auth
// screen is exercised and the six surfaces measured again.
test('the auth screens leave every browser store empty', async ({ page }) => {
  await page.goto('/sign-in');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
  await page.goto('/sign-up');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
  await page.goto('/forgot-password');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
  await page.goto('/sign-in/code?email=smoke@example.com');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
  await page.goto('/auth/callback?code=smoke');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
  await page.waitForTimeout(250); // let the callback's exchange attempt settle

  expect(await emptiness(page)).toEqual(empty);
});

// Issue #1721: the two tests above only ever visit signed-out surfaces — no
// Supabase client exists during their measurements — while the README's
// claim ("the browser is empty after a session") is about the signed-in
// path, the one a dependency regression would actually touch. This test
// establishes a real session through the same facade the profile-home
// suite uses, exercises the authenticated data layer, and measures the six
// surfaces again.
test('a signed-in session leaves every browser store empty', async ({ page }) => {
  test.skip(!(await buildIsConfigured(page)), 'unconfigured build (fork); runs in CI');
  await installSignedInFacade(page);

  // The signed-in home proves the session landed (the facade's
  // /auth/session token lives in page memory, the #1250 contract) and the
  // #1252 data layer ran its sync_pull.
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Maya' })).toBeVisible();

  // One authenticated surface beyond the home: the account page, whose
  // signed-in state is page memory too (issue #1256).
  await page.goto('/account');
  await expect(page.getByRole('main')).toBeVisible();
  await page.waitForTimeout(250); // let any debounced write surface

  expect(await emptiness(page)).toEqual(empty);
});
