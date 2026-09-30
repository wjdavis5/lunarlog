import { expect, test } from '@playwright/test';

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

  // Exercise the invite redemption surface (issue #1255): a link-shaped
  // visit — preview fails closed without a session — must still store
  // nothing, especially not the code.
  await page.goto('/invite?code=e2e-no-storage-check&profile=&kind=');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();

  const emptiness = await page.evaluate(async () => {
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

  expect(emptiness).toEqual({
    localStorage: 0,
    sessionStorage: 0,
    indexedDB: 0,
    caches: 0,
    serviceWorkers: 0,
    cookies: '',
  });
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

  const emptiness = await page.evaluate(async () => {
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

  expect(emptiness).toEqual({
    localStorage: 0,
    sessionStorage: 0,
    indexedDB: 0,
    caches: 0,
    serviceWorkers: 0,
    cookies: '',
  });
});
