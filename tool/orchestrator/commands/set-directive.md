---
description: Record what a coordinator should work on next in the orchestrator control plane.
argument-hint: <coordinator> <issue> [model] [reason]
---

# set-directive

Record one directive in `docs/coordinator/orchestrator-directives.md`.

Arguments: `$ARGUMENTS` — `<coordinator> <issue> [model] [reason]`.

1. Read `docs/coordinator/orchestrator-directives.md`.
2. Update (or add) the row for the coordinator: issue number, chosen model
   (validate with `python3 tool/orchestrator/models.py --role <role>` when a
   model is given), a short reason, and the current date.
3. Keep the table's other rows unchanged.

Do not claim the issue, add labels, or dispatch — this only records intent.
