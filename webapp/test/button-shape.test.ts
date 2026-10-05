import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

/**
 * One button shape. The app theme's buttons are fully rounded, and the web
 * client's should match it and each other. It had drifted into two: `.btn`
 * and `.auth-button` were rounded rectangles while `.button` and a few
 * page-specific buttons were pills, so both shapes met on one screen.
 */

const css = readFileSync(
  join(import.meta.dirname, '..', 'src', 'styles', 'global.css'),
  'utf8',
).replaceAll('\r\n', '\n');

/** Every `selector { body }` rule, media-query wrappers flattened away. */
function rules(): { selector: string; body: string }[] {
  const found: { selector: string; body: string }[] = [];
  for (const match of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    const selector = (match[1] ?? '').replace(/\/\*[\s\S]*?\*\//g, '').trim();
    found.push({ selector, body: match[2] ?? '' });
  }
  return found;
}

/** A selector whose last compound targets one of the three button classes. */
function targetsAButton(selector: string): boolean {
  return selector
    .split(',')
    .some((part) => /\.(?:btn|button|auth-button)(?![\w-])[^\s>+~]*$/.test(part.trim()));
}

describe('button shape', () => {
  const buttonRules = rules().filter((rule) => targetsAButton(rule.selector));

  it('finds the button rules (a scan that matches nothing proves nothing)', () => {
    const selectors = buttonRules.map((rule) => rule.selector);
    expect(selectors).toContain('.btn');
    expect(selectors).toContain('.button');
    expect(selectors).toContain('.auth-button');
  });

  it.each(['.btn', '.button', '.auth-button'])('%s is fully rounded', (selector) => {
    const base = buttonRules.find((rule) => rule.selector === selector);
    expect(base?.body).toContain('border-radius: var(--ll-r-full)');
  });

  it('no rule gives a button any other radius', () => {
    const offenders = buttonRules
      .filter((rule) => /border-radius\s*:/.test(rule.body))
      .filter((rule) => !/border-radius\s*:\s*var\(--ll-r-full\)/.test(rule.body))
      .map((rule) => rule.selector);
    expect(offenders).toEqual([]);
  });
});
