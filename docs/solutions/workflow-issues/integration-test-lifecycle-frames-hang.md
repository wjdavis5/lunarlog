---
title: Fix integration-test hangs when driving the binding into paused/hidden on a real device
date: '2026-09-14'
category: workflow-issues
module: gate integration tests
problem_type: testing_hang
component: integration_testing
severity: high
applies_when:
  - an integration test calls handleAppLifecycleStateChanged with AppLifecycleState.paused or hidden
  - "a `flutter test integration_test/... -d <device>` run hangs forever on one specific test"
  - the same test passes host-mode (or in test/ui/ widget tests) without any change
  - an unlocked-app assertion fails only on a real device (no lock after backgrounding, an unexpected armed timer) — the credential prompt's 3-second settling tail suppressing re-locks
tags:
  - integration-test
  - app-lifecycle
  - scheduleForcedFrame
  - framesEnabled
  - ios-simulator
  - issue-121
related_components:
  - integration_test/gate_test.dart
  - test/ui/gate_lifecycle_frames_test.dart
  - .github/workflows/ci.yml
---

# Fix integration-test hangs when driving the binding into paused/hidden on a real device

## Context

`integration_test/gate_test.dart`'s `transitionTo` helper walks the widget-test binding through lifecycle states with `tester.binding.handleAppLifecycleStateChanged(...)`. Host-mode this is a pure Dart notification. On a real iOS Simulator (`flutter test integration_test/gate_test.dart -d <udid>`, the CI "iOS Simulator tests" job), the two tests that reach `paused`/`hidden` ("backgrounding re-locks..." and "inactivity timeout re-locks...") hung forever — execution reached the transition and never returned, with no timeout, because `IntegrationTestWidgetsFlutterBinding.defaultTestTimeout` is `Timeout.none`. CI originally sidestepped it with a `--name` filter running only the four safe tests.

## Problem

The original diagnosis (issue #121) assumed the manual binding call was triggering genuine OS-level app suspension. Source-reading the pinned Flutter 3.47.2 shows that is not what happens — `handleAppLifecycleStateChanged` never sends anything to the engine, so the OS is uninvolved. The actual mechanism is entirely framework-side:

1. `SchedulerBinding.handleAppLifecycleStateChanged` (`packages/flutter/lib/src/scheduler/binding.dart`) calls `_setFramesEnabledState(false)` for exactly `hidden`, `paused`, and `detached` — **not** for `inactive` (which is why the issue #65 test, which only touches `inactive`, never hung).
2. `IntegrationTestWidgetsFlutterBinding` extends `LiveTestWidgetsFlutterBinding`, whose `pump()` requests a real engine frame via `scheduleFrame()` and then awaits it.
3. `scheduleFrame()` returns immediately when `!framesEnabled`. No frame can ever be requested, the awaited completer never fires, and the run hangs permanently.

On the host (`AutomatedTestWidgetsFlutterBinding`), `pump()` calls `handleBeginFrame`/`handleDrawFrame` directly and never waits on the engine, so the same code passes — the hang is invisible until the file runs against a device. (On this toolchain `flutter test` routes any file under `integration_test/` to a connected device, so there is no host-mode escape for that file at all; see `_shouldRunAsIntegrationTests` in the flutter tool.)

## Solution

Use `SchedulerBinding.scheduleForcedFrame()` — the framework's own documented escape hatch ("ignores the [lifecycleState] when scheduling a frame"; used by the framework itself for rotation-while-screen-off). Because the app was never really backgrounded, the engine is still foreground and delivers the frame, so the live pump completes.

A helper in `integration_test/gate_test.dart`:

```dart
void forceFrameIfBackgrounded(WidgetTester tester) {
  if (!tester.binding.framesEnabled) {
    tester.binding.scheduleForcedFrame();
  }
}
```

called before **every** pump that may run in a frames-disabled state: each `transitionTo` step, `transitionTo`'s final settle, and `disposeDb`'s `pumpWidget`/`pump` pair (each pump consumes exactly one frame and the live binding does not re-request after a pumped frame). Two non-obvious traps:

- **Suite-state leakage.** The binding's lifecycle state persists across tests in a file. A test ending on `hidden` leaves the *next* test's first `pumpWidget` in a frames-disabled state — hang again. Every test must return to `resumed` before finishing (`ensureResumed`).
- **Host-mode parity.** `scheduleForcedFrame` is a no-op wherever frames are already enabled, and on the automated host binding it just sets `hasScheduledFrame`, so the host path is unchanged.

`test/ui/gate_lifecycle_frames_test.dart` pins the whole mechanism host-mode (frames disabled at `hidden`/`paused`, a plain pump renders nothing then, `scheduleForcedFrame` + pump renders, `inactive`/`resumed` re-enable) so a future SDK change that re-breaks the simulator run fails fast in the host suite instead of as a stuck CI job.

## Second finding: the settle-tail race (first real-simulator CI run)

Un-hanging the file exposed a second, behavioral layer: both lifecycle-driving tests then **failed their assertions** on the simulator (`4 tests passed, 2 failed`, in bounded time). Every unlock — cold start's automatic one included — opens a system-UI window for the credential prompt and leaves a 3-second settling tail behind it (`kSystemUiSettleTimeout`, #65 KTD2a), during which a departure covers content but does **not** lock (`_suppressingLock`), and the window-deadline timer stays armed. The host twin never sees this because `test/ui/gate_test.dart`'s `Harness.pump`/`unlockViaButton` expire that tail deterministically after every unlock (`timers.fireWithDelay(kSystemUiSettleTimeout)`) — a fake clock never reaches 3s on its own. The integration file's helpers did neither, so on the live device its assertions raced 3 wall-clock seconds of suppression:

- "backgrounding re-locks...": `transitionTo(paused)` landed inside the tail → departure suppressed → `Found 0 lock-screen`.
- "inactivity timeout...": the toggle-off half found `timers.anyActive` true — the never-expired tail's window-deadline timer (and, depending on ordering, an inactivity timer the still-in-flight `relockEnabled` watch emission had not yet cancelled).

The fix mirrors the twin: the integration file's `FakeInactivityTimer` now records its `delay` (the duration is what tells the controller's three timer kinds apart), `FakeInactivityTimers` gains `fireWithDelay`, and a new `expireSystemUiSettleTail(tester, timers)` helper (fire the tail, pump, settle, `drainIsolateTraffic`) runs after every unlock whose subsequent assertions depend on the steady-state unlocked app. Verified by re-running the file's exact content as a host widget test (same file minus the `IntegrationTestWidgetsFlutterBinding.ensureInitialized` line): with the expiry calls removed, "backgrounding re-locks" fails on host exactly as it did on the simulator; with them, all six pass.

## Verification

- `flutter test test/ui/gate_lifecycle_frames_test.dart` (mechanism pin)
- Host mirror of the integration file (see above): 6/6 with the fix, test 1 fails without it — the failure mode is not device-specific, only previously unobservable because the file could not run host-mode at all on this toolchain.
- CI "iOS Simulator tests" job runs the full `integration_test/gate_test.dart` (filter removed); the step carries `timeout-minutes: 15` so any regression fails in bounded time rather than parking the job.
