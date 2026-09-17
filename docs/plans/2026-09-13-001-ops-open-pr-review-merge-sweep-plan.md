---
title: "Open-PR review-and-merge sweep"
date: 2026-09-13
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
execution: code
product_contract_source: ce-plan-bootstrap
---

# Open-PR review-and-merge sweep

## Goal Capsule

Drive every open PR in `wjdavis5/lunarlog` to a correct terminal state —
merged, closed-as-superseded, or (only where the owner already decided)
deliberately left draft — with each merge landing only after conflicts with
`origin/main` are resolved, the ruleset "Main" required checks pass on the
rebased head, and the repo's migration-ordering discipline (AGENTS.md,
Migration Flow item 7) is honored.

Authority hierarchy: the owner's directive for this session ("review them all
and ensure they get merged") > AGENTS.md standing rules > each PR's own stated
scope. Stop conditions: a PR whose correct terminal state requires a product
decision the owner has already made against merging (U7 / A1), a coordinator
that wakes and resumes a PR mid-lane (KTD7), or a lane that fails two
rebase-verify cycles (bounded-attempt rule, DoD).

## Product Contract

### Context

Seven PRs are open. Recon on 2026-09-13/14 (UTC) established:

| PR | Branch | State vs main (`8465d38`) | Carries | Owner markers |
|---|---|---|---|---|
| #503 | `fix/499-delete-account-cleanup-transfers-connections` | CONFLICTING; content already on main via merged #603 (`b91b478`) | dup migration `20260913031000` | none |
| #502 | `fix/496-ownership-transfer-revoke-prediction-connections` | CONFLICTING; fix verified still absent on main | migration `20260913030000` + pgTAP | none |
| #504 | `fix/498-gate-releases-on-ci-checks` | MERGEABLE but BLOCKED (required-check names changed under it; green on old job names) | ci.yml, release workflows, `check-ci-gate.sh` | none |
| #643 | `opencode-deepseek/bundle-a-sync` | CONFLICTING; migration `20260913022000` collides with main's identical prefix; full CI never ran | 2 migrations + pgTAP + lib/data/sync + lib/data/db | `in-progress`, `owner:opencode-deepseek` (dormant 36h+) |
| #377 | `feat/255-numeric-measurements` | CONFLICTING; full CI green on old base | migration `20260911090000` + pgTAP + **Drift schema v13 bump** (main is already at v15 — slot taken) | `owner:claude-orch` (no `in-progress`) |
| #378 | `feat/259-tracking-prefs` | CONFLICTING; full CI never ran; touches `ci.yml`; **stacked on #377** (carries a renamed duplicate of #377's units migration, same 96,288-byte body) | migrations `20260910110000` (dup of #377) + `20260910120000` + pgTAP + **Drift schema v13+v14 bumps** | `owner:claude-orch` (no `in-progress`) |
| #489 | `opencode-muse/199-unmapped-data-escape-hatch` | CONFLICTING; DRAFT; CI green on old base | no migration, no Drift bump | `in-progress`, `owner:opencode-muse`; **owner deferred Clue import post-launch on 2026-09-12** |

Platform facts that shape the work:

- Ruleset "Main" (no classic branch protection) requires: PRs, no force-push
  to main, and 11 required checks — `Release guard scripts (unit tests +
  actionlint)`, `Release guard scripts on macOS (bash 3.2 compatibility)`,
  `Verify (codegen, analyze, web build)`, `Test (shard 0|1|2)`,
  `Quality gate (coverage floor + CRAP)`, `Edge Functions (deno test)`,
  `Database tests (pgTAP)`, `Build Android (debug APK)`, `Build iOS (unsigned)`.
  **Zero required approvals**; Copilot review is auto-requested on push
  (assumed advisory — A4).
- The required check names come from merged #644's ci.yml restructure
  (sharded tests); PRs based on older main produced old-named checks and can
  never satisfy the ruleset until rebased. Merge conflicts also suppress the
  `refs/pull/N/merge` ref, so conflicted PRs get no full CI at all.
- Main CI at `8465d38` is green (run 34777403179); the `3adcbab` shard-1
  failure (issue #646) did not reproduce at the current head.
- main's latest migration is `20260913022000_account_deletion_transfers_and_connections.sql`;
  main's Drift schemaVersion is 15 with `drift_schemas/` v1–v15 taken.
- Every migration PR also edits the same AGENTS.md schema-history paragraph —
  a guaranteed textual conflict on every pair.

### Requirements

- R1 — Every open PR receives a real review: diff read, CI state established,
  correctness judgment made (not just a green-check merge). For feature/fix
  PRs this includes verifying the rebased diff against the source issue's
  acceptance criteria.
- R2 — Each PR reaches its correct terminal state: merged, closed
  superseded, or (only where the owner already decided) left draft with the
  readiness verdict reported.
- R3 — No merge introduces a migration whose filename does not sort strictly
  after every migration already on `origin/main` at merge time.
- R4 — A PR merges only when the ruleset-required checks pass on its rebased
  head, or when a required-check gap is affirmatively diagnosed as a ruleset
  artifact and reported (never silently bypassed).
- R5 — All local work happens in isolated worktrees under `.worktrees/`,
  never the primary checkout (AGENTS.md strict requirement).
- R6 — Review findings about a PR that are real but out of that PR's scope are
  filed as issues, not silently dropped and not scope-creeped into the PR.

### Scope boundaries

- No new feature work beyond what each PR already contains; fixes are limited
  to rebase fallout, CI-rename fallout, schema/migration renumbering, and
  review-blocking defects (a lane that needs more than that stops and reports
  per the bounded-attempt rule instead of growing scope).
- Issue #646 is report-only for this sweep: do not close it as part of the
  merges; include its current-green evidence in the final summary.
- Do not undraft or merge #489 (A1).

## Planning Contract

### Key Technical Decisions

- KTD1 — Handle all seven PRs, including ones carrying other coordinators'
  `owner:` labels, and coordinate around dormant coordinators rather than
  waiting on them. (session-settled: user-directed — chosen over handling only
  the three unlabeled PRs: the owner said "review them all and ensure they get
  merged"; both `opencode-*` coordinators have been dormant 36h+/41h+.)
- KTD2 — All work in isolated worktrees under `.worktrees/pr-sweep-<n>`,
  branches pushed back to each PR's existing head branch. (session-settled:
  user-approved — chosen over checking branches out in the primary checkout:
  AGENTS.md marks worktree isolation a strict requirement.)
- KTD3 — Landing order: U1 close #503 → U2 #502 → U3 #504 → U4 #643 →
  U5 #377 → U6 #378 → U7 #489 review/report. Rationale: superseded PR first
  (verification-only, no code lands, clears the duplicate before any renames);
  the live privacy fix #502 before process infra #504 (if the sweep is
  interrupted, the privacy fix has landed); #643 after both (largest migration
  rebase, semantic conflicts against main's landed sync fixes); #377 strictly
  before #378 because #378 is stacked on #377's content (its diff contains a
  renamed duplicate of #377's units migration plus the second Drift schema
  version — landing #378 first would strand that dependency). After each
  migration-PR merge, re-verify the next PR's planned migration filenames and
  Drift schema versions against the new main head (KTD4 re-check).
- KTD4 — Migration/Drift filename discipline: any landing migration must sort
  strictly after the latest on `origin/main` at merge time (currently
  `20260913022000_*`; rename target `20260914xxxxx`), and any landing Drift
  schema bump must use the next free schemaVersion (currently 15 taken →
  #377's becomes 16; #378's prefs-only schema becomes 17 after U5 lands).
  Renames keep each file's own header note pattern ("renamed from an original
  … prefix") per repo convention. **Before any rename**, check the linked
  project has not already applied the branch's original version
  (`npx supabase@2.116.0 migration list --linked` — issue #163 documents
  out-of-band production application as a real failure class here); if the
  original version is recorded on the linked project, stop that lane and
  report instead of renaming.
- KTD5 — #489 remains draft and unmerged: the owner's 2026-09-12 comment
  ("Clue import issues are deferred to a post-launch milestone") is a
  specific product decision that outranks the generic sweep directive. The
  lane delivers a readiness review (does the diff meet its own ACs? what
  would merging take?) as a PR comment, not a merge. The PR stays draft
  regardless of what the review finds; if the review finds evidence the
  deferral may be moot (including the A1 tripwire), that evidence goes into
  the readiness comment and the final report for the owner to act on.
- KTD6 — #503 closes as superseded by merged #603 (`b91b478`), after
  diff-equivalence verification (its migration vs main's
  `20260913022000_account_deletion_transfers_and_connections.sql`, its test
  changes vs main's `account_deletion_test.sql`); anything on #503 that main
  lacks is carved into a fresh issue rather than merged from a stale duplicate
  branch.
- KTD7 — Coordinator-collision guard: immediately before pushing to any
  coordinator-labeled branch (#643, #377, #378, #489), re-check the PR
  timeline for events in the last hour; if the owning coordinator resumed,
  stop that lane, leave findings as a PR comment, and move on to the next
  lane. `--force-with-lease` on every rebase push fails safely if a head
  moves between check and push.
- KTD8 — Merge method: squash-merge via `gh pr merge --squash` (the repo's
  merged history is squash-shaped: `(#NNN)`-suffixed single commits), with the
  PR head branch deleted after merge (no open PR is stacked on another's
  branch — #378's overlap is content duplication, not a git stack).

### Technical design notes

- Rebase strategy per PR: fetch, create `.worktrees/pr-sweep-<n>` on the PR
  head, `git rebase origin/main`, resolve conflicts (AGENTS.md: take main's
  structure and append the PR's migration/test entries with corrected
  filenames/counts; migration collisions: rename per KTD4; Drift versions:
  renumber per KTD4 and run the AGENTS.md codegen steps 1–6; `ci.yml`: re-map
  the PR's edit onto the sharded job layout), run the verification gates,
  push with `--force-with-lease`.
- U2 (#502) specificity: confirm issue #496 still reproduces on main (no
  accept_ownership_transfer → prediction-connection revocation exists —
  verified in recon); rebase; rename `20260913030000_…` per KTD4; its
  `supabase/tests/prediction_connection_test.sql` conflict resolves by
  unioning test sections and fixing the plan count line.
- U3 (#504) specificity: its new `.github/scripts/check-ci-gate.sh` enumerates
  ci.yml check runs by name; it must gate on the post-#644 job names
  (`Verify …`, `Test (shard N)`, `Quality gate …`), and its
  `.github/scripts/tests/check-ci-gate.test.sh` expectations must be updated
  to match — otherwise the release gate passes/fails on checks that no longer
  exist. A name-agnostic rollup is NOT acceptable: the ruleset pins names, and
  the gate script should verify the same names the ruleset requires.
- U4 (#643) specificity: two migration renames (KTD4); lib/data/sync conflicts
  against main's #588 client-side sync fixes are semantic, not just textual —
  the rebase must re-verify the bundle's three fixes (finite timestamps,
  observation reparenting, future-stamp rebase) still hold via its pgTAP +
  unit suites, and the rebased diff must be checked against the acceptance
  evidence on issues #641/#639.
- U5 (#377) specificity: rename `20260911090000_numeric_measurement_units.sql`
  per KTD4; the Drift bump re-expresses as schemaVersion 16 on post-rebase
  main (dump `drift_schema_v16.json`, regenerate every
  `test/data/db/generated_migrations/schema_v*.dart` + `schema.dart`, update
  `schema_migration_test.dart`'s version lists, bump the CI codegen-freshness
  dump filename) per AGENTS.md's six-step codegen procedure; verify the
  rebased diff against issue #255's acceptance criteria before merging.
- U6 (#378) specificity: during the rebase onto post-U5 main, **drop the
  duplicated units migration** (`20260910110000_numeric_measurement_units.sql`
  and its test/helper files that #377 already landed) rather than
  conflict-resolving them — the branch keeps only its tracking-prefs delta;
  rename only `20260910120000_profile_tracking_preferences.sql` per KTD4;
  re-express the Drift bump as v17 on top of #377's landed v16; state the
  dedup explicitly in a PR comment; inspect its `ci.yml` edit and port it onto
  the sharded layout if still needed, else drop it with a note; verify the
  rebased diff against issue #259's acceptance criteria before merging.

## Assumptions

- A1 — The owner's 2026-09-12 deferral of Clue-import work still stands. The
  session directive ("review them all and ensure they get merged") postdates
  the deferral; treating specificity-over-recency as decisive is an
  assumption, not a fact — but leaving #489 draft is the reversible choice
  (a readiness comment is trivially resumable; merging a deferred feature
  into release-gated main is not), and the final report surfaces the call
  prominently so the owner can override with one word. Tripwire: U7 verifies
  issue #199's milestone/labels/parent epic actually place it inside the
  deferred Clue-import scope; if #199 also serves already-shipped import
  paths (JSON restore / file import), the mismatch is reported in the
  readiness comment and final report instead of a plain readiness verdict.
- A2 — Squash-merging PRs authored by `wjdavis5` as `wjdavis5` with the
  ruleset's zero required approvals is the owner's intended operating mode
  (that is how #603/#644/#645/#647 already landed).
- A3 — Issue #646's shard-1 failure was transient to `3adcbab` (current head
  green); noted for the final report, not treated as a blocker.
- A4 — The Copilot code-review ruleset rule requests reviews on push but does
  not block merge (observed: no required-approval count). If it does block,
  that surfaces at merge time and is reported, not bypassed.
- A5 — pgTAP runs locally via the pinned Supabase CLI per AGENTS.md Migration
  Flow step 2; if the local Docker/Supabase stack is unavailable in this
  environment, the CI `Database tests (pgTAP)` job becomes the gate and the
  substitution is stated in the PR comment.

## Implementation Units

### U1. Close #503 as superseded by #603

Covers R1, R2, KTD6.
- Verify: diff #503's migration against main's
  `supabase/migrations/20260913022000_account_deletion_transfers_and_connections.sql`
  and its `supabase/tests/account_deletion_test.sql` changes against main's;
  confirm issue #499 is closed.
- If strictly superseded: close #503 with a comment naming #603 and the
  verification result; delete nothing. If anything is unique to #503: file it
  as a new issue (R6) and still close the PR.
- Test scenarios: none (no code lands). Verification is the diff itself.

### U2. Rebase and merge #502 (ownership transfer revokes prediction connections)

Covers R1–R5, KTD3, KTD4, KTD8.
- Confirm the fix is still absent on main (already verified in recon: no
  accept_ownership_transfer body on main touches `prediction_connections`);
  check issue #496 is still open.
- KTD4 production check (`migration list --linked`), then rebase; rename
  `supabase/migrations/20260913030000_ownership_transfer_revoke_prediction_connections.sql`
  to sort after main's latest at merge time; resolve AGENTS.md (append its
  entry) and `supabase/tests/prediction_connection_test.sql` (union sections,
  fix plan count).
- Gates: pgTAP suite (A5); `flutter analyze`/`flutter test` if lib/ files
  change; required checks green; squash-merge.
- Test scenarios: the PR's own pgTAP cases (revocation of live connections and
  pending invites at accept; idempotency) plus the full existing
  `prediction_connection_test.sql`/`ownership_transfer_test.sql` suites.

### U3. Rebase, update, and merge #504 (release gating on CI checks)

Covers R1–R5, KTD3, KTD8.
- Rebase `fix/498-gate-releases-on-ci-checks` onto `origin/main`; resolve the
  `.github/workflows/ci.yml` conflict by re-expressing the gate step against
  the sharded layout.
- Update `.github/scripts/check-ci-gate.sh` to the post-#644 required check
  names and update `.github/scripts/tests/check-ci-gate.test.sh` to match
  (name-agnostic rollup rejected — see Technical design notes).
- Verify the rebased diff answers issue #498's ask (release workflows gated on
  the PR's own ci.yml checks) end-to-end.
- Gates: the script's bash unit tests (both release-guard CI jobs run them),
  actionlint; required checks green; squash-merge.
- Test scenarios: gate passes when all required checks succeed; fails closed
  when one fails or is missing; references only check names that exist in the
  sharded ci.yml.

### U4. Rebase, rename migrations, and merge #643 (sync bundle A)

Covers R1–R5, KTD3, KTD4, KTD7, KTD8.
- KTD7 check; KTD4 production check; rebase
  `opencode-deepseek/bundle-a-sync`; rename both migrations
  (`20260913022000_finite_timestamp_policy.sql` collides with main's identical
  prefix — a schema_migrations PK collision — and
  `20260913023000_sync_push_observation_reparent.sql`) to sort after main's
  latest at merge time, with header notes per convention; resolve
  `supabase/tests/*` and AGENTS.md conflicts.
- Semantic rebase review of `lib/data/sync/supabase_sync_engine.dart` and
  `lib/data/db/storage_local_writes.dart` against main's #588 fixes: the three
  bundle fixes (finite timestamps; same-date observation reparenting;
  future-stamped rebase) must survive intact and not reintroduce what #588
  fixed. Verify the rebased diff against issues #641/#639's stated findings.
- Gates: pgTAP (its two new test files), `flutter test` (storage/sync tests),
  quality gate re-verified post-rebase (main moved since the branch's claimed
  94.62%); required checks green; squash-merge.
- Test scenarios: `timestamp_policy_test.sql` and
  `sync_push_observation_reparent_test.sql` pass against the renamed
  migrations; `test/data/storage_sync_test.dart` passes; no regression in the
  #588-adjacent sync tests on main.

### U5. Rebase, renumber, and merge #377 (numeric measurements)

Covers R1–R5, KTD3, KTD4, KTD7, KTD8.
- KTD7 check; KTD4 production check; rebase `feat/255-numeric-measurements`;
  rename `supabase/migrations/20260911090000_numeric_measurement_units.sql`
  per KTD4; expected conflicts: AGENTS.md, `lib/data/db/db.dart`,
  `drift_schemas/drift_schema_v13.json` (slot taken on main),
  `test/data/db/generated_migrations/schema_v13.dart`.
- Re-express the Drift bump as schemaVersion 16: `build_runner` regen,
  `drift_dev schema dump … drift_schema_v16.json`, regenerate all
  `schema_v*.dart` helpers, update `schema_migration_test.dart`'s
  `_kOlderSchemaVersions`/`_kCurrentSchemaVersion`, bump the CI
  codegen-freshness dump filename (AGENTS.md six-step procedure).
- Verify the rebased diff against issue #255's acceptance criteria; file gaps
  per R6.
- Gates: pgTAP (its units test file), `flutter analyze`, `flutter test`,
  quality gate, codegen freshness; required checks green; squash-merge.
- Test scenarios: the PR's own unit/widget coverage for BBT/weight entry and
  display; the schema-migration harness proves every historical upgrade path
  lands on v16; existing logging tests keep passing.

### U6. Rebase, dedup, renumber, and merge #378 (tracking preferences)

Covers R1–R5, KTD3, KTD4, KTD7, KTD8.
- KTD7 check; KTD4 production check; rebase `feat/259-tracking-prefs` onto
  post-U5 main. **Drop the duplicated units content** — #378's
  `20260910110000_numeric_measurement_units.sql`, its pgTAP file, and any
  other files whose content #377 already landed (verify per-file rather than
  by name) — keeping only the tracking-prefs delta; note the dedup in a PR
  comment.
- Rename `supabase/migrations/20260910120000_profile_tracking_preferences.sql`
  per KTD4; re-express the Drift bump as v17 on top of #377's landed v16
  (same six-step codegen procedure).
- Inspect its `ci.yml` edit: port onto the sharded layout if still needed,
  else drop from the branch with a note.
- Verify the rebased diff against issue #259's acceptance criteria; file gaps
  per R6.
- Gates and test scenarios: as U5, plus its day-sheet read-path tests and the
  tracking-preferences pgTAP files.

### U7. Review #489 and report readiness (no merge)

Covers R1, R2 (terminal state = deliberately draft), KTD5, KTD7.
- KTD7 check (opencode-muse dormant 41h+; still re-check).
- A1 tripwire: verify issue #199's milestone/labels/parent epic place it
  inside the deferred Clue-import scope; if not, the readiness comment names
  the mismatch explicitly.
- Review the diff against its own AC1–AC7 and its "Not done" section (3
  out-of-scope CRAP failures attributed to main drift — verify they exist on
  main and are not the PR's); leave the readiness verdict as a PR comment so
  the deferred work has a trustworthy resumption point.
- Do not undraft, rebase, or merge. The PR stays draft regardless of the
  verdict.

## Verification Contract

- Repo gates (AGENTS.md): `flutter analyze`; `flutter test`;
  `dart run tool/quality_gate.dart`; for migration PRs the pgTAP suite per
  Migration Flow step 2 (A5); for `ci.yml`/script PRs the release-guard script
  tests + actionlint (run in CI's two release-guard jobs).
- Drift-schema PRs additionally: `build_runner` regen, schema dump, generated
  migration helpers, and `test/data/db/schema_migration_test.dart` (AGENTS.md
  six-step codegen procedure), with the version renumbering KTD4 specifies.
- Migration-landing PRs additionally: the KTD4 linked-project production check
  before any rename.
- Remote gate: ruleset "Main" required checks green on the rebased head.
- Each merge is verified post-merge by main's CI run on the merge commit.

## Definition of Done

- Global: every open PR is merged, closed-superseded, or (only #489) left
  draft with a posted readiness review; main is green after each merge; the
  final report lists each PR's terminal state, the #646 evidence, and the
  A1/#489 call prominently.
- Bounded-attempt rule: a lane that fails two rebase-verify cycles stops
  there, leaves its findings as a PR comment, and is reported as unmerged —
  the sweep proceeds to the next lane rather than growing scope.
- Follow-up filings (R6), regardless of sweep outcome:
  - An issue proposing a single name-stable rollup required check (all sharded
    jobs as its dependencies) so future ci.yml job renames stop orphaning open
    PRs — the mechanism that produced this backlog.
  - An issue proposing restructuring or automating the AGENTS.md
    schema-history paragraph / migration-timestamp allocation, citing this
    sweep's guaranteed-conflict count as evidence.
- U1: #503 closed with the equivalence evidence in the closing comment.
- U2–U6: PR merged (squash), required checks green, issue references
  auto-closed by the PR's own `Closes #n` lines intact.
- U7: readiness comment posted on #489 (including the A1 tripwire result);
  PR still draft.
