---
name: opencode-bridge
description: Invoke the opencode-muse coordinator and read back its session. Use when the master planner needs to start or inspect an opencode run.
---

# opencode bridge

Wrap `tool/orchestrator/opencode_bridge.py` and `models.py`.

## Start an iteration

```
python3 tool/orchestrator/opencode_bridge.py --run "<prompt>" [--model <id>]
```

Or from Python: `run_iteration(prompt, agent="coordinator", model=...)` returns
`{session_id, raw}`.

## Read a session

```
python3 tool/orchestrator/opencode_bridge.py --read <sessionID>
```

`read_session` prefers `opencode export <id>` and falls back to an
`opencode db` query. Summarize the transcript with `summarize_session`.

## Pick a model

```
python3 tool/orchestrator/models.py --role coder
```

Role defaults: `planner`/`reviewer` → `deepseek/deepseek-v4-flash`;
`coder` → `opencode/muse-spark-1.3-contributor-free`. Every id is validated
against `opencode models` before dispatch; a per-dispatch override wins.
