# Orchestrator directives

The control plane the Claude Code master planner reads and writes. It records
**intent** — what each coordinator should be working on — while GitHub labels
remain the single source of truth for ownership and status.

Update a row with the `set-directive` command; read the current state with
`orchestrator-status`. Keep each entry to one line: the issue, the chosen model,
and a short reason.

## Directives

| coordinator | issue | model | intent | set at |
|---|---|---|---|---|
| `opencode-<model>` | — | (the model that coordinator runs) | none — awaiting first directive | — |
| `claude-orch` | — | — | none — awaiting first directive | — |

## Model roster

Available OpenCode models are discovered at runtime with `opencode models`.
Default role mapping:

| role | model | why |
|---|---|---|
| planner / reviewer | `deepseek/deepseek-v4-flash` | stronger reasoning for planning and review |
| coder (bulk) | `opencode/muse-spark-1.3-contributor-free` | cheap, fast, sufficient for scoped units |

A per-dispatch override wins over this default. Every model id is validated
against `opencode models` before dispatch.

## Notes

- A directive is advisory: the coordinator still claims via GitHub labels and
  follows its own ownership rules.
- Never record credentials, tokens, or health data here.
