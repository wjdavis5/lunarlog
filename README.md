# lunarlog

Local-first menstrual-cycle tracker built with Flutter: one adult operator
manages cycle profiles for the family (some profiles are minors). Entries are
stored on the device encrypted at rest behind a biometric gate, and the app
works fully without a network. An **optional account** (Supabase Auth) mirrors
the local store into row-level-secured Postgres and syncs it offline-first
across the operator's devices; nothing is uploaded until the operator signs in
and, on a device that already holds data, explicitly consents to the upload.
Exactly two parties receive data off-device, both only for app functionality:
**Supabase** (the account email and the synced cycle rows) and **Sentry**
(crash reports reduced to an allowlist — no user, no health content). No
fertility features, by design. Targets iOS (iPhone first-class), Android, and
an installable web PWA used for iteration only. The app holds sensitive health
data, including minors'; this repo stays private and must never contain real
personal or health data.

**Privacy Policy:** Read our full [Privacy Policy](PRIVACY.md).  
**License:** [PolyForm Noncommercial 1.0.0](LICENSE) (Free for personal/noncommercial use; commercial resale prohibited).

**Status:** dev project, not deployed. Release is gated (see Known limitations).

## Build / run

Flutter lives at `C:\src\flutter` on the lab desktop and is **not** on the
persistent PATH — prepend it in each shell that needs it:

```powershell
$env:Path = "C:\src\flutter\bin;$env:Path"
```

Then, from the repo root:

```powershell
flutter pub get
flutter analyze                 # lints (flutter_lints)
flutter test                    # unit + widget tests
flutter run -d chrome           # web, for iteration (no account, no sync)
flutter run --dart-define-from-file=dart_defines.json   # with Supabase/Sentry configured
flutter build apk --debug       # Android debug APK
flutter build web --release     # installable web build
flutter build ios --release --no-codesign   # unsigned; requires macOS
```

Without `--dart-define`s the app is a purely local build: no account section,
no sync, no crash reporting. See "Config & credentials".

### Supabase local stack (database tests)

The remote schema, RLS policies, and the `sync_push` RPC live in
`supabase/migrations/` and are proven by pgTAP tests in `supabase/tests/`.
The Supabase CLI is pinned to 2.116.0 and run through `npx` (not installed
globally); Docker must be running.

```powershell
npx supabase@2.116.0 start -x realtime,storage-api,imgproxy,mailpit,studio,edge-runtime,logflare,vector,supavisor
npx supabase@2.116.0 db reset --local    # re-apply migrations from scratch
npx supabase@2.116.0 test db --local     # 135 pgTAP tests
npx supabase@2.116.0 stop --no-backup
```

`supabase/config.toml` configures the **local** stack only (its auth
settings — 6-character passwords, confirmations off, 1-hour JWT — are the CLI
defaults and do not reflect the cloud project's dashboard settings; see
[`docs/ops/supabase-go-live.md`](docs/ops/supabase-go-live.md)).

### iOS build, sign & deploy (Mac)

On `Williams-Mini` (or any macOS build machine with Xcode and Apple Team ID `5273C9R3V4`):

```bash
# 1. Fetch dependencies
flutter pub get

# 2. Build unsigned archive
flutter build ipa --release --no-codesign
# Or via xcodebuild:
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -archivePath build/ios/archive/Runner.xcarchive archive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

# 3. Export signed IPA using ExportOptions.plist
xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive -exportOptionsPlist ios/ExportOptions.plist -exportPath build/ios/ipa

# 4. Deploy to connected physical device
xcrun devicectl device install app --device <device-id> build/ios/ipa/lunarlog.ipa
# or via flutter:
flutter install -d <device-id>
```

The iOS target now carries `ios/Runner/Runner.entitlements` (Sign in with
Apple), so any signing profile — local or CI — must be generated with that
capability enabled on the `com.wjdavis5.lunarlog` App ID.

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs analyze +
test + a release web build on ubuntu, the pgTAP database tests against a
local Supabase stack (`db-tests` job), a debug APK on ubuntu, and an unsigned
iOS build on macOS, for pushes and PRs to `main`. Every build passes the
Supabase, Sentry, and Google `--dart-define`s from repository secrets; on
forks they resolve to empty and the build must still succeed.

Database migrations are pushed to the cloud project by
[`.github/workflows/supabase-migrate.yml`](.github/workflows/supabase-migrate.yml)
when `supabase/**` changes on `main`, inside the `production` GitHub
environment (required reviewer). Automated iOS release to TestFlight and App
Store review (primary) is handled by
[`.github/workflows/ios-release.yml`](.github/workflows/ios-release.yml)
(mirrored from `taxiGame`). Automated Android release to Google Play is handled
by [`.github/workflows/play-store-release.yml`](.github/workflows/play-store-release.yml).

## Accounts

The account is optional and lives in Supabase Auth. Sign-in methods:
email/password, Google (iOS and Android, native picker), Apple (iOS), and
passwordless email — a sign-in link opened on the requesting device or the
code from the same email typed into the app. Web builds have no Google
button (`google_sign_in_web` cannot supply an ID token), and accounts are
off on web anyway unless `LUNARLOG_WEB_SYNC=true`. A signed-in operator can
see which methods the account has in the account section and add Google
(or Apple on iOS) to it after a fresh device-credential check; methods
cannot be removed in-app. Once the household is onboarded, sign-ups are
closed in the dashboard and every create path says accounts are set up by
the account owner. Passkeys are deferred (Supabase passkeys are beta and
need an HTTPS relying-party domain the app does not yet have). The Google
button is hidden in any build without both `GOOGLE_*` defines. Plans:
[`docs/plans/2026-09-02-001-feat-supabase-auth-cloud-sync-plan.md`](docs/plans/2026-09-02-001-feat-supabase-auth-cloud-sync-plan.md)
and
[`docs/plans/2026-09-03-001-feat-social-logins-plan.md`](docs/plans/2026-09-03-001-feat-social-logins-plan.md).

## Config & credentials

Remote backend: Supabase Cloud (`dleexnnevuuddcgcpztq`); crash reporting:
Sentry. Configuration reaches the app in exactly one way and the tooling in
another:

- **App (client-side, build time):** `lib/config.dart` (`AppConfig`) reads
  `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SENTRY_DSN`,
  `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_WEB_CLIENT_ID`, and `LUNARLOG_WEB_SYNC`
  via `--dart-define`. Empty means unconfigured. For local runs copy
  `dart_defines.example.json` to `dart_defines.json` (gitignored;
  client-safe values only — the publishable key, DSN, and Google client ids
  are designed to ship inside the binary) and pass
  `--dart-define-from-file=dart_defines.json`. The iOS reversed Google
  client id is committed as a URL scheme in `ios/Runner/Info.plist` once the
  ids exist.
- **Tooling (server-side only):** `.env` (gitignored; `.env.example` is the
  template) feeds the Supabase CLI and direct database access — project ref,
  database password, `DATABASE_URL`. The app never reads it.
- **CI:** GitHub repository secrets on `wjdavis5/lunarlog` supply the five
  client-safe defines to every workflow build; the `production` environment
  holds the migration credentials (`SUPABASE_ACCESS_TOKEN`,
  `SUPABASE_DB_PASSWORD`, `SUPABASE_PROJECT_REF`) behind a required reviewer.

Never commit credential values. The full list of secrets, the dashboard
settings the code cannot apply, and the go-live checklist live in
[`AGENTS.md`](AGENTS.md) and [`docs/ops/supabase-go-live.md`](docs/ops/supabase-go-live.md).

## Lab context

Part of the home lab; the canonical inventory lives in the lab root's
`CLAUDE.md` (`C:\git` on the lab desktop).

## Verified

- 2026-09-03, Flutter 3.47.2 stable on Windows (branch
  `feat/supabase-auth-cloud-sync`): `flutter analyze` clean (0 issues);
  `flutter test` 377/377 passed; `flutter build web --release` (no defines)
  and `flutter build apk --debug` both succeeded (the Android Gradle build
  prints an upstream warning that `sentry_flutter` applies the Kotlin Gradle
  Plugin itself; harmless today, but a future Flutter may reject it);
  `npx supabase@2.116.0 start` + `db reset --local` + `test db --local` ran
  135/135 pgTAP tests. Dependencies: supabase_flutter 2.17.2,
  sign_in_with_apple 8.2.0, sentry_flutter 9.28.0, Supabase CLI 2.116.0.
  Not run in this environment: the iOS build on `Williams-Mini`, the device
  checklist, the Sentry smoke test, `supabase db push --dry-run`, and the
  MCP `get_advisors` check — all tracked in `docs/ops/supabase-go-live.md`.
- 2026-09-02, Flutter 3.47.2 stable on Williams-Mini (macOS arm64, Xcode 26.6):
  `flutter analyze` clean (0 issues); `flutter test` 162/162 tests passed;
  `flutter build ipa --release --no-codesign` built `Runner.xcarchive` (179.9MB);
  `flutter build ios --release --no-codesign` built `Runner.app` (20.3MB).
  (Pre-dates the Sign in with Apple entitlement; re-verify.)
- 2026-09-02, Flutter 3.47.2 stable on Windows: `flutter analyze` clean (0 issues);
  `flutter test` 162/162 unit & widget tests passed across domain, data, gate,
  notifications, profiles, logging, and overview suites; `ios/Runner.xcodeproj`
  configured with `PRODUCT_BUNDLE_IDENTIFIER = com.wjdavis5.lunarlog`,
  `DEVELOPMENT_TEAM = 5273C9R3V4`, `ExportOptions.plist`, and `PrivacyInfo.xcprivacy`.
- 2026-08-30, Flutter 3.47.2 stable on Windows: `flutter doctor -v` all green
  (Android SDK 36.0.0, all licenses accepted, Chrome present); `flutter
  analyze` clean; `flutter test` 1/1 passed; `flutter build apk --debug` and
  `flutter build web --release` both succeeded.
- Re-verify after a Flutter SDK upgrade or any change to build config.

## Known limitations (accepted)

- Web build is iteration-only — browser storage does not provide the
  encryption-at-rest guarantee; do not treat the PWA as a secure data store.
  Account sign-in and sync are **off** on web unless the build is compiled
  with `LUNARLOG_WEB_SYNC=true` (a signed-in browser would hold the account's
  bearer token and rows unencrypted; the dev banner says so when it is on).
  Never set it in CI.
- Backup is account-based: a device signed in to an account keeps a copy of
  its data in that account and can restore it on another device. A device
  that never signed in has no backup — losing it loses the data. There is no
  file export.
- In-app account deletion and data export are follow-up work, and they
  **gate release**: no `version:` bump in `pubspec.yaml` and no
  `submit_for_review` dispatch of `ios-release.yml` until in-app account
  deletion has shipped (App Store guideline 5.1.1(v)).
- "Sign out everywhere" revokes sessions, not tokens: other devices keep
  access until their JWT expires, which is why the project's JWT expiry is
  set to the dashboard minimum.
- No fertility features, by design; do not add them.
- App-switcher snapshots are suppressed by an opaque Flutter cover whenever
  the app is not resumed, plus FLAG_SECURE on Android (a tiny platform
  channel in `MainActivity.kt`); iOS has no Flutter-level FLAG_SECURE
  equivalent, so the cover is the only mechanism there.
- iOS: the database file is not explicitly excluded from iCloud backups
  (skipped in U7 — it needs AppDelegate work on the Mac; the keychain-stored
  key is already device-only, and Android covers the equivalent with
  `allowBackup="false"`). The Supabase session and PKCE verifier are stored
  with `first_unlock_this_device` and never travel in a backup.

## License

This project is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE).  
You are free to view, modify, and run this software for noncommercial personal and family use. Commercial use, reproduction, distribution, or resale is strictly prohibited without a separate commercial license from the author.

