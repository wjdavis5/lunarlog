# Web security posture

**Status:** decision record, slice 1 of epic #831. The owner chose **Option A —
the web build is a first-class client**. This document resolves the KTD9
posture epic #831 called out: a signed-in browser holds the account's rows and
a bearer token in a context whose threat model differs materially from a
signed app binary. It records the decisions this slice makes, the code facts
behind them, and what remains deliberately deferred.

**Scope of this slice:** the security posture itself, the static headers, the
disclosure copy that must land with sync (the banner and first-run
acknowledgement), and the privacy disclosure. Hosting, deploy automation, DNS,
and the PWA/offline decision are tracked as follow-ups and are **not** changed
here.

---

## 1. What the browser build is today

Everything below is read directly from the current code, not asserted from
external documentation.

- **The web build compiles on every PR** (`flutter build web --release` in the
  `Verify` job of `.github/workflows/ci.yml`) but is **not deployed anywhere
  yet** — there is no Pages/Netlify/Vercel/Hosting step. The artifact is built
  and discarded.
- **Accounts and sync are off by default on web.** `AppConfig.hasSupabase`
  (`lib/config.dart`) is false on web unless the build was compiled with
  `LUNARLOG_WEB_SYNC=true`; no workflow sets that define. Without it, the web
  build is a purely local client: no Supabase client is initialized, no
  account section renders, and nothing leaves the browser.
- **Local storage on web is drift over WASM SQLite with IndexedDB
  persistence** (`lib/data/db/web_db.dart`), loaded from the version-matched
  `web/sqlite3.wasm` and `web/drift_worker.js`. There is no app-managed cipher
  on any platform — local data relies on the OS at-rest protection on
  iOS/Android, and on **nothing equivalent** in a browser (Section 2).
- **The banner and first-run acknowledgement currently say "not for real
  data."** `lib/ui/web/dev_banner.dart`'s own header states the old posture
  plainly: *"the web build is deliberately insecure, so it carries its own
  warnings and an escape hatch."* Epic #831's non-negotiable rule is that the
  web build must never quietly become sync-enabled while it still tells the
  user it is not for real data; this slice changes both surfaces together with
  the disclosure in Section 5.

## 2. Browser threat model vs a signed binary

A signed app binary and a page served from an origin are not the same trust
boundary. The differences that matter here:

| Property | Signed native app | Browser page |
| :--- | :--- | :--- |
| **Code identity** | Code-signed, reviewed, installed by the OS; ships as one artifact | Arbitrary JavaScript executes in the page's origin context the moment it is reached |
| **Script execution** | Only the app's own compiled code runs in its process | Any script on the origin — a bug or dependency in the app, a browser extension with host permission, injected code — shares the page's DOM, memory, and storage |
| **Token storage** | Session + PKCE verifier in Keychain/Keystore (`SecureLocalStorage`, iOS `first_unlock_this_device`) | Browser storage, readable by any script on the origin and not protected by a device credential |
| **At-rest data protection** | OS Data Protection / full-disk encryption on the SQLite file; app lock gate on top | None; IndexedDB/localStorage are plain stores scoped to the origin |
| **App lock** | Face ID / Touch ID / device passcode gate | No OS-backed gate; the page is as reachable as the unlocked browser |
| **Network surface** | Content Security Policy is not a native control; the binary talks only to its own endpoints | CSP is the control, and it must be deployed correctly or not at all |

The practical consequences:

- **XSS becomes a total compromise, not a UI bug.** Any script that runs on
  the origin can read the access/refresh token from browser storage and issue
  PostgREST requests as the user until the token is revoked or expires. The
  server still enforces RLS (Section 4), so the blast radius is exactly the
  rows that account is entitled to — no more, no less.
- **A malicious or over-permissioned extension is in scope.** Extensions with
  host access can read the page's storage with no user-visible signal. This is
  inherent to the browser and cannot be fixed by the app.
- **There is no browser equivalent of the app's lock gate.** The launch
  unlock gate and the inactivity relock (`GateController`) are native-only;
  a web page has no device-credential prompt of its own. The browser build's
  honest disclosure must say what the browser stores and how to clear it,
  because it cannot promise OS-level protection.
- **Assets must be same-origin and pinned by CSP.** Flutter's engine, fonts,
  and `sqlite3.wasm` are all bundled into the build (no CDN, no
  `google_fonts`), so a strict `script-src 'self'` is achievable. The one
  engine requirement is `'wasm-unsafe-eval'`, which permits `WebAssembly`
  compilation without enabling general `eval`. `web/_headers` (Section 3) is
  where this is enforced.

## 3. Where the Supabase session lives on web today

From `lib/startup/supabase_bootstrap.dart`:

```dart
final authOptions = kIsWeb
    ? const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: false,
      )
    : FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: false,
        localStorage: SecureLocalStorage(),
        pkceAsyncStorage: SecureLocalStorage(),
      );
```

- **The `SecureLocalStorage` override is native-only.** It is constructed
  only in the non-web branch of that ternary; on web the bootstrap passes no
  `localStorage` and no `pkceAsyncStorage`, so the Supabase/gotrue client uses
  its own package-default browser storage (`localStorage`). The session's
  access token, refresh token, and PKCE code verifier therefore live in
  **browser storage that any script on the origin can read** — not in
  Keychain/Keystore, not OS-protected.
- **PKCE only, `detectSessionInUri: false` on both branches.** Web-safe by
  construction; the app's `SupabaseAuthService` handles the auth callback, and
  a hijacked one-time code is useless without the verifier held in the same
  browser storage.
- **Local data is drift over IndexedDB** (`lib/data/db/web_db.dart`), with no
  cipher. When the build is sync-enabled, the browser holds the account's
  synced `profile` and `day_entry` rows unencrypted in that store, alongside
  the token. Signing out through the app's reset path
  (`resetDevice()` → `LunarLogRoot`, KTD16) wipes the local database and
  removes the persisted session; a plain browser-storage clear (or clearing
  site data) discards the copy without touching the account.

## 4. What `LUNARLOG_WEB_SYNC=true` exposes

The define does exactly two things: it makes `AppConfig.hasSupabase` true on
web (so the Supabase client initializes and the account surface renders), and
it allows the sync engine to run. It does **not** change the server's
authorization model.

- **Sign-in is enabled.** On web the available methods are email/password and
  passwordless email (`signInWithOtp` + `verifyOTP`). Google and Apple are
  hidden on web by construction (`AppConfig.hasGoogle` and the Apple
  availability both require `!kIsWeb`, and passkeys are off on web
  (`AppConfig.hasPasskeys` excludes web). Both the account section and the
  sign-in screen derive Apple availability from the shared, unit-tested
  `computeAppleSignInAvailable(isWeb:, isIos:)` rule, so the browser can
  never render it.
- **Email links redirect to the page origin, not the custom scheme (slice 2).**
  Native mail goes to `lunarlog://auth-callback`; a browser cannot open that
  scheme, so a web build sends confirmation, passwordless, and password-reset
  mail to `https://<origin>/auth/callback` (`resolveAuthRedirectUrl` in
  `lib/data/auth/supabase_auth_providers.dart`) and `SupabaseAuthService`
  exchanges the returned `?code=` from the initial `Uri.base` over the same
  PKCE path (`detectSessionInUri` stays `false`; the app, not the SDK,
  performs the exchange so a cold-start recovery link is latched before any
  widget exists). The emailed 8-digit code (`verifyOTP`) is
  redirect-independent and works on web unchanged. **Owner step:** the
  deployed origin's callback — `https://app.lunarlog.app/auth/callback` —
  must be added to the Supabase dashboard's Auth **redirect allow-list**
  before web sign-in links resolve; this is a dashboard action, not a code
  change (see `docs/ops/supabase-go-live.md`). The hosting must also serve
  the built single page for that path so `Uri.base` carries the code (a
  normal SPA fallback).
- **The browser URL is cleaned after the callback is handled (slice 4).**
  `SupabaseAuthService` holds an injectable `WebUrlCleaner` and calls it once
  a web callback has been handled, passing the URL with the auth parameters
  removed (`cleanAuthUrl`): the spent `code` (and `type`) after a successful
  exchange, or the provider's `error`/`error_code`/`error_description` when
  the link was rejected. The path, parameter order, and every unrelated
  parameter are preserved. The production implementation is
  `window.history.replaceState` on web (no new history entry; native compiles
  a no-op half through a `dart.library.js_interop` conditional import). This
  is why a reload after sign-in restores the existing session instead of
  replaying a spent code and showing a bogus expired-link failure. A
  *transient network* failure deliberately does **not** clean the URL, so the
  un-latched link stays retryable from the address bar.
- **Sign out clears the browser session.** On web the bootstrap passes no
  custom `localStorage`/`pkceAsyncStorage` (`buildAuthClientOptions` in
  `lib/startup/supabase_bootstrap.dart`), so the session and PKCE verifier
  live in gotrue's own browser storage, which gotrue's `signOut` clears with
  the session. The app's sign-out paths run the one device reset
  (`resetDevice`), which signs out locally and, on web, wipes the drift
  IndexedDB store (`db.wipeAllData()`); both are pinned in
  `test/architecture/web_auth_seam_test.dart` and
  `test/ui/device_reset_test.dart`.
- **RLS still applies, precisely.** Every request is a normal authenticated
  PostgREST/Realtime call carrying the user's JWT. Row-Level Security policies
  scoped to `auth.uid()` and the caller's `profile_guardians` memberships
  decide which rows the token can read or write. Enabling web sync widens the
  *client surface*, not the *authorization boundary*: a browser token can
  reach exactly the rows that account's memberships would let any native
  client reach.
- **RLS is authorization, not encryption.** Entry content is stored as
  readable Postgres columns and protected by TLS in transit plus Supabase's
  infrastructure encryption at rest — the same non-end-to-end posture
  `PRIVACY.md` §6 already states for every platform. RLS governs which
  application queries return which rows; it does not make a stolen token
  harmless. The residual risk a browser adds is that token theft via XSS or an
  extension grant is a real path, which is why the CSP and the disclosure copy
  matter and why the copy must be honest.

## 5. Decisions

**D1 — Session lifetime on web: keep the provider session model; do not
invent a shorter web-specific lifetime in this slice.** The session is a
PKCE-flow Supabase session with its normal access-token expiry (the project's
default 1 hour) and automatic refresh; the refresh token persists in browser
storage. A per-platform token lifetime is not available — the dashboard JWT
expiry is project-global — and the app's own revoke path is "Sign out
everywhere", whose copy honestly says other devices may take up to an hour to
notice (`PRIVACY.md` §7; issue #971). A browser-specific session strategy
(short refresh lifetime, server-set HTTPOnly cookie, a server-side auth proxy)
is deferred, not rejected; see Section 6.

**D2 — What web sync exposes is disclosed at the point of use, in the same
change.** When `webSyncEnabled` is true the banner becomes a truthful,
per-session-dismissible "browser build" notice that names what the browser
stores and that signing out clears it; the first-run acknowledgement is
rewritten (not removed) to say the same. When the flag is false the existing
"Development build — not for real data" warning is unchanged. This is epic
#831's non-negotiable: the build and the disclosure move together.

**D3 — A strict CSP is deployed with the build from the start.** `web/_headers`
carries the policy (Section 3), including `'wasm-unsafe-eval'` for
`sqlite3.wasm`, `script-src 'self'`, `object-src 'none'`, `base-uri 'self'`,
`frame-ancestors 'none'`, `form-action 'self'`, and cross-origin isolation
(`Cross-Origin-Opener-Policy: same-origin`,
`Cross-Origin-Embedder-Policy: require-corp`) so drift's WASM executor can use
shared-memory modes. Without COOP/COEP drift falls back to IndexedDB modes, so
the app works either way; the isolation headers are included because they are
strictly better and cost nothing for a same-origin app. `connect-src` is
limited to the app origin, the `dleexnnevuuddcgcpztq.supabase.co` project
(HTTPS + WSS), and Sentry's ingest host.

**D4 — Local data and token are cleared only by the app's own reset or a
browser site-data clear; the copy tells the user that.** `WebGuardrails` keeps
the confirm-guarded wipe action (the device reset, KTD16) and the browser
notice states that signing out removes the browser copy. The notice is
per-session dismissible — a reload brings it back — so a signed-in user is
never permanently separated from the disclosure that real data is present.

## 6. Deferred (explicitly out of scope for this slice)

- **HTTPOnly-cookie sessions / a server-side auth proxy.** With today's
  storage, any origin script can read the token. Moving the session to an
  HTTPOnly, SameSite cookie would mitigate token theft but requires a trusted
  server component; deferred.
- **A shorter web session or refresh lifetime.** Needs dashboard/backend
  support that does not exist per-client today.
- **Hosting, deploy automation, DNS, and the `app.lunarlog.app`/apex split.**
  Epic #831 scope items 3 and 4, tracked with the marketing-site work (#830).
- **PWA / offline installability.** `web/manifest.json` exists; whether it is
  in scope or explicitly deferred is an epic-level product decision not made
  here.
- **Web push.** `AppConfig.hasPush` is false on web by construction.
- **Auth flows on web beyond email/password and passwordless email.** Slice 2
  landed the web redirect target (`<origin>/auth/callback`) and the
  `Uri.base` PKCE exchange, so email/password, passwordless email, password
  recovery, and the emailed code all work in a browser, and Google/Apple/
  passkeys are pinned hidden there. Making any of the native providers work
  in a browser (a popup OAuth flow, WebAuthn) is separate work.
- **Trusted Types, a CSP report collector, and nonce/hash-based `script-src`**
  (dropping `'unsafe-inline'` from `style-src`, tightening the wasm allowance).
  Worth revisiting once hosting exists and real-browser verification is
  possible; this slice cannot run a browser to prove the tighter policy.
- **Live-browser verification of the URL cleanup.** The `replaceState`
  rewrite (slice 4) is proven by the injectable seam and the pure
  `cleanAuthUrl` tests, but no hosted origin exists yet, so it has not been
  exercised in a real browser; the hosting slice owns that end-to-end check.
  The cleanup also assumes the `/auth/callback` path reaches the app at all
  (the SPA-fallback dependency above) — if the host 404s the path, the code
  never reaches `Uri.base` and there is nothing to clean.
- **A dedicated XSS/penetration review of the Flutter engine and every web
  dependency.** The strict CSP is the first layer; a review is a follow-up.

## 7. References

- Epic #831 — "deploy the Flutter web app at lunarlog.app".
- `lib/config.dart` — `webSyncEnabled`, `hasSupabase` (web requires the flag).
- `lib/startup/supabase_bootstrap.dart` — where the web session storage is
  chosen (`buildAuthClientOptions`).
- `lib/data/auth/supabase_auth_service.dart` /
  `lib/data/auth/supabase_auth_providers.dart` — the web `<origin>/auth/callback`
  redirect target, the `Uri.base` PKCE exchange, and the post-callback
  `WebUrlCleaner` call.
- `lib/data/auth/web_url_cleaner.dart` — the URL-cleanup seam, its pure
  `cleanAuthUrl`, and the web/native conditional import
  (`web_url_cleaner_web.dart` / `web_url_cleaner_stub.dart`).
- `lib/data/db/web_db.dart` — web drift/WASM/IndexedDB wiring.
- `lib/ui/web/dev_banner.dart` — the banner and first-run acknowledgement.
- `web/_headers` — the deployed policy.
- `test/architecture/web_auth_seam_test.dart` — the web-storage and
  redirect pin.
- `test/data/web_url_cleaner_test.dart` /
  `test/architecture/web_url_cleanup_test.dart` — the URL-cleanup behavior
  and platform-split pins.
- `docs/ops/supabase-go-live.md` — the dashboard redirect allow-list owner step.
- `PRIVACY.md` §6/§7 — the public security and retention disclosure.
