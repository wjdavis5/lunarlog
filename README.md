# lunarlog

Local-first menstrual-cycle tracker built with Flutter: one adult operator
manages cycle profiles for the family (some profiles are minors), and the data
never leaves the device. v1 is fully offline — entries are stored encrypted at
rest behind a biometric gate — and has no fertility features, by design.
Targets iOS (iPhone first-class), Android, and an installable web PWA used for
iteration only. The app will hold sensitive health data, including minors';
this repo stays private and must never contain real personal or health data.

**Status:** dev project, not deployed.

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
flutter test                    # widget tests
flutter run -d chrome           # web, for iteration
flutter build apk --debug       # Android debug APK
flutter build web --release     # installable web build
flutter build ios --release --no-codesign   # unsigned; requires macOS
```

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

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs analyze +
test + a release web build on ubuntu, a debug APK on ubuntu, and an unsigned
iOS build on macOS, for pushes and PRs to `main`.

Automated Android release to Google Play is handled by
[`.github/workflows/play-store-release.yml`](.github/workflows/play-store-release.yml),
supporting automatic internal track publishing and manual dispatch for alpha,
beta, and production.

## Config & credentials

Remote backend: Supabase Cloud (`dleexnnevuuddcgcpztq`).
Credentials live in `.env` (gitignored; `.env.example` provides the template)
and GitHub repository secrets. Never commit credential values.
Details on backend setup and MCP integration live in [`AGENTS.md`](AGENTS.md).

## Lab context

Part of the home lab; the canonical inventory lives in the lab root's
`CLAUDE.md` (`C:\git` on the lab desktop).

## Verified

- 2026-09-02, Flutter 3.47.2 stable on Williams-Mini (macOS arm64, Xcode 26.6):
  `flutter analyze` clean (0 issues); `flutter test` 162/162 tests passed;
  `flutter build ipa --release --no-codesign` built `Runner.xcarchive` (179.9MB);
  `flutter build ios --release --no-codesign` built `Runner.app` (20.3MB).
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
- No backup or export in v1 — losing the device loses the data.
- No fertility features, by design; do not add them.
- App-switcher snapshots are suppressed by an opaque Flutter cover whenever
  the app is not resumed, plus FLAG_SECURE on Android (a tiny platform
  channel in `MainActivity.kt`); iOS has no Flutter-level FLAG_SECURE
  equivalent, so the cover is the only mechanism there.
- iOS: the database file is not explicitly excluded from iCloud backups
  (skipped in U7 — it needs AppDelegate work on the Mac; the keychain-stored
  key is already device-only, and Android covers the equivalent with
  `allowBackup="false"`).
