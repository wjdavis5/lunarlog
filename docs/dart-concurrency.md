# Local dart.exe/flutter_tester.exe concurrency cap

## The problem

`flutter test` spawns one test-worker process per CPU core by default (no explicit
`--concurrency` flag means Flutter picks that for you), and `dart run
tool/quality_gate.dart` runs a second, separate `flutter test --coverage` internally on
top of whatever a coder already ran directly. With several OpenCode coder subagents
verifying their own work at the same time — each in its own worktree, all on this one
desktop — dart.exe/flutter_tester.exe process count multiplies fast enough to exhaust
memory. This is a repeat of a previously-documented failure mode (`orchestrated-run-lessons`
project memory, from an earlier orchestrated run): five concurrent `flutter test
--coverage` runs hit ~99% commit charge, produced `uv_spawn` failures, and left orphaned
`flutter_tester.exe` processes that outlived their parent coders. It recurred live on
2026-09-11 once `#449` and a queue sweep opened up 55+ eligible issues at once and two
`opencode-<model>` coordinators each dispatched coders in parallel.

## The fix — two layers

1. **Fewer coders at once.** `.opencode/prompts/coordinator.md` caps each coordinator at
   2 parallel coder dispatches per iteration (not 3). Two `opencode-<model>` coordinators
   running concurrently is therefore at most 4 concurrent coders — the documented safe
   ceiling on this desktop.
2. **A hard process-count cap, not just fewer callers.** `tool/dart_concurrency_guard.ps1`
   polls the actual live `dart.exe` + `flutter_tester.exe` process count before launching
   a wrapped command, and waits (default: up to 30 min, then proceeds anyway with a
   warning rather than blocking forever) until the count is below 3. This is a real
   process-count check, not a cooperative slot file, so it catches load from any source —
   not just invocations that go through the guard.

   **It counts working processes only, never `dart language-server --lsp` (issue #768).**
   One LSP daemon is spawned per attached editor/agent session (`opencode.json` sets
   `"lsp": true`), so the daemon count scales with the number of coders — exactly the
   thing the cap is meant to manage. The original name-only `Get-Process -Name dart`
   match therefore saturated at five concurrent coders, the wait loop never saw headroom,
   and every invocation burned the full `MaxWaitSeconds` before running anyway: a
   30-minute stall *and* no throttling, which is strictly worse than no guard at all.
   Three coders sat blocked simultaneously before it was noticed, because the warning
   scrolls past inside a coder's tool output.

   To see what the guard counts and what it ignores, without running anything:

   ```
   pwsh -File tool/dart_concurrency_guard.ps1 -ShowCount -Command flutter
   ```

   If you ever see the `==== HEADROOM WAIT EXHAUSTED ====` warning, the run was **not**
   throttled — report it rather than treating it as a normal run.

   Both of the actual dart-process-spawning steps route through it, **locally, on
   Windows only** — CI runs one isolated job per runner, so the guard is pointless
   overhead there and CI's own commands are untouched:
   - `coder.md`'s own verification step: `flutter test` → `pwsh -File
     tool/dart_concurrency_guard.ps1 -Command flutter.bat -Arguments
     test,--concurrency=1` (also pinned to `--concurrency=1` so a single invocation never
     spawns more than one worker on top of the cap).
   - `tool/quality_gate.dart`'s internal `flutter test --coverage` call, gated on
     `Platform.isWindows && Platform.environment['CI'] != 'true'`.

## Why 3

Matches the figure the repo owner set directly during the 2026-09-11 incident, informed
by the documented "four concurrent coding agents is the safe ceiling" figure from the
`orchestrated-run-lessons` memory — 3 dart-family processes leaves headroom under that
ceiling for the desktop's other concurrent work (the opencode server itself, `gh`/`git`
calls, an interactive Claude Code session, etc.), rather than using the full ceiling on
test processes alone.

## Tuning

`tool/dart_concurrency_guard.ps1` takes `-MaxConcurrent`, `-PollSeconds`, and
`-MaxWaitSeconds` parameters if this figure ever needs to change — see the script's own
comment header. `-ShowCount` prints the current tally and exits.

Raising `-MaxConcurrent` is the right lever when more coders are deliberately in flight;
it is **not** the fix for a stall, since a stall now means the cap is genuinely binding on
real work. Free physical memory is the constraint the process count only approximates —
five LSP daemons alone held roughly 3.6 GB during the issue #768 incident — so check
memory too before assuming the cap is the problem.
