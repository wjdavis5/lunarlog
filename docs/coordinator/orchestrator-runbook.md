# Claude Code orchestrator runbook

The Claude Code central orchestrator lives in `tool/orchestrator/` as a
repo-local plugin. It is loaded with `--plugin-dir tool/orchestrator` for both
interactive sessions and the headless product-manager loop.

## Components

| Path | Purpose |
|---|---|
| `tool/orchestrator/skills/master-planner` | Read the control plane and GitHub, recommend next work |
| `tool/orchestrator/skills/dispatch-orchestrator` | Start one opencode-<model> iteration for a chosen issue |
| `tool/orchestrator/skills/reconcile-orchestrators` | Reconcile each coordinator's PRs and worktrees |
| `tool/orchestrator/skills/opencode-bridge` | Invoke opencode and read its sessions |
| `tool/orchestrator/skills/ci-triage` | Triage the issue the CI watcher filed |
| `tool/orchestrator/skills/product-manager` | The daily review pass |
| `tool/orchestrator/opencode_bridge.py`, `models.py`, `ci_watch.py` | Scripts behind the skills |

The control plane is `docs/coordinator/orchestrator-directives.md`.

## Interactive use

```
claude --plugin-dir tool/orchestrator
```

Then invoke `/lunarlog-orchestrator:master-planner`, or the other skills.

## Daily product-manager loop

```
pwsh -File tool/orchestrator/pm_loop.ps1
```

Register as a Windows scheduled task (do this manually):

```powershell
$action = New-ScheduledTaskAction -Execute "pwsh.exe" `
  -Argument '-NoProfile -File "C:\git\repos\lunarlog\tool\orchestrator\pm_loop.ps1"'
$trigger = New-ScheduledTaskTrigger -Daily -At 07:00
Register-ScheduledTask -TaskName "lunarlog-pm-loop" `
  -Action $action -Trigger $trigger -RunLevel Limited
```

Stop the loop by creating `docs/coordinator/orchestrator-STOP`.

## CI-failure watcher

`.github/workflows/ci-failure-watch.yml` runs on every `CI` completion for
`main` and files or updates one `P1`/`bug` issue per failing head SHA. It needs
no live Claude Code session. Triage with `/lunarlog-orchestrator:ci-triage`.

## Validate

```
claude plugin validate tool/orchestrator
python3 -m unittest discover -s tool/orchestrator/tests
```
