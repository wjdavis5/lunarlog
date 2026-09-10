<#
.SYNOPSIS
  Outer loop for the opencode-deepseek coordinator.

.DESCRIPTION
  A single `opencode run` turn ends when the agent replies, so unattended
  operation needs something outside OpenCode driving repeated iterations. This
  script does exactly that: it invokes the `coordinator` agent for one loop
  iteration, sleeps, and repeats -- forever, until a STOP file appears.

  Stop the loop by creating docs/coordinator/opencode-deepseek/STOP (any content,
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

# UTF-8 everywhere, so non-ASCII issue text never corrupts tool output.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Single-instance guard: a scheduled task plus a manual start must never run two
# coordinator loops against the same labels and worktrees.
$mutex = New-Object System.Threading.Mutex($false, "Global\lunarlog-opencode-deepseek-coordinator")
if (-not $mutex.WaitOne(0)) {
    Write-Host "another lunarlog-opencode-deepseek coordinator loop is already running -- exiting."
    exit 1
}

$stateDir = Join-Path $RepoRoot "docs\coordinator\opencode-deepseek"
$stopFile = Join-Path $stateDir "STOP"
$prompt = "Resume from docs/coordinator/opencode-deepseek/STATE.md. Run one loop iteration, then stop."

Write-Host "lunarlog opencode-deepseek coordinator loop starting. Interval: ${IntervalSeconds}s. Stop file: $stopFile"

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
        & opencode run --agent coordinator $prompt
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
