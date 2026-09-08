# Coordinator process — lunarlog

Operating rules for the Engineering Coordinator (supplements the role brief given by the
owner; where they conflict, the owner's latest instruction wins). State lives in
`STATE.md` (tables) and `log.md` (one line per action); briefs in `briefs/<issue>.md`.
Everything here is committed to `main` directly with `chore(coordinator): ...`.

## Issue labeling lifecycle (owner instruction, 2026-09-08)

GitHub issues are the visible status board — label them as we work, not just comment:

| Moment | Action |
|---|---|
| Dispatch to a coder | add `in-progress`, comment "Dispatched to coder on branch `feat/...`." |
| PR opened (review queue) | keep `in-progress` (optionally also `orch:review` per the legacy taxonomy) |
| Merged / issue closed | GitHub closes the issue; remove `in-progress` if still present |
| Blocked → `needs-human-review` | remove `in-progress`, add `needs-human-review` |
| Abandoned / two failed attempts | remove `in-progress` (the blocking issue carries the state) |

Never leave an issue's status only in STATE.md — the label and the comment are the
user-facing truth. STATE.md remains the detailed record (worktree, PR, attempts).

## Loop (abridged — full rules in the owner's role brief)

1. **Sync**: fetch, pull `main` ff-only, `git worktree prune`, refresh STATE.md from `gh pr list`.
2. **Pick**: open issues, skip `needs-human-review`/`blocked`-class/`epic`/in-progress/blocked-table
   and anything with an open dependency; order P0→P1→P2→P3, then by unblocked dependents, then number.
3. **Brief**: `briefs/<issue>.md` — issue body, ACs checklist, verified file paths, gate commands,
   PR template. Label `in-progress` + comment at dispatch (see lifecycle above).
4. **Dispatch**: coder subagent, one issue / one worktree / one branch (`../lunarlog-wt/<n>-<slug>`),
   max 3 parallel.
5. **Review**: CI on the PR's *head SHA* (verify check-runs exist — a GitHub event gap can skip
   `ci.yml` entirely; if missing, force a `synchronize` via branch update), diff scope, ACs walked
   against the diff, correctness (mobile state, sync/offline, RLS never weakened, migrations
   additive), tests required. Merge squash + good title; clean worktree; update STATE/log.
6. **Discoveries**: unrelated bugs found in review → new issues with priority labels, never fixed
   in passing. Product questions → `needs-human-review`.
7. **Stop conditions**: no eligible issues; three consecutive blocks; CI failing on `main` after a
   merge (revert, file `needs-human-review`, stop); auth/quota errors (record and stop).

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
- After ANY scripted conflict resolution, `grep -c '<<<<<<<'` before committing — a failed script
  plus a non-`set -e` shell once shipped markers to the remote branch (fixed forward, never
  force-push).
