import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

import tokens from '../src/theme/tokens.generated.json';

/**
 * A logged period day is filled with its flow colour, and the day number
 * sits on that fill. Two things have to hold for the number to stay
 * readable: each fill rule must take the ink the app theme pairs with that
 * exact fill, and the pair must clear WCAG AA for text in both colour
 * schemes. The pairs come from the app theme (tool/export_webapp_tokens.dart),
 * so a palette change there is checked here before it reaches a browser.
 */

const css = readFileSync(
  join(import.meta.dirname, '..', 'src', 'styles', 'global.css'),
  'utf8',
).replaceAll('\r\n', '\n');

/** The declarations of the one rule with exactly this selector. */
function ruleBody(selector: string): string {
  const bodies: string[] = [];
  for (const match of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    const found = (match[1] ?? '').replace(/\/\*[\s\S]*?\*\//g, '').trim();
    if (found === selector) bodies.push(match[2] ?? '');
  }
  expect(bodies, `one rule for ${selector}`).toHaveLength(1);
  return bodies[0] ?? '';
}

/** WCAG relative luminance of a `#rrggbb` colour. */
function luminance(hex: string): number {
  const channel = (offset: number) => {
    const value = Number.parseInt(hex.slice(offset, offset + 2), 16) / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5);
}

function contrast(a: string, b: string): number {
  const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [number, number];
  return (light + 0.05) / (dark + 0.05);
}

const LEVELS = ['light', 'medium', 'heavy'] as const;

function tokenKey(prefix: 'flow' | 'onFlow', level: (typeof LEVELS)[number]): string {
  return `${prefix}${level.charAt(0).toUpperCase()}${level.slice(1)}`;
}

describe('the calendar flow fill', () => {
  it.each(LEVELS)('the %s fill takes its own on-flow ink', (level) => {
    const body = ruleBody(`.cal-flow-${level} .cal-day-link`);
    expect(body).toContain(`background: var(--ll-cal-flow-${level});`);
    expect(body).toContain(`color: var(--ll-cal-on-flow-${level});`);
  });

  it('draws the flow marks in the cell ink, not the fill they sit on', () => {
    expect(ruleBody('.cal-flow .cal-mark')).toContain('background: currentColor;');
    // The mark ramp has the same specificity, so the fill rule must come later.
    expect(css.indexOf('.cal-flow .cal-mark {')).toBeGreaterThan(
      css.lastIndexOf('.cal-mark:nth-child('),
    );
  });

  describe.each(['light', 'dark'] as const)('in the %s scheme', (scheme) => {
    const palette = tokens.calendar[scheme] as Record<string, string>;

    it.each(LEVELS)('the day number on a %s fill clears AA', (level) => {
      const fill = palette[tokenKey('flow', level)];
      const ink = palette[tokenKey('onFlow', level)];
      expect(fill, `flow token for ${level}`).toMatch(/^#[0-9a-f]{6}$/);
      expect(ink, `on-flow token for ${level}`).toMatch(/^#[0-9a-f]{6}$/);
      expect(contrast(fill ?? '', ink ?? '')).toBeGreaterThanOrEqual(4.5);
    });
  });
});
