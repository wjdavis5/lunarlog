# Coordinator process — lunarlog — `claude-orch`

Operating rules for the Engineering Coordinator (supplements the role brief given by the
owner; where they conflict, the owner's latest instruction wins). This coordinator's id
is **`claude-orch`** — see [`README.md`](README.md) for the multi-coordinator ownership
model it now shares this repo under. State lives in `STATE.md` (tables) and `log.md`
(one line per action); briefs in `briefs/<issue>.md` — all still at this same flat
`docs/coordinator/` path (see "Why state isn't under `docs/coordinator/claude-orch/`"
below), committed to `main` directly with `chore(coordinator): ...`.

## Ownership (multi-coordinator, 2026-09-09)

This repo now has more than one coordinator running concurrently (see `README.md`). The
three ownership markers apply to `claude-orch`:

| Thing | Marker | Rule |
|---|---|---|
| Issue | `owner:claude-orch` label | Never label, comment on, close, or dispatch an issue owned by a different id. Never remove another owner's `in-progress`. |
| PR | head branch prefix `claude-orch/` **and** PR label `owner:claude-orch` | Never review, approve, merge, close, or comment on a PR that isn't ours by both markers. |
| Worktree | path prefix `.worktrees/claude-orch/` | Never list-and-prune, remove, or `cd` into a worktree outside our own prefix. `git worktree prune` is allowed. |

**Transition note:** pre-existing branches (`feat/<n>-<slug>`, `fix/<n>-<slug>`) and
worktrees (`../lunarlog-wt/<n>-<slug>`) predate the branch-prefix rule and are **not**
renamed or moved — they stay as-is until their PRs merge; the `owner:claude-orch` PR
label is the ownership marker for them in the meantime. **Every new worktree from here
on** goes to `.worktrees/claude-orch/<n>-<slug>` on branch `claude-orch/<n>-<slug>`.

**Why state isn't under `docs/coordinator/claude-orch/`:** the first draft of this
ownership model physically moved `STATE.md`/`log.md`/`briefs/` there. That collided with
this coordinator's own direct-to-`main` commits to those same paths on essentially every
iteration — a live process writing every few minutes will always outrace a competing PR
touching the same files, so the "move" produced a fresh conflict on every rebase rather
than resolving once. State stays flat at `docs/coordinator/` — a grandfathered exception
to the "each coordinator owns a directory" rule in `README.md` — for exactly this reason.
Only genuinely new coordinators (with no pre-existing direct-to-`main` habit) get a clean
`docs/coordinator/<id>/` from day one.

Claiming an issue is now, atomically, in this order:

1. `gh issue view <n> --json labels` — abort if `in-progress` is present.
2. `gh issue edit <n> --add-label in-progress --add-label owner:claude-orch`.
3. Comment: `Claimed by claude-orch. Branch: claude-orch/<n>-<slug>`.
4. Re-read labels. If an `owner:*` label is present that is **not** `owner:claude-orch`,
   another coordinator won the race: remove only our `owner:claude-orch` label, leave
   `in-progress` alone, skip the issue.

Stale-issue detection stays scoped to this coordinator's own `STATE.md`. A foreign
`in-progress` issue that looks abandoned gets a `needs-human-review` issue, never an
unclaim — see `README.md`.

## Issue labeling lifecycle (owner instruction, 2026-09-08)

GitHub issues are the visible status board — label them as we work, not just comment:

| Moment | Action |
|---|---|
| Dispatch to a coder | add `in-progress` + `owner:claude-orch`, comment "Claimed by claude-orch. Branch: `claude-orch/<n>-<slug>`." |
| PR opened (review queue) | keep `in-progress` (optionally also `orch:review` per the legacy taxonomy) |
| Merged / issue closed | GitHub closes the issue; remove `in-progress` if still present |
| Blocked → `needs-human-review` | remove `in-progress`, add `needs-human-review` |
| Abandoned / two failed attempts | remove `in-progress` (the blocking issue carries the state) |

Never leave an issue's status only in STATE.md — the label and the comment are the
user-facing truth. STATE.md remains the detailed record (worktree, PR, attempts).

## Loop (abridged — full rules in the owner's role brief)

1. **Sync**: fetch, pull `main` ff-only, `git worktree prune`, refresh STATE.md from `gh pr list`.
2. **Pick**: open issues, skip `needs-human-review`/`blocked`-class/`epic`/in-progress/blocked-table,
   anything carrying a foreign `owner:*` label, and anything with an open dependency; order
   P0→P1→P2→P3, then by unblocked dependents, then number.
3. **Brief**: `briefs/<issue>.md` — issue body, ACs checklist, verified file paths, gate commands,
   PR template. Claim per "Ownership" above before writing the brief.
4. **Dispatch**: coder subagent, one issue / one worktree / one branch
   (`.worktrees/claude-orch/<n>-<slug>` on `claude-orch/<n>-<slug>` — see "Transition note" for
   already-live work), max 3 parallel.
5. **Review**: confirm the PR carries the `owner:claude-orch` label (or a pre-transition
   `feat/`/`fix/` head branch already tracked in STATE.md) before touching it at all. Then: CI on
   the PR's *head SHA* (verify check-runs exist — a GitHub event gap can skip `ci.yml` entirely; if
   missing, force a `synchronize` via branch update), diff scope, ACs walked against the diff,
   correctness (mobile state, sync/offline, RLS never weakened, migrations additive), tests
   required. Merge squash + good title; clean worktree; update STATE/log.
6. **Discoveries**: unrelated bugs found in review → new issues with priority labels, never fixed
   in passing. Product questions → `needs-human-review`.
7. **Stop conditions**: no eligible issues; three consecutive blocks; CI failing on `main` after a
   merge (revert, file `needs-human-review`, stop); auth/quota errors (record and stop).

## State commits (rule change 2026-09-09)

`main` now has a repository rule requiring all changes through PRs — direct pushes are
rejected. Coordinator state (`STATE.md`, `log.md`, `briefs/`) moves via a small
`chore/coordinator-state-sync` branch + PR; batch updates rather than one PR per action.
When committing state in the shared checkout: stage ONLY `docs/coordinator/STATE.md`,
`log.md`, and the specific `briefs/<n>.md` you wrote — other sessions keep their own
files under `docs/coordinator/` (e.g. `opencode-muse/`); never `git add` the directory.

## Session-recovery notes (learned the hard way)

- New PRs may silently lack `ci.yml` runs (event gap). Always list head-SHA check-runs; if the CI
  jobs are absent, merge `origin/main` into the PR branch (resolve conflicts carefully — verify
  which side you keep) and push to force a `synchronize`.
- PR branches based before recent merges usually conflict in `AGENTS.md` (schema section + test
  counts): keep main's paragraphs and append the branch's new sentences; test counts = main's
  total + branch's new files/counts (filenames are backtick-quoted — regex accordingly).
- Migration filenames must sort after the current tip; renumber on the PR branch if a parallel
  merge took the timestamp.
- Self-approval is impossible on the owner's own PRs: record the review as a comment, then merge.
- Any schemaVersion bump requires ALL of: build_runner regen, drift_schemas/drift_schema_v<N>.json
  dump, AND the filename bump in ci.yml's codegen-freshness step (missed twice: #344, #356 — put
  it in every schema-touching brief).
- NEVER push a merge commit whose full test suite is still failing — fix first, then push
  (#369: pushed a red merge, had to hand the behavioral fix to the branch's coder).
- Behavioral merge conflicts (two features touching the same logic, not just imports) go back
  to a coder with both parents' context; the coordinator resolves textual conflicts only.
- After ANY scripted conflict resolution, `grep -c '<<<<<<<'` before committing — a failed script
  plus a non-`set -e` shell once shipped markers to the remote branch (fixed forward, never
  force-push).
