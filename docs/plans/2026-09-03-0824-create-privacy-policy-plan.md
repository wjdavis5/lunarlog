# Implementation Plan: Create LunarLog Privacy Policy

```yaml
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
execution: code
```

## Summary

Create a comprehensive, technically accurate, and legally robust Privacy Policy for LunarLog. The policy accurately reflects LunarLog's local-first architecture, encrypted storage, optional Supabase cloud sync, strict Sentry telemetry scrubbing, and minors' profile custodianship. The policy will be provided as:
1. Canonical markdown document in repository root (`PRIVACY.md`), published publicly at `https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md`.
2. Static standalone HTML page (`web/privacy.html`) bundled in web builds.
3. In-app access via a "Privacy policy" tile in `SettingsScreen` (`lib/ui/settings/settings_screen.dart`) displaying the policy details offline.
4. Reference in `README.md`.

## Key Technical Decisions (KTDs)

- **KTD1 (Canonical Location):** `PRIVACY.md` in the repository root serves as the authoritative privacy policy. Its public URL on GitHub main branch is `https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md`.
- **KTD2 (Static Web Asset):** `web/privacy.html` provides a self-contained, mobile-friendly HTML rendering with zero external scripts, trackers, or remote fonts.
- **KTD3 (Architectural Fidelity):** The privacy policy strictly mirrors the code's real behavior and `ios/Runner/PrivacyInfo.xcprivacy`:
  - Cycle data stored encrypted locally via SQLCipher.
  - Optional cloud account via Supabase with RLS; explicit upload consent required.
  - Sentry error monitoring governed by the KTD12 scrub floor (`lib/observability/scrub.dart`) which strips all health content, dates, notes, and identity tokens.
  - Minor profiles managed under guardian custodianship; no behavioral tracking, profiling, or advertising.
- **KTD4 (In-App Privacy Dialog):** A new "Privacy policy" tile in `SettingsScreen` opens a dialog or scrollable sheet displaying the complete policy text natively offline.

## Units of Work

### U1: Canonical `PRIVACY.md` in Repository Root
- Create `PRIVACY.md` covering:
  - Introduction & Core Principles (local-first, privacy-by-design, no advertising).
  - Information We Collect & Process (cycle data, symptoms, optional account email, authentication tokens, crash logs).
  - Storage & Encryption (SQLCipher AES-256 local database, biometric gate, screen obfuscation).
  - Optional Cloud Sync (Supabase Auth, row-level security, explicit upload consent).
  - Third-Party Processors & Data Sharing (Supabase for sync/auth, Sentry for scrubbed crash reports, Apple/Google for optional OAuth).
  - Minors' Privacy & Parental Custodianship (family profile management).
  - Data Retention, Export, and Deletion (local wipes, sign out everywhere, account deletion requests).
  - User Rights (GDPR, CCPA, and global privacy frameworks).
  - Contact information and policy updates.

### U2: Static Web Asset `web/privacy.html`
- Create `web/privacy.html` styled with LunarLog's aesthetic (dark mode compatible, clean typography, responsive layout).
- Embed all content directly without external stylesheet or JavaScript dependencies.

### U3: In-App Settings Tile & README Link
- In `lib/ui/settings/settings_screen.dart`:
  - Add a `ListTile` for "Privacy policy" with `Icons.privacy_tip_outlined` (or `Icons.shield_outlined`).
  - On tap, show a dialog or bottom sheet displaying the policy summary and full text with a close button.
- In `README.md`:
  - Add a section linking to `PRIVACY.md`.

### U4: Verification & Tests
- Add a widget test in `test/ui/settings_test.dart` verifying the "Privacy policy" tile renders in `SettingsScreen` and tapping it opens the policy dialog.
- Run `flutter analyze` (0 issues required).
- Run `flutter test` (all 480+ tests passing required).
