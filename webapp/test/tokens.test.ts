import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'postcss';
import { describe, expect, it } from 'vitest';

import {
  buildTokensCss,
  tokensCssOutPath,
  tokensJsonPath,
  webappRoot,
} from '../scripts/generate.mjs';

const tokens = JSON.parse(readFileSync(tokensJsonPath, 'utf8')) as {
  fonts: { text: string; display: string };
  space: Record<string, number>;
  type: Record<string, Record<string, unknown>>;
  schemes: { light: Record<string, string>; dark: Record<string, string> };
};
const committedCss = readFileSync(tokensCssOutPath, 'utf8');

// Parse-level checks (issue #1271): postcss's parser is deliberately
// lenient — on the first cut it happily folded the `//` header into the next
// rule's selector and hung the bare non-colour declarations straight off the
// AST root. "It parses" therefore proves nothing; the assertions below
// inspect the parsed structure itself.
const parsedCss = parse(committedCss, { from: tokensCssOutPath });
const declared = new Set<string>();
parsedCss.walkDecls((decl) => {
  if (decl.prop.startsWith('--ll-')) declared.add(decl.prop);
});

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

describe('the generated tokens.css is valid, rule-scoped CSS (issue #1271)', () => {
  it('contains no // line comments (CSS has none)', () => {
    const offenders = committedCss
      .split('\n')
      .map((text, index) => ({ line: index + 1, text }))
      .filter(({ text }) => text.includes('//'))
      .map(({ line, text }) => `${line}: ${text.trim()}`);
    expect(offenders).toEqual([]);
  });

  it('sits every declaration inside a rule block', () => {
    const stray: string[] = [];
    parsedCss.walkDecls((decl) => {
      if (decl.parent?.type !== 'rule') stray.push(`${decl.prop}: ${decl.value}`);
    });
    expect(stray).toEqual([]);
  });

  it('emits only :root rules under the dark-scheme media query', () => {
    // The `//` header used to fold into the first rule's selector, which
    // took the light-scheme block down with it — this pins the selector to
    // exactly `:root` so any polluted prelude fails here.
    const selectors = new Set<string>();
    parsedCss.walkRules((rule) => {
      selectors.add(rule.selector);
    });
    expect([...selectors]).toEqual([':root']);
    const atRules: string[] = [];
    parsedCss.walkAtRules((atRule) => {
      atRules.push(`@${atRule.name} ${atRule.params}`);
    });
    expect(atRules).toEqual(['@media (prefers-color-scheme: dark)']);
  });

  it('exposes the hyphenated names the hand-written CSS reads', () => {
    // kebab splits letter→digit boundaries now: `space3` → `space-3` (and,
    // by the same mechanical rule, `e1` → `e-1`). The pre-fix spellings
    // must not survive anywhere in the generated file.
    for (const name of [
      '--ll-space-1',
      '--ll-space-3',
      '--ll-space-5',
      '--ll-r-md',
      '--ll-e-1',
    ]) {
      expect(declared.has(name)).toBe(true);
    }
    for (const stale of ['--ll-space1', '--ll-space3', '--ll-e1']) {
      expect(declared.has(stale)).toBe(false);
    }
  });

  it('resolves every type slot’s font family to the two role variables', () => {
    // The first cut emitted `var(--ll-font-fraunces)`/`var(--ll-font-inter)`
    // — family names nothing defines. Only the two role variables exist.
    const families: string[] = [];
    parsedCss.walkDecls((decl) => {
      if (decl.prop.endsWith('-font-family')) families.push(decl.value);
    });
    expect(families).toHaveLength(13); // one per type ramp slot
    for (const value of families) {
      expect(value === 'var(--ll-font-text)' || value === 'var(--ll-font-display)').toBe(true);
    }
  });
});

describe('every var(--ll-…) reference under src/ resolves (issue #1271)', () => {
  const sources: { path: string; content: string }[] = [];
  const collect = (dir: string): void => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) collect(path);
      else if (/\.(css|ts|tsx)$/.test(entry.name)) {
        sources.push({ path, content: readFileSync(path, 'utf8') });
      }
    }
  };
  collect(join(webappRoot, 'src'));

  const referenced = new Set<string>();
  for (const { content } of sources) {
    for (const match of content.matchAll(/var\(\s*(--ll-[A-Za-z0-9-]+)/g)) {
      referenced.add(match[1]);
    }
  }

  it('scanned src and found references (a silently empty scan proves nothing)', () => {
    expect(sources.length).toBeGreaterThan(5);
    expect(referenced.size).toBeGreaterThan(30);
  });

  it('defines every referenced variable in tokens.css', () => {
    const unresolved = [...referenced].filter((name) => !declared.has(name)).sort();
    expect(unresolved).toEqual([]);
  });
});
