import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test } from '@playwright/test';

import { installSignedInFacade, json, loggedSnapshot, messages } from './fixtures';

/**
 * The marketing site's browser CTA figure (issue #1431): a capture of the
 * React web client's own signed-in home, rendered from the same fabricated
 * fixtures the profile-home suite asserts against — no backend, no real
 * data, never committed by hand. The site workflows (site.yml,
 * site-deploy.yml) set `LUNARLOG_BROWSER_CAPTURE_OUT` to
 * `site/public/screenshots/` before the Astro build; the ordinary e2e
 * suite leaves it unset and this test skips.
 *
 * The PNG lands under the #1162 browser device class' name grammar —
 * `today-browser-light.png`, a 1280x800 viewport at 1.5 DPR, i.e. the
 * 1920x1200 pixel size `site/src/components/Screenshot.astro`'s kDevices
 * mirror and `tool/screenshots/manifest.dart` pin (a size mismatch shifts
 * the page's layout: the <img> carries width/height attributes). Light
 * only: the light theme is the only one the home page's figure asks for.
 *
 * The build must be configured (`VITE_SUPABASE_*` non-empty, as this
 * repo's CI builds it): an unconfigured app never leaves the signed-out
 * welcome, and the readiness waits below fail rather than capture that.
 */
const OUT_DIR = process.env.LUNARLOG_BROWSER_CAPTURE_OUT;

test.describe('the browser CTA capture (issue #1431)', () => {
  // The #1162 browser class: a small-desktop viewport whose 1.5 DPR is the
  // product — the PNG is 1920x1200.
  test.use({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1.5 });

  test('captures the signed-in home from the fabricated fixtures', async ({ page }) => {
    test.skip(
      !OUT_DIR,
      'set LUNARLOG_BROWSER_CAPTURE_OUT to capture (the site workflows set it)',
    );

    // "Today" is a day the fixtures have rows for, whatever day CI runs
    // on — the same pin the "what is logged today" suite uses.
    await page.clock.setFixedTime(new Date(2026, 8, 30, 12, 0, 0));
    await installSignedInFacade(page);
    // Maya's 30 September filled in (flow, tags, a note, a reading), and
    // her own marker set so the home says what is logged (the app's lens
    // rule hides the card from a guardian).
    await page.route('**/rest/v1/rpc/sync_pull', (route) => json(route, loggedSnapshot(true)));

    await page.goto('/');

    // Readiness: the signed-in home, not the momentary signed-out welcome
    // the session restore starts from, and the full stack the figure
    // advertises — the estimate, the today log, the shared calendar.
    await expect(page.getByRole('heading', { name: 'Maya' })).toBeVisible();
    await expect(
      page.getByRole('region', { name: messages['todayLogTitle'] ?? 'missing' }),
    ).toBeVisible();
    await expect(page.getByRole('grid')).toBeVisible();
    await page.evaluate(() => document.fonts.ready);

    mkdirSync(OUT_DIR!, { recursive: true });
    await page.screenshot({
      path: join(OUT_DIR!, 'today-browser-light.png'),
      animations: 'disabled',
    });
  });
});
