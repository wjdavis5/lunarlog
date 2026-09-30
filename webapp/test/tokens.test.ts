import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

import { buildTokensCss, tokensCssOutPath, tokensJsonPath } from '../scripts/generate.mjs';

const tokens = JSON.parse(readFileSync(tokensJsonPath, 'utf8')) as {
  fonts: { text: string; display: string };
  space: Record<string, number>;
  type: Record<string, Record<string, unknown>>;
  schemes: { light: Record<string, string>; dark: Record<string, string> };
};
const committedCss = readFileSync(tokensCssOutPath, 'utf8');

describe('the generated design tokens (issue #1249)', () => {
  it('are fresh against tokens.generated.json', () => {
    expect(committedCss).toBe(buildTokensCss(tokens));
  });

  it('carry both colour schemes from the app theme', () => {
    expect(Object.keys(tokens.schemes.light).length).toBeGreaterThan(20);
    expect(Object.keys(tokens.schemes.dark).length).toBe(
      Object.keys(tokens.schemes.light).length,
    );
    for (const hex of [
      ...Object.values(tokens.schemes.light),
      ...Object.values(tokens.schemes.dark),
    ]) {
      expect(hex).toMatch(/^#[0-9a-f]{6}$/);
    }
  });

  it('bundle the app theme’s two font families', () => {
    expect(tokens.fonts).toEqual({ text: 'Inter', display: 'Fraunces' });
  });

  it('expose the spacing scale', () => {
    expect(tokens.space).toEqual({
      space1: 4,
      space2: 8,
      space3: 12,
      space4: 16,
      space5: 24,
      space6: 32,
      space7: 48,
    });
  });

  it('cover the type ramp', () => {
    expect(Object.keys(tokens.type)).toContain('displayMedium');
    expect(Object.keys(tokens.type)).toContain('labelSmall');
  });
});

describe('the hand-written CSS (issue #1249)', () => {
  const cssDir = join(tokensCssOutPath, '..', '..', 'styles');
  const handWritten = readdirSync(cssDir).filter((f) => f.endsWith('.css'));

  it('exists', () => {
    expect(handWritten.length).toBeGreaterThan(0);
  });

  it.each(handWritten)('never hand-copies a colour literal: %s', (file) => {
    const content = readFileSync(join(cssDir, file), 'utf8');
    // rgb()/hsl()/named colours are banned by review; this scan catches the
    // hex case mechanically. `#root` (an id selector) is the one allowed `#`.
    const stripped = content.replaceAll('#root', '');
    const hexMatches = stripped.match(/#[0-9a-fA-F]{3,8}\b/g);
    expect(hexMatches, `found colour literals: ${hexMatches?.join(', ')}`).toBeNull();
  });
});
