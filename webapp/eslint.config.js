// ESLint flat config for the React web client (issue #1249).
//
// Two bans are the scaffold's reason to exist, both scoped to `src/**` —
// the app code that ships to the browser (tests and e2e specs legitimately
// *read* storage to assert it stays empty):
//
//   1. The nothing-stored ban. The browser client keeps nothing at rest —
//      not data, not even the auth session. `no-restricted-globals` +
//      `no-restricted-properties` make localStorage, sessionStorage,
//      indexedDB, caches, cookieStore, navigator.serviceWorker, and
//      document.cookie compile errors for app code. `no-restricted-globals`
//      only fires on the bare global and `no-restricted-properties` only on
//      an `Identifier` object, so the same surfaces through a qualified
//      reference — window.localStorage, globalThis.sessionStorage,
//      self.indexedDB, window.navigator.serviceWorker,
//      window.document.cookie — used to slip past (issue #1275); a
//      `no-restricted-syntax` selector over MemberExpression property
//      names closes that. test/lint-bans.test.ts proves the ban actually
//      fires (CI fails if someone scopes it away).
//
//   2. The no-typed-copy ban. No user-facing string is typed in TSX: every
//      visible string comes from the message catalogue generated from
//      `lib/l10n/app_en.arb` (see scripts/generate.mjs and the i18n module).
//      JSX text nodes and the user-facing string attributes below are
//      banned; `t('messageId')` is the only source.
//
// The ban definitions are exported so the lint tests lint against exactly
// what this config enforces — one source of truth for both.

import js from '@eslint/js';
import globals from 'globals';
import reactHooks from 'eslint-plugin-react-hooks';
import reactRefresh from 'eslint-plugin-react-refresh';
import tseslint from 'typescript-eslint';

/**
 * The banned storage surfaces. Anything here is a place a browser could
 * persist data or state past the page — which this client must never do
 * (epic #831's nothing-stored rule, enforced from the first commit).
 *
 * @type {{ name?: string, object?: string, property?: string, message: string }[]}
 */
export const STORAGE_BANS = [
  {
    name: 'localStorage',
    message:
      'localStorage stores data at rest in the browser. The web client keeps nothing at rest (issue #1249) — keep state in memory (TanStack Query) or on the server via supabase-js.',
  },
  {
    name: 'sessionStorage',
    message:
      'sessionStorage stores data at rest in the browser. The web client keeps nothing at rest (issue #1249) — keep state in memory (TanStack Query) or on the server via supabase-js.',
  },
  {
    name: 'indexedDB',
    message:
      'indexedDB is a browser database; the web client is a thin client with no local store (issue #1249) — read and write through supabase-js instead.',
  },
  {
    name: 'caches',
    message:
      'the CacheStorage API persists responses past the page. The web client caches in memory only (issue #1249).',
  },
  {
    name: 'cookieStore',
    message:
      'the CookieStore API reads and writes cookies, which persist state in the browser. The web client keeps nothing at rest (issue #1249).',
  },
  {
    object: 'navigator',
    property: 'serviceWorker',
    message:
      'service workers install persistent, offline-capable code in the browser. The web client has no offline mode (issue #1249).',
  },
  {
    object: 'document',
    property: 'cookie',
    message:
      'cookies persist state in the browser. The web client keeps nothing at rest (issue #1249).',
  },
];

/**
 * The banned surfaces reached through a *qualified* reference. The bare-name
 * rules above only report the global itself and an `Identifier`-named
 * object, so `window.localStorage`, `globalThis.sessionStorage`,
 * `self.indexedDB`, `window.caches`, `window.cookieStore`,
 * `window.navigator.serviceWorker`, and `window.document.cookie` used to
 * pass untouched (issue #1275). A member access carrying one of these
 * property names — from any receiver — is the same persistence surface, and
 * in this codebase nothing else legitimately owns properties with these
 * names. Both spellings are covered: the dot form matches on
 * `property.name`, and the computed string-literal form
 * (`window['localStorage']`, `document['cookie']` — issue #1722) on
 * `property.value`.
 *
 * @type {{ selector: string, message: string }[]}
 */
export const STORAGE_SYNTAX_BANS = [
  {
    selector:
      'MemberExpression[property.name=/^(localStorage|sessionStorage|indexedDB|caches|cookieStore|cookie|serviceWorker)$/]',
    message:
      'Browser storage reached through a qualified reference — e.g. window.localStorage, globalThis.sessionStorage, self.caches, window.cookieStore, window.navigator.serviceWorker, window.document.cookie — keeps data at rest exactly like the bare name does. The web client keeps nothing at rest (issue #1249) — keep state in memory (TanStack Query) or on the server via supabase-js.',
  },
  {
    selector:
      'MemberExpression[computed=true][property.value=/^(localStorage|sessionStorage|indexedDB|caches|cookieStore|cookie|serviceWorker)$/]',
    message:
      "Browser storage reached through a computed member access — e.g. window['localStorage'], globalThis['sessionStorage'], document['cookie'] — keeps data at rest exactly like the dot form does. The web client keeps nothing at rest (issue #1249) — keep state in memory (TanStack Query) or on the server via supabase-js.",
  },
];

/**
 * The user-facing string attributes a component could smuggle copy through
 * instead of the catalogue.
 */
const COPY_ATTRIBUTE_NAMES =
  '^(aria-label|aria-description|aria-placeholder|aria-roledescription|aria-valuetext|title|alt|placeholder|label)$';

/**
 * no-restricted-syntax selectors implementing the no-typed-copy ban.
 *
 * @type {{ selector: string, message: string }[]}
 */
export const COPY_BANS = [
  {
    selector: 'JSXText[value=/\\S/]',
    message:
      'User-facing copy must come from the message catalogue: use t(id)/formatMessage, never a string literal in JSX (issue #1249).',
  },
  {
    selector: `JSXAttribute[name.name=/${COPY_ATTRIBUTE_NAMES}/i][value.type=/^(Literal|TemplateLiteral)$/]`,
    message:
      'User-facing copy must come from the message catalogue: bind the attribute to t(id)/formatMessage instead of a literal (issue #1249).',
  },
  {
    selector: `JSXAttribute[name.name=/${COPY_ATTRIBUTE_NAMES}/i] JSXExpressionContainer[expression.type=/^(Literal|TemplateLiteral)$/]`,
    message:
      'User-facing copy must come from the message catalogue: bind the attribute to t(id)/formatMessage instead of a literal (issue #1249).',
  },
  {
    selector: 'JSXAttribute[name.name="dangerouslySetInnerHTML"]',
    message:
      'dangerouslySetInnerHTML is banned in the web client: with require-trusted-types-for in the CSP it is a guaranteed runtime failure, and it is the XSS hole the strict posture exists to close (issue #1249).',
  },
];

/**
 * zod's runtime may only be imported by `src/lib/zod.ts`, which sets
 * `jitless` before any schema is built. A schema module that imported 'zod'
 * directly could be evaluated first, and zod would then probe for `eval`,
 * which the CSP refuses and the browser logs as a Trusted Types violation on
 * every page load. `import type` is unaffected.
 */
export const ZOD_IMPORT_BAN = {
  name: 'zod',
  message:
    "Import { z } from 'src/lib/zod' instead: it sets zod's jitless mode before any schema is built, so zod never probes for eval under the CSP (a Trusted Types violation on every page load otherwise). `import type` from 'zod' is fine.",
  allowTypeImports: true,
};

const storageBanRules = {
  'no-restricted-globals': [
    'error',
    ...STORAGE_BANS.filter((ban) => ban.name !== undefined).map((ban) => ({
      name: ban.name,
      message: ban.message,
    })),
  ],
  'no-restricted-properties': [
    'error',
    ...STORAGE_BANS.filter((ban) => ban.object !== undefined).map((ban) => ({
      object: ban.object,
      property: ban.property,
      message: ban.message,
    })),
  ],
};

// Both selector families share `no-restricted-syntax` — a second spread of
// a rules object carrying the same rule key would silently drop the first,
// so the storage and copy selectors are merged into one array here.
const syntaxBanRules = {
  'no-restricted-syntax': [
    'error',
    ...STORAGE_SYNTAX_BANS.map((ban) => ({
      selector: ban.selector,
      message: ban.message,
    })),
    ...COPY_BANS.map((ban) => ({
      selector: ban.selector,
      message: ban.message,
    })),
  ],
};

export default tseslint.config(
  {
    ignores: [
      'dist/**',
      'node_modules/**',
      'coverage/**',
      'playwright-report/**',
      'test-results/**',
    ],
  },
  {
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      ecmaVersion: 2022,
      globals: { ...globals.browser, ...globals.node },
    },
    plugins: {
      'react-hooks': reactHooks,
      'react-refresh': reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      'react-refresh/only-export-components': 'warn',
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
    },
  },
  {
    // The nothing-stored + no-typed-copy bans: app code only. test/ and e2e/
    // legitimately *read* storage to assert it stays empty.
    files: ['src/**/*.{ts,tsx}'],
    rules: {
      ...storageBanRules,
      ...syntaxBanRules,
      '@typescript-eslint/no-restricted-imports': ['error', { paths: [ZOD_IMPORT_BAN] }],
    },
  },
);
