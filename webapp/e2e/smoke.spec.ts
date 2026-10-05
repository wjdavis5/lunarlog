import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

// The catalogue the app itself renders from (read directly — Node 22 needs
// an import attribute for JSON modules, and this keeps the spec runtime-
// agnostic).
const messages = JSON.parse(
  readFileSync(join(import.meta.dirname, '..', 'src', 'i18n', 'messages.en.json'), 'utf8'),
) as Record<string, string>;

/**
 * The smoke test (issue #1249): the built app renders its shell from the
 * catalogue, is accessible, and — because vite preview serves the staging
 * Worker's real headers — produces zero CSP violations in an enforcing
 * Chromium (including the `require-trusted-types-for 'script'` directive).
 */

// CSP / Trusted Types refusals surface as console errors and page errors;
// any other console noise is reported but only CSP violations fail.
//
// Chromium words a Trusted Types refusal as "This document requires
// 'TrustedScript' assignment" (or 'TrustedHTML' / 'TrustedScriptURL'), with
// no "TrustedTypes" in it. The pattern used to look for that word only, so
// zod's eval probe was refused on every page load and this test stayed
// green. `Trusted(Script|HTML|ScriptURL)` is what the browser actually says.
const CSP_PATTERN =
  /Content Security Policy|Refused to (?:apply|load|execute|connect|create)|TrustedTypes|Trusted(?:Script|HTML|ScriptURL)|Content-Security-Policy/i;

test('the shell renders, is accessible, and violates nothing', async ({ page }) => {
  const consoleErrors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });
  page.on('pageerror', (error) => consoleErrors.push(String(error)));

  await page.goto('/');
  await expect(page.getByRole('banner')).toBeVisible();
  // Issue #1253: the home is the profile home — signed out it is the
  // welcome: its title, what signing in is for, and what this browser
  // keeps, all catalogue copy.
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    messages['webWelcomeTitle'] ?? '',
  );
  await expect(page.getByText(messages['webHomeNeedsSignIn'] ?? '')).toBeVisible();
  await expect(page.getByText(messages['webWelcomeStorageNote'] ?? '')).toBeVisible();
  // Signed out, the header offers the way home and the way in — and no
  // "Today" link, which names the signed-in home.
  await expect(
    page.getByRole('banner').getByRole('link', { name: messages['gateLockScreenAppTitle'] }),
  ).toHaveAttribute('href', '/');
  await expect(
    page.getByRole('banner').getByRole('link', { name: messages['calendarTodayTooltip'] }),
  ).toHaveCount(0);

  const axeResults = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze();
  expect(axeResults.violations).toEqual([]);

  const cspViolations = consoleErrors.filter((text) => CSP_PATTERN.test(text));
  expect(cspViolations, `CSP violations: ${cspViolations.join('\n')}`).toEqual([]);
});

test('the reserved /auth/* route lands in the app (Worker entry for #1250)', async ({
  page,
}) => {
  const consoleErrors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });
  page.on('pageerror', (error) => consoleErrors.push(String(error)));

  await page.goto('/auth/callback?code=smoke');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    messages['accountSignInTitle'] ?? '',
  );

  const cspViolations = consoleErrors.filter((text) => CSP_PATTERN.test(text));
  expect(cspViolations, `CSP violations: ${cspViolations.join('\n')}`).toEqual([]);
});

// An invited guardian is often new to lunarlog and arrives signed out. The
// invitation page has to say so and bring them back after signing in.
test('a signed-out visitor at an invitation is sent to sign in, and back', async ({ page }) => {
  const consoleErrors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });
  page.on('pageerror', (error) => consoleErrors.push(String(error)));

  await page.goto('/invite?code=EXAMPLE123');
  // A fork's build has no Supabase configuration, so there is no account to
  // sign in to and the page shows its own "not available" copy instead.
  // This repo's CI always builds configured.
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
  test.skip(
    await page
      .getByText(messages['webInviteNeutralIntro'] ?? 'missing')
      .isVisible()
      .catch(() => false),
    'unconfigured build (fork); runs in CI',
  );
  await expect(page.getByText(messages['webInviteSignedOutBody'] ?? 'missing')).toBeVisible();
  const signIn = page
    .getByRole('main')
    .getByRole('link', { name: messages['accountSectionSignIn'] ?? 'missing' });
  await expect(signIn).toHaveAttribute(
    'href',
    `/sign-in?next=${encodeURIComponent('/invite?code=EXAMPLE123')}`,
  );
  // The accept form is not offered to someone who cannot use it.
  await expect(
    page.getByRole('button', { name: messages['sharingAcceptInviteAccept'] ?? 'missing' }),
  ).toHaveCount(0);

  // Following the link keeps the way back in the address bar.
  await signIn.click();
  await expect(page).toHaveURL(/\/sign-in\?next=%2Finvite%3Fcode%3DEXAMPLE123$/);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    messages['accountSignInTitle'] ?? '',
  );

  const axeResults = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze();
  expect(axeResults.violations).toEqual([]);

  const cspViolations = consoleErrors.filter((text) => CSP_PATTERN.test(text));
  expect(cspViolations, `CSP violations: ${cspViolations.join('\n')}`).toEqual([]);
});
