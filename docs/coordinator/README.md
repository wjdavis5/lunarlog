# Coordinators — ownership model

Multiple autonomous coordinators work this repo concurrently. Each coordinator
picks GitHub issues, dispatches coder subagents into worktrees, and reviews
and merges PRs — unattended, on its own loop. This document is the contract
that lets them share one repo without colliding.

**The rule a human can skim:** every coordinator has a short id. It only ever
labels, comments on, closes, dispatches, reviews, merges, or deletes things
that carry its own id — as a GitHub label on an issue, a GitHub label plus a
branch prefix on a PR, or a path prefix on a worktree and its state directory.
If a thing isn't marked as its own, the coordinator leaves it alone completely
— no reading it for "just a status check," no touching it "since it looks
abandoned," no exception for something that looks trivial or urgent. GitHub
labels are the only ownership source of truth; a coordinator's own state files
are a cache of what *it* did, never a way to determine what belongs to someone
else.

## Coordinators currently running

| id | Engine | Branch prefix | Worktree root | State dir |
|---|---|---|---|---|
| `claude-orch` | Claude Code (interactive, owner-driven sessions) | `feat/<n>-<slug>` / `fix/<n>-<slug>` (pre-existing branches keep this until they merge — see `claude-orch`'s `PROCESS.md`) | `../lunarlog-wt/<n>-<slug>` (legacy; new worktrees go to `.worktrees/claude-orch/<n>-<slug>`) | [`STATE.md`](STATE.md)/[`log.md`](log.md)/[`briefs/`](briefs/) — flat, **not** `docs/coordinator/claude-orch/`; see "Why one coordinator's state isn't in its own directory" below |
| `opencode-muse` | OpenCode (`opencode/muse-spark-1.3-contributor-free`) | `opencode-muse/<n>-<slug>` (`opencode-muse/fix-<n>-<slug>` for bugs) | `.worktrees/opencode-muse/<n>-<slug>` | [`docs/coordinator/opencode-muse/`](opencode-muse/) |

### Why one coordinator's state isn't in its own directory

`claude-orch` predates this ownership model and already commits `STATE.md`/`log.md`/
`briefs/` directly to `main` (no PR) on essentially every loop iteration — that habit is
unchanged here. Moving those files into `docs/coordinator/claude-orch/` was tried first
and produced a fresh merge conflict on every rebase, indefinitely: a process committing
every few minutes always outraces a competing PR touching the same paths. So `claude-orch`
keeps its state at the flat `docs/coordinator/` path it already used — a grandfathered
exception — while still following every ownership rule below (issue/PR/worktree markers,
never touching another coordinator's things). A coordinator that starts *after* this
model exists, like `opencode-muse`, gets a clean per-id directory from day one and has no
reason to ever deviate from it.

## The three markers

| Thing | Marker | Rule |
|---|---|---|
| Issue | `owner:<id>` label | A coordinator never labels, comments on, closes, or dispatches an issue owned by a different id. Never removes another owner's `in-progress`. |
| PR | head branch prefix `<id>/` **and** PR label `owner:<id>` | A coordinator never reviews, approves, merges, closes, or comments on a PR that isn't its own by both markers — not even a trivial, all-green one. |
| Worktree | path prefix `.worktrees/<id>/` | A coordinator never lists-and-prunes, removes, or `cd`s into a worktree outside its own prefix. `git worktree prune` is the one exception — it only drops entries whose directories are already gone, so it can't touch anyone's live work. |

State (`docs/coordinator/<id>/STATE.md`, `log.md`, `briefs/` — or, for `claude-orch`
only, the flat `docs/coordinator/` path it already used before this model existed; see
above) is per-coordinator and never shared or cross-read: a coordinator's own state is a
bookkeeping cache of *its* actions, and GitHub labels are always the ground truth for
what belongs to whom. If coordinator A needs to know whether issue #N is claimed, it
reads the GitHub label — never coordinator B's STATE.md.

## Claiming an issue

Atomically, in this order:

1. `gh issue view <n> --json labels` (or `tool/coord/issue_labels.py <n>`) — abort if `in-progress` is already present.
2. `gh issue edit <n> --add-label in-progress --add-label owner:<id>`.
3. Comment: `Claimed by <id>. Branch: <id>/<n>-<slug>`.
4. Re-read labels. If an `owner:*` label is present that is **not** ours, another
   coordinator won the race: remove only our `owner:` label, leave `in-progress`
   alone, skip the issue. It is not ours regardless of which coordinator got
   there first — the second `owner:` label to land loses, deterministically,
   by this rule.

`tool/coord/claim.py` implements this exactly (see below).

A coder is dispatched only **after** the claim succeeds and the issue carries both `in-progress`
and `owner:<id>`. The coder re-verifies both labels before starting and refuses to work an
unclaimed issue; no coder ever adds, removes, or edits labels itself — claiming is the
coordinator's job. Every dispatched coder also gets its **own unique worktree and branch**; no two
coders ever share a worktree, branch, or working directory.

## Stale-issue handling is scoped to self

A coordinator may reconcile only rows in its own `STATE.md`. If it sees a
*foreign* `in-progress` issue that looks abandoned, it opens a
`needs-human-review` issue describing what it saw and moves on — it never
unclaims on another coordinator's behalf, no matter how confident it is that
the claim is stale.

## Labels

| Label | Meaning |
|---|---|
| `in-progress` | Claimed by some coordinator. Which one is `owner:<id>`, not this label. |
| `owner:claude-orch` | Owned by the `claude-orch` coordinator. |
| `owner:opencode-muse` | Owned by the `opencode-muse` coordinator. |
| `needs-human-review` | A coordinator hit a product question, an abandoned foreign claim, or something it isn't equipped to resolve. |

Labels are cheap — one `owner:` label exists per coordinator, created once.

## Adding a third coordinator

1. Pick a short, stable id (lowercase, hyphenated, no `/`).
2. Create its `owner:<id>` label: `gh label create owner:<id> --color <hex>`.
3. Give it its own branch prefix (`<id>/<n>-<slug>`), worktree root
   (`.worktrees/<id>/`), and state directory (`docs/coordinator/<id>/`).
4. Point it at `tool/coord/` for claiming, listing, and worktree operations —
   every script takes `--owner <id>` and enforces the prefix rules above, so a
   misconfigured id fails loudly instead of touching someone else's work.
5. Add a row to the table above.

## `tool/coord/` helper scripts

Python 3, stdlib only, shell out to `gh`. Written because the single biggest
time sink in the first (failed) coordinator run was PowerShell/`gh --jq`
quoting — every script takes `--json` for machine output, is plain text by
default, exits non-zero with a short message on error, and resolves the repo
root itself so it works from any cwd.

| Script | Purpose |
|---|---|
| `list_issues.py` | Open issues, `#n<TAB>labels<TAB>title`; `--eligible <id>` applies the pick filter and priority sort. |
| `claim.py <n> --owner <id> --branch <name>` | The claim sequence above. Exit 0 = claimed, 1 = lost the race / already claimed, 2 = error. |
| `release.py <n> --owner <id>` | Removes `in-progress` and `owner:<id>`, only if `owner:<id>` is present. |
| `worktree_add.py <n> <slug> --owner <id>` | Creates `.worktrees/<id>/<n>-<slug>` on `<id>/<n>-<slug>` from `origin/main`. |
| `worktree_rm.py <path> --owner <id>` | Refuses if `<path>` is not under `.worktrees/<id>/`. |
| `pr_status.py [--owner <id>]` | Open PRs: number, head, labels, CI rollup, review decision; `--mine` filters to both ownership markers. |
| `issue_labels.py <n>` | Labels, one per line. |

See each script's `--help` for the full flag set.
