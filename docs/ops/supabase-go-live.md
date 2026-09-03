# Supabase go-live, device checklist, and release gate

Operational record for the account + cloud-sync feature
([plan](../plans/2026-09-02-001-feat-supabase-auth-cloud-sync-plan.md),
branch `feat/supabase-auth-cloud-sync`). Tick items here as they are done;
the "Not yet run" section is the honest list of what has not been exercised.
Never record a credential value in this file.

Project: Supabase Cloud `dleexnnevuuddcgcpztq` (Postgres 17). Secrets and
their locations are catalogued in [`AGENTS.md`](../../AGENTS.md) ("Config &
Credential Locations"); every secret and dashboard setting named below
appears there.

## Go-live checklist

Dashboard and account configuration the code cannot apply. `supabase/config.toml`
governs the local stack only (6-character passwords, confirmations off, 1-hour
JWT are CLI defaults) and says nothing about the cloud project.

### Supabase Auth

- [ ] Custom SMTP configured (Authentication → SMTP). Until then the built-in
      sender delivers 2 emails per hour to team addresses only, so every
      non-team sign-up and password reset silently fails.
- [ ] "Confirm email" on (Authentication → Providers → Email). The app depends
      on it: `signUp` returns a user and no session, the status tile shows
      "Waiting for email confirmation — open the link on this device", and
      binding/upload consent wait for a confirmed session.
- [ ] Password policy: minimum length 12; require letters, digits, and
      symbols; leaked-password protection on. The client enforces the same
      12-character minimum (`kMinPasswordLength` in
      `lib/ui/account/sign_in_screen.dart`) and maps the server's
      `weakPassword` rejection to generic copy, so the two must agree.
- [ ] JWT expiry at the dashboard minimum (target 10 minutes). "Sign out
      everywhere" revokes sessions, not tokens, so this bounds how long another
      device keeps access.
- [ ] Session inactivity timeout set, if the project tier offers it.
- [ ] Apple provider enabled with the bundle id `com.wjdavis5.lunarlog` as
      the client id (native iOS flow only; no Services ID or client secret
      needed).
- [ ] `lunarlog://auth-callback` added to the redirect allow-list
      (Authentication → URL Configuration). Both the confirmation and the
      reset email link through it (`ios/Runner/Info.plist` `CFBundleURLSchemes`
      and the Android `VIEW` intent filter register the scheme).

### Sentry

- [ ] Sentry project created; DSN stored as the `SENTRY_DSN` repository
      secret and (locally) in `dart_defines.json`.
- [ ] "Prevent storing of IP addresses" on (Project Settings → Security &
      Privacy).
- [ ] Server-side data scrubbing on, with the default sensitive-field list
      plus `note`, `tags`, `display_name`, `local_date`, `email` (defense in
      depth behind the client allowlist in `lib/observability/scrub.dart`).

### GitHub

- [ ] `production` environment on `wjdavis5/lunarlog` with a required
      reviewer.
- [ ] `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD` (and
      `SUPABASE_PROJECT_REF`) set as environment secrets on `production`
      (`supabase-migrate.yml` runs `supabase link` + `db push` there).
- [ ] `SENTRY_DSN` repository secret added.

### Apple / Google store plumbing

- [ ] App Store provisioning profile regenerated with the Sign in with Apple
      capability on the `com.wjdavis5.lunarlog` App ID, and
      `IOS_PROVISION_PROFILE_BASE64` replaced. Until then `ios-release.yml`
      fails at signing because `Runner.entitlements` now requests
      `com.apple.developer.applesignin`.
- [ ] App Privacy details in App Store Connect updated to match
      `ios/Runner/PrivacyInfo.xcprivacy`: Health and Email Address collected,
      linked to the user, for app functionality; Crash Data collected, not
      linked; no tracking.
- [ ] Play Console Data safety updated to the same statement (health info and
      email address, encrypted in transit, user can request deletion — see
      the gate below).

### Migrations

- [ ] Supabase MCP `get_advisors` (security and performance) run against the
      cloud project with no security or RLS findings.
- [ ] `supabase db push --dry-run` on the linked project lists only
      `20260903014208_initial_sync_schema.sql` and `20260903014211_sync_push.sql`.
- [ ] First `supabase-migrate.yml` run approved and green.

### Release gate

- [ ] **Release gate: no `version:` bump in `pubspec.yaml` and no
      `submit_for_review` dispatch of `ios-release.yml` until in-app account
      deletion has shipped.** App Store guideline 5.1.1(v) makes deletion a
      submission blocker once account creation exists. Account deletion (Edge
      Function calling `auth.admin.deleteUser`, cascading rows, Apple token
      revocation) and JSON data export are follow-up work; file the deletion
      issue as a blocker of the first review submission.

## Device checklist

Run on an iPhone build (`Williams-Mini`, signed with a profile that carries
the Apple capability) with a **throwaway account** and **fabricated
profiles**. Never use real family data. Each item lists the expected
observation; record the date and build number next to it when it passes.

- [ ] **Cold-start password reset (F4, AE8).** Kill the app. Request a reset
      from the sign-in screen, open the email link on the same device. The
      device-credential gate appears first; declining it shows neither the
      recovery screen nor any profile data. Granting it shows "Set a new
      password" before any profile screen. Saving a new password returns to
      the normal state; "Not now" also clears the recovery state.
- [ ] **Confirmation link on the signing-up device (F1, AS10).** Create an
      account; the status tile reads "Waiting for email confirmation — open the
      link on this device". Open the link on this device: a session arrives,
      the device binds, and the first-run flow continues (an empty account
      goes to the name form; the first profile is created and pushed). Opening
      the link on a different device must not sign this device in.
- [ ] **Apple Sign-In (F1/F2, KTD9).** "Sign in with Apple" shows only on iOS.
      Cancelling the Apple dialog returns to the sign-in screen with no error.
      A completed sign-in binds like an email account.
- [ ] **Hide My Email mismatch (F7, AE5).** On a device bound to account A,
      sign in with Apple using "Hide My Email" so Supabase creates a new user.
      The "Different account" screen appears naming the Hide My Email case;
      sync does not run. "Switch account" signs out locally and A's data is
      intact. "Remove this device's data" asks for confirmation, then resets
      the device to first-run.
- [ ] **Two-device convergence (F3, F5, AE3, AE13).** Device 1 holds
      fabricated profiles and entries and is signed in. Sign in on device 2
      with an empty database: "Restoring your data…" holds until the pull
      completes, then the picker shows device 1's profiles and no name form
      appears. Then, both offline, log the same date for the same profile on
      both devices; reconnect and "Sync now" on each: both end with exactly one
      live entry for that date and no error.
- [ ] **Upload consent on an existing device (F2).** A device with local data
      that signs in shows "Upload to your account?" with row counts; "Not now"
      leaves the tile at "Upload pending — tap to review" and tapping the tile
      reopens the consent screen; "Upload to my account" pushes everything and
      the tile reaches "Up to date".
- [ ] **Lock mid-sync (AE4, R13).** Start a sync of a large pull (many
      fabricated entries) and background the app before it finishes. On
      unlock, sync resumes from the persisted cursor with no duplicate or
      missing rows, and no fail-closed screen.
- [ ] **Expired session (AE9).** With the session unable to refresh (airplane
      mode long enough, or revoke it from the dashboard), the app still
      unlocks, reads, and edits; the tile shows "Sign in again to sync" and
      edits stay pending until sign-in.
- [ ] **Sign-out reset (F6, AE10).** With unsynced edits, "Sign out" warns
      ("Unsynced changes") and offers sync-first or discard. After sign-out,
      the next cold start reaches first-run with a fresh key and an empty
      database — never the fail-closed screen. Repeat for "Sign out
      everywhere" and confirm the other device's session ends within the JWT
      expiry window.
- [ ] **Sentry smoke test (AE7).** In a dev build with `SENTRY_DSN` set,
      throw a deliberate test exception from a `lib/data` path and a UI path.
      In Sentry the events carry only `contexts.os`, `contexts.runtime`, and
      `contexts.app.version`; no user, no `extra`, no request query string,
      headers, or body; the `lib/data` exception is reduced to its type name;
      breadcrumbs carry no `note`, `tags`, `display_name`, `local_date`,
      `email`, `record`, or `p_day_entries` keys and HTTP URLs are truncated at
      `?`.

## Not yet run

Verification-contract steps that could not be executed in the Windows
implementation environment as of 2026-09-03. None of them changes code; each
is a gate before go-live.

- Supabase MCP `get_advisors` against the cloud project (needs an interactive
  MCP login in the calling session).
- `supabase db push --dry-run` on the linked cloud project (needs
  `SUPABASE_ACCESS_TOKEN` locally or the first `supabase-migrate.yml` run).
- `flutter build ios --release --no-codesign` on `Williams-Mini` with the new
  entitlements file, and the whole device checklist above.
- Sentry smoke test (no DSN configured yet).
- Provisioning profile regeneration with the Sign in with Apple capability.

What **was** run (2026-09-03, Windows): `flutter analyze` clean; `flutter
test` 377/377; `flutter build web --release` and `flutter build apk --debug`;
`npx supabase@2.116.0 start` + `db reset --local` + `test db --local`, 135/135
pgTAP tests.

## Operating notes

- **How migrations flow.** PR with SQL under `supabase/migrations/` and pgTAP
  under `supabase/tests/` → CI `db-tests` job starts a database-only local
  stack and runs `supabase test db --local` → merge to `main` →
  `supabase-migrate.yml` (path filter `supabase/**`) runs `supabase link`,
  `db push --dry-run`, and `db push` inside the `production` environment; the
  required reviewer checks `get_advisors` output and the dry-run list before
  approving. The workflow never cancels in progress (`cancel-in-progress:
  false`) so migrations apply in order.
- **Local stack.** `npx supabase@2.116.0 start -x realtime,storage-api,imgproxy,mailpit,studio,edge-runtime,logflare,vector,supavisor`
  (Docker required; excluding those services keeps startup to Postgres and
  the auth/API containers), `db reset --local` to re-apply every migration
  from scratch, `test db --local` for pgTAP, `stop --no-backup` when done.
  Keep the CLI pinned at 2.116.0 in both `ci.yml` and `supabase-migrate.yml`;
  bump all three places together.
- **Kotlin Gradle Plugin warning.** `flutter build apk` prints a warning that
  `sentry_flutter` 9.28.0 applies the Kotlin Gradle Plugin itself. Upstream
  and harmless today; a future Flutter may reject plugins that do this.
  Re-check on every Flutter or `sentry_flutter` upgrade and pin or patch if
  it becomes an error.
- **Custom SMTP limits.** Supabase's built-in sender is a development
  courtesy: 2 emails per hour, to team members' addresses only. With
  "Confirm email" on, every sign-up and reset depends on delivery, so custom
  SMTP is a go-live blocker, not a nicety. After configuring it, set the
  auth email rate limit deliberately (Authentication → Rate Limits) — the
  app has no resend button, so a hit limit shows up as a user seeing
  "Check your email" and nothing arriving.
- **JWT expiry rationale.** "Sign out everywhere" (`signOut(scope: AuthSignOutScope.global)`)
  revokes refresh tokens, not issued access tokens; a lost or shared device
  keeps reading the account's rows through PostgREST until its JWT expires.
  The dashboard minimum (target 10 minutes) bounds that window at the cost of
  a refresh every few minutes, which the SDK does automatically. The
  confirmation copy in the app ("Ends every session of this account…") is
  written against this behaviour.
- **What the client stores.** Native builds keep the Supabase session and
  PKCE verifier in `flutter_secure_storage` (iOS Keychain
  `first_unlock_this_device`, non-synchronizable; Android encrypted
  preferences under `allowBackup="false"`), so they never travel in a
  backup. Web keeps the SDK default (browser storage) and only when
  `LUNARLOG_WEB_SYNC=true`.
- **Deferred follow-ups** (from the plan's Scope Boundaries): in-app account
  deletion and JSON export (release gate); Realtime "pull now" hint; Apple
  Sign-In on Android/web; client-side syncing of `settings`; `birth_year` /
  `color` profile attributes; client-side encryption of `note` and
  `display_name`; Sentry debug-symbol upload (`SENTRY_AUTH_TOKEN`); managing
  auth settings via `supabase config push`; iCloud backup exclusion and the
  `ThisDeviceOnly` key-class migration; `https` App Links; new-device sign-in
  email notice.
