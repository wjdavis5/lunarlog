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

iOS device builds happen on the lab Mac per the project plan; this Windows box
covers Android, web, and tests.

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs analyze +
test + a release web build on ubuntu, a debug APK on ubuntu, and an unsigned
iOS build on macOS, for pushes and PRs to `main`.

## Config & credentials

None. v1 is fully offline with no accounts, services, or keys — no `.env` is
needed.

## Lab context

Part of the home lab; the canonical inventory lives in the lab root's
`CLAUDE.md` (`C:\git` on the lab desktop).

## Verified

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
