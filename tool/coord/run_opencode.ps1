<#
.SYNOPSIS
  Outer loop for the opencode-muse coordinator.

.DESCRIPTION
  A single `opencode run` turn ends when the agent replies, so unattended
  operation needs something outside OpenCode driving repeated iterations. This
  script does exactly that: it invokes the `coordinator` agent for one loop
  iteration, sleeps, and repeats -- forever, until a STOP file appears.

  Stop the loop by creating docs/coordinator/opencode-muse/STOP (any content,
  even empty) in the repo. The loop checks for it before every iteration and
  exits cleanly if found. It does NOT delete the STOP file for you -- remove it
  yourself before restarting the loop.

.PARAMETER IntervalSeconds
  Delay between iterations. Default 300 (5 minutes).

.PARAMETER RepoRoot
  Path to the lunarlog repo root. Defaults to two levels up from this script
  (tool/coord/run_opencode.ps1 -> repo root), which is correct when run from a
  checkout in place. Override for a worktree or a different checkout.

.EXAMPLE
  pwsh -File tool/coord/run_opencode.ps1

.EXAMPLE
  pwsh -File tool/coord/run_opencode.ps1 -IntervalSeconds 600

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
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
)

$ErrorActionPreference = "Stop"

$stateDir = Join-Path $RepoRoot "docs\coordinator\opencode-muse"
$stopFile = Join-Path $stateDir "STOP"
$prompt = "Resume from docs/coordinator/opencode-muse/STATE.md. Run one loop iteration, then stop."

Write-Host "lunarlog opencode-muse coordinator loop starting. Interval: ${IntervalSeconds}s. Stop file: $stopFile"

while ($true) {
    if (Test-Path $stopFile) {
        Write-Host "STOP file found at $stopFile -- exiting loop."
        break
    }

    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
    Write-Host "[$timestamp] running one coordinator iteration..."

    Push-Location $RepoRoot
    try {
        & opencode run --agent coordinator $prompt
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-Warning "[$timestamp] opencode run exited with code ${exitCode}."
        }
    }
    catch {
        Write-Warning "[$timestamp] opencode run threw: $_"
    }
    finally {
        Pop-Location
    }

    if (Test-Path $stopFile) {
        Write-Host "STOP file found after iteration -- exiting loop without sleeping."
        break
    }

    Write-Host "sleeping ${IntervalSeconds}s..."
    Start-Sleep -Seconds $IntervalSeconds
}
