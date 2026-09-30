import { expect, test } from '@playwright/test';

/**
 * The compiled Dart domain module loads and answers under the real
 * response headers (issue #1251). vite preview serves the staging Worker's
 * CSP — `script-src 'self'` and `require-trusted-types-for 'script'` — so
 * a clean invoke here is the live-loading half of the issue's acceptance
 * (the static-analysis half lives in the parity suite and the dart2js
 * output scan).
 */
test('the domain module loads and answers under the CSP', async ({ page }) => {
  const consoleErrors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });
  page.on('pageerror', (error) => consoleErrors.push(String(error)));

  await page.goto('/');

  // The script tag in index.html must have installed the global — a 404
  // or a CSP refusal would leave it absent and this assertion fails.
  const version = await page.evaluate(() => window.lunarlogDomain?.version);
  expect(version).toBe('1');

  // One real round trip: a date inside the bounds validates clean.
  const status = await page.evaluate(() => {
    const today = new Date().toISOString().slice(0, 10);
    const response = window.lunarlogDomain!.invoke(
      'validateDayEntryDate',
      JSON.stringify({ date: today, today }),
    );
    return JSON.parse(response) as { ok: boolean; data?: { status: string } };
  });
  expect(status).toEqual({ ok: true, data: { status: 'valid' } });

  // And none of that tripped the CSP / Trusted Types policy.
  const cspViolations = consoleErrors.filter((text) =>
    /Content Security Policy|Refused to (?:apply|load|execute|connect|create)|TrustedTypes|Content-Security-Policy/i.test(
      text,
    ),
  );
  expect(cspViolations, `CSP violations: ${cspViolations.join('\n')}`).toEqual([]);
});
