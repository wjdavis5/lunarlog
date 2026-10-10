# lunarlog product review, October 2026

This review grounds every claim in the repository. It cites files, issues, and command output. Claims about people's behavior are labeled inferred or guess. The evidence base is `origin/main` at `070e1c35`, the open issue and pull request lists read on 2026-10-10, and four read-only reconnaissance passes recorded in the run trail.

## The verdict

lunarlog is a mature, well-tested, privacy-first family cycle tracker with a real differentiator, and its gap is launch proof rather than product surface. The phone app covers logging, prediction, life-stage modes, sharing, health sync, export, notifications, and a home-screen widget, backed by about 8,550 Flutter tests and strict CI gates. The web client and the marketing site shipped and deploy green. What stands between this product and a successful public launch is proof and operations. The Android release path has never completed a run, two privacy bugs sit open at P1 and P2, the device checklists have never run, and a wide set of owner-gated operational steps remains. The written record has also drifted from shipped reality in several places, which costs trust in every other document. None of this is a feature shortage. It is a finishing problem, and finishing is cheaper than another feature.

## What the product promises, and to whom

lunarlog is for households where more than one person touches one person's cycle data (README.md:3-10, docs/product/positioning.md:9-37). The promise set is specific and testable.

- A Supabase account syncs profiles across the household's devices, and guardians share a profile with four roles, invitations, attribution, and a tag-union merge (README.md:212-232).
- Offline use is reliability, not identity (README.md:14-15).
- At-rest protection is the operating system's, behind the app's biometric gate, and explicitly not app-managed encryption (PRIVACY.md:15, 132, 141).
- No ads and no data brokers (PRIVACY.md:16).
- Estimates run on-device and carry a not-contraception disclaimer (PRIVACY.md:18).
- Telemetry is scrubbed, and six external services appear, each for app function (PRIVACY.md:59-62, 86-95).
- Export and deletion work without an account (PRIVACY.md:146-158).
- Minors are 13 and older, enter through a parent invitation, and carry read rules and private notes (PRIVACY.md:116-125).

The positioning doc names the family collaboration as the product's priority and its differentiator, not an add-on. Nothing in this review weakens that read.

## What is built

- Day logging and calendar. Day sheet, month calendar, quick log, custom tags, merge notices (`lib/ui/logging`, `lib/domain/logging`).
- Prediction and insights. Cycle estimates, fertile window, PMS, cycle history, comparison, basal body temperature chart (`lib/domain/prediction`, `lib/ui/insights`).
- Profiles and life-stage modes. Multi-profile, pregnancy, postpartum, perimenopause, conceive, birth control, cycle overrides, ownership transfer (`lib/ui/profiles`, `lib/domain/` mode files).
- Sharing and care. Invitations, manage guardians, roles, activity feed, care notes, prediction connections (`lib/ui/sharing`, `lib/ui/care`).
- Health sync. HealthKit and Health Connect write and import, background import, deleted-record reconciliation (`lib/domain/health`, `lib/data/health`).
- Export and import. JSON, CSV, FHIR bundle, clinical PDF, account restore, Clue import (`lib/domain/export`, `lib/domain/import`).
- Notifications. Reminders, caregiver alerts, preferences (`lib/domain/notifications`).
- Home-screen widget with quick log (`lib/domain/widget`).
- Account and auth. Email and password, Google, Apple, passwordless, deletion, sync status (`lib/ui/account`).

Platform gates in `lib/config.dart` shape what ships. Health sync is on for both platforms. Passkeys, universal links, and MFA are off in every build. Crash reporting is inert until issue #19 provides a Sentry project. An unconfigured build drops accounts, sync, and crash reporting, which is a development mode and not a product mode.

## The other two surfaces

The web client at `app.lunarlog.app` is a signed-in thin client that keeps nothing at rest in the browser. The rule is enforced three ways: lint bans on browser storage APIs, an in-memory access token, and a Playwright spec that asserts every storage surface stays empty. Cycle math comes from the same Dart domain compiled to JavaScript, so parity with the phone is structural. First-run onboarding shipped the same day (PR #1803), followed by the insights section, the BBT chart, the recap card, and the phase card (PRs #1805 through #1814). Its staging alias shares the production Supabase project, which the deploy docs note.

The marketing site is an Astro build with zero client JavaScript and strict response headers, deployed by its own workflow. Its checks (html validation, links, axe, Lighthouse budgets) are deliberately not release-gating. One documented drift: `docs/links/README.md:52` withholds the web-app button until #1258, which shipped on 2026-10-04 (the cutover was executed the same day this review landed, PR #1800).

## Quality and maturity

Measured on 2026-10-10. The Flutter suite runs about 8,550 tests. CI enforces a 90 percent coverage floor and a CRAP gate at 10, and the latest merged run passed at 95.68 percent. The pgTAP suite covers 83 files and 2,819 assertions. The web client carries 52 unit test files, six end-to-end specs including the storage-empty spec, and a Deno-tested auth worker.

An earlier draft of this review called the account, insights, and prediction areas thin. It counted files in the narrow directories `test/ui/account`, `test/ui/insights`, and `test/domain/prediction`. That count was wrong about the repo's layout. The UI and domain tests live flat in `test/ui/` and `test/domain/`, and spot-checking every screen and boundary case the resulting issues named found existing behavior tests in `test/ui/account_test.dart`, `test/ui/account_deletion_test.dart`, `test/ui/analysis_tab_test.dart`, `test/ui/cycle_comparison_test.dart`, `test/domain/prediction_test.dart`, and elsewhere. Issues #1792 through #1794 were closed on 2026-10-10 with that evidence, and no replacement thin-spot claim is made here.

## Release and operations state

Measured 2026-10-10 from `gh run list`, `gh variable list`, and the workflow files.

- iOS. The release workflow's last run, on 2026-09-30, succeeded end to end, including the TestFlight upload and the migrations-applied gate.
- Android. `play-store-release.yml` has never completed a run. Its only two runs, both from early September, failed.
- Migrations. The latest `supabase-migrate` run waits at the production environment's approval gate. Four runs on 2026-10-09 were cancelled or superseded. Issue #1505 describes the hole underneath: migrations can reach production on merge, before the run is approved.
- Gate. `RELEASE_GATE_ACCOUNT_DELETION` reads `shipped`, so the mechanical submission gate is open.
- Credentials. Issue #1261 records an App Store Connect key ambiguity between `.env` and the docs.
- Manual verification. The device checklists (#22, #29, #725) have never run.

## The backlog in one view

Thirty-nine issues are open. Thirty-three carry `needs-human-review`, two are in progress by other owners (#551, #1564), three are epics (#831, #830, #116), and one is a documented deferral (#161). By theme: health sync 6, privacy and sharing bugs 4, owner decisions 7, operations 8, features and epics 12, QA checklists 2. The backlog is almost entirely owner-gated, and that is the strongest signal in this review. The product is not waiting on engineering throughput. It is waiting on decisions, credentials, and a device.

## The written record has drifted

Verified drifts, each small and fixable.

- `docs/product/positioning.md:78-85` calls the fertile window and ovulation unshipped. They shipped as #143.
- `docs/product/positioning.md:71-72` says import from a file is unshipped. It shipped as #140.
- `docs/product/positioning.md:103-106` hedges health-platform sync. Both directions shipped (#217, #458, #1478).
- `README.md:179-181` says dashboard sign-ups are closed. AGENTS.md documents them open (#800, #821, #971).
- `README.md:38` says the app is not deployed. TestFlight has carried builds since 2026-09-30.
- `PRIVACY.md:18, 125` keeps conception outside scope. The Conceive and Perimenopause modes shipped (`docs/clinical/`).
- `docs/links/README.md:52` withholds the web-app button until #1258, which shipped.
- AGENTS.md flags the health-consent column promised by #188 as never shipped. No such column exists (#782).

## Risks, ranked

1. The Android release path is unproven. Zero green runs, and the submission gate is already open.
2. Two privacy bugs sit open while the gate is open. #1501 lets a guardian read a private note by removing its author. #1705 lets a same-date row destroy the subject's note.
3. Migrations can reach production before approval (#1505), and the latest run is pending.
4. Credential ambiguity (#1261) plus unrun device checklists (#22, #29, #725) put the first submission on manual verification that has not happened.
5. Launch operations are incomplete. Custom SMTP (#970), console steps (#1093, #1100), and crash reporting (#19).
6. Documentation drift erodes the record the next person trusts.

## What success looks like

A public launch that works on both stores, with the privacy promise intact and provable, and the family-sharing differentiator deepened rather than the surface widened. Concretely: both store paths green, the privacy bugs closed, the checklists run, the launch operations done, the docs true, and the family features (#850, #1048) advanced. `2026-10-10-future-plan.md` turns this into a priority order and a set of issues.
