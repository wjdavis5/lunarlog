<#
.SYNOPSIS
  Outer loop for the Claude Code product-manager pass.

.DESCRIPTION
  Runs the `product-manager` skill headlessly once per interval (default daily)
  via `claude -p`, mirroring tool/coord/run_opencode.ps1: single instance,
  exponential backoff on failure, and a STOP file checked mid-sleep.

  Stop the loop by creating docs/coordinator/orchestrator-STOP (any content).
  Registration as a Windows scheduled task is documented in
  docs/coordinator/orchestrator-runbook.md and is not done automatically.

.PARAMETER IntervalSeconds
  Delay between passes. Default 86400 (daily).

.PARAMETER RepoRoot
  Repo root. Defaults to two levels up from this script.
#>

param(
    [int]$IntervalSeconds = 86400,
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
)

$ErrorActionPreference = "Stop"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$mutex = New-Object System.Threading.Mutex($false, "Global\lunarlog-pm-loop")
if (-not $mutex.WaitOne(0)) {
    Write-Host "another lunarlog product-manager loop is already running -- exiting."
    exit 1
}

$stopFile = Join-Path $RepoRoot "docs\coordinator\orchestrator-STOP"
$pluginDir = Join-Path $RepoRoot "tool\orchestrator"
$prompt = "Run the product-manager pass: review main since the last run and the open backlog, write the report artifact, and file only actionable prioritized follow-ups. Then stop."

Write-Host "lunarlog product-manager loop starting. Interval: ${IntervalSeconds}s. Stop file: $stopFile"

$consecutiveFailures = 0

while ($true) {
    if (Test-Path $stopFile) {
        Write-Host "STOP file found -- exiting loop."
        break
    }

    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
    Write-Host "[$timestamp] running one product-manager pass..."

    Push-Location $RepoRoot
    $failed = $false
    try {
        & claude -p --plugin-dir $pluginDir --permission-mode acceptEdits $prompt
        if ($LASTEXITCODE -ne 0) {
            $failed = $true
            Write-Warning "[$timestamp] claude exited with code $LASTEXITCODE."
        }
    }
    catch {
        $failed = $true
        Write-Warning "[$timestamp] claude threw: $_"
    }
    finally {
        Pop-Location
    }

    if ($failed) {
        $consecutiveFailures++
        if ($consecutiveFailures -ge 3) {
            Write-Warning "[$timestamp] 3 consecutive failures -- writing STOP and exiting."
            New-Item -ItemType File -Path $stopFile -Force | Out-Null
            break
        }
    }
    else {
        $consecutiveFailures = 0
    }

    $backoff = [Math]::Min($IntervalSeconds * [Math]::Pow(2, [Math]::Max(0, $consecutiveFailures - 1)), 604800)
    $sleepFor = [int]$backoff
    Write-Host "sleeping ${sleepFor}s..."
    $remaining = $sleepFor
    while ($remaining -gt 0) {
        if (Test-Path $stopFile) { break }
        $chunk = [Math]::Min(30, $remaining)
        Start-Sleep -Seconds $chunk
        $remaining -= $chunk
    }
    if (Test-Path $stopFile) {
        Write-Host "STOP file found during sleep -- exiting loop."
        break
    }
}
