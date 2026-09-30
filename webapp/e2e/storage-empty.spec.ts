import { expect, test } from '@playwright/test';

/**
 * The nothing-stored guard (issue #1249): after exercising the app, every
 * at-rest surface the browser offers is empty. Later slices extend this
 * test as the client grows; it fails the day anything — the app, a
 * dependency, an injected script — persists so much as a cookie.
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
