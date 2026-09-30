---
title: Thin-Client Web (Issue #1161 umbrella, #1173 plan doc) - Plan
type: docs
date: 2026-09-28
issue: wjdavis5/lunarlog#1173
artifact_contract: ce-unified-plan/v1
artifact_readiness: ready-for-owner-review
product_contract_source: issue-1161
execution: ideation
---

# Thin-Client Web — Plan for Owner Review (Issue #1173, umbrella #1161)

> **Superseded by #831 (React client).** The thin client this plan designed
> is being built as the React app in `webapp/` — scaffolded by issue #1249
> (Vite + React + TypeScript strict, in-memory-only data, the
> nothing-stored rule enforced by lint and an end-to-end test) — rather
> than as the evolution of the Flutter web build several sections here
> analyse. The plan's requirement (the browser keeps nothing at rest) is
> the same one `webapp/` enforces from its first commit; read this document
> for the analysis and the decision trail, `webapp/README.md` for the
> shipped posture.

Date: 2026-09-28 · Branch: `zcode-flow/1173-web-thin-client-plan-doc` ·
Umbrella: #1161 (open; this plan is what its implementation gates on) ·
Companion inputs: #831 (the signed-in-web epic this revises), #1091/#1101
(web CSP and policy hosting), #30 (passkeys — web explicitly out of scope
there), #1095 (PWA installability, deferred), #1110 (Sentry on web,
unverified).

All paths repo-relative. Every citation was re-verified against this
checkout (tip `16ca695e`, 2026-09-28). Where #1173's body, the triage
brief, or a doc has drifted from the tree, the drift is called out rather
than copied — one material correction is called out up front (G5).

## Context

The owner's direction on #1161 (2026-09-28):

> "the browser shouldn't be storing anything really, it should simply be
> interacting with the back end. aka front end / back end etc."

Today the web build runs the **full offline-first local store in the
browser**: Drift over WASM SQLite persisted to IndexedDB
(`lib/data/db/web_db.dart:14-32`, assets `web/sqlite3.wasm` +
`web/drift_worker.js`), with accounts/sync additionally gated behind the
`LUNARLOG_WEB_SYNC` define. The deployed web app is already compiled with
that define set to `true` (`.github/workflows/web-deploy.yml:96`), so
production web is a signed-in *capable* client — but sign-in is optional:
signed out, the browser build happily uses its own local IndexedDB store
offline-first, exactly like a phone.

The change #1161/#1173 ask a plan for: **on web, the browser becomes a
thin client — sign-in required, every byte of app data served from the
backend over the existing sync path, and the only thing the browser keeps
at rest is the auth session.** Mobile is untouched: offline-first local
storage stays an iOS/Android device feature.

This document is that plan. It merges as a docs PR; implementation slices
get filed as child issues only after the owner approves it (#1173's own
acceptance criterion).

## Inventory — what ships today (verified)

### The storage seam

- **Web executor:** `webDbFactory()` (`lib/data/db/web_db.dart:14-32`)
  opens drift's `WasmDatabase.open` — IndexedDB-backed persistence via
  `web/drift_worker.js` + `sqlite3.wasm` (version-matched drift-2.34.3
  release assets). No COOP/COEP headers required; it falls back through
  shared/unsafe IndexedDB modes.
- **The one factory seam:** `LunarLogDbFactory`
  (`lib/data/db/db_factory.dart:27-68`) is platform-agnostic and owns the
  quarantine-on-failed-open policy; platform wiring is injected via the
  conditional export `lib/startup/startup_web.dart:8` →
  `webDbFactory()` and `lib/startup/startup_native.dart:49-66` →
  `nativeDbFactory()`. Web's `existingFileCheck` is null — "not
  file-backed", treated as first-run (`db_factory.dart:39-44`).
- **Everything above the executor is platform-shared.** The single
  composition root `buildAppDependencies`
  (`lib/composition/app_dependencies.dart:296-530`) constructs every
  repository — `DriftProfilesRepository`, `DriftDayEntriesRepository`,
  and twelve more — from one `db.storage` (`LunarLogStorage`),
  typed as the pure domain interfaces in `lib/domain/repositories/`
  (fourteen files). `lib/ui` never sees a concrete implementation.
- **`LunarLogStorage` is where the hard rules live**
  (`lib/data/db/storage.dart:1-50`): strictly-increasing `updated_at`
  LWW, payload limits mirroring the server CHECKs, the server-clock
  offset, dirty flags for the push half, tombstoned deletes, the
  same-date resolver, the per-id resolvers for observations/care
  notes/visit-prep items.
- **The sync path** (`lib/data/sync/supabase_sync_engine.dart:1-37`,
  contract in `lib/domain/sync/sync_engine.dart:16-56`): pushes dirty
  rows through `sync_push`, pulls remote pages per table by
  `server_version`, full reconcile at bind and daily. Phases include
  `restoring` (bind-time full pull) and `awaitingUploadConsent` (a
  confirmed session over a **non-empty unbound** database — R14). Cycle
  triggers: gate-unlock edge, auth transitions, app resume, a debounced
  local-write signal, a periodic timer. Gating (KTD10): a cycle runs only
  while unlocked + signed in + bound.

**Consequence worth stating plainly:** "repositories over a remote-backed
store" already exists in everything but name — the repositories are
remote-*backed* through the sync engine; what makes the browser "heavy"
today is only the *persistence backend* the executor picks. The plan's
central recommendation (D-1) turns on this fact.

### The define story

- `LUNARLOG_WEB_SYNC` is read exactly once —
  `AppConfig.webSyncEnabled` (`lib/config.dart:49-54`, literal `true`
  only; `parseWebSyncEnabled` at `:335` is the testable rule).
- `hasSupabase` additionally requires it on web
  (`lib/config.dart:65-67`): a web build without the define has **no
  account section, no sync** — the unconfigured/dev posture.
- The single-seam pin is `test/architecture/web_sync_flag_seam_test.dart`
  (define literal appears only in `lib/config.dart`; consumers read the
  resolved constant through injection seams).
- The deployed build passes it (`web-deploy.yml:96`); CI never does
  (`ci.yml:480,503` builds web release with the eleven client-safe
  defines, `LUNARLOG_WEB_SYNC` absent); `dart_defines.example.json:6`
  carries `"false"` for local runs.
- Web auth plumbing already shipped with #831 slice 2:
  `buildAuthClientOptions` keeps PKCE-only + `detectSessionInUri: false`
  on every platform, passes **no** custom storage on web — so the session
  and PKCE verifier live in gotrue's own browser storage (`localStorage`),
  cleared by `signOut` — and web auth emails redirect to
  `<origin>/auth/callback` (`test/architecture/web_auth_seam_test.dart`;
  `web/_redirects` SPA fallback is load-bearing for that route).

### The device-credential gate

- `AppGate` (`lib/domain/gate/app_gate.dart:14-33`) is the one seam: the
  shell refuses to render profile data until `requestAccess` returns
  true, and on gated platforms refuses to open the database at all.
- The conditional export (`lib/startup/gate/gate.dart:6-8`) gives web the
  no-op: `WebAppGate` — `requiresUnlock` false, `canAuthenticate`/
  `requestAccess` trivially true (`lib/startup/gate/web_gate.dart:11-20`).
  There is no OS device credential to present in a browser, so v1 ships
  none.
- The in-app PIN (`lib/data/gate/pin_credential_store.dart`, issue-set
  #271/#845-adjacent) is a second, additive layer over the device
  credential; its web build runs PBKDF2 on the UI isolate
  (`:75`). It guards an open session, not data at rest — on web there
  is no OS-protected store behind it (`flutter_secure_storage` on web is
  browser-storage-backed, the same exposure PRIVACY.md §6 already
  discloses for the session).

### Export / import

- The JSON export builder reads the repositories over the local store and
  merges the server half via `export_account_data()` when signed in
  (`lib/domain/export/account_export.dart:1-38` — "The local encrypted
  Drift store is the app's source of truth (KTD5)").
- **Drift from the brief, verified and corrected:** the triage brief and
  #1173's body describe web export as "the no-account-required export
  story today reads the local Drift store". The builder does — but the
  export/import UI does not render on web **at all** today:
  `_canExport => widget.showExport ?? !kIsWeb` and
  `_canImport => widget.showImport ?? !kIsWeb`
  (`lib/ui/settings/your_data_section.dart:149-150`), and the CSV/FHIR
  tiles return `SizedBox.shrink()` on web
  (`lib/ui/settings/csv_export_tile.dart:126`,
  `lib/ui/settings/clinical_export_tile.dart:162`). No-account export is
  a native-only story today; the thin client cannot resurrect it (no
  local data exists to export), it can only add a *signed-in* export.
  This is G5 below and D-5's subject.

### The docs surface (what the change must rewrite)

- **`site/src/pages/guides/browser-version.astro`** — "What the browser
  keeps" (`:30-57`) teaches today's model verbatim ("the browser holds a
  working copy of it while you are signed in", unencrypted, no lock of
  its own), "Shared computers" (`:59-94`) leans on sign-out-wipes-the-copy,
  and "What the browser version is good for" (`:96-113`) covers the
  dev-build banner state. Every factual claim carries a `<!-- cite: ...`
  ledger entry validated by `site/scripts/check-claims.mjs`, which fails
  the Astro build when a cited path no longer exists — so code removals
  and this rewrite must land together or the site breaks. (The site
  workflow runs on pull requests: `.github/workflows/site.yml:20-22`.)
  #1173 pins this rewrite to PRs #1159's and #1167's review conditions;
  I could not retrieve that review-condition text from either PR's
  comments or merge commits on GitHub — the requirement stands on
  #1173's own body and on the guide's current content, which plainly
  describes the at-rest-copy model this plan retires.
- **`PRIVACY.md`** — §6's "Signed-In Browser Build (Web)" bullet
  (`PRIVACY.md:133`) discloses the IndexedDB copy and the
  localStorage session; §1's "Protected at Rest" bullet names the browser
  as the deliberate exception (per the 2026-09-21 change-history entry,
  `PRIVACY.md:201`); §10 carries the dated change history. The policy is
  rendered at lunarlog.app/privacy from this file (issue #1101;
  `web/_redirects`'s `/privacy.html` 301).
- **`docs/web/security-posture.md`** — the whole doc is today's posture:
  "What the browser build is today" (`:18`), "Where the Supabase session
  lives on web today" (`:91`), "What `LUNARLOG_WEB_SYNC=true` exposes"
  (`:128`), Decisions (`:197`), Deferred (`:260`).
- **ARB copy the guide renders through `<UiLabel>`** —
  `webBannerSyncedCopy` ("this browser stores a copy of the signed-in
  profiles' data unencrypted, plus your sign-in…"),
  `webFirstRunSyncedBody`, `webWipe*` (`lib/l10n/app_en.arb:4932-4949`),
  surfaced by `lib/ui/web/dev_banner.dart` (two honest states selected by
  `AppConfig.webSyncEnabled` — its header doc is the cleanest statement
  of today's model) and the first-run acknowledgement. `app_en.arb` edits
  regenerate `cards.json` via `tool/export_help_cards.dart`
  (freshness-pinned by `test/tool/export_help_cards_test.dart`).
- **AGENTS.md** describes the current posture too ("accounts and sync are
  off on web unless `LUNARLOG_WEB_SYNC=true`", the web bullet in the
  Supabase section) and must move in the final slice.
- `CONCEPTS.md`, `docs/product/positioning.md`, and
  `lib/domain/help/help_cards.dart` carry no web-storage claims today
  (grepped, zero hits) — the sweep surface is the four files above.

### What CI can and cannot prove (honest constraint)

`flutter test` cannot execute `dart:js_interop`/WASM code paths, and the
repo has no headless-browser integration harness. CI proves a web change
by: the seam/unit/widget pins around it (`test/config_test.dart`, the
`test/architecture/web_*` tests), `flutter build web --release` in the
Verify job (`ci.yml:503`), the site's `check-claims.mjs` on PRs, and the
full analyze/test/coverage/CRAP gates. **The ephemeral executor's runtime
behavior (does the store truly survive nothing? does bind-time pull
populate it?) is verified by a manual device checklist against the
deployed build, not by CI** — the same posture as the existing device
checklist in `docs/ops/supabase-go-live.md`. The slice plan below marks
where that manual run is the acceptance evidence.

## The four named areas, answered

### 1. The storage-layer seam

**Recommended shape (D-1, Option A): keep the entire stack; change only
the web executor's persistence backend, from IndexedDB to volatile
in-memory.**

- `webDbFactory()` swaps `WasmDatabase.open` (IndexedDB) for drift's
  in-memory WASM executor — `WasmDatabase.inMemory(sqlite3)` exists in
  the pinned drift 2.34.3 (verified in the local pub cache,
  `drift-2.34.3/lib/wasm.dart:80-84`) over the same `sqlite3.wasm`
  asset. `web/drift_worker.js` becomes unused and is deleted in the same
  slice.
- Everything above the executor is untouched: `LunarLogStorage`'s
  invariants, the fourteen domain interfaces, the fifteen drift
  implementations, `buildAppDependencies`, the sync engine, prediction,
  the UI. "What stays shared with mobile" is therefore: **all of it** —
  the only platform-divergent code is the ~30-line executor wiring in
  `lib/startup/startup_web.dart` and `lib/data/db/web_db.dart`, exactly
  the divergence that exists today.
- The sync path *is* the serving path: at sign-in the engine binds and
  runs the full pull (`restoring` phase) into the in-memory store; every
  write lands in the store and the debounced local-write trigger pushes
  it through `sync_push` within moments. Read streams, LWW, tombstones,
  and the same-date resolver are the same code mobile runs.
- The browser's at-rest footprint collapses to gotrue's session in
  `localStorage` — literally "nothing but the auth session".
- **Honest residual (KTD6):** an *offline* browser tab accumulates writes
  in memory that a tab close destroys, whereas today's web queues them in
  IndexedDB for later. The thin client therefore requires connectivity
  for durability, and the guide must say so ("the browser version needs a
  connection; if you log while offline, keep the tab open until it
  syncs"). This is the one real UX regression, and it is the price of the
  owner's stated model.
- `awaitingUploadConsent` (R14) never fires on a thin client: that phase
  triggers on a **non-empty unbound** database (`sync_engine.dart:41-44`),
  and a fresh in-memory store is empty at every bind — there is nothing
  to consent to. No code change is needed; a test pins it (S2).

**Rejected (Option B, recorded): per-interface remote-backed repository
implementations** — `RemoteProfilesRepository` et al. speaking
REST/RPC/Realtime directly. This re-implements exactly what the sync
engine already is (pull pages, `sync_push`, LWW, tombstones, resolvers),
doubles the security-reviewed surface, and would need reactive `watch`
re-implementations over Realtime for the fourteen interfaces. The owner's
direction is satisfied more faithfully by A: under B the browser still
holds a client-side cache whose consistency the app now maintains twice.
If the owner wants B anyway (OQ-1), it is a different plan — this
document does not pretend A's slices compose into B.

### 2. `LUNARLOG_WEB_SYNC` once web is sign-in-required

The define exists for exactly one reason: "a signed-in web session would
hold a bearer token in browser storage, so a default web build opts out
of accounts entirely" (`lib/config.dart:56-59`). The thin client does not
remove that exposure — the session still lives in `localStorage` — it
shrinks everything *around* it. What the define gates is no longer a
posture anyone wants: a signed-out web build with a local at-rest store
is precisely the thing #1161 retires.

**Recommendation (D-2): retire the define.** Web + configured Supabase
(`SUPABASE_URL` + key non-empty) ⇒ accounts on, sign-in required — the
same rule as native. `computeHasSupabase`'s `isWeb` conjunct goes away;
the literal's last read disappears; the seam pin flips to assert the
define appears **nowhere** in `lib/`; `web-deploy.yml` drops the flag;
`dart_defines.example.json` loses the key; AGENTS.md and
`docs/web/security-posture.md` §4 become history notes. Unconfigured web
builds (forks, PR Verify builds) keep today's dev posture — no account
section, and (post-S2) an ephemeral store — so "every workflow build must
succeed with empty defines" is preserved. Recorded alternative if the
owner wants a kill switch: keep the define with flipped default
semantics; rejected here because a boolean whose meaning changed
mid-life is worse than no boolean, and a second web posture means a
second disclosure, a second banner state, and a second test matrix
forever.

### 3. The device-credential gate on web

A browser has no device credential for `local_auth` to present, so the
honest answer is: **the gate's job is not re-implemented on web — it is
replaced.** On mobile the gate answers "may data be shown?" with a
biometric; on a thin client the equivalent question is "is there a
session?", and the answer is the sign-in requirement itself: a signed-out
web build renders the sign-in screen, never a data surface (S1). No
WebAuthn device-ceremony gate is proposed — #30 explicitly scoped
platform-authenticator use to native and its groundwork stays client-side
only.

`WebAppGate` stays a deliberate no-op for the *credential* ceremony
(`requiresUnlock` false), because KTD10's sync gating (a cycle runs only
unlocked) then means "whenever signed in" on web — correct for a client
whose store dies with the tab. The optional in-app PIN keeps working as a
shoulder-surf guard for an unattended open tab; it gains no at-rest
meaning on web (nothing is at rest) and keeps its existing browser-storage
backing, already covered by the session disclosure. The
shared-computer guidance ("sign out when you are done, every time") moves
from the guide's at-rest story to its session story, and stays the
primary control.

### 4. Export/import on web

With G5's correction on the table, the decision is not "re-wire" but
"introduce or don't":

- **Keep export native-only** (the default, smallest posture): the
  thin client changes nothing here; `Your data` stays absent on web; the
  no-account export story remains a native feature, correctly described
  as such in AGENTS.md.
- **Add signed-in JSON export on web (D-5's recommendation, as a late
  optional slice S4):** on a thin client the export's "local" half is the
  pulled account data, so `buildMergedAccountExport` degrades to
  "pulled rows + server section" with no builder change; the only new
  surface is a web download path in the writer seam (share_plus has no
  browser equivalent — a browser download/`AnchorElement` writer behind
  the existing `AccountExportWriter` interface). This closes the
  right-of-access parity gap the current web-hide creates (a browser user
  cannot exercise export at all) at the cost of one new writer plus its
  tests. Import stays native-only either way on this plan (additive merge
  into an account from a browser is fine mechanically — it is the same
  coordinator — but it widens the write surface for no stated demand;
  deferred with a recorded rationale).

### 5. Migration of today's browser-resident data

Real users of the deployed app.lunarlog.app have months of IndexedDB
rows. The flip must **delete that copy, not orphan it** — leaving it
would violate the very direction ("the browser shouldn't be storing
anything") on every upgraded device. S2 carries a one-time, best-effort
removal of the drift-created IndexedDB databases on first thin-client
launch (browser `indexedDB.deleteDatabase` against the `lunarlog`
database name and drift's internal stores; the exact handle is a coder
detail verified in the manual run), *before* the first pull, with the
discard disclosed in PRIVACY.md §10 and the guide's rewrite. Doing
nothing (OQ-5's silent-orphan option) is recorded and rejected: silent
at-retention of health data the product just promised not to keep is the
worst of both worlds.

## Numbered decisions

**D-1 — Option A: ephemeral in-memory store + the existing sync path.
**Owner's** to confirm (OQ-1) because #1173's brief says "repositories
over a remote-backed store", and A keeps the repositories Drift-backed
over an ephemeral store. The plan's position: the brief's wording
describes a mechanism, the owner's direction describes a property —
"stores nothing, served from the backend" — and A delivers the property
with one executor change instead of a fourteen-interface rewrite that
duplicates the sync engine. B remains available as a separate plan if the
owner reads it differently.

**D-2 — Retire `LUNARLOG_WEB_SYNC`.** Recommended; alternative (kill
switch with flipped semantics) recorded at OQ-2.

**D-3 — Sign-in required = the web's gate.** `WebAppGate` stays a
no-op for the credential ceremony; the session requirement is the gate;
the PIN layer continues as an optional open-tab guard. Recorded as
decided unless the owner wants a WebAuthn ceremony (out of scope per
#30).

**D-4 — Banner/first-run copy collapses to the thin-client truth.**
Today's two banner states (`dev_banner.dart` header doc) and the
first-run acknowledgement teach the at-rest-copy model. Post-change there
is one web truth: "this browser holds only your sign-in until you sign
out; your data lives in your account; you need a connection." Whether
that survives as a slim persistent banner, a one-time first-run notice,
or nothing is copy the **owner** should see (OQ-4); the plan defaults to
a one-time notice + the rewritten guide, and retires the wipe action
(there is no local data left to wipe — sign-out/clear-site-data covers
the session).

**D-5 — Signed-in JSON export on web is recommended as optional slice S4;
import stays native-only.** Owner includes or drops S4 (OQ-3).

**D-6 — One-time best-effort disposal of existing IndexedDB data at
upgrade, disclosed.** Recorded as decided (see §5 above); OQ-5 records
the rejected silent alternative and a "notify before discarding" middle
option.

**D-7 — Docs move with behavior, atomically.** #831's non-negotiable
("the build and the disclosure move together") applies to every slice
that flips a user-visible fact: PRIVACY.md, the guide, and the ARB copy
land in the same PR as the code. The site's cite-ledger enforces this
where the ledger actually reaches: a cited path that disappears fails
the Astro build, and the site workflow runs on any PR touching
`lib/ui/**` — so deleting `lib/ui/web/dev_banner.dart` (cited five
times by `site/src/pages/guides/browser-version.astro`) without
rewriting that guide goes red on `check:claims`. The example this
decision originally claimed was covered — `web/drift_worker.js` — is
*not* ledger-cited (no guide names it) and, once slice S2 deletes it,
never can be; a code-only `web/**` PR does not even trigger the site
workflow. Its guide rewrite therefore rests on the slice rule itself
(same PR, reviewer-checked), not on the ledger. (Correction: post-merge
audit, issue #1182.)

**D-8 — No server-side change of any kind.** No migration, no RLS
change, no new RPC: `sync_push`, the pull queries, and `export_account_data()`
already serve everything the thin client needs, and RLS is unchanged.
Regenerating `supabase/database.types.ts` is therefore not required, and
the Drift `schemaVersion` does not move (the schema is untouched; only
the executor's persistence backend changes — `build_runner` has nothing
to regenerate). Each slice's CI story is `flutter analyze`, targeted
`flutter test`, the Verify job's web build, and (for doc-touching
slices) the site's claim checks.

## Units of work (PR-sized slices, each independently CI-verifiable)

Ordered; each lands green on `main` alone. S1 must precede S2 (a flipped
executor under today's signed-out-optional posture would strand a
signed-out user in an empty app); S3 is safe any time after S1 but reads
best after S2; S4/S5 are optional/independent.

- **S1 — Sign-in required on web (~300).** The web shell renders the
  sign-in screen in place of every data surface until a session exists;
  `FirstRunScreen`'s web branch — including the `webSyncOff` empty state
  (`lib/ui/profiles/first_run_screen.dart:938`, `isWebBuild` seam `:147`)
  — is replaced by the sign-in entry; the banner's first copy pass lands
  (D-4's interim truth). `hasSupabase`'s web conjunct is untouched in
  this slice (the define still gates accounts; the *behavior* of a
  sync-enabled web build changes). PRIVACY.md §6 gains the "sign-in
  required" sentence; the guide's "good for" section updates.
  **Tests:** widget pins for the signed-out web shell (sign-in shown, no
  data screens, both flag values in one default-off run per the
  injection-idiom rule), `test/config_test.dart` unchanged. **CI:**
  analyze, targeted tests, Verify's web build, site checks (guide +
  PRIVACY.md anchors).

- **S2 — Ephemeral executor + disposal + at-rest disclosures, atomically
  (~400).** `webDbFactory()` → in-memory executor; `web/drift_worker.js`
  deleted; one-time IndexedDB disposal (§5, D-6); the pinned
  `awaitingUploadConsent`-never-fires-on-web test; the connectivity
  durability note (KTD6) in the guide; PRIVACY.md §1/§6/§10 rewritten
  (at-rest exception removed, session-only story stated, change-history
  entry dated); `docs/web/security-posture.md` §1/§3 rewritten; the
  browser-version guide's "What the browser keeps" rewritten per D-4/D-7.
  **Tests:** db-factory pins for the volatile executor (both platforms'
  wiring via the seam), disposal best-effort unit pins (typed failure
  only), all existing storage/repository/sync suites green unchanged (the
  point of D-1). **Manual (recorded in the PR, not CI):** deployed-build
  checklist — sign in, pull populates, write+push, tab close destroys,
  IndexedDB empty after upgrade, offline-tab behavior matches the guide's
  words. **CI:** as S1.

- **S3 — Retire `LUNARLOG_WEB_SYNC` (~200).** `computeHasSupabase` loses
  the `isWeb` conjunct; the define literal's last read goes; the seam pin
  flips to "appears nowhere in `lib/`"; `web-deploy.yml` drops the flag
  and `.github/scripts/tests/check-web-deploy.test.sh` is updated in the
  same change; `dart_defines.example.json` loses the key;
  `lib/config.dart` docs and AGENTS.md move to the new posture;
  `security-posture.md` §4 becomes a history note. **Tests:**
  `test/config_test.dart` (the conjunct's removal pinned),
  `web_sync_flag_seam_test.dart` (flipped assertion), the check-web-deploy
  test. **CI:** analyze, targeted tests, Verify web build (empty defines
  — the unconfigured posture must still compile and boot).

- **S4 — (Optional, on OQ-3) Signed-in JSON export on web (~250).** A web
  download writer behind `AccountExportWriter`; `your_data_section.dart`'s
  `!kIsWeb` default flips to "export when signed in" (import stays
  hidden); PRIVACY.md §7 gains the web export sentence. **Tests:** writer
  unit pins (browser download seam), tile visibility matrix (web
  signed-in/signed-out, native). Dropped without ceremony if the owner
  keeps export native-only.

- **S5 — Docs sweep (~100, docs-only).** Whatever drift the earlier
  slices left: AGENTS.md web sentences (if S3 didn't absorb them),
  `docs/web/security-posture.md` §5 decisions list, any straggler
  "offline-first on web" phrasing a repo-wide grep finds at merge time.
  **CI:** site checks only.

## Test plan

- **Per slice:** named targeted suites above; the repo's standing gates
  (`flutter analyze`, the three coverage shards + 90% floor + CRAP) run
  in CI on every PR regardless.
- **Must stay green unchanged** (the D-1 payoff): every
  `test/data/**` storage/repository suite, every sync-engine suite, every
  prediction/domain suite. A slice that touches one of those is a bug in
  the slice.
- **Web runtime truth is manual** (see the honest-constraint note):
  S2's PR records the deployed-build checklist and its results; CI
  cannot substitute for it, and this plan says so rather than wiring a
  new browser-test harness under this epic (out of scope; if the owner
  wants headless-browser CI, it is its own infrastructure issue).

## Out of scope

- Any server-side change: migrations, RLS, RPCs, Edge Functions (D-8).
- Mobile behavior of any kind — offline-first, gate, health sync, widget
  (the whole point of the shared-stack result).
- The web visual layout (#1161's own out-of-scope note).
- PWA installability/offline (#1095), WebAuthn/passkeys on web (#30),
  Sentry-on-web verification (#1110), web push (FCM is native-gated,
  `lib/config.dart:192-199`).
- Import (restore-from-file) on web (D-5).
- A headless-browser CI harness (recorded as its own future
  infrastructure issue if wanted).

## Open questions

1. **D-1's mechanism: ephemeral store + sync path (recommended), or
   true per-interface remote repositories?** — **owner's.** The plan
   reads #1161 as a property ("stores nothing, backend-served") and
   delivers it with the smallest security-reviewed change; if the owner
   meant the mechanism literally, B is a different plan and this one
   should be re-scoped before any slice lands.
2. **Retire `LUNARLOG_WEB_SYNC`, or keep it as a kill switch?** —
   **owner's** (D-2 / OQ-2). Recommendation: retire.
3. **Export on web: add signed-in JSON export (S4), or keep export
   native-only?** — **owner's** (D-5 / OQ-3). Recommendation: add S4;
   a browser user's inability to exercise right-of-access export is a
   real gap once web is the only place they live.
4. **Banner/first-run copy: which honest form survives — slim persistent
   banner, one-time notice, or nothing beyond the guide?** — **owner's**
   (copy/voice; D-4 / OQ-4). Default in the slices: one-time notice.
5. **Existing browser data: best-effort silent delete at upgrade
   (recommended, disclosed in §10), or a one-time "we're removing the
   browser copy" acknowledgement before deleting?** — **owner's**
   (D-6 / OQ-5); the silent option still discloses via the policy and the
   guide, it just doesn't interrupt.
6. **Exact ephemeral drift API (`WasmDatabase.inMemory` vs an
   `open()`-family variant) and the disposal handle for drift's IndexedDB
   stores** — **coder's**, resolved in S2 with the spike proven by the
   manual deployed-build run; the pub-cache verification above
   (`drift-2.34.3/lib/wasm.dart:80-84`) says the primitive exists.
