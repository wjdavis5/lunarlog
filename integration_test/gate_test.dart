/// U7 gate integration matrix (R7, flow F3, AE4), run with a fake
/// authenticator: `flutter test integration_test/gate_test.dart` (which,
/// on this Flutter toolchain, routes any file under `integration_test/`
/// to a connected device) — CI runs it on a real iOS Simulator (the
/// "iOS Simulator tests" job). Real biometrics are verified manually
/// on-device later (U9 checklist).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/domain/gate/app_gate.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';

class FakeGate implements AppGate {
  FakeGate({this.grantNext = true});

  bool grantNext;
  int requests = 0;

  /// Fired from inside [requestAccess], before it answers: the real
  /// credential prompt reports its own lifecycle transition while it is
  /// up (iOS sends `inactive` for Face ID). Reproducing that is what
  /// issue #65 needs (#65 U3). Independent of the widget-test fake in
  /// `test/ui/gate_test.dart`, which this suite does not import.
  void Function()? onPrompt;

  @override
  bool get requiresUnlock => true;

  /// Issue #534: always true here — a credential is enrolled in every
  /// scenario this suite exercises.
  @override
  Future<bool> canAuthenticate() async => true;

  @override
  Future<bool> requestAccess() async {
    requests++;
    onPrompt?.call();
    return grantNext;
  }
}

class FakeInactivityTimer implements InactivityTimer {
  FakeInactivityTimer(this.delay, this._onTimeout);

  /// The delay this timer was created with. The controller creates three
  /// kinds of timer through one factory — the inactivity countdown, the
  /// system-UI window deadline, and the settling tail (#65 U1) — and their
  /// durations are what tell them apart. Mirrors the host twin in
  /// `test/ui/gate_test.dart`, which `fireWithDelay` below depends on.
  final Duration delay;
  final void Function() _onTimeout;
  bool active = true;

  void fire() {
    if (!active) return;
    active = false;
    _onTimeout();
  }

  @override
  void cancel() => active = false;
}

class FakeInactivityTimers {
  final created = <FakeInactivityTimer>[];

  InactivityTimer create(Duration delay, VoidCallback onTimeout) {
    final timer = FakeInactivityTimer(delay, onTimeout);
    created.add(timer);
    return timer;
  }

  /// Fires every active timer created with [delay]; the others stay armed,
  /// so a test can expire the settling tail without also expiring the
  /// inactivity countdown or the window deadline. The host twin's Harness
  /// does exactly this after every unlock — see
  /// [expireSystemUiSettleTail].
  void fireWithDelay(Duration delay) {
    for (final timer in List.of(created)) {
      if (timer.delay == delay) timer.fire();
    }
  }

  InactivityTimerFactory get factory => create;

  void fireActive() {
    for (final timer in List.of(created)) {
      timer.fire();
    }
  }

  bool get anyActive => created.any((timer) => timer.active);
}

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<LunarLogDatabase> seededDb({String? activeOfTwo}) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final profiles = DriftProfilesRepository(db.storage);
    final a = await profiles.create(displayName: 'Alice', isMinor: false);
    final b = await profiles.create(displayName: 'Barb', isMinor: true);
    await DriftSettingsStore(db.storage).set(SettingsKeys.lastActiveProfile,
        activeOfTwo == null ? a.id : (activeOfTwo == 'a' ? a.id : b.id));
    return db;
  }

  /// Issue #121: a manual `handleAppLifecycleStateChanged` walk into
  /// `hidden`/`paused` is a framework-level simulation — nothing is sent to
  /// the OS — but `SchedulerBinding.handleAppLifecycleStateChanged` still
  /// flips `framesEnabled` to false for exactly those two states (it stays
  /// true for `inactive`, which is why the issue #65 test never hung).
  ///
  /// That flip is invisible host-mode, where `pump()` drives
  /// `handleBeginFrame`/`handleDrawFrame` directly. On a real device,
  /// `IntegrationTestWidgetsFlutterBinding` is a *live* binding: `pump()`
  /// waits for a real engine frame, `scheduleFrame()` is now a no-op, and
  /// the binding's default test timeout is `Timeout.none` — so the first
  /// pump after a `paused`/`hidden` step waited on a frame that could never
  /// be requested and hung the run forever (the #121 failure).
  ///
  /// `scheduleForcedFrame()` is the framework's own escape hatch for this —
  /// documented as "ignores the [lifecycleState] when scheduling a frame" —
  /// and, because the app was never really backgrounded, the engine is
  /// still foreground and delivers the frame. A no-op wherever frames are
  /// already enabled, so the resumed/inactive path is unchanged.
  void forceFrameIfBackgrounded(WidgetTester tester) {
    if (!tester.binding.framesEnabled) {
      tester.binding.scheduleForcedFrame();
    }
  }

  Future<void> disposeDb(WidgetTester tester, LunarLogDatabase db) async {
    // Issue #121: callers may still be in a frames-disabled state here (the
    // inactivity-timeout test ends on `hidden`), and on a live device
    // binding each pump in that state needs its own forced frame.
    forceFrameIfBackgrounded(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    forceFrameIfBackgrounded(tester);
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  }

  /// Walks the legal lifecycle path (resumed ↔ inactive ↔ hidden ↔ paused);
  /// the binding asserts on direct jumps like paused → resumed.
  Future<void> transitionTo(
      WidgetTester tester, AppLifecycleState target) async {
    const path = [
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];
    final start = tester.binding.lifecycleState ?? AppLifecycleState.resumed;
    var from = path.indexOf(start);
    final to = path.indexOf(target);
    assert(from >= 0 && to >= 0, 'unsupported transition $start -> $target');
    while (from != to) {
      from += to > from ? 1 : -1;
      tester.binding.handleAppLifecycleStateChanged(path[from]);
      // Issue #121: every step landing in hidden/paused must force the
      // frame the following pump waits for, or a real-device run hangs.
      forceFrameIfBackgrounded(tester);
      await tester.pump();
    }
    forceFrameIfBackgrounded(tester);
    await tester.pumpAndSettle();
  }

  /// The binding's lifecycle state persists across tests in a suite; every
  /// test starts from a clean foreground.
  Future<void> ensureResumed(WidgetTester tester) async {
    if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
      await transitionTo(tester, AppLifecycleState.resumed);
    }
  }

  /// The drift NativeDatabase answers from a worker isolate, so repository /
  /// settings-watch responses arrive as real event-loop events. A bare
  /// pumpAndSettle can exit before the last hop (e.g. the payload seam's
  /// selectProfile → watch → rebuild) lands; give the loop turns to drain.
  Future<void> drainIsolateTraffic(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
    }
  }

  /// Issue #121's second finding (from the first real-simulator CI run):
  /// every unlock — cold start's automatic one included — opens a
  /// system-UI window for the credential prompt and leaves a 3-second
  /// settling tail behind it (#65 KTD2a), during which a departure covers
  /// content but does NOT lock, and the window-deadline timer stays armed.
  /// On the live device binding those are 3 wall-clock seconds the test's
  /// assertions would race (the first CI run failed exactly there: zero
  /// lock-screens after transitionTo(paused), and `timers.anyActive` true
  /// where the toggle-off half expected false). The host twin expires the
  /// tail deterministically after every unlock — Harness.pump's
  /// `fireWithDelay(kSystemUiSettleTimeout)` — because a fake clock never
  /// reaches 3s on its own; do the same here, then drain so the reconcile
  /// and the settings watch both land before the caller asserts.
  Future<void> expireSystemUiSettleTail(
    WidgetTester tester,
    FakeInactivityTimers timers,
  ) async {
    timers.fireWithDelay(kSystemUiSettleTimeout);
    await tester.pump();
    await tester.pumpAndSettle();
    await drainIsolateTraffic(tester);
  }

  Future<void> unlockViaButton(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('unlock-button')));
    await tester.pump();
    await tester.pumpAndSettle();
    await drainIsolateTraffic(tester);
  }

  testWidgets('cold start requires the gate; declined credential shows no '
      'data and never opens the database', (tester) async {
    final db = await seededDb();
    final gate = FakeGate()..grantNext = false;
    var dbOpenerCalls = 0;

    await tester.pumpWidget(LunarLogRoot(
      gate: gate,
      dbOpener: () async {
        dbOpenerCalls++;
        return db;
      },
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('lock-screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('lock-denied-message')), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Barb'), findsNothing);
    expect(dbOpenerCalls, 0, reason: 'AE4: declined never decrypts');
    await disposeDb(tester, db);
  });

  testWidgets('retry loop: repeated declines stay locked, one grant unlocks '
      'into the stored active profile', (tester) async {
    final db = await seededDb();
    final gate = FakeGate()..grantNext = false;
    var dbOpenerCalls = 0;

    await tester.pumpWidget(LunarLogRoot(
      gate: gate,
      dbOpener: () async {
        dbOpenerCalls++;
        return db;
      },
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('unlock-button')));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lock-screen')), findsOneWidget,
          reason: 'decline $i keeps the app locked');
      expect(find.text('Alice'), findsNothing);
      expect(dbOpenerCalls, 0);
    }

    gate.grantNext = true;
    await unlockViaButton(tester);

    expect(find.byKey(const ValueKey('lock-screen')), findsNothing);
    expect(find.text('Alice'), findsOneWidget);
    expect(dbOpenerCalls, 1);
    await disposeDb(tester, db);
  });

  testWidgets('issue #65: the credential prompt reporting its own focus '
      'loss still unlocks into the data', (tester) async {
    // The field defect, end to end: Face ID succeeds, and the lock screen
    // used to stay up with no error because the prompt's own `inactive`
    // report was read as the operator leaving.
    //
    // Cold start presents the credential automatically (app_lifecycle.dart's
    // initState postFrameCallback, F3) -- there is no button tap before the
    // first attempt, so `onPrompt` must be wired *before* pumpWidget to be
    // in place when that automatic attempt fires. An earlier version of
    // this test asserted a lock-screen was present immediately after the
    // first pump/pumpAndSettle, before wiring onPrompt or tapping anything;
    // that assumed cold start waits for an explicit tap, which it does not
    // (and never has, since issue #65's own fix) -- the assertion only
    // looked correct on host-mode's own timing and was never actually
    // exercised against a real device until this suite ran on one.
    final db = await seededDb();
    final gate = FakeGate();
    gate.onPrompt = () => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);

    await tester.pumpWidget(LunarLogRoot(
      gate: gate,
      dbOpener: () async => db,
    ));
    await tester.pump();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await drainIsolateTraffic(tester);

    expect(find.byKey(const ValueKey('lock-screen')), findsNothing,
        reason: 'the system accepted the credential');
    expect(find.byKey(const ValueKey('lock-denied-message')), findsNothing,
        reason: 'nothing was declined');
    expect(find.text('Alice'), findsOneWidget);
    await disposeDb(tester, db);
  });

  testWidgets('backgrounding re-locks; warm resume gates before data '
      'returns', (tester) async {
    final db = await seededDb();
    final gate = FakeGate();
    // Injected so expireSystemUiSettleTail can expire the cold-start
    // prompt's settling tail deterministically (issue #121).
    final timers = FakeInactivityTimers();

    await tester.pumpWidget(LunarLogRoot(
      gate: gate,
      dbOpener: () async => db,
      inactivityTimerFactory: timers.factory,
    ));
    await tester.pump();
    await tester.pumpAndSettle();
    await expireSystemUiSettleTail(tester, timers);
    expect(find.text('Alice'), findsOneWidget);

    await transitionTo(tester, AppLifecycleState.paused);
    expect(find.byKey(const ValueKey('lock-screen')), findsOneWidget);
    expect(find.text('Alice'), findsNothing);

    await transitionTo(tester, AppLifecycleState.resumed);
    expect(find.byKey(const ValueKey('lock-screen')), findsOneWidget,
        reason: 'warm resume still gated');

    await unlockViaButton(tester);
    expect(find.text('Alice'), findsOneWidget);
    await disposeDb(tester, db);
  });

  testWidgets('inactivity timeout re-locks by default; the persisted toggle '
      'disables it (background re-lock unaffected)', (tester) async {
    final timers = FakeInactivityTimers();

    // Default on: the armed timeout locks.
    var db = await seededDb();
    await tester.pumpWidget(LunarLogRoot(
      gate: FakeGate(),
      dbOpener: () async => db,
      inactivityTimerFactory: timers.factory,
    ));
    await tester.pump();
    await tester.pumpAndSettle();
    await expireSystemUiSettleTail(tester, timers);
    expect(find.text('Alice'), findsOneWidget);
    expect(timers.anyActive, isTrue);

    timers.fireActive();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lock-screen')), findsOneWidget);
    await disposeDb(tester, db);
    timers.created.clear();

    // Toggle off (persisted): no timeout re-lock.
    db = await seededDb();
    await DriftSettingsStore(db.storage)
        .set(SettingsKeys.relockEnabled, 'false');
    await ensureResumed(tester);
    await tester.pumpWidget(LunarLogRoot(
      gate: FakeGate(),
      dbOpener: () async => db,
      inactivityTimerFactory: timers.factory,
    ));
    await tester.pump();
    await tester.pumpAndSettle();
    // Expiring the settle tail also lets the settings watch's 'false'
    // emission cancel whatever the reconcile armed, so anyActive is
    // deterministically false here rather than racing the drift isolate
    // (issue #121: the first CI run found the window-deadline timer still
    // armed from the never-expired tail).
    await expireSystemUiSettleTail(tester, timers);
    expect(timers.anyActive, isFalse);

    timers.fireActive();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lock-screen')), findsNothing,
        reason: 'timeout re-lock disabled by the toggle');

    // Background re-lock still applies with the toggle off.
    await transitionTo(tester, AppLifecycleState.hidden);
    expect(find.byKey(const ValueKey('lock-screen')), findsOneWidget);
    // Issue #121 suite hygiene: the binding's lifecycle state persists
    // across tests in a suite (see ensureResumed), and the next test's very
    // first pumpWidget would hang a real-device run if it inherited the
    // frames-disabled `hidden` state. Return to the foreground like every
    // other test in this file.
    await ensureResumed(tester);
    await disposeDb(tester, db);
  });

  testWidgets('simulated launch payload routes through the gate, then opens '
      "the firing profile's overview", (tester) async {
    final db = await seededDb(activeOfTwo: 'a');
    final profiles = await DriftProfilesRepository(db.storage).list();
    final barbId = profiles
        .firstWhere((profile) => profile.displayName == 'Barb')
        .id;
    final gate = FakeGate()..grantNext = false;

    await tester.pumpWidget(LunarLogRoot(
      gate: gate,
      dbOpener: () async => db,
      launchProfileId: barbId,
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('lock-screen')), findsOneWidget);
    expect(find.text('Barb'), findsNothing,
        reason: 'the payload waits behind the gate');
    expect(find.byType(OverviewPanel), findsNothing);

    gate.grantNext = true;
    await unlockViaButton(tester);

    expect(gate.requests, greaterThanOrEqualTo(1),
        reason: 'the payload routed through the gate');
    expect(find.text('Barb'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
    expect(find.byType(OverviewPanel), findsOneWidget);
    await disposeDb(tester, db);
  });
}
