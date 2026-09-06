# AGENTS.md — lunarlog

This document is the operating guide and technical context for AI agents working in this repository.

## Project Overview

`lunarlog` is a privacy-first family menstrual-cycle tracking application built with Flutter. It supports one adult operator managing multiple family profiles (including minors). The app is local-first (encrypted Drift/SQLCipher store behind a device-credential gate) with an optional Supabase account: email/password, native Google Sign-In (iOS and Android), native Apple Sign-In (iOS), or passwordless email (link or emailed code), offline-first sync of `profiles` and `day_entries` into RLS-protected Postgres via the `sync_push` RPC, and Sentry crash reporting behind an allowlist scrubber. An unconfigured build (no `--dart-define`s) has no account section, no sync, and no crash reporting.

Target platforms: iOS (iPhone first-class), Android, and web (iteration only; accounts and sync are off on web unless `LUNARLOG_WEB_SYNC=true`).

Implementation plans of record: [`docs/plans/2026-09-02-001-feat-supabase-auth-cloud-sync-plan.md`](docs/plans/2026-09-02-001-feat-supabase-auth-cloud-sync-plan.md) (accounts and sync) and [`docs/plans/2026-09-03-001-feat-social-logins-plan.md`](docs/plans/2026-09-03-001-feat-social-logins-plan.md) (Google, passwordless email, identity linking; its IDs are cited with a `#2` prefix). Operational go-live, device, and release checklists: [`docs/ops/supabase-go-live.md`](docs/ops/supabase-go-live.md).

## Supabase Backend & Cloud Infrastructure

The remote backend is hosted on Supabase Cloud.

- **Project Ref:** `dleexnnevuuddcgcpztq`
- **Project URL:** `https://dleexnnevuuddcgcpztq.supabase.co`
- **Database Engine:** PostgreSQL
- **Database Host:** `db.dleexnnevuuddcgcpztq.supabase.co` (port 5432)
- **MCP Server:** Configured via `.mcp.json`:
  `https://mcp.supabase.com/mcp?project_ref=dleexnnevuuddcgcpztq&features=docs%2Caccount%2Cdatabase%2Cdebugging%2Cdevelopment%2Cfunctions%2Cbranching`
- **Supabase CLI:** Initialized in the repository (`supabase/config.toml`). Pinned to **2.116.0**, run locally through `npx supabase@2.116.0 ...` (not installed globally) and in CI through `supabase/setup-cli@v1` with the same version. `config.toml` governs the **local** stack only; the cloud project's auth settings are set in the dashboard (see "Dashboard prerequisites").
- **Schema (`supabase/migrations/`):** `20260903014208_initial_sync_schema.sql` creates `public.profiles`, `public.day_entries`, and `public.settings`. `20260903014211_sync_push.sql` adds `public.sync_push(p_profiles jsonb, p_day_entries jsonb)`. `20260904010000_multi_guardian_schema.sql` adds `public.profile_guardians` and `public.guardian_invitations` with role-based check constraints (`primary_guardian`, `co_parent`, `caregiver`, `viewer`) and RLS policies. `20260904020000_sync_push_and_invitations.sql` updates `sync_push` to support multi-guardian access, enforce caregiver attribution stamping (`logged_by_user_id`, `last_modified_by_user_id`), and adds `create_guardian_invitation`, `accept_guardian_invitation`, and `revoke_guardian` RPCs. `20260905090000_close_guardian_revocation_bypass.sql` adds `profile_guardians.revoked_at` and `create or replace`s `revoke_guardian` (cancels the profile's outstanding invitations), `accept_guardian_invitation` (refuses to revive a revoked membership via a token that predates the revocation), and `create_guardian_invitation` (stamps `created_at` with `clock_timestamp()` so that comparison is meaningful) - closing the revocation bypass tracked as Issues #81/#82. `20260905100000_realtime_publication.sql` adds `public.sync_signals` (profile_id, updated_at — nothing else) to the `supabase_realtime` publication (Issue #77). It deliberately does **not** publish `public.profiles`/`public.day_entries`, not even with a narrow *publication* column list: Realtime's WALRUS decodes with wal2json, which only honors a publication as a table-level membership list, and this schema's table-wide `select` grant on `day_entries`/`profiles` for `authenticated` means `has_column_privilege` (the check Realtime actually applies) passes for every column regardless of the publication's declared column list — publication column lists are a pgoutput-only feature and are inert here. AFTER triggers on `profiles`/`day_entries` upsert `sync_signals`' row for the affected profile on every change (or delete it, if the profile no longer exists — e.g. a hard profile delete cascading via `profiles.user_id -> auth.users(id) on delete cascade` — so profile deletion never leaves an orphaned signal row behind; PR #92 review round 2, verified against local Supabase), so `RealtimeSyncCoordinator` gets a wake signal with no entry content (`note`/`tags`/`flow`) ever able to cross the websocket, and always re-reads through the RLS-checked sync pull. `public.reconcile_realtime_publication()` (called by the migration, and re-callable) corrects — not just checks — publication membership, `puballtables`, and `sync_signals`'s column list, so a Supabase Studio "Enable Realtime" toggle on `profiles`/`day_entries` is reverted rather than silently accepted as already-correct. That self-healing only happens automatically when the migration *file itself* runs (a `db reset`, or a from-scratch environment applying every migration) — an ordinary `supabase db push` against an already-migrated project does not re-run an already-applied migration, so a Studio toggle used there would sit live-leaking until something else re-invokes the guard. [`supabase-migrate.yml`](.github/workflows/supabase-migrate.yml)'s "Reconcile Realtime publication" step closes that gap by explicitly calling `reconcile_realtime_publication()` via `supabase db query --linked` after every `db push` to `main`, so drift is caught on every deploy. There is still no *periodic* reconciliation between deploys (e.g. catching a toggle used the same day nothing else merges) — tracked as a follow-up, not yet scheduled. `20260905120000_feedback_tickets.sql` (Issue #6) adds `public.feedback_tickets` and `public.feedback_replies` with a server-side diagnostics allowlist (`is_allowed_device_info`), a 5-ticket/hour rate-limit trigger, and a reply-driven status trigger. `20260905130000_feedback_attachments_bucket.sql` adds the private `feedback-attachments` Storage bucket and its per-user object policies, guarded to no-op if the local stack's storage schema is absent.
- **Edge Functions (`supabase/functions/`):** Issue #6's `feedback-notify` (client-invoked, best-effort admin alert on a new ticket) and `feedback-reply` (Database Webhook target on `feedback_replies` insert, dispatches the admin-reply email), both thin handlers over `_shared/format.ts` (pure email-content builders, `deno test`-covered) and `_shared/email.ts` (a single Resend fetch). Deployed by `.github/workflows/supabase-migrate.yml` after `db push`; CI does not run Deno (tracked as a follow-up, issue #103).
- **Database tests (`supabase/tests/`):** 259 pgTAP tests (`000-setup.sql` 1, `rls_isolation_test.sql` 51, `sync_push_test.sql` 87, `profile_guardians_rls_test.sql` 35, `guardian_sync_push_test.sql` 26, `guardian_revocation_bypass_test.sql` 7, `realtime_publication_test.sql` 28, `feedback_rls_test.sql` 20, `feedback_attachments_rls_test.sql` 4 — its plan's "delete own object" case does not run here; `storage.protect_delete()` blocks every direct SQL DELETE against `storage.objects` in this stack, see the file's header comment). The `basejump/supabase_test_helpers` API subset the tests use is inlined in `000-setup.sql`, so the suite needs no network access to `dbdev`. Local and CI Supabase both start with `-x realtime` (no Realtime container), so `realtime_publication_test.sql` proves catalog state (publication membership, `sync_signals`'s column list, replica identity) plus trigger *behavior* (a profiles/day_entries write actually populates `sync_signals`, a hard profile delete removes its `sync_signals` row rather than leaving it orphaned and does not error even with day_entries rows still attached, a non-guardian cannot read another family's signal row, and `reconcile_realtime_publication()` corrects a simulated Studio-toggle drift rather than skipping it) — end-to-end websocket delivery is still a manual check against the cloud project before every merge touching this migration (see the Migration Flow verification step below and "Known limitations" in README.md).
- **Auth client (`lib/startup/supabase_bootstrap.dart`):** `supabase_flutter` 2.17.2 with `publishableKey`, PKCE only, `detectSessionInUri: false` (the app's `SupabaseAuthService` handles `lunarlog://auth-callback` links itself via `app_links` so a cold-start recovery link is latched before the first frame), and a `SecureLocalStorage` (`flutter_secure_storage`, iOS `first_unlock_this_device`, non-synchronizable) for the session and PKCE verifier on native. Apple Sign-In is native iOS only (`sign_in_with_apple` 8.2.0, `signInWithIdToken` with a hashed nonce; entitlement in `ios/Runner/Runner.entitlements`; the Supabase Apple provider's client id is the bundle id `com.wjdavis5.lunarlog`). Google Sign-In is native on iOS and Android (`google_sign_in` 7.2, Credential Manager on Android; `signInWithIdToken` with a per-process hashed nonce; the Web client id is the token audience on Android and the iOS client id on iOS) and hidden when either `GOOGLE_*` define is empty or on web. Passwordless email is `signInWithOtp` + `verifyOTP(type: email)` over the same `lunarlog://auth-callback` PKCE link. A second method is linked with `linkIdentityWithIdToken` behind a fresh device-credential check; there is no unlink.

### Database & Security Guidelines

- **Row-Level Security (RLS) is Mandatory:** All user-facing tables must have RLS enabled and strictly enforce policies scoped to `auth.uid()`. This app stores sensitive health data for family members and minors.
- **Agent Skills Available:**
  - `supabase`: Best practices, client integrations, auth, migrations, and CLI usage.
  - `supabase-postgres-best-practices`: Schema design, indexes, RLS testing, and query efficiency.
- Load these skills before altering database schemas or writing Supabase integration code.

### Migration Flow

1. `npx supabase@2.116.0 migration new <name>` creates the file under `supabase/migrations/`; write imperative SQL and add or extend the pgTAP tests in `supabase/tests/`.
2. Run the suite locally: `npx supabase@2.116.0 start -x realtime,storage-api,imgproxy,mailpit,studio,edge-runtime,logflare,vector,supavisor`, then `db reset --local`, then `test db --local`.
3. Open a PR: the `db-tests` job in [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs the same suite.
4. Merge to `main`: [`.github/workflows/supabase-migrate.yml`](.github/workflows/supabase-migrate.yml) runs `supabase link`, `db push --dry-run`, `db push`, and then `supabase db query --linked "select public.reconcile_realtime_publication();"` inside the `production` GitHub environment and waits for the required reviewer. That last step is what makes the Realtime publication drift guard fire on every deploy (not just a from-scratch environment) — see the note on `20260905100000_realtime_publication.sql` above. It is a **follow-up TODO**, not yet done, to also run this reconciliation *periodically* (e.g. a scheduled workflow) so drift introduced between merges by a Studio toggle is caught without waiting for the next `supabase/**` push.
5. **Before approving the run:** call the Supabase MCP `get_advisors` tool (security and performance lints; there is no CLI equivalent) against project `dleexnnevuuddcgcpztq` and confirm no security or RLS findings. The MCP server needs an interactive login (`authenticate` / `complete_authentication`) in the session that calls it.
6. **Touching `20260905100000_realtime_publication.sql` or the coordinator's subscription shape specifically:** also run `supabase/tests/manual/verify_realtime_delivery.mjs` (see its header for usage) against local Supabase started **without** excluding `realtime` (Docker required), or against the cloud project. This is a real websocket assertion of what Realtime actually delivers — pgTAP alone only proves catalog state (`db-tests` in CI runs with `-x realtime`, so it never exercises the real container). Not wired into CI (investigated and found out of proportion — see the plan's KTD4).

### Dashboard Prerequisites

Settings the code cannot apply; each is a checkbox in [`docs/ops/supabase-go-live.md`](docs/ops/supabase-go-live.md):

- Apple provider with the bundle id as client id; `lunarlog://auth-callback` in the redirect allow-list; custom SMTP before any non-team user signs up (built-in SMTP sends 2 emails per hour to team addresses only); "Confirm email" left on; minimum password length 12 with letters, digits, and symbols and leaked-password protection on; JWT expiry set to the shortest value the dashboard allows (target 10 minutes); session inactivity timeout where the project tier offers it; Sentry "prevent storing IP addresses" and server-side scrubbing.
- Social logins and passwordless (issue #2): Google provider with the Web and iOS client ids as authorized client ids (the Android client id is never an audience) and "Skip nonce check" **off**; "Allow manual linking" **on**; both the Magic Link and the Confirm signup email templates carrying `{{ .Token }}` plus a never-share line (the in-app code field needs both); email OTP expiry 600 s and length 8 (that expiry also governs confirmation and reset links, and the app has no resend button); "Allow new users to sign up" closed once the household's accounts exist (or a `before_user_created` allow-list hook whose table lives only in the project, never in a migration, `docs/`, or a secret) — reopen briefly to onboard a new member.
- A Sentry project and DSN.

## Config & Credential Locations

Credentials and environment variables live in:
- **App configuration (build-time dart-defines):** the app reads its client-side configuration from `lib/config.dart` (`AppConfig`) via `const String.fromEnvironment`. Keys:
  - `SUPABASE_URL` - project URL.
  - `SUPABASE_PUBLISHABLE_KEY` - the `sb_publishable_...` key. In CI this is fed from the existing `secrets.SUPABASE_ANON_KEY` repository secret (kept under its old name; it already holds the publishable key) and mapped to `--dart-define=SUPABASE_PUBLISHABLE_KEY=...`.
  - `SENTRY_DSN` - empty disables crash reporting.
  - `LUNARLOG_WEB_SYNC` - the literal `true` opts a web build into account sign-in and sync; never set in CI.
  - `GOOGLE_IOS_CLIENT_ID` / `GOOGLE_WEB_CLIENT_ID` - the Google OAuth client ids (`AppConfig.hasGoogle` needs both, non-web, and `hasSupabase`; empty hides the Google button). Client-safe, but held as GitHub repository secrets and in `dart_defines.json`, never committed as values. The iOS reversed client id (`com.googleusercontent.apps.<iOS client id>`) is a literal `CFBundleURLTypes` entry in `ios/Runner/Info.plist`, added in the same change that sets the ids; it is the one Google value that is committed.
  - Empty means unconfigured (`AppConfig.hasSupabase` / `hasSentry` are false); every workflow build must succeed with empty defines.
  - **Local run:** copy `dart_defines.example.json` to `dart_defines.json` (gitignored, client-safe values only) and run `flutter run --dart-define-from-file=dart_defines.json`.
- **Server-side only (CLI / database):** `.env` in the repository root (gitignored) - the app never reads it. See `.env.example` for the required keys:
  - `SUPABASE_URL`
  - `SUPABASE_PUBLISHABLE_KEY`
  - `SUPABASE_PROJECT_REF`
  - `DATABASE_PASSWORD`
  - `DATABASE_URL`
- **CI / GitHub Actions:** Repository secrets configured on `wjdavis5/lunarlog`:
  - Supabase: `SUPABASE_URL`, `SUPABASE_ANON_KEY` (holds the publishable key; see above), `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `DATABASE_URL`.
  - Sentry: `SENTRY_DSN` (client-safe; the DSN ships inside the binary). Sentry debug-symbol upload (`SENTRY_AUTH_TOKEN`) is deferred and not configured.
  - Google: `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_WEB_CLIENT_ID` (client-safe OAuth client ids; see above).
  - The five client-safe values (`SUPABASE_URL`, `SUPABASE_ANON_KEY` -> `SUPABASE_PUBLISHABLE_KEY`, `SENTRY_DSN`, `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_WEB_CLIENT_ID`) are passed as `--dart-define` flags to every `flutter build` in `ci.yml`, `ios-release.yml`, and `play-store-release.yml`; on forks they resolve to empty strings and the Google button is absent.
  - **`production` GitHub environment** (required reviewer; used only by `supabase-migrate.yml`): `SUPABASE_ACCESS_TOKEN` (a Supabase personal access token for `supabase link`/`db push`; environment-scoped so no other workflow can read it), plus `SUPABASE_DB_PASSWORD` and `SUPABASE_PROJECT_REF` (environment-scoped copies, or the repository secrets of the same name — environment secrets override repository secrets when both exist). Rotating the access token means replacing it in the environment only.
  - iOS App Store & TestFlight:
    - `ASC_KEY_ID`: App Store Connect API key ID.
    - `ASC_ISSUER_ID`: App Store Connect API issuer ID.
    - `ASC_PRIVATE_KEY`: Full contents of the AuthKey file (`AuthKey_<KEY_ID>.p8`).
    - `IOS_DIST_CERT_P12_BASE64`: Base64 of the Apple Distribution `.p12` certificate.
    - `IOS_DIST_CERT_PASSWORD`: Password protecting that `.p12`.
    - `IOS_PROVISION_PROFILE_BASE64`: Base64 of the App Store `.mobileprovision` profile.
  - Android Play Store:
    - `ANDROID_KEYSTORE_BASE64`: Base64-encoded release `.jks`/`.keystore`.
    - `ANDROID_KEYSTORE_PASSWORD`: Keystore password.
    - `ANDROID_KEY_ALIAS`: Signing key alias.
    - `ANDROID_KEY_PASSWORD`: Key password.
    - `PLAY_STORE_JSON_KEY`: Google Play Developer service account credentials JSON.
- **The Rule:** Never paste, print, or commit raw secret values into files, commits, or pull requests.

## Development & Build Workflow

- **Worktree Isolation (Strict Requirement):** All new work, feature branches, PR reviews, and code changes MUST be performed in isolated git worktrees under `.worktrees/` (e.g. `.worktrees/pr-<n>` or `.worktrees/<branch-name>`). Never check out PR branches or make scratch changes in the primary checkout directory to avoid clobbering in-flight work.
- **Flutter SDK:** Flutter 3.47.2 stable / Dart 3.13.2.
- **Dependency Management:** `flutter pub get`
- **Linter:** `flutter analyze`
- **Tests:** `flutter test` and the pgTAP suite (see "Migration Flow").
- **Quality gates:** `dart run tool/quality_gate.dart` — 90% total line-coverage floor and a per-method CRAP gate (`comp² × (1 − cov/100)³ + comp`, gate at 10), both from one `flutter test --coverage` run filtered through `tool/quality/exclusions.dart`'s reviewed exclusion list (generated code plus platform adapters that can't run under `flutter test`); also the CI `check` job's step right after `flutter test`. `dart run tool/mutation_gate.dart` (`--full` for the whole `lib/`) is local-only mutation testing via the `mutation_test` package, scoped to changed files' test coverage when a direct test mirror exists; see README "Quality gates" for detail. `flutter test` alone is unaffected and stays the fast iteration loop.
- **Codegen:** after any Drift schema change, `dart run build_runner build --delete-conflicting-outputs` and commit `lib/data/db/db.g.dart`.
- **Android build note:** `flutter build apk` prints a Gradle warning that `sentry_flutter` 9.28.0 applies the Kotlin Gradle Plugin itself. It is upstream and harmless today; a future Flutter release may reject it, so re-check after every Flutter or `sentry_flutter` upgrade.
- **Device checklist:** auth links, Apple and Google Sign-In, magic links and emailed codes, adding a sign-in method, two-device sync convergence, lock-mid-sync, and the sign-out reset cannot be covered by `flutter test`; they are verified by hand on iPhone and Android builds with a throwaway account per [`docs/ops/supabase-go-live.md`](docs/ops/supabase-go-live.md) ("Device checklist"). Use fabricated profiles only — never real family data.
- **Release gate:** no App Store submission and no Play `production` dispatch until in-app account deletion has shipped (App Store guideline 5.1.1(v) makes deletion a submission blocker once account creation exists). Mechanically enforced, not just documented: [`.github/scripts/check-release-gate.sh`](.github/scripts/check-release-gate.sh) fails closed unless the `RELEASE_GATE_ACCOUNT_DELETION` repository variable is set to `shipped`; a Play `production` dispatch additionally requires typing `production` into the `confirm_production` input. Issue #17 is what flips the variable once deletion ships. Pushes to `main` still upload to TestFlight and the Play `internal` track; that is acceptable for internal testing only.
- **iOS App Store / TestFlight Release Workflow (Primary):**
  - Automated via [`.github/workflows/ios-release.yml`](.github/workflows/ios-release.yml) (mirrored from `taxiGame`).
  - Triggers on push to `main`: builds, signs, and uploads to TestFlight.
  - Submits for App Store review when `version:` in `pubspec.yaml` changes anywhere across the pushed commit range (not just the tip commit; see [`.github/scripts/detect-version-bump.sh`](.github/scripts/detect-version-bump.sh)), or manually via `workflow_dispatch` (`submit_for_review: true`). Either path is withheld while the release gate above is closed — an automatic bump degrades to TestFlight-only with a warning, an explicit dispatch fails fast before the build.
  - Monotonic build number calculated via GitHub run counter (`$(( github.run_number + 1000 ))`).
  - Manual signing in CI via [`ios/ExportOptions-ci.plist`](ios/ExportOptions-ci.plist). The target now has the Sign in with Apple entitlement (`ios/Runner/Runner.entitlements`, wired via `CODE_SIGN_ENTITLEMENTS`), so the App Store provisioning profile in `IOS_PROVISION_PROFILE_BASE64` must be regenerated with that capability on the `com.wjdavis5.lunarlog` App ID before the workflow can sign — not yet done.
  - Export-compliance declaration (`ITSAppUsesNonExemptEncryption` in `ios/Runner/Info.plist`, aligned in `fastlane/Fastfile`, verified in the "Verify the exported bundle" step): classification rationale and the operator's recurring filing duties are in [`docs/ops/ios-export-compliance.md`](docs/ops/ios-export-compliance.md).
- **Android Play Store Release Workflow:**
  - Automated via [`.github/workflows/play-store-release.yml`](.github/workflows/play-store-release.yml).
  - Manual only via `workflow_dispatch` with a target track (`internal`, `alpha`, `beta`, `production`) — there is no push trigger.
  - A `production` dispatch is gated by the release gate above before any build runs.
  - Automatically resolves monotonic build numbers from GitHub run count offset (`$(( github.run_number + 1000 ))`).
  - Generates both signed `.aab` (uploaded to Google Play) and `.apk` (saved as run artifact).
- **iOS Local Device Builds:** Run on a macOS build machine with Xcode:
  ```bash
  flutter build ipa --release --no-codesign
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -archivePath build/ios/archive/Runner.xcarchive archive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
  xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive -exportOptionsPlist ios/ExportOptions.plist -exportPath build/ios/ipa
  ```
