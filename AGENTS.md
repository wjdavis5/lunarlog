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
- **Schema (`supabase/migrations/`):** `20260903014208_initial_sync_schema.sql` creates `public.profiles`, `public.day_entries`, and `public.settings` (per-user composite primary keys `(id, user_id)`, a composite FK from `day_entries` to `profiles`, a partial unique index on live `(profile_id, local_date)`, a `server_version` sequence + trigger, RLS enabled **and forced** on all three tables, four `to authenticated` owner-equality policies per table, and column-list `update` grants). `20260903014211_sync_push.sql` adds `public.sync_push(p_profiles jsonb, p_day_entries jsonb)`, the last-writer-wins upsert RPC (`security invoker`, `set search_path = ''`, executable by `authenticated` only).
- **Database tests (`supabase/tests/`):** 135 pgTAP tests (`000-setup.sql` 1, `rls_isolation_test.sql` 52, `sync_push_test.sql` 82). The `basejump/supabase_test_helpers` API subset the tests use is inlined in `000-setup.sql`, so the suite needs no network access to `dbdev`.
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
4. Merge to `main`: [`.github/workflows/supabase-migrate.yml`](.github/workflows/supabase-migrate.yml) runs `supabase link`, `db push --dry-run`, and `db push` inside the `production` GitHub environment and waits for the required reviewer.
5. **Before approving the run:** call the Supabase MCP `get_advisors` tool (security and performance lints; there is no CLI equivalent) against project `dleexnnevuuddcgcpztq` and confirm no security or RLS findings. The MCP server needs an interactive login (`authenticate` / `complete_authentication`) in the session that calls it.

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
- **Tests:** `flutter test` (377 tests as of 2026-09-03) and the pgTAP suite (see "Migration Flow").
- **Codegen:** after any Drift schema change, `dart run build_runner build --delete-conflicting-outputs` and commit `lib/data/db/db.g.dart`.
- **Android build note:** `flutter build apk` prints a Gradle warning that `sentry_flutter` 9.28.0 applies the Kotlin Gradle Plugin itself. It is upstream and harmless today; a future Flutter release may reject it, so re-check after every Flutter or `sentry_flutter` upgrade.
- **Device checklist:** auth links, Apple and Google Sign-In, magic links and emailed codes, adding a sign-in method, two-device sync convergence, lock-mid-sync, and the sign-out reset cannot be covered by `flutter test`; they are verified by hand on iPhone and Android builds with a throwaway account per [`docs/ops/supabase-go-live.md`](docs/ops/supabase-go-live.md) ("Device checklist"). Use fabricated profiles only — never real family data.
- **Release gate:** no `version:` bump in `pubspec.yaml` and no `submit_for_review` dispatch of `ios-release.yml` until in-app account deletion has shipped (App Store guideline 5.1.1(v) makes deletion a submission blocker once account creation exists). Pushes to `main` still upload to TestFlight and the Play `internal` track; that is acceptable for internal testing only.
- **iOS App Store / TestFlight Release Workflow (Primary):**
  - Automated via [`.github/workflows/ios-release.yml`](.github/workflows/ios-release.yml) (mirrored from `taxiGame`).
  - Triggers on push to `main`: builds, signs, and uploads to TestFlight.
  - Submits for App Store review automatically when `version:` in `pubspec.yaml` changes, or manually via `workflow_dispatch` (`submit_for_review: true`).
  - Monotonic build number calculated via GitHub run counter (`$(( github.run_number + 1000 ))`).
  - Manual signing in CI via [`ios/ExportOptions-ci.plist`](ios/ExportOptions-ci.plist). The target now has the Sign in with Apple entitlement (`ios/Runner/Runner.entitlements`, wired via `CODE_SIGN_ENTITLEMENTS`), so the App Store provisioning profile in `IOS_PROVISION_PROFILE_BASE64` must be regenerated with that capability on the `com.wjdavis5.lunarlog` App ID before the workflow can sign — not yet done.
- **Android Play Store Release Workflow:**
  - Automated via [`.github/workflows/play-store-release.yml`](.github/workflows/play-store-release.yml).
  - Triggers on push to `main` (uploads to `internal` track) or manually via `workflow_dispatch` with target track (`internal`, `alpha`, `beta`, `production`).
  - Automatically resolves monotonic build numbers from GitHub run count offset (`$(( github.run_number + 1000 ))`).
  - Generates both signed `.aab` (uploaded to Google Play) and `.apk` (saved as run artifact).
- **iOS Local Device Builds:** Run on a macOS build machine with Xcode:
  ```bash
  flutter build ipa --release --no-codesign
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -archivePath build/ios/archive/Runner.xcarchive archive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
  xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive -exportOptionsPlist ios/ExportOptions.plist -exportPath build/ios/ipa
  ```
