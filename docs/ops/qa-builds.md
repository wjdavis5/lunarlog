# QA builds (the `LUNARLOG_QA_BUILD` flag)

Operator and tester runbook for cutting a QA build — the explicitly
requested, clearly marked build (issue
[#739](https://github.com/wjdavis5/lunarlog/issues/739)) that compiles the
client-side security-prompt bypasses in, so testers can exercise the core
feature set on real devices without the credential ceremony. This file is
also the record of **why a QA build can never become a store build** and
of every mechanical guard that enforces that.

## What a QA build is

`--dart-define=LUNARLOG_QA_BUILD=true`, read through exactly one seam:
`AppConfig.qaBuild` in `lib/config.dart` (pinned by
`test/architecture/qa_flag_seam_test.dart`). Default `false`, everywhere:
CI, forks, every ordinary dispatch, and every store build. No runtime
toggle, no server flag, no account allowlist — the flag is compile-time or
it does not exist.

When `true`:

| Behaviour | QA build | Store build |
| --- | --- | --- |
| Launch unlock gate (Face ID / passcode) | skipped — `GateController` starts unlocked | enforced before any data renders or the database opens |
| Re-lock (backgrounding, 2-minute inactivity) | permanently off; the Settings toggle renders disabled with a "QA build" note | on by default, toggleable |
| `reauthenticate()` (add/remove sign-in method, PIN change, destructive actions) | auto-grants | real device-credential prompt |
| `ensureAal2` (TOTP step-up before deletion / transfer / sign-out-everywhere) | auto-passes — OR-ed into `ensureAal2`'s `mfaEnabled` early return, independently, so it holds even when MFA is re-enabled globally (#738) | real step-up dialog when a verified factor exists |
| MFA enrolment itself | fully exercisable (only the pre-action prompt is bypassed) | unchanged |
| Privacy cover / snapshot suppression | unchanged — the flag skips prompts, not privacy posture | unchanged |
| Server-side behaviour (the `delete-account` Edge Function's AAL2 check, gotrue session enforcement, every RLS policy) | **identical** — a QA build skips client prompts, never permissions | unchanged |

Visible markers (scope item 3): a persistent "QA build" banner above every
screen (`lib/ui/startup/qa_build_banner.dart`), the OS task-switcher app
title `lunarlog (QA build)`, and the Settings → About version line carries
an `(QA build)` suffix — so a screenshot or screen recording identifies
the build at a glance.

## How to cut one

- **iOS:** dispatch
  [`ios-release.yml`](../../.github/workflows/ios-release.yml) with
  `qa_build: true` (leave `submit_for_review: false` — anything else fails
  the `qa-build-gate` job before any build work). The build lands on
  TestFlight with a build number in the **501xxx+ range** (production
  builds are 1xxx–10xxx).
- **Android:** dispatch
  [`play-store-release.yml`](../../.github/workflows/play-store-release.yml)
  with `qa_build: true` and `track: internal` (any other track fails the
  `qa-build-gate` job). The Play release name carries `QA <version>
  (<build>)`, and the workflow-run artifact is named `android-qa-release-…`.
- **Locally:** `flutter run --dart-define=LUNARLOG_QA_BUILD=true`
  (add `--dart-define-from-file=dart_defines.json` as usual for a
  configured build).

### The one manual step (iOS)

`xcrun altool` cannot set TestFlight's "What to Test" field, so after a QA
build finishes processing in App Store Connect, set that field to text
containing `QA build` by hand. The workflow prints a `::notice::` reminder
at the end of the upload step. The 501xxx build number and the in-app
banner are the automated markers; this note is the third, and it is the
one a reviewer reading TestFlight sees first.

## Why a QA build can never be submitted or promoted

The iOS workflow uploads to TestFlight, and a `submit_for_review: true`
dispatch later submits **that same binary** to App Store review — so a QA
flag compiled into an ordinary TestFlight build would reach store users.
On Android, a build on `internal` can be promoted in Play Console toward
production. A QA build ships with the unlock gate, relock, and re-auth
prompts compiled out; it must never be the binary a store user runs.

Guards (each fails the dispatch **before any build work**):

- `.github/scripts/check-qa-build-gate.sh` — the single implementation,
  called by both workflows' `qa-build-gate` job. Refuses
  `qa_build: true` + `submit_for_review: true` (iOS) and `qa_build: true`
  + any Play track but `internal`. Its truth table *and* the workflows'
  wiring of it are pinned by
  `.github/scripts/tests/check-qa-build-gate.test.sh`, which CI runs on
  every PR (ubuntu and macOS arms).
- The Android publish step for QA dispatches hard-codes `track: internal`
  even if the gate were ever loosened.
- The distinct 501xxx+ build-number range, the Play `QA …` release name,
  and the in-app banner exist so that a **manual** promotion attempt in
  App Store Connect or Play Console is recognisable before it ships.

## Tester expectations

A QA build opens straight into the app with no unlock prompt, never
re-locks, and never shows a re-auth or TOTP step-up prompt. Server-side
rules still apply exactly as in a store build: an account with a verified
TOTP factor still needs a real AAL2 session for `delete-account` to
succeed, sharing/invitation permissions are unchanged, and RLS isolates
families as always. Use fabricated profiles only (the same rule as the
device checklist in [`supabase-go-live.md`](supabase-go-live.md)).
