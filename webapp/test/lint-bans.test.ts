import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ESLint } from 'eslint';
import { expect, describe, it } from 'vitest';

import {
  COPY_BANS,
  STORAGE_BANS,
  STORAGE_SYNTAX_BANS,
  ZOD_IMPORT_BAN,
} from '../eslint.config.js';

const webappRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// Lint a snippet as if it lived in src/, so the real flat config — the same
// one `npm run lint` and CI run — selects its storage/copy bans for it.
const linter = new ESLint({ cwd: webappRoot });
async function lintSrc(code: string, fileName = 'probe.ts') {
  const [result] = await linter.lintText(code, {
    filePath: join(webappRoot, 'src', fileName),
  });
  if (result === undefined) throw new Error('ESLint returned no result');
  return result.messages;
}

describe('the nothing-stored storage ban (issue #1249)', () => {
  const bannedSnippets: [string, string, string][] = [
    ['localStorage', "export const x = localStorage.getItem('k');", 'no-restricted-globals'],
    [
      'sessionStorage',
      "export const x = sessionStorage.setItem('k', 'v');",
      'no-restricted-globals',
    ],
    [
      'indexedDB',
      'export async function f() { return indexedDB.databases(); }',
      'no-restricted-globals',
    ],
    ['caches', 'export async function f() { return caches.keys(); }', 'no-restricted-globals'],
    [
      'cookieStore',
      "export async function f() { return cookieStore.get('k'); }",
      'no-restricted-globals',
    ],
    [
      'navigator.serviceWorker',
      'export async function f() { return navigator.serviceWorker.getRegistrations(); }',
      'no-restricted-properties',
    ],
    [
      'document.cookie',
      'export function f(): string { return document.cookie; }',
      'no-restricted-properties',
    ],
  ];

  it.each(bannedSnippets)('bans %s', async (surface, snippet, expectedRule) => {
    const messages = await lintSrc(snippet);
    const hits = messages.filter((m) => m.ruleId === expectedRule);
    expect(hits, `expected ${expectedRule} to fire for ${surface}`).not.toHaveLength(0);
    expect(
      hits.some(
        (m) => m.message.includes('nothing at rest') || m.message.includes('issue #1249'),
      ),
    ).toBe(true);
  });

  it('matches every surface listed in the exported ban table', () => {
    expect(bannedSnippets.map(([surface]) => surface)).toEqual(
      STORAGE_BANS.map((ban) => ban.name ?? `${ban.object}.${ban.property}`),
    );
  });

  it('lets ordinary memory-only code through', async () => {
    const messages = await lintSrc(
      'export function f(items: string[]): string | undefined { return items.at(0); }\n',
    );
    expect(messages).toHaveLength(0);
  });

  it('does not apply the ban to test/ and e2e/ (they assert emptiness)', async () => {
    const [result] = await linter.lintText('export const n = localStorage.length;\n', {
      filePath: join(webappRoot, 'e2e', 'probe.spec.ts'),
    });
    expect(result?.messages.filter((m) => m.ruleId === 'no-restricted-globals')).toHaveLength(
      0,
    );
  });
});

describe('the qualified-reference storage ban (issue #1275)', () => {
  // no-restricted-globals only reports the bare global and
  // no-restricted-properties only an Identifier-named object, so these
  // qualified forms used to pass both. The no-restricted-syntax selector
  // over MemberExpression property names is what must fire here.
  const qualifiedSnippets: [string, string][] = [
    [
      'window.localStorage',
      'export function f(): number { return window.localStorage.length; }',
    ],
    [
      'globalThis.sessionStorage',
      'export function f(): number { return globalThis.sessionStorage.length; }',
    ],
    [
      'self.indexedDB',
      'export function f(): IDBFactory | undefined { return self.indexedDB; }',
    ],
    ['window.caches', 'export async function f() { return window.caches.keys(); }'],
    ['window.cookieStore', "export async function f() { return window.cookieStore.get('k'); }"],
    [
      'window.navigator.serviceWorker',
      'export async function f() { return window.navigator.serviceWorker.getRegistrations(); }',
    ],
    [
      'window.document.cookie',
      'export function f(): string { return window.document.cookie; }',
    ],
  ];

  it.each(qualifiedSnippets)('bans %s', async (surface, snippet) => {
    const messages = await lintSrc(snippet);
    const hits = messages.filter((m) => m.ruleId === 'no-restricted-syntax');
    expect(
      hits,
      `expected the qualified-reference selector to fire for ${surface}`,
    ).not.toHaveLength(0);
    expect(hits.some((m) => m.message.includes('nothing at rest'))).toBe(true);
  });

  it('does not fire on member access with unrelated property names', async () => {
    const messages = await lintSrc(
      'export function f(w: Window): void { w.scrollTo(0, 0); }\n',
    );
    expect(messages.filter((m) => m.ruleId === 'no-restricted-syntax')).toHaveLength(0);
  });

  it('stays scoped to src/ (e2e reads qualified storage to assert emptiness)', async () => {
    const [result] = await linter.lintText('export const n = window.localStorage.length;\n', {
      filePath: join(webappRoot, 'e2e', 'probe.spec.ts'),
    });
    expect(result?.messages.filter((m) => m.ruleId === 'no-restricted-syntax')).toHaveLength(0);
  });

  it('exports exactly the selector the config consumes', () => {
    expect(STORAGE_SYNTAX_BANS).toHaveLength(1);
  });
});

describe('the no-typed-copy ban (issue #1249)', () => {
  it.each([
    ['JSX text', '<h1>Hand-typed heading</h1>;\n', 'probe.tsx'],
    [
      'aria-label literal',
      'export const f = () => <button aria-label="Close">{\'x\'}</button>;\n',
      'probe.tsx',
    ],
    [
      'placeholder literal',
      'export const f = () => <input placeholder="Search" />;\n',
      'probe.tsx',
    ],
    [
      'title template literal',
      'export const f = () => <span title={`Hi`}>{"x"}</span>;\n',
      'probe.tsx',
    ],
  ])('bans %s', async (_label, snippet, fileName) => {
    const messages = await lintSrc(snippet, fileName);
    const hits = messages.filter((m) => m.ruleId === 'no-restricted-syntax');
    expect(hits).not.toHaveLength(0);
    expect(hits.some((m) => m.message.includes('message catalogue'))).toBe(true);
  });

  it('bans dangerouslySetInnerHTML outright', async () => {
    const messages = await lintSrc(
      'export const f = (html: string) => <div dangerouslySetInnerHTML={{ __html: html }} />;\n',
      'probe.tsx',
    );
    expect(messages.some((m) => m.ruleId === 'no-restricted-syntax')).toBe(true);
  });

  it('lets catalogue-driven copy through', async () => {
    const messages = await lintSrc(
      "import { useT } from '../src/i18n/t';\n" +
        "export const F = () => { const t = useT(); return <h1>{t('calendarTodayTooltip')}</h1>; };\n",
      'probe.tsx',
    );
    expect(messages.filter((m) => m.ruleId === 'no-restricted-syntax')).toHaveLength(0);
  });

  it('exports exactly the selectors the config consumes', () => {
    // Four selectors: JSXText, direct literal attribute, wrapped literal
    // attribute, dangerouslySetInnerHTML.
    expect(COPY_BANS).toHaveLength(4);
  });
});

// zod probes for `eval` when a schema is built unless `jitless` is already
// set; under the CSP that probe is a Trusted Types violation logged on every
// page load. src/lib/zod.ts sets it, so nothing else in src/ may import the
// runtime.
describe('the zod runtime import ban (the CSP eval probe)', () => {
  const RULE = '@typescript-eslint/no-restricted-imports';

  it("bans importing zod's runtime in app code", async () => {
    const messages = await lintSrc("import { z } from 'zod';\nexport const s = z.string();\n");
    const hits = messages.filter((m) => m.ruleId === RULE);
    expect(hits).not.toHaveLength(0);
    expect(hits[0]?.message).toContain('src/lib/zod');
  });

  it('lets a type-only import through', async () => {
    const messages = await lintSrc(
      "import type { z } from 'zod';\nexport type S = z.infer<z.ZodString>;\n",
    );
    expect(messages.filter((m) => m.ruleId === RULE)).toEqual([]);
  });

  it('lets schema modules import z from the wrapper', async () => {
    const messages = await lintSrc(
      "import { z } from './lib/zod';\nexport const s = z.string();\n",
    );
    expect(messages.filter((m) => m.ruleId === RULE)).toEqual([]);
  });

  it('stays scoped to src/ (tests may import zod directly)', async () => {
    const [result] = await linter.lintText(
      "import { z } from 'zod';\nexport const s = z.string();\n",
      {
        filePath: join(webappRoot, 'test', 'probe.test.ts'),
      },
    );
    expect((result?.messages ?? []).filter((m) => m.ruleId === RULE)).toEqual([]);
  });

  it('exports exactly the ban the config consumes', () => {
    expect(ZOD_IMPORT_BAN.name).toBe('zod');
    expect(ZOD_IMPORT_BAN.allowTypeImports).toBe(true);
  });
});
