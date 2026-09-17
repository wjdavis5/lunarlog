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
    [int]$MaxWaitSeconds = 1800,
    # Issue #768: print what this script counts, and what it deliberately
    # ignores, then exit without running anything. The bug this diagnoses --
    # idle `dart language-server` daemons saturating the cap -- was invisible
    # from inside a stalled coder run, so make it one command to check.
    [switch]$ShowCount
)

$ErrorActionPreference = "Stop"

function Get-DartFamilyProcessCount {
    # Issue #768: count only processes doing Dart *work*, never idle editor
    # daemons. `dart language-server --lsp` is spawned once per attached
    # editor/agent session (opencode.json sets "lsp": true), so a name-only
    # match scaled with the number of coders -- five sessions put the count
    # permanently at or above MaxConcurrent, the wait loop never saw headroom,
    # and every invocation burned the full MaxWaitSeconds before running
    # anyway. That is worse than no guard: a 30-minute stall and no throttling.
    # An LSP daemon holds memory but is not competing for test-runner CPU.
    $names = @("dart", "dartaotruntime", "flutter_tester")
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            $names -contains $base -and $_.CommandLine -notmatch 'language-server'
        }
    if ($null -eq $procs) { return 0 }
    return @($procs).Count
}

if ($ShowCount) {
    $names = @("dart", "dartaotruntime", "flutter_tester")
    $all = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $names -contains [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }
    $working = @($all | Where-Object { $_.CommandLine -notmatch 'language-server' })
    $ignored = @($all | Where-Object { $_.CommandLine -match 'language-server' })
    Write-Host "dart_concurrency_guard: counting $($working.Count)/$MaxConcurrent working dart/flutter_tester processes"
    foreach ($p in $working) {
        $cmd = if ($p.CommandLine) { $p.CommandLine } else { $p.Name }
        Write-Host ("  count  pid={0,-7} {1}" -f $p.ProcessId, $cmd.Substring(0, [Math]::Min(110, $cmd.Length)))
    }
    Write-Host "dart_concurrency_guard: ignoring $($ignored.Count) idle language-server daemon(s) (issue #768)"
    foreach ($p in $ignored) {
        Write-Host ("  ignore pid={0,-7} {1}" -f $p.ProcessId, "dart language-server --lsp")
    }
    exit 0
}

$waited = 0
while ($true) {
    $count = Get-DartFamilyProcessCount
    if ($count -lt $MaxConcurrent) {
        break
    }
    if ($waited -ge $MaxWaitSeconds) {
        # Issue #768: this escape hatch is defensible, but it must never look
        # like success -- the old single Write-Warning scrolled past inside a
        # coder's tool output and nobody noticed three coders stalling at once.
        Write-Warning "dart_concurrency_guard: ==== HEADROOM WAIT EXHAUSTED ===="
        Write-Warning "dart_concurrency_guard: waited ${MaxWaitSeconds}s and still see $count/$MaxConcurrent working dart/flutter_tester processes. Running '$Command' ANYWAY -- this run is NOT throttled and may contend for the desktop."
        Write-Warning "dart_concurrency_guard: if you are an agent, report this rather than treating the run as normal."
        break
    }
    Write-Host "dart_concurrency_guard: $count/$MaxConcurrent dart/flutter_tester processes running, waiting ${PollSeconds}s for headroom before starting '$Command'..."
    Start-Sleep -Seconds $PollSeconds
    $waited += $PollSeconds
}

$flatArgs = @()
foreach ($arg in $Arguments) {
    if ($arg -match ',') {
        $flatArgs += $arg.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries)
    } else {
        $flatArgs += $arg
    }
}

& $Command @flatArgs
exit $LASTEXITCODE
