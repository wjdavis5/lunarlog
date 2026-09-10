---
description: Show the orchestrator control plane alongside the live GitHub state.
---

# orchestrator-status

1. Read `docs/coordinator/orchestrator-directives.md`.
2. For each directive, show the live issue/PR state:
   `gh issue view <n> --json state,labels` and
   `python3 tool/coord/pr_status.py --owner <coordinator> --mine`.
3. Flag any directive whose issue is closed or whose PR merged (stale), and any
   red `main` run with no tracking issue.

Read-only: do not mutate labels, claims, or the control plane.
