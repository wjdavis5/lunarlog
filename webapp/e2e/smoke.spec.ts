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
const CSP_PATTERN =
  /Content Security Policy|Refused to (?:apply|load|execute|connect|create)|TrustedTypes|Content-Security-Policy/i;

test('the shell renders, is accessible, and violates nothing', async ({ page }) => {
  const consoleErrors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });
  page.on('pageerror', (error) => consoleErrors.push(String(error)));

  await page.goto('/');
  await expect(page.getByRole('banner')).toBeVisible();
  // Issue #1253: the home is the profile home now — signed out it shows
  // the Profiles heading and the sign-in prompt, both catalogue copy.
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    messages['profilePickerTitle'] ?? '',
  );
  await expect(page.getByText(messages['webHomeNeedsSignIn'] ?? '')).toBeVisible();
  await expect(
    page.getByRole('link', { name: messages['calendarTodayTooltip'] }),
  ).toBeVisible();

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
