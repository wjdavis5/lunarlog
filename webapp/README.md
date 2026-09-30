# webapp — the React web client (issue #1249, epic #831)

The signed-in browser client for lunarlog: a thin client over the Supabase
backend that keeps **nothing at rest in the browser** — no data copy, no
offline store, not even the auth session. Every later slice of the web
client epic builds on this scaffold.

> The issue referenced `docs/repo-docs-standard.md` as the README standard;
> no such file exists in the repo (as of this scaffold's branch), so this
> file follows the live README conventions of `docs/links/README.md`
> instead.

## Stack

| Layer      | Choice                                                                  | Note                                                       |
| :--------- | :---------------------------------------------------------------------- | :--------------------------------------------------------- |
| Build      | Vite 7 + TypeScript 5, `strict`                                         | `npm run build` typechecks first.                          |
| UI         | React 19 + React Router 7                                               | One shell, one real screen; `auth/*` reserved (#1250).     |
| Data       | TanStack Query 5, **in-memory only**                                    | No persister, by construction.                             |
| Backend    | supabase-js v2, typed by `supabase/database.types.ts`                   | The snapshot's first consumer (see below).                 |
| Validation | Zod at the network boundary                                             | `src/lib/schemas.ts` validates what actually comes back.   |
| Copy       | FormatJS (`react-intl`), catalogue generated from `lib/l10n/app_en.arb` | No user-facing string is typed in TSX — ESLint bans it.    |
| Styling    | Plain CSS files + generated design tokens                               | No CSS-in-JS (nothing may inject `<style>` under the CSP). |
| Test       | Vitest + Testing Library; Playwright + `@axe-core/playwright`           | `npm run test` / `npm run e2e`.                            |
| Toolchain  | npm with a lockfile; Node pinned `22` like `site/`                      | `.github/workflows/ci.yml`, `webapp-deploy.yml`.           |

## The nothing-stored rule

The browser keeps nothing at rest — the rule is enforced from three
directions, and CI fails if any of them regresses:

1. **ESLint bans the storage surfaces in app code** (`eslint.config.js`):
   `localStorage`, `sessionStorage`, `indexedDB`, `caches`,
   `navigator.serviceWorker`, and `document.cookie` are restricted in
   `src/**`. `test/lint-bans.test.ts` lints offending snippets through the
   real config and fails if the ban stops firing (the acceptance criterion:
   "a lint test proves the storage ban fires").
2. **supabase-js cannot write a session either**: the client is created with
   an in-memory storage adapter (`src/lib/supabase.ts`), so even a signed-in
   session lives only in page memory.
3. **A Playwright test asserts the browser is empty after a session**
   (`e2e/storage-empty.spec.ts`): all six surfaces measured, all must be
   empty. Later issues extend this test as the client grows.

## Generated sources (never edit by hand)

Two build-time generators feed the client from single sources outside
`webapp/`; both artifacts are committed, and freshness tests fail when they
drift — the same discipline CI applies to `db.g.dart`:

- **Message catalogue** (`scripts/generate.mjs`, run by every
  `npm run dev`/`build`): `src/i18n/messages.en.json` + the typed
  `MessageId` union in `src/i18n/message-ids.ts`, generated from
  `lib/l10n/app_en.arb` — the same file the Flutter app translates from, so
  user-facing copy has exactly one home. `t('id')` (in `src/i18n/t.ts`) is
  the only door to copy; the ESLint no-typed-copy ban enforces it.
- **Design tokens** (`src/theme/tokens.generated.json` + derived
  `src/theme/tokens.css`): the resolved M3 colour schemes, type ramp,
  spacing, radii, elevation, and motion — produced from the app theme by
  `flutter test tool/export_webapp_tokens_generate_test.dart` (re-run that
  after touching `lib/ui/theme/`). Hand-written CSS may reference
  `var(--ll-*)` only; `test/tokens.test.ts` scans for literal colours.

## Supabase types

`src/lib/supabase.ts` imports `supabase/database.types.ts` directly — the
web client is that snapshot's first consumer. A migration that changes a
shape this client reads breaks `npm run typecheck` here, and CI's
`db-tests` job breaks the other direction when the snapshot drifts from the
migrations. Zod schemas (`src/lib/schemas.ts`) strip unknown keys, so a
column _addition_ is never a runtime failure — the field is picked up when
the UI wants it.

## Commands

```
npm ci                # pinned by package-lock.json
npm run generate      # regenerate catalogue + tokens CSS (predev/prebuild run it)
npm run dev           # Vite dev server
npm run lint          # ESLint (storage + copy bans) and Prettier
npm run typecheck     # tsc --noEmit
npm run test          # Vitest unit tests
npm run build         # typecheck + Vite production build -> dist/
npm run e2e           # Playwright: smoke + axe + nothing-stored guard
```

The e2e suite runs against `vite preview`, which serves the build with the
staging Worker's exact security headers (`worker/headers.ts` — the single
source of truth, imported by both `worker/index.ts` and `vite.config.ts`).

## Staging deploy

`.github/workflows/webapp-deploy.yml` builds and deploys to the
`lunarlog-app-staging` Cloudflare Worker on every push to `main` that
touches `webapp/**`, `supabase/database.types.ts`, or
`lib/l10n/app_en.arb`. Staging **only**: the origin is the Worker's
`workers.dev` hostname (the per-account subdomain is resolved from the
Cloudflare API at deploy time), backed by the production Supabase project,
and used **only with the fabricated accounts from #710**. Moving
`app.lunarlog.app` over is #1258. Until the `CLOUDFLARE_*` secrets are
present the deploy steps warn and skip, like `site-deploy.yml`.

Every response carries the security headers declared in
`worker/headers.ts` (set by `worker/index.ts`, which owns all routes via
`run_worker_first`): CSP with `script-src 'self'` (no `unsafe-inline`,
`unsafe-eval`, or `wasm-unsafe-eval`), `connect-src` self plus the Supabase
project over https and wss, `frame-ancestors 'none'`,
`require-trusted-types-for 'script'` (the stack passes with it — proven by
the e2e suite under real Chromium enforcement), HSTS, COOP `same-origin`,
`X-Robots-Tag: noindex`, and no third-party anything. After each deploy,
`.github/scripts/check-webapp-staging.sh` (the repurposed
`check-web-deploy.sh` header/beacon assertions) re-asserts the posture
against the live origin.

## CI

The `Web app (lint, typecheck, unit, build, e2e)` job in `ci.yml` is
path-filtered to `webapp/**`, `supabase/database.types.ts`, and
`lib/l10n/app_en.arb` (issue #1249; #1251 adds the domain module's paths),
and runs `deno check`/`deno test` on `worker/` plus the full npm suite and
the Playwright tests. It is deliberately **not** a required check — not in
`.github/scripts/check-ci-gate.sh`'s `REQUIRED_CHECKS` and not in the
ruleset rollup's `needs:` — so the store release gate stays anchored to the
app's own suites (the issue's acceptance criterion; a path-filtered job in
the rollup would fail every docs-only PR with a "skipped" dependency).

## Deliberately not here yet

- **Auth** (#1250): the `/auth/*` route and Worker entry are reserved; the
  page renders catalogue placeholder copy.
- **Domain module** (#1251): `useProfiles` proves the
  supabase-js → Zod → TanStack Query path; the real screens come later.
- **Custom domain** (#1258): staging is workers.dev only.
- **`/auth/*` Worker special-casing**: none needed yet — the SPA fallback
  serves it; #1250 decides whether the Worker must answer it first.
