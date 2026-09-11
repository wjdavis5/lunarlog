<#
.SYNOPSIS
  Wait for headroom, then run a command -- caps how many dart.exe/flutter_tester.exe
  processes are running system-wide at once.

.DESCRIPTION
  `flutter test` and `dart run tool/quality_gate.dart` (which itself runs `flutter test
  --coverage`) spawn Flutter's own test-worker processes on top of the dart.exe runner
  process itself. With several OpenCode coder subagents verifying their work at the same
  time -- each running these commands in its own worktree -- dart.exe/flutter_tester.exe
  count multiplies fast and can exhaust this desktop's memory (documented in the
  `orchestrated-run-lessons` project memory: five concurrent `flutter test --coverage`
  runs hit 99% commit charge and produced orphaned flutter_tester.exe processes that
  outlive their parents).

  This wrapper polls the actual live process count before launching -- not a cooperative
  slot file, a real count of what's running, so it catches load from any source, not just
  invocations that go through this script. `coder.md`'s verification commands and
  `tool/quality_gate.dart`'s internal `flutter test --coverage` call both route through
  this so the cap is enforced everywhere a coder can spawn one of these processes.

.PARAMETER Command
  The executable to run once headroom is available (e.g. "flutter", "flutter.bat", "dart").

.PARAMETER Arguments
  Arguments to pass to Command.

.PARAMETER MaxConcurrent
  Maximum combined dart.exe + flutter_tester.exe process count allowed before this script
  launches its own. Default 3 (the documented safe figure for this desktop; see
  `docs/dart-concurrency.md`).

.PARAMETER PollSeconds
  How often to re-check the process count while waiting. Default 5.

.PARAMETER MaxWaitSeconds
  Give up waiting and launch anyway after this long, rather than blocking a coder forever
  on a count that never drops (e.g. a leaked/orphaned process from an earlier run that
  nothing will ever clean up). Default 1800 (30 min). Logs a warning when this triggers --
  that is itself a signal worth noticing, not something to silently swallow.

.EXAMPLE
  pwsh -File tool/dart_concurrency_guard.ps1 -Command flutter -Arguments test,--concurrency=1

.EXAMPLE
  pwsh -File tool/dart_concurrency_guard.ps1 -Command dart -Arguments run,tool/quality_gate.dart
#>

param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string[]]$Arguments = @(),
    [int]$MaxConcurrent = 3,
    [int]$PollSeconds = 5,
    [int]$MaxWaitSeconds = 1800
)

$ErrorActionPreference = "Stop"

function Get-DartFamilyProcessCount {
    $names = @("dart", "flutter_tester")
    $procs = Get-Process -Name $names -ErrorAction SilentlyContinue
    if ($null -eq $procs) { return 0 }
    return @($procs).Count
}

$waited = 0
while ($true) {
    $count = Get-DartFamilyProcessCount
    if ($count -lt $MaxConcurrent) {
        break
    }
    if ($waited -ge $MaxWaitSeconds) {
        Write-Warning "dart_concurrency_guard: waited ${MaxWaitSeconds}s for headroom (still $count/$MaxConcurrent dart/flutter_tester processes running) -- proceeding anyway rather than blocking forever."
        break
    }
    Write-Host "dart_concurrency_guard: $count/$MaxConcurrent dart/flutter_tester processes running, waiting ${PollSeconds}s for headroom before starting '$Command'..."
    Start-Sleep -Seconds $PollSeconds
    $waited += $PollSeconds
}

& $Command @Arguments
exit $LASTEXITCODE
