# AGENTS.md — lunarlog

This document is the operating guide and technical context for AI agents working in this repository.

## Project Overview

`lunarlog` is a privacy-first family menstrual-cycle tracking application built with Flutter. It supports one adult operator managing multiple family profiles (including minors). The app is pivoting from offline-only to supporting user logins, multi-device synchronization, and remote data storage backed by Supabase.

Target platforms: iOS (iPhone first-class), Android, and web.

## Supabase Backend & Cloud Infrastructure

The remote backend is hosted on Supabase Cloud.

- **Project Ref:** `dleexnnevuuddcgcpztq`
- **Project URL:** `https://dleexnnevuuddcgcpztq.supabase.co`
- **Database Engine:** PostgreSQL
- **Database Host:** `db.dleexnnevuuddcgcpztq.supabase.co` (port 5432)
- **MCP Server:** Configured via `.mcp.json`:
  `https://mcp.supabase.com/mcp?project_ref=dleexnnevuuddcgcpztq&features=docs%2Caccount%2Cdatabase%2Cdebugging%2Cdevelopment%2Cfunctions%2Cbranching`
- **Supabase CLI:** Initialized in the repository (`supabase/config.toml`).

### Database & Security Guidelines

- **Row-Level Security (RLS) is Mandatory:** All user-facing tables must have RLS enabled and strictly enforce policies scoped to `auth.uid()`. This app stores sensitive health data for family members and minors.
- **Agent Skills Available:**
  - `supabase`: Best practices, client integrations, auth, migrations, and CLI usage.
  - `supabase-postgres-best-practices`: Schema design, indexes, RLS testing, and query efficiency.
- Load these skills before altering database schemas or writing Supabase integration code.

## Config & Credential Locations

Credentials and environment variables live in:
- **Local Dev:** `.env` in the repository root (gitignored). See `.env.example` for the required keys:
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`
  - `SUPABASE_PROJECT_REF`
  - `DATABASE_PASSWORD`
  - `DATABASE_URL`
- **Mac Mini Build Machine:** `~/git/lunarlog/.env` on `Williams-Mini` (`192.168.0.9`).
- **CI / GitHub Actions:** Repository secrets configured on `wjdavis5/lunarlog`:
  - Supabase: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `DATABASE_URL`.
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

- **Flutter SDK:** Flutter 3.47.2 stable / Dart 3.13.2.
- **Dependency Management:** `flutter pub get`
- **Linter:** `flutter analyze`
- **Tests:** `flutter test`
- **iOS App Store / TestFlight Release Workflow (Primary):**
  - Automated via [`.github/workflows/ios-release.yml`](.github/workflows/ios-release.yml) (mirrored from `taxiGame`).
  - Triggers on push to `main`: builds, signs, and uploads to TestFlight.
  - Submits for App Store review automatically when `version:` in `pubspec.yaml` changes, or manually via `workflow_dispatch` (`submit_for_review: true`).
  - Monotonic build number calculated via GitHub run counter (`$(( github.run_number + 1000 ))`).
  - Manual signing in CI via [`ios/ExportOptions-ci.plist`](ios/ExportOptions-ci.plist).
- **Android Play Store Release Workflow:**
  - Automated via [`.github/workflows/play-store-release.yml`](.github/workflows/play-store-release.yml).
  - Triggers on push to `main` (uploads to `internal` track) or manually via `workflow_dispatch` with target track (`internal`, `alpha`, `beta`, `production`).
  - Automatically resolves monotonic build numbers from GitHub run count offset (`$(( github.run_number + 1000 ))`).
  - Generates both signed `.aab` (uploaded to Google Play) and `.apk` (saved as run artifact).
- **iOS Local Device Builds:** Run on the lab Mac Mini (`Williams-Mini`, `192.168.0.9`, SSH user `williamdavis` via lab key `ha_vm_ed25519`):
  ```bash
  flutter build ipa --release --no-codesign
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -archivePath build/ios/archive/Runner.xcarchive archive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
  xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive -exportOptionsPlist ios/ExportOptions.plist -exportPath build/ios/ipa
  ```

## Lab Context

Part of the home lab managed from `C:\git`. The canonical lab systems inventory and credentials map live in `C:\git\CLAUDE.md`.
