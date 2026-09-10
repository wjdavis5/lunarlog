---
name: dispatch-orchestrator
description: Start one opencode-deepseek coordinator iteration for a chosen issue. Use after the master planner has chosen work.
---

# Dispatch an orchestrator

Start exactly one opencode-deepseek iteration for a chosen issue, or steer it to a
different issue. GitHub labels remain the claim mechanism — the coordinator
claims the issue itself.

## Preconditions

1. The issue carries no foreign `owner:*` label.
2. The issue is not `needs-human-review` or `blocked`.
3. The chosen model is valid (`python3 tool/orchestrator/models.py --role coder`).

## Run

```
python3 tool/orchestrator/opencode_bridge.py --run "Run one loop iteration. Prioritize issue #<n>."
```

Record the intent with `set-directive` and return the session id.

## Rules

- One issue per worktree; never ask for two issues in one dispatch.
- Never dispatch for an issue that already has an open PR.
- If the run fails, report it and stop; do not retry more than once.
