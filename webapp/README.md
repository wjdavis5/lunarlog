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
| UI         | React 19 + React Router 7                                               | One shell; the auth screens (#1250) sit outside `/auth/*`. |
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
   `localStorage`, `sessionStorage`, `indexedDB`, `caches`, `cookieStore`,
   `navigator.serviceWorker`, and `document.cookie` are restricted in
   `src/**` — as bare globals and through a qualified reference alike
   (`window.localStorage`, `globalThis.sessionStorage`,
   `window.navigator.serviceWorker`, `window.document.cookie`, …; issue
   #1275). `test/lint-bans.test.ts` lints offending snippets through the
   real config and fails if the ban stops firing (the acceptance criterion:
   "a lint test proves the storage ban fires").
2. **supabase-js cannot write a session either**: the client is created with
   the `accessToken` option (`src/lib/supabase.ts`, issue #1250) — per its
   own contract the `auth` namespace is then unusable, so no session is ever
   persisted or read back; an inert storage adapter sits underneath as
   belt-and-braces.
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
- **Tag taxonomy** (`src/lib/taxonomy/taxonomy.generated.json`,
  `scripts/generate-taxonomy.mjs`, issue #1254): the day editor's symptom
  vocabulary — codes, categories, display labels, the single-select and
  positive-assertion rules — extracted from the app's own
  `lib/domain/tags.dart` (and `tracking_preferences.dart`'s
  minor-visibility set, `care_modes.dart`'s standard category headings),
  so the web picker speaks the app's taxonomy instead of re-typing it.
  `test/taxonomy.test.ts` re-runs the builder and fails on drift; when
  #1251 compiles `lib/domain` to JavaScript, the compiled module replaces
  this artifact.

## The day editor (issue #1254)

`src/pages/DayPage.tsx` (route `/day/:profileId?date=YYYY-MM-DD`) writes
every day category — flow, spotting, symptom and test tags, note with the
#849 privacy rules, PMS, BBT, weight, cycle corrections, life-stage mode —
through the same `sync_push` RPC the phones use, with client-generated ULID
ids and client-minted `updated_at`, so the server's last-writer-wins and
same-date merge rules treat the web as just another device. Reads go
through `sync_pull` (`src/lib/day/day-data.ts`), never raw `day_entries`
selects: the #849 private-note mask lives inside `sync_pull`, and a raw
select would hand a non-subject guardian text they must not hold. The
per-uid walk cache is page memory only; the storage-empty e2e guard
covers the day route.

## Supabase types

`src/lib/supabase.ts` imports `supabase/database.types.ts` directly — the
web client is that snapshot's first consumer. A migration that changes a
shape this client reads breaks `npm run typecheck` here, and CI's
`db-tests` job breaks the other direction when the snapshot drifts from the
migrations. Zod schemas (`src/lib/schemas.ts`) strip unknown keys, so a
column _addition_ is never a runtime failure — the field is picked up when
the UI wants it.

## The data layer (issue #1252)

`src/lib/domain.ts` is the one module every web screen reads and writes
account data through; `src/lib/queries.ts` wraps it in TanStack Query.
Reads go through **`sync_pull`** — the app's authoritative, guardian-scoped,
`server_version`-cursor RPC — paged to exhaustion (500 rows/page) so a
profile's full cycle history loads; `guardian_notes` and `settings`, which
`sync_pull` does not carry, ride their own RLS-scoped selects paged past
PostgREST's 1,000-row cap with `.range()`. The `sync_pull` path is chosen
over raw selects because private-note masking lives only on the RPC paths
(`mask_day_entry_note`): a raw `select` on `day_entries` passes guardian RLS
but would return an unmasked private note. Writes go exactly where the
app's writes go — the **`sync_push`** RPC with client-generated ULID ids
(`src/lib/ulid.ts`, the Dart `lib/data/db/ulid.dart` algorithm ported) and
client-generated `updated_at`; per-row rejections come back mapped to the
offending payload row. Guardian-membership changes ride the sharing RPCs.
Live updates subscribe to **`public.sync_signals`** (the Realtime
publication's only table) for the visible profiles and invalidate the
synced-data query; the wake payload is never treated as data.
`resetWebDataForSignOut` clears the pull cursors, the merged snapshot, and
the TanStack cache — all strictly in page memory.

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
`app.lunarlog.app` since 2026-10-03 (#1258): `webapp-deploy.yml` retires the
Flutter build's `lunarlog-app` Pages project (freeing the hostname) and
attaches `app.lunarlog.app` to this Worker as a custom domain
(`wrangler.jsonc`'s `routes`), with the `workers.dev` hostname kept as the
staging alias (#1249). The Worker also performs the #1248 retirement
duties on the production origin: `Clear-Site-Data: "cache", "storage"` on
the app shell (never `"cookies"` — the refresh cookie must survive), a
301 from `/privacy.html` to the apex policy, and a self-unregistering
service worker at the old `/flutter_service_worker.js` path. Until the `CLOUDFLARE_*` secrets are
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
`lib/l10n/app_en.arb` (issue #1249; data-layer paths — `webapp/src/lib/**`
and `webapp/test/integration/**`, issue #1252 — additionally turn on the
database suite), and runs `deno check`/`deno test` on `worker/` plus the
full npm suite and the Playwright tests. The data layer's integration tests
run in the **`db-tests`** job against the local Supabase stack that job
already boots for pgTAP (the suite skips itself when no stack is
reachable); realtime delivery itself is proven manually by
`supabase/tests/manual/verify_realtime_delivery.mjs` — the db-tests stack
deliberately excludes the realtime container (AGENTS.md, Migration Flow).
The webapp job is deliberately **not** a required check — not in
`.github/scripts/check-ci-gate.sh`'s `REQUIRED_CHECKS` and not in the
ruleset rollup's `needs:` — so the store release gate stays anchored to the
app's own suites (the issue's acceptance criterion; a path-filtered job in
the rollup would fail every docs-only PR with a "skipped" dependency).

## Auth (issue #1250)

Sign-in runs entirely through the same-origin Worker (`worker/auth.ts`),
which proxies Supabase Auth's GoTrue HTTP API. The browser's only credential
is the **access token in page memory**; the refresh token lives in the
rotating `__Host-ll_refresh` HttpOnly Secure SameSite=Strict cookie and is
never in a response body, and the PKCE verifier rides its own short-lived
`__Host-ll_pkce` HttpOnly SameSite=Lax cookie so the OAuth/emailed links
land in the same browser. Every state-changing route demands the app's
`Origin` plus an `x-lunarlog-csrf` custom header (the CSRF gate), on top of
the SameSite=Strict cookie. supabase-js is created with the `accessToken`
client option fed from `src/lib/auth.ts`'s in-memory token, renewed through
`GET /auth/session` (which rotates the cookie) with a single in-flight
renewal per tab.

- **Routes** (`worker/auth.ts`): password sign-in/sign-up, the emailed
  8-digit code and magic link (send + verify), Google/Apple PKCE start and
  the `POST /auth/callback` exchange (the provider's `GET` lands on the SPA
  page), password reset + update, session refresh, and sign-out on this
  device or everywhere. Failures carry GoTrue's own error codes so the UI
  can reuse the app's failure copy (`src/lib/authCopy.ts`). The recover
  email's PKCE cookie carries a `recovery:` marker beside the verifier that
  the callback echoes in its response (issue #1293) — GoTrue's redirect back
  carries only `?code=`, never `?type=recovery`, so the marker is what sends
  the callback page to the new-password step.
- **Upstream shapes** mirror the installed @supabase/auth-js wire format
  (grants at `/auth/v1/token?grant_type=…`, `redirect_to` as a query
  parameter, `code_challenge` in the body), verified against
  `node_modules/@supabase/auth-js`.
- **Tests**: `worker/auth.test.ts` (Deno) covers the cookie flags,
  rotation, CSRF rejection, the different-browser `verifier_missing`
  callback error, and the OAuth start against a stubbed Supabase; the
  browser side is covered by `test/auth.test.ts`, `test/authCopy.test.ts`,
  and `test/auth-pages.test.tsx`. Real Google/Apple/email-link sign-in
  needs #1093's console steps; the live-provider checklist is #1258.
- **Deploy**: the Worker's publishable key is set as the Wrangler secret
  `SUPABASE_PUBLISHABLE_KEY` by `webapp-deploy.yml` from the
  `SUPABASE_ANON_KEY` repository secret (warn-and-skip on forks; the auth
  routes answer `503 auth_not_configured` until it exists).

## The Dart domain module (issue #1251)

The web client does not re-implement the app's cycle logic in TypeScript:
`lib/domain` (pure Dart — no Flutter, `dart:io`, Drift, or Supabase imports)
is compiled to JavaScript once and both platforms run the same engine.

- **Build** (from the repo root; needs the Flutter SDK's `dart`, because the
  root pubspec resolves under the Flutter SDK):

  ```
  flutter pub get
  dart compile js -O2 tool/web_domain/main.dart \
    -o webapp/public/domain/lunarlog_domain.js
  ```

  The artifact is **not committed** (gitignored); CI builds it before the
  suite runs. dart2js (not WASM) keeps the output a plain same-origin
  script — clean under the staging CSP's `script-src 'self'` and no
  Trusted Types sink; `index.html` loads it with a static `<script>` tag
  and `e2e/domain-module.spec.ts` proves it answers under the real headers.

- **The facade** (`tool/web_domain/facade.dart`) is JSON-in/JSON-out:
  `window.lunarlogDomain.invoke(method, requestJson)` answers
  `{"ok": true, "data": ...} | {"ok": false, "error": "..."}`. It covers
  prediction (life-stage/birth-control suppression and the confidence tier
  included), cycle history, the home-screen insights, day-entry date-bounds
  validation, the JSON export builder (app file format, phone-restorable),
  and invite-link parsing. `today` and the browser's IANA zone are passed
  in on every request; the tz database (`latest_10y`) is loaded explicitly.

- **The typed client** (`src/domain/client.ts`) unwraps the envelope
  (`DomainCallError` on `ok: false`) and validates every output with the
  Zod schemas in `src/domain/schemas.ts` — the same boundary discipline
  the Supabase schemas apply.

- **Parity** (`test/domain/parity.test.ts`): the committed
  `test/domain/fixtures.json` is generated by the Dart side
  (`dart run tool/web_domain/generate_fixtures.dart`), pinned in the
  Flutter suite by `test/domain/web_domain_fixtures_test.dart`, and run
  through the compiled module here — Dart and JavaScript can never drift
  apart silently. A fixture change shows up in the PR diff; regenerate it
  only when a domain output change is intentional.

## Deliberately not here yet

- **Domain screens** (#1251's successors): the compiled module and its
  typed client exist (`src/domain/`); no screen consumes them yet — the
  prediction/history/insights UIs are later slices of the epic. The
  raw-data half of that story is the data layer (issue #1252):
  `useLiveProfiles` proves the supabase-js → `sync_pull` → Zod →
  TanStack Query path.
- ~~**Custom domain** (#1258)~~ — shipped 2026-10-03: the custom-domain attach runs in the deploy; that move also
  re-checks the live-provider flows and how Supabase counts the Worker's
  rate-limited requests (the Worker already forwards
  `CF-Connecting-IP` as `X-Forwarded-For`).
