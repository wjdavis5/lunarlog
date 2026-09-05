---
title: Attribution Wiring for DaySheet in MonthCalendar - Plan
type: test
date: 2026-09-05
issue: wjdavis5/lunarlog#79
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan-bootstrap
execution: code
---

# Attribution Wiring for DaySheet in MonthCalendar - Plan

**Target repo:** `lunarlog` (`repos/lunarlog` / `wjdavis5/lunarlog`), branch `issue-79`. All file paths are repo-relative.

---

## Goal Capsule

- **Objective:** Close issue #79 — the day sheet opened from the month calendar must render real caregiver attribution ("Logged by you", "Logged by Dad") instead of the generic "Caregiver" fallback.
- **Means:** The production wiring already landed (commit `7a4c7a6`, "fix(review): harden multi-guardian sharing after PR #73 review"). What is missing is the regression coverage that keeps it wired: no test in the repo pumps `MonthCalendar` with an `AuthController` or a `ProfileGuardiansRepository`, so deleting either argument from `_openDay` would pass every gate. This plan verifies the live path end-to-end and pins it with widget tests.
- **Authority hierarchy:** GitHub issue #79 owns the product requirement; this plan owns technical scope; `docs/plans/2026-09-04-0710-feat-multi-guardian-support-plan.md` (R10/R12) is the upstream attribution contract.
- **Stop conditions:** Stop and surface if the pre-work verification (U1) shows the production path is in fact broken in a way not described here — the plan then needs a fix unit, not only coverage. Also stop if closing a coverage hole would require loosening `tool/quality/exclusions.dart`.
- **Execution profile:** `code`; standard depth, test-first, three units.

---

## Problem Frame

Issue #79 reports that `MonthCalendar._openDay` constructs `DaySheet` without `currentUserId` or `guardians`, so `CaregiverAttributionBadge` degrades to the literal string "Caregiver" for every entry.

**As of `main` at `4c35cab`, the reported code defect is already fixed.** Verified by reading the tree:

- `lib/ui/logging/month_calendar.dart` holds `_currentUserId` (read from `context.read<AuthController?>()` in `initState`, refreshed via an `AuthController` listener) and `_guardians` (a subscription to `ProfileGuardiansRepository.watchForProfile`, reset on profile switch), and `_openDay` passes both into `DaySheet`.
- `lib/ui/profiles/profile_detail_screen.dart` builds a `ProfileGuardiansRepository` from the ambient `LunarLogStorage` and passes it as `guardiansRepository`.
- `lib/app.dart` provides both `AuthController` (line ~287, present whenever an `authService` was supplied) and `LunarLogStorage` (line ~303) above that subtree.
- `lib/ui/logging/day_sheet.dart` forwards both fields into `CaregiverAttributionBadge` at each of its two render sites (editable body and read-only body).
- Guardian `display_name` reaches local storage through the sync path (`lib/data/sync/row_codec.dart`, `profile_guardians`), so the badge's display-name branch is reachable in production, not dead code.

The live risk is therefore **regression, not absence**. `test/ui/logging_test.dart`'s `pumpLogging` harness registers no `LunarLogStorage` and no `AuthController`, so every existing calendar/day-sheet test exercises the null-user / empty-guardians fallback. `test/ui/caregiver_attribution_badge_test.dart` covers the badge in isolation; `test/ui/sharing_flow_test.dart` covers `ManageGuardiansScreen`, not the calendar. Nothing asserts the seam between them. This is the same class of gap as issues #76 and #82 — correct code with an untested wiring path.

---

## Requirements

- **R1.** A day entry logged by the signed-in user, opened from the month calendar, renders "Logged by you".
- **R2.** A day entry logged by another accepted guardian renders that guardian's `displayName` ("Logged by Dad"); when the guardian row carries no display name, it renders the role label.
- **R3.** A day entry logged by a user id absent from the profile's guardian list renders the generic "Caregiver" fallback.
- **R4.** Local-only operation (no `AuthController`, no `LunarLogStorage` in the tree) keeps working with no crash and no attribution — the existing offline-first posture is preserved.
- **R5.** `ProfileDetailScreen` supplies the guardians repository to `MonthCalendar` whenever storage is ambient, and supplies `null` when it is not.
- **R6.** Switching the active profile does not leak the previous profile's guardians into the new profile's attribution.
- **R7.** A sign-in or sign-out while the calendar is mounted updates the attribution the *next* day sheet renders.

---

## Key Technical Decisions

- **KTD1. Cover the seam with widget tests at the `ProfileDetailScreen` level, not by refactoring `MonthCalendar`.** The wiring is correct; a test that pumps the real screen with real providers is what proves it stays correct. No production restructuring is in scope.
- **KTD2. Extend the existing `pumpLogging` harness with optional providers rather than adding a parallel harness.** `test/ui/logging_test.dart` already owns the drift-in-memory setup and the `disposeLogging` teardown discipline; adding optional `authService`/storage-provider parameters keeps one harness and avoids a second teardown convention to get wrong.
- **KTD3. Seed guardian rows through `storage.applyRemoteRows` with a `guardianRow(...)`-style helper, mirroring `test/ui/sharing_flow_test.dart`.** That is the established way this repo materializes server-authored guardian rows locally; reusing it keeps the fixtures honest about where `display_name` comes from.
- **KTD4. Attribution resolves against *all* guardian rows, not only `accepted` ones.** `MonthCalendar` passes the unfiltered list, and that is correct: a revoked guardian's past entries should still read "Logged by Dad" rather than losing their name. Recorded here so a future reviewer does not "fix" it into a status filter.
- **KTD5. Fake the auth seam, do not reach Supabase.** Attribution needs only `AuthController.currentUserId`; the tests supply a minimal fake auth service (or the existing test double used by `test/ui/auth_controller_test.dart`) so the suite stays hermetic.

---

## Implementation Units

### U1. Verify the live path before writing coverage

**Goal:** Confirm on `issue-79` that the production wiring behaves as read, so the rest of the plan is coverage rather than a fix.

**Requirements:** R1, R5.

**Dependencies:** none.

**Files:**
- `lib/ui/logging/month_calendar.dart` (read)
- `lib/ui/profiles/profile_detail_screen.dart` (read)
- `lib/ui/logging/day_sheet.dart` (read)
- `lib/app.dart` (read)

**Approach:**
1. Re-read the four files above and confirm `currentUserId` + `guardians` flow `app.dart` -> `ProfileDetailScreen` -> `MonthCalendar._openDay` -> `DaySheet` -> `CaregiverAttributionBadge`.
2. Run `flutter analyze` and `flutter test` on a clean branch to establish the baseline.
3. If any link is actually broken, stop and add a fix unit before U2 — do not paper over it with a test that asserts the broken behavior.

**Execution note:** This is a read-and-baseline unit; it produces no diff.

**Test expectation:** none — verification only; its output is the go/no-go for U2.

**Verification:** Baseline `flutter analyze` clean and `flutter test` green; a written statement in the PR body of which links were confirmed.

---

### U2. Extend the logging test harness with auth and storage providers

**Goal:** Give `test/ui/logging_test.dart` the ability to pump the real attribution path.

**Requirements:** R4, R5.

**Dependencies:** U1.

**Files:**
- `test/ui/logging_test.dart` (modify — `pumpLogging`, `Harness`)

**Approach:**
1. Add optional parameters to `pumpLogging`: a fake auth service (or pre-built `AuthController`) and a flag/seed hook for guardian rows. Default them off so all existing tests keep exercising the local-only fallback unchanged.
2. When the auth parameter is supplied, register `ChangeNotifierProvider<AuthController>` above `ProfileDetailScreen`; always register `Provider<LunarLogStorage>.value(value: db.storage)` when guardian seeding is requested, matching `lib/app.dart`'s provider set.
3. Add a `guardianRow(...)` fixture helper (id, userId, role, displayName, status) and seed via `db.storage.applyRemoteRows`, mirroring `test/ui/sharing_flow_test.dart`.
4. Expose the `AuthController` (or its fake service) on `Harness` so U3 can flip the signed-in user mid-test, and dispose it in `disposeLogging`.

**Patterns to follow:** `test/ui/sharing_flow_test.dart` (guardian row seeding via `applyRemoteRows`), `test/ui/logging_test.dart`'s existing `disposeLogging` drift-stream teardown, `lib/app.dart`'s provider ordering.

**Test scenarios:**
- Existing `logging_test.dart` tests still pass unmodified with the new parameters defaulted off (no auth provider, no storage provider) — proves R4's local-only posture is untouched.
- `pumpLogging` with the auth parameter supplied builds without throwing and the calendar renders.
- `disposeLogging` tears down the added auth listener and guardian stream without leaving a pending drift stream (the suite's existing teardown assertion stays green).

**Verification:** `flutter test test/ui/logging_test.dart` green with no behavior change to existing cases.

---

### U3. Pin the MonthCalendar -> DaySheet attribution seam

**Goal:** Assert that opening a day from the calendar renders real attribution, so removing either argument from `_openDay` fails the suite.

**Requirements:** R1, R2, R3, R4, R6, R7.

**Dependencies:** U2.

**Files:**
- `test/ui/logging_test.dart` (modify — new `group('caregiver attribution', ...)`)

**Approach:**
1. Seed a profile with day entries carrying distinct `loggedByUserId` / `lastModifiedByUserId` values, plus guardian rows for a subset of those users.
2. Pump with a signed-in user, tap the day cell to open the sheet, and assert the badge text.
3. Cover both `DaySheet` bodies — the editable one (`readOnly: false`) and the read-only archived one (`readOnly: true`) — since `day_sheet.dart` renders `CaregiverAttributionBadge` at two independent call sites and a regression could hit only one.
4. Cover the profile-switch reset by rebuilding `ProfileDetailScreen` at the same tree position with a second profile whose guardian set differs.

**Test scenarios:**
- Entry logged by the signed-in user -> the opened sheet shows "Logged by you". (Fails today if `currentUserId` is dropped from `_openDay`.)
- Entry logged by another guardian with `displayName: 'Dad'` -> shows "Logged by Dad". (Fails today if `guardians` is dropped.)
- Entry logged by a guardian row with a null/empty `displayName` -> shows the role label (e.g. "Co-Parent").
- Entry logged by a user id with no guardian row -> shows "Logged by Caregiver".
- Entry logged by one guardian and last-modified by another -> shows both segments, "Logged by Mom • Modified by Dad".
- Same tree pumped with no `AuthController` and no `LunarLogStorage` -> the sheet opens, no exception, and no "you"/display-name text appears (R4).
- Archived (`readOnly: true`) profile -> the read-only body's badge renders the same attribution as the editable body (R1/R2 on the second call site).
- Guardian rows for profile A, then the screen is rebuilt for profile B whose guardians differ -> profile B's sheet never renders profile A's guardian names (R6).
- `AuthController` transitions signed-out -> signed-in while the calendar is mounted; a day sheet opened afterwards renders "Logged by you" for that user's entry (R7).
- A revoked guardian's past entry still resolves to that guardian's display name (KTD4).

**Verification:** `flutter test test/ui/logging_test.dart` green; each new test demonstrably fails when the corresponding argument is temporarily removed from `MonthCalendar._openDay` (spot-check at least the R1 and R2 cases before finalizing). Full suite and gates green per the Verification Contract.

---

## Verification Contract

Run from the repo root in the `issue-79` worktree:

1. `flutter pub get`
2. `flutter analyze` — zero issues.
3. `flutter test` — full suite green.
4. `dart run tool/quality_gate.dart` — 90% line-coverage floor and the per-method CRAP gate (gate at 10) both pass. This is the CI `check` job's gate; new test-only code must not drag either metric.
5. `dart run tool/mutation_gate.dart` — local-only; run it scoped to the changed files. Because U3's whole point is mutation resistance, the two attribution arguments in `_openDay` should now be killed mutants rather than survivors.

Manual/device verification is not required: the change is test-only and touches no platform channel, no migration, and no Supabase surface. The pgTAP suite is unaffected.

---

## Scope Boundaries

**In scope:** widget-test coverage for the `MonthCalendar` -> `DaySheet` -> `CaregiverAttributionBadge` seam, the harness changes needed to write it, and a verification pass over the existing production wiring.

**Non-goals:**
- Changing `CaregiverAttributionBadge`'s copy, layout, or fallback strings.
- Filtering guardians by status for attribution (see KTD4).
- Any change to the sync engine, `profile_guardians` schema, RLS, or the sharing service.

### Deferred to Follow-Up Work

- **Live refresh of an already-open day sheet.** `_openDay` snapshots `_currentUserId` and `_guardians` when the modal is built, so a guardian-stream tick or a sign-in while the sheet is open does not restyle the badge until it is reopened. Closing this means passing streams (or a listenable) into `DaySheet` rather than values — a real refactor with its own review surface. R7 above is deliberately scoped to "the next sheet opened". File as a separate issue if the behavior is ever user-visible.
- **`ProfileDetailScreen` allocating a new `ProfileGuardiansRepository` on every build.** Harmless today (`MonthCalendar` only re-subscribes on `profileId` change), but it is an allocation per frame; a tidy-up belongs with a broader `ProfileDetailScreen` pass, not here.

---

## Risks

- **The plan is coverage for code that already works, so it can look like a no-op PR.** Mitigation: U3's verification step requires demonstrating that each new test fails when the wiring is removed — that is the evidence the coverage is load-bearing.
- **Harness churn breaking unrelated logging tests.** Mitigation: every new `pumpLogging` parameter defaults to the current behavior (U2 scenario 1 asserts exactly this).
- **Coverage-gate interaction.** Test-only additions raise covered lines in `lib/ui/logging/`, so the 90% floor should improve rather than regress; if the CRAP gate flags a method newly touched by these tests, treat it as a signal about that method, not a reason to weaken `tool/quality/exclusions.dart` (a stop condition).

---

## Definition of Done

- `flutter analyze`, `flutter test`, and `dart run tool/quality_gate.dart` are green on `issue-79`.
- `test/ui/logging_test.dart` contains a caregiver-attribution group covering R1-R7, including both `DaySheet` render bodies.
- Removing `currentUserId` or `guardians` from `MonthCalendar._openDay` fails the suite (verified by spot-check, then reverted).
- The PR body states that the reported defect was already fixed in `7a4c7a6` and that this change pins the wiring, so issue #79 closes with an accurate record.

---

## Sources

- GitHub issue `wjdavis5/lunarlog#79`.
- `docs/plans/2026-09-04-0710-feat-multi-guardian-support-plan.md` — R10/R12 attribution contract.
- Commit `7a4c7a6` "fix(review): harden multi-guardian sharing after PR #73 review" — where the wiring landed.
- `AGENTS.md` "Quality gates" — the verification commands above.
