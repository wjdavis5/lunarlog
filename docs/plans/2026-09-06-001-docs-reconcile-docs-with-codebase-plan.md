---
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan-bootstrap
execution: code
issue: 50
type: docs
created: 2026-09-06
branch: issue-50
---

# docs: reconcile documentation with codebase reality (issue #50)

## Summary

Issue #50 collects seven documentation claims (review findings #4, #8, #24, #26,
#27, #30, #31 from #37) that contradict the code. A verification pass on branch
`issue-50` at merge `997e9f3` found that **three have already been fixed by
later PRs**, **three are live and wrong**, and **one is not what the issue
describes** (the stale count lives in a *dated historical log entry*, which must
be appended to rather than rewritten).

This plan is a focused doc-accuracy pass. No production code behavior changes;
the only `lib/` edits are doc comments. Depth: **Lightweight** (3 units).

---

## Problem Frame

Docs drift silently. Each of these claims is load-bearing for an agent or a
human reading the repo cold: a wrong release-trigger claim invites a wrong
release action, a wrong layering comment invites a wrong refactor, and a
sign-out doc comment that overstates what the code does hides a real
security-relevant boundary (server sessions on other devices are **not**
revoked by `resetDevice`).

---

## Verification Findings (done at plan time — do not re-derive)

| # | Issue claim | Status at `997e9f3` | Evidence |
|---|---|---|---|
| 1 | `AGENTS.md` claims Play Store release triggers on push to main | **LIVE — wrong** | `AGENTS.md` "Release gate" bullet ends "Pushes to `main` still upload to TestFlight and the Play `internal` track". `.github/workflows/play-store-release.yml` has `workflow_dispatch` only, and AGENTS.md's *own* Android bullet says "Manual only via `workflow_dispatch` … there is no push trigger" — the file contradicts itself. TestFlight half of the sentence is correct (`ios-release.yml` does trigger on push to `main`). |
| 2 | `AGENTS.md` claimed the Google reversed client ID was committed before it was | **ALREADY FIXED** | `ios/Runner/Info.plist` line 44 carries the `com.googleusercontent.apps.…` entry under `CFBundleURLTypes` (line 27). The AGENTS.md sentence is now true. No edit needed; record as verified. |
| 3 | `.github/workflows/ci.yml` comment claims "no release pipeline yet" | **LIVE — wrong** | `ci.yml` lines 3-4: "There is no release pipeline yet, so this workflow is the only consumer of runner minutes." Four workflows exist: `ci.yml`, `ios-release.yml`, `play-store-release.yml`, `supabase-migrate.yml`. |
| 4 | `AGENTS.md` claims iOS signing blocked pending SIWA profile regeneration | **LIVE — stale** | The iOS bullet still ends "must be regenerated with that capability on the `com.wjdavis5.lunarlog` App ID before the workflow can sign — not yet done." Issue #50 reports TestFlight release signing works cleanly, i.e. the profile was regenerated. |
| 5 | `AGENTS.md:96` lists an outdated test count (377) | **NOT AS DESCRIBED** | `AGENTS.md`'s Tests bullet carries no count. The `377/377` figure is in `README.md:210`, inside the `## Verified` section — a **dated log** ("2026-09-03, Flutter 3.47.2 … on branch `feat/supabase-auth-cloud-sync`"). Historical entries are correct as history; the fix is to append a current entry, not to edit `377` in place. (`test/` now holds 61 `*_test.dart` files.) |
| 6 | `lib/app.dart:4` claims it is the only file touching `lib/data` | **PARTLY FIXED, STILL WRONG** | The comment was already amended to except `lib/app_lifecycle.dart`, but 8 `lib/ui/**` files import `lib/data` — `ui/account/account_section.dart`, `ui/feedback/feedback_controller.dart`, `ui/feedback/feedback_screen.dart`, `ui/logging/month_calendar.dart`, `ui/profiles/profile_detail_screen.dart`, `ui/profiles/profile_picker_screen.dart`, `ui/sharing/manage_guardians_screen.dart`, `ui/startup/fail_closed_screen.dart` — plus `lib/main.dart` and `lib/startup/*`. |
| 7 | `lib/app_lifecycle.dart` comments that `resetDevice` signs out on the server | **LIVE — wrong** | The `_signOutLocally` doc comment reads "Best-effort local **+ server** sign-out … A server-side failure never skips the local step"; the body calls `auth.signOut(scope: AuthSignOutScope.local)`. The `catch` also `debugPrint`s "server sign-out failed", reinforcing the wrong mental model. |

---

## Requirements

- **R1** — Every claim in the table above that is LIVE-and-wrong is corrected in place; the two already-correct items are left alone (no churn) and recorded as verified in the PR body.
- **R2** — Corrections state what the code *does*, without inventing new intent. Where the doc described an aspiration (SIWA profile regeneration), the replacement text says what is true now, not what someone hopes.
- **R3** — Historical/dated records (`README.md`'s `## Verified` section) are **appended to**, never retro-edited.
- **R4** — No behavior change. `lib/` edits are comments only; `flutter analyze`, `flutter test`, and both quality gates stay green.
- **R5** — The sign-out correction makes the *scope boundary* explicit: `resetDevice` ends the local session only; sessions on the user's other devices survive.

---

## Key Technical Decisions

**KTD1 — Fix the AGENTS.md Play-track sentence rather than the Android bullet.**
Two AGENTS.md passages disagree; the Android bullet matches `play-store-release.yml`, so the Release-gate sentence is the wrong one. Correct it to: pushes to `main` upload to TestFlight only; the Play `internal` track is reached only by a `workflow_dispatch` run.

**KTD2 — README `## Verified` gets a new entry, not an edit.**
The section is an append-only, dated verification log; rewriting `377/377` under a 2026-09-03 heading would fabricate history. The implementer runs the suite fresh on `issue-50` and appends a `2026-09-06` entry with the real numbers.

**KTD3 — Replace the `lib/app.dart` exception list with a statement of the actual rule.**
Enumerating every `lib/ui` importer would go stale within a PR. State the real invariant instead: `lib/app.dart` is the composition root that *wires* the drift-backed repositories; other files (UI screens, `lib/app_lifecycle.dart`, `lib/main.dart`, `lib/startup/*`) import `lib/data` types directly where they need them. If the stricter layering is still desired as a goal, that is a separate refactor — see Scope Boundaries.

**KTD4 — The sign-out fix touches the comment *and* the debugPrint string.**
Leaving `'lunarlog reset: server sign-out failed'` in place would keep the wrong claim alive in runtime output, which is where a future debugger meets it.

---

## Implementation Units

### U1. Correct the two AGENTS.md release claims and the ci.yml header comment

**Goal:** `AGENTS.md` and `.github/workflows/ci.yml` describe the release pipeline that actually exists.

**Requirements:** R1, R2 (findings 1, 3, 4).

**Dependencies:** none.

**Files:**
- `AGENTS.md` — the `**Release gate:**` bullet (its final sentence) and the `**iOS App Store / TestFlight Release Workflow (Primary):**` sub-bullet about `IOS_PROVISION_PROFILE_BASE64`.
- `.github/workflows/ci.yml` — the file-header comment, lines 3-4.

**Approach:**
1. Release-gate bullet: replace "Pushes to `main` still upload to TestFlight and the Play `internal` track" with a sentence that keeps the TestFlight half and states the Play track is `workflow_dispatch`-only (KTD1). Keep the "internal testing only" caveat.
2. iOS sub-bullet: drop the trailing "— not yet done" and restate the entitlement/profile relationship as satisfied: the App Store profile in `IOS_PROVISION_PROFILE_BASE64` carries the Sign in with Apple capability, and TestFlight signing runs clean. Keep the *requirement* sentence (a future profile regeneration must retain the capability) so the constraint is not lost with the stale status.
3. `ci.yml` header: replace the "no release pipeline yet" clause. State what is true — `ci.yml` validates pushes to `main` and PRs; `ios-release.yml`, `play-store-release.yml`, and `supabase-migrate.yml` handle delivery. Do not re-assert any runner-minutes claim that is no longer checkable.

**Patterns to follow:** the existing AGENTS.md bullet voice (dense, present-tense, links to the owning file); the `play-store-release.yml` header comment is the model for an accurate trigger description.

**Test scenarios:** `Test expectation: none — documentation and a YAML comment; no behavior.` Guard instead via verification below.

**Verification:**
- `grep -n "Play \`internal\` track" AGENTS.md` returns no sentence claiming a push trigger.
- `grep -rn "no release pipeline yet" .github/` returns nothing.
- `grep -n "not yet done" AGENTS.md` returns nothing in the iOS bullet.
- `actionlint` (already run by `ci.yml`'s `release-guards` job) still passes — the comment edit must not disturb YAML structure.

---

### U2. Correct the two inaccurate code comments (`lib/app.dart`, `lib/app_lifecycle.dart`)

**Goal:** the layering comment and the sign-out comment match the code.

**Requirements:** R1, R4, R5 (findings 6, 7).

**Dependencies:** none (independent of U1).

**Files:**
- `lib/app.dart` — library doc comment, the "only lib/ui-adjacent file that touches `lib/data`" sentence (~line 4).
- `lib/app_lifecycle.dart` — `_signOutLocally` doc comment (~line 933) and the `debugPrint` string in its `catch` (~line 944).
- `test/app_lifecycle_reset_test.dart` (or the existing test file that already covers `resetDevice`/sign-out — locate it before creating a new one; do not add a duplicate suite).

**Approach:**
1. `lib/app.dart`: replace the false exclusivity claim with the actual composition-root statement (KTD3). Keep the KTD4/KTD7/U8/KTD9 references already in that comment.
2. `lib/app_lifecycle.dart`: retitle `_signOutLocally`'s doc as a **local-only** sign-out. Say explicitly that `AuthSignOutScope.local` clears this device's session only and does **not** revoke sessions on the user's other devices (R5), and keep the existing and still-correct rationale about running before the reopen so the fresh database's first sync cycle cannot bind to the outgoing account. Rewrite the "server-side failure" sentence — the call can still throw (network/plugin), and the catch swallows it so the reset completes; that is the behavior to document.
3. Update the `debugPrint` text to name the local scope (KTD4). Check whether any test asserts on the current string before changing it.

**Execution note:** comment-only edits with one string literal change — verify by locating the existing `resetDevice` coverage first, then confirm the suite is still green rather than writing new tests for prose.

**Test scenarios:**
- If an existing test asserts the `debugPrint` output (search `test/` for `server sign-out failed`), update that expectation to the new string; otherwise no new test.
- Confirm the existing `resetDevice` coverage still asserts `signOut` is called with `AuthSignOutScope.local` — if it asserts only that `signOut` was called, tighten it to pin the scope, so the comment and the code can no longer drift apart silently.

**Verification:**
- `grep -rn "server sign-out" lib/ test/` returns nothing stale.
- `flutter analyze` clean (0 issues).
- `flutter test` green.
- `dart run tool/quality_gate.dart` passes (comment edits must not move coverage; a tightened scope assertion may only improve it).

---

### U3. Append a current dated verification entry to README's `## Verified` log

**Goal:** the repo's most recent verification record reflects the current tree, retiring the `377/377` figure by superseding it rather than editing history.

**Requirements:** R3, R1 (finding 5).

**Dependencies:** U1 and U2 — run the suite *after* their edits so the recorded numbers describe the shipped state.

**Files:**
- `README.md` — insert a new bullet at the **top** of the `## Verified` list (newest-first, matching the existing order).

**Approach:**
1. Run, from the worktree with `C:\src\flutter\bin` on PATH: `flutter analyze`, `flutter test`, `dart run tool/quality_gate.dart`. Record the real analyze issue count and the real `N/N` test total — **do not carry a number forward from this plan or from the old entry.**
2. Append an entry in the established shape: date, `Flutter 3.47.2 stable on Windows`, branch `issue-50`, then the command results. Mirror the existing entries' "Not run in this environment" convention for anything skipped (the pgTAP suite needs Docker; the iOS build needs `Williams-Mini`; the device checklist is manual).
3. Leave every existing entry byte-for-byte unchanged (KTD2).
4. While in `README.md`, scan its release/CI prose for the same push-trigger claim corrected in U1; if present, correct it consistently. (Not confirmed present at plan time — check, don't assume.)

**Test scenarios:** `Test expectation: none — README log entry.` The suite run *is* the evidence.

**Verification:**
- The new entry's numbers were produced by the commands run in this worktree in this session.
- `git diff README.md` shows additions only within `## Verified` (plus any U1-consistency fix), no deletions of prior entries.

---

## Scope Boundaries

**In scope:** the seven claims in issue #50, verified against `997e9f3`.

**Deferred to follow-up work:**
- **Enforcing the `lib/ui` → `lib/data` layering boundary.** KTD3 documents reality; if the strict boundary is the intended architecture, the 8 `lib/ui` importers need repository-facing abstractions moved behind `lib/domain`. That is a refactor with real test surface — file it as its own issue rather than smuggling it into a docs PR.
- **Revoking sessions on other devices during `resetDevice`.** U2 documents that this does not happen. Whether it *should* (`AuthSignOutScope.global`) is a product/security decision, not a docs fix — it changes behavior for multi-device households and interacts with the sync coordinator's teardown ordering.
- **Adding a `deno test` file for `delete-account`** (AGENTS.md Open Question Q2) — an unrelated documented gap noticed nearby.

**Out of scope:** any change to workflow triggers, release gating, or `AuthSignOutScope`. This issue reconciles docs *to* the code, never the reverse.

---

## Risks

- **Fixing the doc to match a bug.** Finding 7 is the one where "the docs were right and the code is wrong" is plausible. Handled by R5/KTD4 — the correction makes the narrower behavior *explicit and visible* rather than quietly matching prose to code, and the deferred item above keeps the behavior question open. If the implementer believes the local scope is a genuine defect, stop and file it; do not widen the scope in this PR.
- **A stale number replaced by another stale number.** Mitigated by U3 step 1: the count must come from a run in this worktree, after U1/U2.
- **Finding 4 rests on the issue reporter's claim** that TestFlight signing works, not on a CI run observed at plan time. Before landing U1 step 2, check the most recent `ios-release.yml` run (`gh run list --workflow=ios-release.yml`); if it never signed successfully, keep the caveat and note the check in the PR instead of asserting success.

---

## Definition of Done

1. U1, U2, U3 landed on `issue-50`.
2. `flutter analyze` clean, `flutter test` green, `dart run tool/quality_gate.dart` passes.
3. `grep -rn "no release pipeline yet" .github/` and `grep -rn "server sign-out" lib/` both return nothing.
4. `README.md`'s `## Verified` carries a new top entry dated the day of the run, with numbers from that run; no prior entry modified.
5. PR body lists all seven findings with their dispositions — corrected, or verified-already-fixed (findings 2 and, partially, 6) — so #37's reviewer can close each one.

---

## Sources

- GitHub issue #50 (`gh issue view 50`); review findings #4, #8, #24, #26, #27, #30, #31 in #37.
- Verified at merge `997e9f3` in worktree `.worktrees/issue-50`: `AGENTS.md`, `README.md`, `.github/workflows/*.yml`, `ios/Runner/Info.plist`, `lib/app.dart`, `lib/app_lifecycle.dart`, `lib/ui/**`.
