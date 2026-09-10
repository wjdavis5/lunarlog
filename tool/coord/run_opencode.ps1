<#
.SYNOPSIS
  Outer loop for an `opencode-<model>` coordinator.

.DESCRIPTION
  A single `opencode run` turn ends when the agent replies, so unattended
  operation needs something outside OpenCode driving repeated iterations. This
  script does exactly that: it invokes the `coordinator` agent for one loop
  iteration, sleeps, and repeats -- forever, until a STOP file appears.

  The coordinator id is `opencode-<model>` for the `-Model` this loop runs. It is
  derived by `tool/coord/coordinator_id.py` and exported as
  LUNARLOG_COORDINATOR_ID, which `opencode.json` injects into the coordinator and
  coder prompts as `COORDINATOR_ID=<id>`. Several coordinators, one per model, can
  therefore run at once -- each with its own `owner:<id>` label, `.worktrees/<id>/`
  worktree prefix, and `docs/coordinator/<id>/` state directory.

  Stop the loop by creating docs/coordinator/<id>/STOP (any content, even empty)
  in the repo. The loop checks for it before every iteration and exits cleanly if
  found. It does NOT delete the STOP file for you -- remove it yourself before
  restarting the loop.

.PARAMETER IntervalSeconds
  Delay between iterations. Default 300 (5 minutes).

.PARAMETER Model
  The model this coordinator runs, e.g. `opencode/muse-spark-1.3-contributor-free`
  or `deepseek/deepseek-v4-flash`. The id is derived from it as `opencode-<model>`.
  Default: opencode/muse-spark-1.3-contributor-free.

.PARAMETER RepoRoot
  Path to the lunarlog repo root. Defaults to two levels up from this script
  (tool/coord/run_opencode.ps1 -> repo root), which is correct when run from a
  checkout in place. Override for a worktree or a different checkout.

.EXAMPLE
  pwsh -File tool/coord/run_opencode.ps1

.EXAMPLE
  pwsh -File tool/coord/run_opencode.ps1 -IntervalSeconds 600

.EXAMPLE
  pwsh -File tool/coord/run_opencode.ps1 -Model deepseek/deepseek-v4-flash

.NOTES
  Registering as a Windows scheduled task (do this manually -- it is not done
  by this script or by the coordinator itself):

    $action = New-ScheduledTaskAction -Execute "pwsh.exe" `
      -Argument '-NoProfile -File "C:\git\repos\lunarlog\tool\coord\run_opencode.ps1"'
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    Register-ScheduledTask -TaskName "lunarlog-opencode-coordinator" `
      -Action $action -Trigger $trigger -RunLevel Limited

  Unregister with:
    Unregister-ScheduledTask -TaskName "lunarlog-opencode-coordinator" -Confirm:$false

  This is documentation only -- nothing in this repo registers the task
  automatically, and the coordinator loop must not be started unattended
  without the owner's explicit go-ahead.
#>

param(
    [int]$IntervalSeconds = 300,
    [string]$Model = "opencode/muse-spark-1.3-contributor-free",
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
)

$ErrorActionPreference = "Stop"

# UTF-8 everywhere, so non-ASCII issue text never corrupts tool output.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Derive `opencode-<model>` -- never hard-coded, so one loop per model can run at
# once. Exported so opencode.json injects it into the prompts as COORDINATOR_ID.
$CoordinatorId = (& python (Join-Path $PSScriptRoot "coordinator_id.py") --model $Model | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $CoordinatorId) {
    Write-Error "could not derive a coordinator id from model '$Model'"
    exit 2
}
$env:LUNARLOG_COORDINATOR_ID = $CoordinatorId

# Single-instance guard: a scheduled task plus a manual start must never run two
# loops for the SAME coordinator id against the same labels and worktrees.
$mutex = New-Object System.Threading.Mutex($false, "Global\lunarlog-$CoordinatorId-coordinator")
if (-not $mutex.WaitOne(0)) {
    Write-Host "another $CoordinatorId coordinator loop is already running -- exiting."
    exit 1
}

$stateDir = Join-Path $RepoRoot "docs\coordinator\$CoordinatorId"
$stopFile = Join-Path $stateDir "STOP"
$prompt = "Resume from docs/coordinator/$CoordinatorId/STATE.md. Run one loop iteration, then stop."

Write-Host "lunarlog $CoordinatorId coordinator loop starting (model: $Model). Interval: ${IntervalSeconds}s. Stop file: $stopFile"

$consecutiveFailures = 0

while ($true) {
    if (Test-Path $stopFile) {
        Write-Host "STOP file found at $stopFile -- exiting loop."
        break
    }

    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
    Write-Host "[$timestamp] running one coordinator iteration..."

    Push-Location $RepoRoot
    $failed = $false
    try {
        & opencode run --agent coordinator --model $Model $prompt
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            $failed = $true
            Write-Warning "[$timestamp] opencode run exited with code ${exitCode}."
        }
    }
    catch {
        $failed = $true
        Write-Warning "[$timestamp] opencode run threw: $_"
    }
    finally {
        Pop-Location
    }

    if ($failed) {
        $consecutiveFailures++
        if ($consecutiveFailures -ge 5) {
            Write-Warning "[$timestamp] 5 consecutive failures -- writing STOP and exiting."
            New-Item -ItemType File -Path $stopFile -Force | Out-Null
            break
        }
    }
    else {
        $consecutiveFailures = 0
    }

    if (Test-Path $stopFile) {
        Write-Host "STOP file found after iteration -- exiting loop without sleeping."
        break
    }

    $backoff = [Math]::Min($IntervalSeconds * [Math]::Pow(2, [Math]::Max(0, $consecutiveFailures - 1)), 3600)
    $sleepFor = [int]$backoff
    Write-Host "sleeping ${sleepFor}s..."
    # Poll STOP during the sleep so a STOP created mid-sleep is honored promptly.
    $remaining = $sleepFor
    while ($remaining -gt 0) {
        if (Test-Path $stopFile) { break }
        $chunk = [Math]::Min(5, $remaining)
        Start-Sleep -Seconds $chunk
        $remaining -= $chunk
    }
    if (Test-Path $stopFile) {
        Write-Host "STOP file found during sleep -- exiting loop."
        break
    }
}
