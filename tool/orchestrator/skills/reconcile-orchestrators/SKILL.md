---
name: reconcile-orchestrators
description: Reconcile each coordinator's PRs, worktrees, and directives against GitHub. Use for a periodic health check of the orchestrator fleet.
---

# Reconcile orchestrators

Check that each coordinator's state matches GitHub, and that the control plane
is not stale.

## Steps

1. For every OpenCode coordinator id in play (`opencode-<model>` — derive it from a
   running model with `python3 tool/coord/coordinator_id.py --model <id>`) run
   `python3 tool/coord/pr_status.py --owner <id> --mine`; do the same for `claude-orch`.
2. `git worktree list` — flag any worktree whose PR is merged or closed.
3. For each directive in `docs/coordinator/orchestrator-directives.md`, check its
   issue state (`gh issue view <n> --json state,labels`). Clear a directive whose
   issue closed or whose PR merged.
4. Report: PRs needing attention, orphaned worktrees, stale directives, and any
   `in-progress` issue with no `owner:*` label (a stuck claim).

## Rules

- Never remove another coordinator's claim or worktree.
- A stuck claim (in-progress, no owner) gets a `needs-human-review` issue, not a
  unilateral unclaim.
