# Supabase go-live, device checklist, and release gate

Operational record for the account + cloud-sync feature
([plan](../plans/2026-09-02-001-feat-supabase-auth-cloud-sync-plan.md),
branch `feat/supabase-auth-cloud-sync`), its social-logins follow-up
([plan](../plans/2026-09-03-001-feat-social-logins-plan.md), branch
`feat/social-logins`; its IDs are cited with a `#2` prefix), and its
account-deletion-and-export follow-up
([plan](../plans/2026-09-05-001-feat-account-deletion-and-json-export-plan.md),
branch `issue-17`; its IDs are cited with a plain `#17` prefix, e.g.
`#17 KTD3`). Tick items here as they are done;
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

### Social logins and passwordless (issue #2)

Prerequisites for Google Sign-In, passwordless email, and adding a second
sign-in method ([plan](../plans/2026-09-03-001-feat-social-logins-plan.md)).
Until the client ids are set, `AppConfig.hasGoogle` is false and no Google
button renders, so the app can ship ahead of the Google Cloud work;
passwordless email depends on custom SMTP above like every other email.

- [ ] Google Cloud OAuth clients (APIs & Services → Credentials) in one
      project: a **Web** client, an **iOS** client (bundle id
      `com.wjdavis5.lunarlog`), and one **Android** client per signing key —
      the debug keystore, the release keystore, and the Play App Signing key
      (Play Console → App integrity) — each with the package name and that
      key's SHA-1. A wrong or missing SHA-1 raises no error: the Android
      picker closes as if the operator cancelled (#2 KTD8), so a "cancel" on
      a fresh build is the first thing to suspect. A device with no Google
      account is likewise not separately detectable; it shows the
      email-alternative copy.
- [ ] Supabase Google provider enabled (Authentication → Providers → Google)
      with the **Web and iOS client ids** in the authorized client id list.
      Those two are the token audiences (Web on Android, iOS on iOS); the
      Android client id is never an audience and is not listed. "Skip nonce
      check" stays **OFF**: the app initializes Google with a hashed nonce
      and passes the raw one to `signInWithIdToken` (#2 AS2); turning the
      check off would let any captured ID token for either client id become
      a session.
- [ ] "Manual linking" **ON** (Authentication → Providers → "Allow manual
      linking"). The account section's "Add Google" / "Add Apple" actions
      call `linkIdentityWithIdToken`, which the server refuses while this is
      off.
- [ ] Email templates (Authentication → Email Templates): **both** the
      *Magic Link* and the *Confirm signup* templates carry `{{ .Token }}`
      beside the link, plus a line saying the code and the link must never
      be shared with anyone, even family. Existing users get the Magic Link
      template; new users requested through `signInWithOtp` get the Confirm
      signup template. The in-app code field therefore works only after both
      are changed (#2 AS4); until then the link path alone works and the code
      field is still shown.
- [ ] Email OTP expiry **600 seconds** and OTP length **8** (Authentication →
      Providers → Email). The expiry setting governs every emailed link —
      confirmation, recovery, email change, and magic link — so the #1 flows
      tighten too. The app has no resend button: an expired confirmation
      link means signing up again; an expired reset or sign-in link means
      requesting a new one (#2 AS5).
- [ ] Sign-ups closed once the household's accounts exist: turn off "Allow
      new users to sign up" (Authentication → Sign In / Providers), or keep
      it on behind a `before_user_created` auth hook that rejects any email
      not on a household allow-list. That allow-list lives **only** in a
      table in the Supabase project, populated from the dashboard SQL editor
      — never in a tracked migration, under `docs/`, or in a secret. Open
      sign-ups let anyone holding the publishable key create accounts and
      burn the project-wide 30 OTP sends per hour, denying the household its
      links (#2 KTD3). With sign-ups closed, every create path — passwordless
      create mode, a first Google or Apple sign-in (Hide My Email included) —
      shows "New accounts for this app are set up by the account owner".
      **Onboarding a new household member after closure:** reopen sign-ups
      briefly (or add the address to the allow-list), have them create the
      account on their device, then close again. A Hide My Email identity is
      attached afterwards from the account section ("Add Apple"), never by a
      fresh sign-up.
- [ ] `ios/Runner/Info.plist` gains a `CFBundleURLTypes` entry whose scheme
      is the **reversed iOS client id**
      (`com.googleusercontent.apps.<iOS client id>`), in the same change
      that sets the client ids (#2 KTD2). No placeholder scheme ships before
      then. OAuth client ids and the reversed id are client-safe and are the
      only Google values that may be committed.
- [ ] `GOOGLE_IOS_CLIENT_ID` and `GOOGLE_WEB_CLIENT_ID` set as repository
      secrets on `wjdavis5/lunarlog` and as the same keys in the local
      `dart_defines.json`. Client-safe values, but still secrets, so forks
      build with them empty (no Google button); every workflow build must
      succeed either way.
- [ ] **Admin recovery for a rogue linked identity** (someone attached their
      Google or Apple identity to the operator's account from an unlocked
      device or with an exfiltrated token; there is no in-app unlink):
      Authentication → Users → the user → delete that identity from the
      user, then revoke every session for that user from the same page. The
      operator signs in again with a remaining method.

### Sentry

- [ ] Sentry project created; DSN stored as the `SENTRY_DSN` repository
      secret and (locally) in `dart_defines.json`.
- [ ] "Prevent storing of IP addresses" on (Project Settings → Security &
      Privacy).
- [ ] Server-side data scrubbing on, with the default sensitive-field list
      plus `note`, `tags`, `display_name`, `local_date`, `email` (defense in
      depth behind the client allowlist in `lib/observability/scrub.dart`).

### GitHub

- [ ] **Prerequisite — configure this before the secrets below.**
      `production` environment on `wjdavis5/lunarlog` with a required
      reviewer (Settings → Environments → `production` → Deployment
      protection rules). **Not yet configured** — the environment
      currently reports no protection rules at all. Until it is,
      `supabase-migrate.yml` has valid deploy credentials the moment the
      next item is done and will push migrations on the next `main` push
      with no one reviewing first, which is exactly the unsupervised run
      the G1-G3 audits in the runbook below are meant to gate.
- [ ] `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD` (and
      `SUPABASE_PROJECT_REF`) set as environment secrets on `production`
      (`supabase-migrate.yml` runs `supabase link` + `db push` there).
- [ ] `SENTRY_DSN` repository secret added.
- [ ] `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_CLIENT_ID`, and
      `APPLE_PRIVATE_KEY` set as environment secrets on `production` (issue
      #17 — the `delete-account` Edge Function's Apple token revocation,
      KTD3). See "Account deletion (issue #17)" below for what each value is
      and where it comes from; `supabase-migrate.yml`'s own "Check deploy
      credentials" step fails the run with an actionable message if any of
      the four is missing.

### Account deletion (issue #17)

Prerequisites for the `delete-account` Edge Function's Apple token
revocation (KTD3) — nothing here is needed for deleting a non-Apple
account, which works with no additional configuration beyond the base
Supabase Auth setup above.

- [ ] An Apple Sign in with Apple **key** (not a Services ID secret)
      generated in the Apple Developer portal (Certificates, Identifiers &
      Profiles → Keys → a key with the "Sign in with Apple" capability
      enabled) and its `.p8` file downloaded once (Apple will not let it be
      downloaded again — store it in the credential vault immediately).
- [ ] The four values recorded as `production` environment secrets, never
      in the repo (see the GitHub checklist item above and AGENTS.md's
      "Config & Credential Locations"):
      - `APPLE_TEAM_ID` — the Apple Developer Team ID (`5273C9R3V4` per
        `README.md`'s iOS build section).
      - `APPLE_KEY_ID` — the 10-character id of the key created above.
      - `APPLE_CLIENT_ID` — the bundle id `com.wjdavis5.lunarlog` (the same
        value already used as the Supabase Apple provider's client id).
      - `APPLE_PRIVATE_KEY` — the full contents of the downloaded `.p8`
        file, including the `BEGIN/END PRIVATE KEY` lines.
- [ ] First `supabase-migrate.yml` run since #17 deploys `delete-account`
      cleanly (its "Set delete-account function secrets" step runs
      `supabase secrets set` for all four values before the deploy step).
- [ ] The device checklist's Apple-account deletion item (below) passes on
      a real Apple ID: the app disappears from Settings → Apple ID → Sign in
      with Apple → apps using this Apple ID.

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
      email address, encrypted in transit, user can request deletion —
      now true in-app via "Delete account" in the account section, issue
      #17).

### Migrations

- [ ] Supabase MCP `get_advisors` (security and performance) run against the
      cloud project with no security or RLS findings.
- [ ] `supabase db push --dry-run` on the linked project lists only
      `20260903014208_initial_sync_schema.sql` and `20260903014211_sync_push.sql`.
- [ ] First `supabase-migrate.yml` run approved and green.
- [ ] First `supabase-migrate.yml` run since issue #17 pushes
      `20260905110000_account_deletion.sql` and reports the `delete-account`
      function deployed (see "Account deletion (issue #17)" above for its
      secrets prerequisite). **Open question (plan Q1, unresolved):** it is
      not yet confirmed whether the `SUPABASE_ACCESS_TOKEN` already on the
      `production` environment carries the scope `supabase functions deploy`
      needs, as opposed to only `db push`. If the first post-#17 run's
      "Deploy delete-account function" step fails on a permissions error,
      the fix is a `production` access token with the function-deploy scope
      (or a full-access personal access token) — this does not block
      anything else in this checklist and is only discoverable by running
      the workflow.

### delete-account Edge Function runbook (issue #17)

The Edge Function itself has no automated CI coverage yet (Open Question
Q2 in the plan — this is the repo's first Edge Function and there is no
Deno tooling in CI). Prove a change to it locally before merging:

```powershell
npx supabase@2.116.0 start -x realtime,storage-api,imgproxy,mailpit,studio,logflare,vector,supavisor
# edge-runtime must NOT be excluded above - it serves the function locally.
npx supabase@2.116.0 db reset --local
npx supabase@2.116.0 functions serve delete-account
```

Then, in another shell, against the local stack (`http://127.0.0.1:54321`):

- No `Authorization` header → `401`, nothing touched (AE6). The local
  gateway's own `verify_jwt = true` check answers this before the
  function's code runs.
- An invalid/malformed JWT → `401` (same gateway check).
- Sign up a throwaway user (`POST /auth/v1/signup`), insert a profile as
  that user, then `POST /functions/v1/delete-account` with that user's
  access token and an empty JSON body (`{}`) → `{"ok":true}`, and the
  profile row and the `auth.users` row are both gone.
- The same call with an unrelated user id or an `appleAuthorizationCode`
  key stuffed into the body → the caller's own rows are still the only
  ones affected (AE6 — no field in the body is ever trusted for identity).
- A simulated Apple identity (insert a row into `auth.identities` with
  `provider = 'apple'` for the test user) with an empty JSON body
  (`appleAuthorizationCode` omitted entirely) → `400
  {"ok":false,"code":"apple_code_required"}` with **no** call to Apple at
  all, and, since the #17 P1 fix (2026-09-06), **no** call to
  `delete_account_data()` either - the missing-code precondition now runs
  *before* the destructive RPC, so nothing is touched at all: the profile
  row and `auth.users` are both still present, and the call is safe to
  retry from any device once a fresh code is available. (Before that fix,
  the RPC ran first and only the precondition check came after it, so the
  profile/day-entry rows were already gone by the time this response came
  back - confirm this is no longer the case when re-proving this locally.
  A round-2 fix (same day) also split this off `apple_revoke_failed`'s own
  code/status: that code's client-side copy says data was already deleted,
  which is only ever true for a real revocation failure below, never for
  this precondition.)
- The same simulated Apple identity, now with a non-empty
  `appleAuthorizationCode` but no `APPLE_*` secrets set locally → `409
  {"ok":false,"code":"apple_revoke_failed"}` (a `misconfigured` revoke
  result) - but this time the profile/day-entry rows **are** gone (the
  precondition passed, so the RPC ran) while `auth.users` is still present
  (KTD4). Retrying with the code still missing goes back to the
  `apple_code_required` 400 above; retrying with a code but secrets still
  missing returns the same 409 every time; only supplying a fresh code once
  `APPLE_*` secrets are configured lets the retry actually revoke and
  complete the deletion.
- Force `auth.admin.deleteUser` to fail (e.g. call delete twice in quick
  succession for the same user, or otherwise make the admin call error) →
  `500 {"ok":false,"code":"delete_user_failed"}` (#17 P1 fix), not the
  generic `unknown` code - the profile/day-entry rows are already gone at
  this point.
- (#17 P1 round 2 fix) The Step 6 final re-home pass now runs on the
  function's service-role client with an explicit caller id, not on the
  caller's own client — `rehome_stray_day_entries` no longer grants
  `EXECUTE` to `authenticated` at all (see
  `20260906120000_account_deletion_final_rehome.sql`). A successful
  deletion above already exercises this path; there is no separate curl
  smoke test for it, since it is unreachable directly from an HTTP client
  by design.

Deploying: `supabase-migrate.yml`'s "Set delete-account function secrets"
step runs `supabase secrets set` for the four `APPLE_*` values, then
"Deploy delete-account function" runs
`supabase functions deploy delete-account --project-ref <ref>`. Both are
gated by a dedicated "Check Apple secrets (account-deletion deploy only)"
step that runs *after* migrations have already been pushed, which fails the
run with an `::error::` if any Apple secret is missing rather than
deploying a function that would silently treat every Apple revocation as
`misconfigured`. Scoping the check to just these two steps (rather than the
whole job, as it once did) means an unrelated `supabase/**` push still gets
its migrations pushed even before an Apple signing key is provisioned; only
the account-deletion deploy itself is skipped.

### Release gate

- [x] **Account deletion and export implemented (issue #17, code-complete
      2026-09-06):** in-app account deletion and JSON export have shipped
      in code, closing the functional gap behind App Store guideline
      5.1.1(v) (deletion required once account creation existed, issue
      #16). The `delete-account` Edge Function checks the Apple-code
      precondition, calls `public.delete_account_data()` for the row
      cascade, revokes the Apple identity when the account has one,
      re-homes any stray `day_entries` a second time immediately before
      the last step, then deletes the `auth.users` row last (KTD4), and
      the client runs the existing `resetDevice()` afterward (KTD16). JSON
      data export ("Export my data" in the account section) shipped
      alongside it.
- [ ] **Release gate: still mechanically closed.** No App Store submission
      and no Play `production` dispatch until an operator sets the
      `RELEASE_GATE_ACCOUNT_DELETION` repository variable to `shipped`
      (`.github/scripts/check-release-gate.sh` fails closed until then; a
      Play `production` dispatch also requires typing `production` into
      `confirm_production`). Flipping the variable — once issue #17 has
      merged and the device-checklist items below have all passed — is a
      separate, deliberate release action, not automatic from merging the
      code. It also does not itself bump `pubspec.yaml`'s `version:` or
      dispatch `submit_for_review` — those are separate actions still.

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

### Social logins and passwordless (issue #2)

Run on an iPhone build **and** an Android build (debug keystore SHA-1
registered), with the go-live section above completed and a throwaway
account. Every Google item needs a throwaway Google account too, not a
household member's.

- [ ] **Google sign-in on a fresh device (#2 F1, AE2).** On a first-run
      device tap "Sign in with Google": the native picker appears, no browser
      tab. Choosing an account signs in and the first-run flow continues as
      after an email sign-in. Dismissing the picker returns to the screen
      with no error and no spinner.
- [ ] **Google same-email auto-link (#2 F2).** On a device bound to an
      email/password account, sign in with Google using the same verified
      address: no "Different account" screen, the same data, and the account
      section's methods line reads Email and Google.
- [ ] **Google different-account mismatch (#2 F2, AE7).** On a device bound
      to account A, sign in with a Google account whose address differs: the
      "Different account" screen appears and its copy names the Google case
      as well as Hide My Email; "Switch account" leaves A's data intact and
      no sync runs.
- [ ] **Google sign-in with sign-ups closed (#2 KTD3).** With "Allow new
      users to sign up" off, sign in with a Google account that has no
      Supabase user: the screen shows "New accounts for this app are set up
      by the account owner", not the generic failure copy.
- [ ] **iOS Google sign-in, no consent prompt (#2 AS3).** On iPhone the
      sign-in completes with no consent or scope prompt after the picker and
      Supabase accepts the token (iOS tokens carry `at_hash`, so the silent
      access-token read must succeed). A failure here is a plan stop
      condition, not something to fix with a prompting read.
- [ ] **Add a method, re-auth declined (#2 F5, AE6).** Signed in with
      email/password, tap "Add Google" in the account section and cancel the
      device-credential prompt: no Google picker, no error, no change.
- [ ] **Add a method, re-auth granted (#2 F5, AE6).** Same, but pass the
      prompt and pick a Google account with a different address: the methods
      line updates to Email and Google and the data is unchanged (same
      `auth.uid()`). Repeat on iOS with "Add Apple".
- [ ] **Magic link on this device (#2 F3, AE5).** In sign-in mode tap "Email
      me a sign-in link": the status tile and the sign-in screen show "check
      your email" with a code field. Open the link on this device: a session
      arrives, the pushed sign-in screen pops without a tap, and the pending
      email clears.
- [ ] **Link opened on another lunarlog install (#2 F4, R7).** Request a
      link on device 1 and open it on device 2 (another lunarlog install):
      device 2 shows the device-credential gate first, then one generic
      "no longer valid" message after unlock, and is not signed in; device 1
      stays signed out with its code field still usable.
- [ ] **Expired link (#2 F4, AE4).** With the app killed, open a sign-in
      link after the 600-second expiry: the gate shows first; after unlock
      the home screen shows "That sign-in link is no longer valid. Request a
      new one." exactly once, and not again on the next unlock.
- [ ] **Confirmation and reset links after expiry (#2 AS5).** Open a
      confirmation link and a reset link after 600 seconds: each shows the
      same generic link message after unlock and nothing else. Recovery is
      signing up again / requesting a new reset (there is no resend button).
- [ ] **Code entry (#2 F3, AS4).** Type the 8-digit code from a magic-link
      email (existing user) and, in create-account mode with sign-ups open,
      from a confirmation email (new user): both sign in without opening the
      link. A wrong or stale code shows the generic invalid-code copy with no
      email in it.
- [ ] **Android without Play Services (#2 R3, KTD8).** On an Android device
      or emulator without Google Play Services (or with no Google account),
      tap the Google button: the copy names email sign-in as the
      alternative; no crash and no provider error text.
- [ ] **Unlock after a re-lock (issue #65).** Lock the app (background it,
      or wait out the inactivity timeout), tap Unlock, and pass Face ID /
      biometrics: the lock screen goes away and profile data is on screen.
      Repeat with the **device passcode fallback** rather than biometrics —
      on Android that path launches a separate activity, so it exercises a
      genuine background rather than a focus loss.
- [ ] **No lock screen during the Google picker or the Apple sheet.**
      Start each sign-in, and each add-a-method action, from an unlocked
      app: no lock screen appears at any point, and the sign-in screen has
      completed (or the methods line has updated) exactly once, with no
      duplicate consent or mismatch screen. The app's content is covered
      (not visible) in the app switcher throughout, and no black cover is
      left behind once the ceremony ends.
      *Known exception, not a regression:* on a **fresh install**, iOS
      raises its notification-permission alert immediately after the first
      unlock and that still re-locks the app. It is the deferred follow-up
      recorded in `docs/plans/2026-09-03-003-fix-gate-discards-granted-unlock-plan.md`.
- [ ] **The lock suppression is bounded — check both halves.**
      *(a) Leave and come back after the prompt closes.* Start a Google
      sign-in, leave the app while the picker is up, let the picker
      finish or dismiss while you are still away, then return: the lock
      screen is showing. Repeat with "Relock after inactivity" turned
      **off** — it must still lock. This is the case that was wrong in
      the first implementation, so check it deliberately.
      *(b) Leave the prompt open.* Start a Google sign-in, leave the app
      with the picker still up, wait past the two-minute window deadline,
      and return: the lock screen is showing. Repeat, returning to the app
      every minute — the deadline still fires on schedule rather than
      being reset by the resumes. Repeat once more with the toggle
      **off**: it still fires.
- [ ] **Google button branding (#2 KTD6).** Screenshot the sign-in screen on
      iOS and Android and compare to Google's light-theme branding spec:
      unmodified "G" mark on a white pad, white fill, `#747775` stroke,
      `#1F1F1F` "Sign in with Google", 40 dp height. On iOS the Apple button
      comes first and is at least as large.

### Account deletion and export (issue #17)

Run on an iPhone build **and** an Android build, each with a throwaway
account and fabricated profiles only.

- [ ] **Delete a throwaway Apple account end-to-end (KTD3).** Sign in with
      Apple, tap "Delete account" in the account section, pass the device
      credential, confirm in the dialog, then grant the fresh Apple
      authorization request that follows. The app lands on first-run. In
      Settings → Apple ID → Sign in with Apple, the app no longer appears
      under "Apps Using Your Apple ID" (proves the revocation actually
      reached Apple, not just the local reset).
- [ ] **Delete a throwaway Google or email account end-to-end.** Same flow,
      no Apple ceremony: device credential → confirmation → first-run.
      Confirm in the Supabase dashboard (Authentication → Users) that the
      user row is gone.
- [ ] **Export on iPhone and open the file.** Tap "Export my data", pick
      Files (or AirDrop to a Mac) from the share sheet, and open the saved
      `lunarlog-export-<timestamp>.json`: it parses, lists only that
      operator's fabricated profiles and entries, and contains no
      `user_id`, `server_version`, guardian ids, tokens, or emails (R9).
- [ ] **Export on Android and open the file.** Same, saving through the
      share sheet to Files (or Drive) and opening it there.
- [ ] **Export first, then delete.** From the delete confirmation dialog,
      tap "Export first": the file is produced and the dialog stays open
      (nothing is deleted yet); then tap "Delete account" to proceed.
- [ ] **Delete while offline.** Turn on airplane mode, tap "Delete account",
      pass the device credential and confirm: a typed network failure
      renders in the account section and the device is **not** reset
      (R12) — reconnect and retry succeeds.
- [ ] **Declined credential and cancelled dialog are silent (AE5).**
      Declining the device-credential prompt, and separately cancelling the
      confirmation dialog, each leave the account untouched with no error
      copy and no server call.

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
- The whole "Social logins and passwordless (issue #2)" go-live section
  (Google Cloud clients, Supabase Google provider, manual linking, both
  email templates, OTP expiry and length, sign-up closure, the Info.plist
  scheme, the `GOOGLE_*` secrets) and every issue #2 device-checklist item
  — none configured or exercised as of 2026-09-03.
- Android device runs for issue #2 (Google picker, Play-Services-less
  device): no Android device or emulator in the implementation environment.
- The whole "Account deletion and export (issue #17)" device-checklist
  section above: no iPhone or Android device in the implementation
  environment. The Edge Function itself was smoke-tested against the local
  Supabase stack (see the runbook above), including a simulated Apple
  identity with no Apple secrets configured — that is not the same as
  proving the real Apple revocation against `appleid.apple.com`, which
  only the device checklist's first item does.
- `supabase functions deploy delete-account` against the cloud project
  (needs `SUPABASE_ACCESS_TOKEN` and the four `APPLE_*` secrets locally, or
  the first `supabase-migrate.yml` run since issue #17).

What **was** run (2026-09-05, Windows, issue #17): `flutter analyze` clean;
`flutter test` green (722 tests); `dart run tool/quality_gate.dart` passed
(coverage floor and CRAP gate); `npx supabase@2.116.0 start` + `db reset
--local` + `test db --local`, 233/233 pgTAP tests (26 of them new, in
`account_deletion_test.sql`); `npx supabase@2.116.0 functions serve
delete-account` + manual `curl` against the local stack covering every
scenario in the runbook above, including the simulated Apple-misconfigured
retry story (KTD4).

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
- **Deferred follow-ups** (from the plan's Scope Boundaries): Realtime
  "pull now" hint; Apple Sign-In on Android/web; client-side syncing of
  `settings`; `birth_year` / `color` profile attributes; client-side
  encryption of `note` and `display_name`; Sentry debug-symbol upload
  (`SENTRY_AUTH_TOKEN`); managing auth settings via `supabase config push`;
  iCloud backup exclusion and the `ThisDeviceOnly` key-class migration;
  `https` App Links; new-device sign-in email notice. (In-app account
  deletion and JSON export shipped in issue #17 — see the "Release gate"
  and "Account deletion (issue #17)" sections above.)
- **Deferred from the social-logins plan** (issue #2, Scope Boundaries):
  **passkeys** — Supabase passkeys are beta and the Dart API is
  `@experimental`; a native flow needs the `passkeys` plugin, a relying-party
  id on an HTTPS domain the app owns serving `apple-app-site-association`
  and `assetlinks.json`, and that rp id is immutable once a passkey is
  enrolled, so file it only after the `https` App Links domain above exists.
  **Unlinking a sign-in method** — needs a second identity and a
  re-authentication story; until then the account keeps every method it has
  and the dashboard recovery in the go-live section is the only removal.
  Also Google Sign-In on web (`google_sign_in_web` offers only its rendered
  button) and security-notification emails for a linked identity or changed
  password once custom SMTP exists (issue #18).
- **Deferred from the account-deletion plan** (issue #17, Scope Boundaries):
  automated Deno test/lint coverage for `supabase/functions/**` in CI (Open
  Question Q2 — the function is smoke-tested, not unit-tested, and this is
  the repo's only untested source tree); server-side export (unnecessary
  while the local Drift store is the source of truth, KTD5); CSV/PDF export
  formats and scheduled backups; a grace period / soft-delete window before
  the account is destroyed; deleting a single profile (as opposed to the
  whole account) from the app; unlinking an individual sign-in method
  (still deferred from #2, above).

## Multi-guardian migration runbook (20260904010000 + 20260904020000)

The two guardian migrations swap constraints on existing tables, so
whoever pushes this deploy runs these read-only audits **before running
`supabase db push`**. This is meant to be enforced by the `production`
environment's required-reviewer rule (see the GitHub checklist above),
but that rule is not yet configured, so until it is, running these audits
first is a manual discipline, not an enforced gate. Each must return
0 rows / the stated result; any deviation stops the deploy.

```sql
-- G1: duplicate profile ids across owners (breaks profiles_id_uq).
select id, count(*) as rows, array_agg(user_id) as owners
  from public.profiles group by id having count(*) > 1;

-- G2: live day-entry duplicates on the new (profile_id, local_date) key
-- (breaks day_entries_live_profile_date_uq as recreated).
select profile_id, local_date, count(*) as live_rows
  from public.day_entries where deleted_at is null
  group by 1, 2 having count(*) > 1;

-- G3: orphaned day_entries.profile_id (breaks the new direct FK).
select count(*) from public.day_entries d
  where not exists (select 1 from public.profiles p where p.id = d.profile_id);
```

Pre-push sanity: `supabase migration list --linked` must show both files
as **pending** (not already applied). If a previous push already applied
these versions, edited files are skipped silently — never re-push edited
migrations in that case; write a new follow-up migration instead.

Post-push verification (within 5 minutes; save baseline counts first):

```sql
-- Every profile's owner is exactly one accepted primary_guardian.
select p.id from public.profiles p
  join lateral (
    select count(*) filter (where role = 'primary_guardian' and status = 'accepted') as primaries
      from public.profile_guardians g where g.profile_id = p.id and g.user_id = p.user_id
  ) x on true where x.primaries <> 1;   -- expect 0 rows

-- Attribution backfill complete.
select count(*) from public.day_entries
  where logged_by_user_id is null or last_modified_by_user_id is null;  -- expect 0
```

Operational notes:

- **Deploy order is mandatory: server migrations first, app release
  second.** The new client pulls `profile_guardians` every sync cycle and
  calls the invitation RPCs, which do not exist on the old schema. Old app
  builds on the new server are fully supported.

  This ordering is now **enforced in CI** (issue #47): `ios-release.yml`'s
  `migration-gate` job compares every migration in `supabase/migrations`
  against `supabase_migrations.schema_migrations` in production and fails
  the release when any is unapplied, so `release` cannot upload to
  TestFlight ahead of its schema. It fails closed — a blocked release is
  recoverable, a client shipped against a missing schema is not.

  It is a backstop, not a substitute for sequencing the deploy yourself.
  It also does not cover `play-store-release.yml`, which is
  `workflow_dispatch`-only and therefore already a deliberate human action.

  This gate exists because the failure is not hypothetical: on 2026-09-05
  two TestFlight builds carrying the multi-guardian feature uploaded on
  merge to `main` roughly an hour before `profile_guardians` existed in
  production. Note also that `supabase-migrate.yml` is still waiting on
  the `production` required-reviewer rule and `SUPABASE_ACCESS_TOKEN`
  (see the GitHub checklist above); until those exist, migrations are
  applied by hand and this gate is what keeps the client from racing them.
- **Rollback.** Migration 2 is reversible via compensating SQL (restore
  the previous `sync_push` body, drop the three RPCs). Migration 1 is
  **not** reversible in place (policy replacement, FK/index swap,
  backfilled attribution): rollback requires a PITR restore to a verified
  pre-deploy recovery point, so confirm the backup timestamp in the
  dashboard before approving the push.
- **Expect a one-time re-pull.** The attribution backfill rewrites every
  `day_entries` row, which bumps `server_version` through the trigger:
  every active client does a full day-entries re-pull on its next sync.
  Bandwidth blip only, not data loss.
- **Lock window.** The unique-index rebuild and FK validation scan take
  ACCESS EXCLUSIVE / SHARE locks on `day_entries` for the scan duration.
  Fine at the current table size; if the table grows past ~1M rows,
  schedule a maintenance window first.
- **Realtime publication.** The realtime coordinator listens on
  `day_entries` and `profiles` `postgres_changes`. The migrations do not
  add the tables to the `supabase_realtime` publication; without it,
  cross-device updates fall back to periodic/foreground sync (acceptable
  degraded mode). If adding it, do so **after** migration 1 completes to
  avoid a fan-out storm from the backfill rewrites.
