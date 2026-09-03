/// Widget tests for U7: the device-credential gate (R7, flow F3, AE4) —
/// lock-first startup, decline/retry, background re-lock, inactivity
/// re-lock with its settings toggle, snapshot suppression, the launch
/// payload seam, and the fail-closed startup screen that replaces U4's
/// basic StartupErrorApp. The authenticator is always a fake; real
/// biometrics are verified manually on-device (U9 checklist).
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/db/errors.dart';
import 'package:lunarlog/data/gate/app_gate.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/sync/sync_transport.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:lunarlog/ui/profiles/profile_home_gate.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_settings_store.dart';
import '../support/fake_sync_engine.dart';
import '../support/fake_sync_transport.dart';

class FakeGate implements AppGate {
  FakeGate({this.grantNext = true, this.requiresUnlock = true});

  bool grantNext;
  int requests = 0;

  /// When set, the next prompt stays up until this completes (its value is
  /// the answer), so a test can act while the credential prompt is showing
  /// (#2 U5; KTD5). Consumed by that request.
  Completer<bool>? holdNext;

  /// Fired from inside [requestAccess], before it answers: the real system
  /// credential prompt reports its own lifecycle transition while it is up
  /// (iOS sends `inactive` for Face ID; Android's passcode fallback
  /// launches a separate activity and sends `paused`). Reproducing *that*
  /// — rather than a lifecycle event next to the prompt — is what issue #65
  /// needs (#65 U3).
  ///
  /// Report transitions from here with
  /// `controller.didChangeAppLifecycleState(...)` or
  /// `tester.binding.handleAppLifecycleStateChanged(...)` directly; never
  /// the pumping [transitionTo] driver, which trips a `TestAsyncUtils`
  /// guarded-function conflict when called from inside an awaited prompt.
  void Function()? onPrompt;

  @override
  bool requiresUnlock;

  @override
  Future<bool> requestAccess() async {
    requests++;
    onPrompt?.call();
    final hold = holdNext;
    if (hold != null) {
      holdNext = null;
      return hold.future;
    }
    return grantNext;
  }
}

class FakeInactivityTimer implements InactivityTimer {
  FakeInactivityTimer(this.delay, this._onTimeout);

  /// The delay this timer was created with. The controller now creates
  /// three kinds through one factory — the inactivity countdown, the
  /// system-UI window deadline, and the settling tail (#65 U1) — and their
  /// durations are what tell them apart.
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

  /// Fires every active timer created with [delay]; the others are left
  /// armed, so a test can expire the window deadline without also
  /// expiring the inactivity countdown, or vice versa.
  void fireWithDelay(Duration delay) {
    for (final timer in List.of(created)) {
      if (timer.delay == delay) timer.fire();
    }
  }

  InactivityTimerFactory get factory => create;

  /// Fires every timer this factory ever created; cancelled ones are no-ops,
  /// so only the currently armed one can lock.
  void fireActive() {
    for (final timer in List.of(created)) {
      timer.fire();
    }
  }

  bool get anyActive => created.any((timer) => timer.active);
}

class Harness {
  Harness(this.tester, {Future<void> Function(LunarLogDatabase db)? seed})
      : db = LunarLogDatabase(NativeDatabase.memory()) {
    if (seed != null) {
      pendingSeed = seed(db);
    }
  }

  final WidgetTester tester;
  final FakeGate gate = FakeGate();
  final FakeInactivityTimers timers = FakeInactivityTimers();
  final LunarLogDatabase db;
  Future<void>? pendingSeed;
  int dbOpenerCalls = 0;

  Future<void> pump({
    bool grant = true,
    String? launchProfileId,
    Duration inactivityTimeout = kDefaultInactivityTimeout,
    AuthService? authService,
    SyncTransport? syncTransport,
    SyncEngineBuilder syncEngineBuilder = defaultSyncEngineBuilder,
  }) async {
    await pendingSeed;
    // The binding's lifecycle state persists across tests in a suite; every
    // test starts from a clean foreground.
    if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
      await transitionTo(tester, AppLifecycleState.resumed);
    }
    gate.grantNext = grant;
    await tester.pumpWidget(LunarLogRoot(
      gate: gate,
      dbOpener: () async {
        dbOpenerCalls++;
        return db;
      },
      launchProfileId: launchProfileId,
      inactivityTimeout: inactivityTimeout,
      inactivityTimerFactory: timers.factory,
      authService: authService,
      syncTransport: syncTransport,
      syncEngineBuilder: syncEngineBuilder,
    ));
    await tester.pump();
    await tester.pumpAndSettle();
  }

Future<void> unlockViaButton() async {
  await tester.tap(find.byKey(const ValueKey('unlock-button')));
  await tester.pump();
  await tester.pumpAndSettle();
  await drainIsolateTraffic(tester);
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

/// Walks the legal lifecycle path (resumed ↔ inactive ↔ hidden ↔ paused);
/// the binding asserts on direct jumps like paused → resumed.
Future<void> transitionTo(WidgetTester tester, AppLifecycleState target) async {
  const path = [
    AppLifecycleState.resumed,
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  final start = tester.binding.lifecycleState ?? AppLifecycleState.resumed;
  var from = path.indexOf(start);
  var to = path.indexOf(target);
  assert(from >= 0 && to >= 0, 'unsupported transition $start -> $target');
  while (from != to) {
    from += to > from ? 1 : -1;
    tester.binding.handleAppLifecycleStateChanged(path[from]);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> background(AppLifecycleState state) =>
    transitionTo(tester, state);

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  }
}

Finder get lockScreen => find.byKey(const ValueKey('lock-screen'));
Finder get deniedMessage => find.byKey(const ValueKey('lock-denied-message'));
Finder get privacyCover => find.byKey(const ValueKey('privacy-cover'));

/// Seeds two profiles; [activeIndex] 0/1 sets the stored last-active id.
Future<void> seedTwoProfiles(LunarLogDatabase db, int activeIndex) async {
  final profiles = DriftProfilesRepository(db.storage);
  final a = await profiles.create(displayName: 'Alice', isMinor: false);
  final b = await profiles.create(displayName: 'Barb', isMinor: true);
  await DriftSettingsStore(db.storage).set(
      SettingsKeys.lastActiveProfile, activeIndex == 0 ? a.id : b.id);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('settled settings naming: relock toggle key', () {
    expect(SettingsKeys.relockEnabled, 'relock_enabled');
  });

  test('default inactivity timeout is two minutes and relock defaults on',
      () {
    expect(kDefaultInactivityTimeout, const Duration(minutes: 2));
    final controller = GateController(gate: FakeGate());
    addTearDown(controller.dispose);
    expect(controller.relockEnabled, isTrue,
        reason: 'auto-relock default ON (fail closed)');
  });

  group('the credential decides, not the lifecycle (#65 U1; KTD1, KTD2a)',
      () {
    testWidgets('a granted credential unlocks even though the prompt '
        'reported inactive while it was up (issue #65)', (tester) async {
      final gate = FakeGate(requiresUnlock: true);
      final timers = FakeInactivityTimers();
      final controller = GateController(
          gate: gate, inactivityTimerFactory: timers.factory);
      addTearDown(controller.dispose);
      expect(controller.locked, isTrue);

      gate.grantNext = true;
      // iOS reports `inactive` for the Face ID prompt itself.
      gate.onPrompt =
          () => controller.didChangeAppLifecycleState(
              AppLifecycleState.inactive);

      await controller.unlock();

      expect(controller.locked, isFalse,
          reason: 'the system accepted the credential; that decides');
      expect(controller.lastAttemptDenied, isFalse,
          reason: 'nothing was declined, so no denial message');
    });

    testWidgets('a granted credential unlocks even though the prompt '
        'reported hidden then paused while it was up', (tester) async {
      // Android's device-credential fallback launches a separate activity
      // through KeyguardManager, genuinely backgrounding the app.
      final gate = FakeGate(requiresUnlock: true);
      final timers = FakeInactivityTimers();
      final controller = GateController(
          gate: gate, inactivityTimerFactory: timers.factory);
      addTearDown(controller.dispose);

      gate.grantNext = true;
      gate.onPrompt = () {
        controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
        controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
        controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      };

      await controller.unlock();

      expect(controller.locked, isFalse);
      expect(controller.lastAttemptDenied, isFalse);
    });

    testWidgets('a departure delivered after the credential result does not '
        're-lock the app', (tester) async {
      // The prompt's dismissal can report `inactive` after the result has
      // already been handed back; `lock()` never sets the denial flag, so
      // this produces the same screen as a discarded grant.
      final gate = FakeGate(requiresUnlock: true);
      final timers = FakeInactivityTimers();
      final controller = GateController(
          gate: gate, inactivityTimerFactory: timers.factory);
      addTearDown(controller.dispose);

      gate.grantNext = true;
      gate.onPrompt =
          () => controller.didChangeAppLifecycleState(
              AppLifecycleState.inactive);
      await controller.unlock();
      expect(controller.locked, isFalse);
      expect(controller.systemUiActive, isTrue,
          reason: 'the window saw a departure, so it settles rather than '
              'closing with the credential result');

      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);

      expect(controller.locked, isFalse,
          reason: 'still settling; this is the same prompt dismissing');
      expect(controller.obscured, isTrue,
          reason: 'covered regardless — the window never suppresses that');
    });

    testWidgets('a declined credential still leaves the app locked with the '
        'denial message, whatever the lifecycle reported', (tester) async {
      final gate = FakeGate(requiresUnlock: true);
      final timers = FakeInactivityTimers();
      final controller = GateController(
          gate: gate, inactivityTimerFactory: timers.factory);
      addTearDown(controller.dispose);

      gate.grantNext = false;
      gate.onPrompt =
          () => controller.didChangeAppLifecycleState(
              AppLifecycleState.inactive);

      await controller.unlock();

      expect(controller.locked, isTrue);
      expect(controller.lastAttemptDenied, isTrue);
    });

    testWidgets('reauthenticate reports a granted credential even though the '
        'prompt reported inactive while it was up', (tester) async {
      final gate = FakeGate(requiresUnlock: true);
      final timers = FakeInactivityTimers();
      final controller = GateController(
          gate: gate, inactivityTimerFactory: timers.factory);
      addTearDown(controller.dispose);
      gate.grantNext = true;
      await controller.unlock();
      expect(controller.locked, isFalse);

      gate.grantNext = true;
      // The real sequence: the prompt reports `inactive` as it appears and
      // the app is back by the time the credential is answered.
      gate.onPrompt = () {
        controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      };

      expect(await controller.reauthenticate(), isTrue,
          reason: 'the add-a-method action must not be cancelled by the '
              'credential prompt reporting its own focus loss');
      expect(controller.locked, isFalse,
          reason: 'the operator is back, so nothing is replayed and a '
              're-auth never changes the lock state itself');
    });
  });

  group('the system-UI window and its bound (#65 U1; KTD2, KTD5, KTD9)', () {
    /// The window deadline defaults to the same two minutes as the
    /// inactivity timeout, so firing by delay would fire both and a broken
    /// deadline would still look locked. These tests give it a distinct
    /// duration to isolate the mechanism they are named for.
    const windowDeadline = Duration(seconds: 90);

    /// A controller with fake timers, ready for a window.
    (GateController, FakeGate, FakeInactivityTimers) unlockedRig() {
      final gate = FakeGate(requiresUnlock: true);
      final timers = FakeInactivityTimers();
      final controller = GateController(
        gate: gate,
        inactivityTimerFactory: timers.factory,
        systemUiDeadline: windowDeadline,
      );
      return (controller, gate, timers);
    }

    testWidgets('a departure inside a window covers but does not lock; the '
        'same departure outside one locks', (tester) async {
      final (controller, gate, timers) = unlockedRig();
      addTearDown(controller.dispose);
      gate.grantNext = true;
      await controller.unlock();
      expect(controller.locked, isFalse);

      final picker = Completer<void>();
      final ceremony = controller.duringSystemUi(() => picker.future);
      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);

      expect(controller.locked, isFalse,
          reason: 'the app put this system UI on screen itself');
      expect(controller.obscured, isTrue,
          reason: 'the window suppresses the lock, never the cover');

      picker.complete();
      await ceremony;
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      timers.fireWithDelay(kSystemUiSettleTimeout);
      expect(controller.systemUiActive, isFalse);

      // Same event, no window: the policy outside is unchanged.
      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(controller.locked, isTrue);
    });

    testWidgets('nesting: an inner window closing does not restore locking '
        'while the outer one is open', (tester) async {
      final (controller, gate, _) = unlockedRig();
      addTearDown(controller.dispose);
      gate.grantNext = true;
      await controller.unlock();

      final outer = Completer<void>();
      final outerDone = controller.duringSystemUi(() async {
        // The credential prompt nests inside the provider ceremony, as
        // "Add Google" does.
        await controller.duringSystemUi(() async {});
        controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
        expect(controller.locked, isFalse,
            reason: 'the outer window is still open');
        await outer.future;
      });
      outer.complete();
      await outerDone;
      expect(controller.systemUiActive, isTrue,
          reason: 'the outer window saw a departure, so it settles');
    });

    testWidgets('the deadline locks the app however long the operator was '
        'away, and whatever else happened', (tester) async {
      final (controller, gate, timers) = unlockedRig();
      addTearDown(controller.dispose);
      gate.grantNext = true;
      await controller.unlock();
      expect(controller.locked, isFalse);

      final picker = Completer<void>();
      final ceremony = controller.duringSystemUi(() => picker.future);
      // Everything that would reset the inactivity countdown: a
      // background-and-return cycle, and pointer activity.
      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      controller.noteActivity();
      expect(controller.locked, isFalse);

      // Both timers are armed at distinct delays, so firing only the
      // window deadline proves the lock came from it rather than from the
      // inactivity countdown the resumes and input just re-armed.
      expect(timers.created.any((t) => t.delay == windowDeadline && t.active),
          isTrue);
      expect(
          timers.created
              .any((t) => t.delay == kDefaultInactivityTimeout && t.active),
          isTrue);

      timers.fireWithDelay(windowDeadline);

      expect(controller.locked, isTrue,
          reason: 'the window deadline is not extended by resumes or input');
      picker.complete();
      await ceremony;
    });

    // A plain `test`: the settings watch delivers over real async, which a
    // `testWidgets` fake-async zone would never advance without pumping,
    // and this case needs no widget tree.
    test('the deadline still fires with the relock toggle off', () async {
      final (controller, gate, timers) = unlockedRig();
      addTearDown(controller.dispose);
      gate.grantNext = true;
      await controller.unlock();

      final settings =
          FakeSettingsStore({SettingsKeys.relockEnabled: 'false'});
      addTearDown(settings.close);
      controller.attachSettings(settings);
      // One event-loop turn for the seeded value to reach the listener;
      // pumpEventQueue would never return against a broadcast stream that
      // stays open for the life of the store.
      await Future<void>.delayed(Duration.zero);
      expect(controller.relockEnabled, isFalse);

      final picker = Completer<void>();
      final ceremony = controller.duringSystemUi(() => picker.future);
      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(controller.locked, isFalse);

      timers.fireWithDelay(windowDeadline);

      expect(controller.locked, isTrue,
          reason: 'the toggle governs foreground inactivity, not the bound '
              'on system UI the app put on screen itself');
      picker.complete();
      await ceremony;
    });

    // A plain `test`: the settings watch delivers over real async, which a
    // `testWidgets` fake-async zone would never advance without pumping.
    test('a granted unlock with the operator still away fails '
        'closed, whatever the relock toggle says', () async {
      // The window absorbed a real departure. The credential decides
      // whether the app *may* open (KTD1), but an operator who walked away
      // and never came back must not find it open: the departure is
      // answered fail-closed when the window settles. Leaning on the
      // inactivity timer here was a hole — it arms nothing when the relock
      // toggle is off, and every resume restarts it.
      final gate = FakeGate(requiresUnlock: true);
      final timers = FakeInactivityTimers();
      final controller = GateController(
        gate: gate,
        inactivityTimerFactory: timers.factory,
        systemUiDeadline: windowDeadline,
      );
      addTearDown(controller.dispose);

      gate.grantNext = true;
      gate.onPrompt = () {
        controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
        controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
        controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      };
      final settings =
          FakeSettingsStore({SettingsKeys.relockEnabled: 'false'});
      addTearDown(settings.close);
      controller.attachSettings(settings);
      await Future<void>.delayed(Duration.zero);
      expect(controller.relockEnabled, isFalse,
          reason: 'the configuration with no inactivity fallback at all');

      await controller.unlock();
      expect(controller.locked, isFalse,
          reason: 'the credential was accepted (KTD1)');

      // The operator never comes back; the settling tail expires.
      timers.fireWithDelay(kSystemUiSettleTimeout);

      expect(controller.locked, isTrue,
          reason: 'the absorbed departure is answered, not waived');
      expect(controller.obscured, isTrue);
    });

    test('a departure absorbed during a provider ceremony still locks when '
        'the operator never returns', () async {
      // The sign-in screen's pickers have no credential result to lean on
      // at all, so this is the path with the least protection.
      final gate = FakeGate(requiresUnlock: true);
      final timers = FakeInactivityTimers();
      final controller = GateController(
        gate: gate,
        inactivityTimerFactory: timers.factory,
        systemUiDeadline: windowDeadline,
      );
      addTearDown(controller.dispose);
      gate.grantNext = true;
      await controller.unlock();
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      timers.fireWithDelay(kSystemUiSettleTimeout);
      expect(controller.locked, isFalse);

      final picker = Completer<void>();
      final ceremony = controller.duringSystemUi(() => picker.future);
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(controller.locked, isFalse, reason: 'suppressed while up');
      picker.complete();
      await ceremony;
      timers.fireWithDelay(kSystemUiSettleTimeout);

      expect(controller.locked, isTrue);
      expect(controller.obscured, isTrue);
    });

    testWidgets('the cover is reconciled when a window closes, never '
        'stranded and never lifted while the app is away', (tester) async {
      final (controller, gate, timers) = unlockedRig();
      addTearDown(controller.dispose);
      gate.grantNext = true;
      await controller.unlock();

      // Closes while the app is back: the cover is lifted, not stranded
      // behind a window with no lock screen.
      var picker = Completer<void>();
      var ceremony = controller.duringSystemUi(() => picker.future);
      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      picker.complete();
      await ceremony;
      timers.fireWithDelay(kSystemUiSettleTimeout);
      expect(controller.obscured, isFalse);
      expect(controller.locked, isFalse);

      // Closes while the app is still away: the cover stays up.
      picker = Completer<void>();
      ceremony = controller.duringSystemUi(() => picker.future);
      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      picker.complete();
      await ceremony;
      timers.fireWithDelay(kSystemUiSettleTimeout);
      expect(controller.obscured, isTrue,
          reason: 'R5: covered whenever the app is not resumed');
    });
  });

  group('re-authentication for linking (#2 U5; KTD5)', () {
    testWidgets('returns false without prompting while an unlock is in '
        'progress; otherwise reports the credential and never changes '
        'locked', (tester) async {
      final gate = FakeGate();
      final controller = GateController(gate: gate);
      addTearDown(controller.dispose);
      expect(controller.locked, isTrue);

      final held = Completer<bool>();
      gate.holdNext = held;
      final unlocking = controller.unlock();
      expect(controller.authenticating, isTrue);
      expect(await controller.reauthenticate(), isFalse);
      expect(gate.requests, 1, reason: 'no second prompt over the first');
      expect(controller.locked, isTrue);
      held.complete(true);
      await unlocking;
      expect(controller.locked, isFalse);

      gate.grantNext = true;
      expect(await controller.reauthenticate(), isTrue);
      expect(gate.requests, 2);
      expect(controller.locked, isFalse);
      expect(controller.authenticating, isFalse);

      gate.grantNext = false;
      expect(await controller.reauthenticate(), isFalse,
          reason: 'declined or unavailable credential');
      expect(controller.locked, isFalse,
          reason: 'a declined re-auth is not a lock');

      // While locked: a granted re-auth does not unlock either.
      controller.lock();
      expect(controller.locked, isTrue);
      gate.grantNext = true;
      expect(await controller.reauthenticate(), isTrue);
      expect(controller.locked, isTrue);
    });

    testWidgets('returns false when the prompt is interrupted by a '
        'lifecycle change, without re-locking mid-prompt', (tester) async {
      final gate = FakeGate(requiresUnlock: false);
      // Fake timers: a closing system-UI window re-arms the inactivity
      // countdown (#65 U1), which would otherwise leave a real 2-minute
      // Timer pending past the end of the test.
      final timers = FakeInactivityTimers();
      final controller = GateController(
          gate: gate, inactivityTimerFactory: timers.factory);
      addTearDown(controller.dispose);
      expect(controller.locked, isFalse);

      final hold = Completer<bool>();
      gate.holdNext = hold;
      final pending = controller.reauthenticate();
      expect(controller.authenticating, isTrue);
      // The system prompt itself reports `inactive`.
      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      hold.complete(true);
      expect(await pending, isFalse);
      expect(controller.authenticating, isFalse);
      expect(controller.locked, isFalse);

      // A clean prompt afterwards works again.
      gate.grantNext = true;
      expect(await controller.reauthenticate(), isTrue);
    });

    testWidgets('an interrupted prompt on a gated platform replays the '
        'departure: covered and re-locked, like unlock', (tester) async {
      final gate = FakeGate(requiresUnlock: true);
      final controller = GateController(gate: gate);
      addTearDown(controller.dispose);
      gate.grantNext = true;
      await controller.unlock();
      expect(controller.locked, isFalse);

      final hold = Completer<bool>();
      gate.holdNext = hold;
      final pending = controller.reauthenticate();
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(controller.locked, isFalse,
          reason: 'no re-lock while the prompt is still up');
      hold.complete(true);
      expect(await pending, isFalse);
      expect(controller.locked, isTrue,
          reason: 'the suppressed departure is replayed after the prompt');
      expect(controller.obscured, isTrue);
      expect(controller.authenticating, isFalse);
    });
  });

  group('cold start gates first (F3, AE4)', () {
    testWidgets('locked screen shows before any data; a declined credential '
        'never opens the database', (tester) async {
      final harness = Harness(tester, seed: (db) async {
        await seedTwoProfiles(db, 0);
      });
      await harness.pump(grant: false);

      expect(lockScreen, findsOneWidget);
      expect(deniedMessage, findsOneWidget,
          reason: 'the declined cold-start attempt is surfaced');
      expect(find.text('Alice'), findsNothing,
          reason: 'no profile data before the gate opens (R7)');
      expect(find.text('Barb'), findsNothing);
      expect(harness.dbOpenerCalls, 0,
          reason: 'AE4: declined credential never decrypts — DB never opened');
      await harness.dispose();
    });

    testWidgets('issue #65 end to end: the prompt reporting its own focus '
        'loss still unlocks into the data', (tester) async {
      // The field defect through the whole tree: Face ID succeeds and the
      // lock screen used to stay up with no error, because the prompt's
      // own `inactive` report was read as the operator leaving.
      final harness = Harness(tester, seed: (db) async {
        await seedTwoProfiles(db, 0);
      });
      await harness.pump(grant: false);
      expect(lockScreen, findsOneWidget);

      harness.gate.grantNext = true;
      harness.gate.onPrompt = () => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await harness.unlockViaButton();
      await harness.background(AppLifecycleState.resumed);

      expect(lockScreen, findsNothing,
          reason: 'the system accepted the credential; that decides');
      expect(deniedMessage, findsNothing, reason: 'nothing was declined');
      expect(privacyCover, findsNothing,
          reason: 'the cover is reconciled once the app is back (KTD9)');
      expect(find.text('Alice'), findsOneWidget);
      expect(harness.dbOpenerCalls, 1);
      await harness.dispose();
    });

    testWidgets('web-style gate is a no-op: no lock, immediate data, no auth '
        'requests (web dev banner is U8)', (tester) async {
      final harness = Harness(tester, seed: (db) async {
        await seedTwoProfiles(db, 0);
      });
      harness.gate.requiresUnlock = false;
      await harness.pump();

      expect(lockScreen, findsNothing);
      expect(find.text('Alice'), findsOneWidget,
          reason: 'un-gated platform renders data directly');
      expect(harness.gate.requests, 0);
      expect(harness.dbOpenerCalls, 1);
      await harness.dispose();
    });
  });

  group('decline and retry loop (F3)', () {
    testWidgets('declined retries stay locked with no data; a granted retry '
        'unlocks once and shows the active profile', (tester) async {
      final harness = Harness(tester, seed: (db) async {
        await seedTwoProfiles(db, 0);
      });
      await harness.pump(grant: false);
      expect(harness.gate.requests, 1, reason: 'one automatic cold-start ask');

      // Retry that is declined again: still locked, still no data.
      harness.gate.grantNext = false;
      await harness.unlockViaButton();
      expect(lockScreen, findsOneWidget);
      expect(deniedMessage, findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(harness.dbOpenerCalls, 0);

      // Retry that is granted: data appears exactly once the DB is opened.
      harness.gate.grantNext = true;
      await harness.unlockViaButton();
      expect(lockScreen, findsNothing);
      expect(find.text('Alice'), findsOneWidget,
          reason: 'stored last-active profile opens after the gate');
      expect(find.text('Profiles'), findsNothing);
      expect(harness.dbOpenerCalls, 1);
      expect(harness.gate.requests, 3,
          reason: 'cold start + declined retry + granted retry');
      await harness.dispose();
    });
  });

  group('backgrounding re-locks (R7)', () {
    testWidgets('paused hides all data behind the lock; resume keeps the '
        'gate until an explicit unlock', (tester) async {
      final harness = Harness(tester, seed: (db) async {
        await seedTwoProfiles(db, 0);
      });
      await harness.pump();
      expect(find.text('Alice'), findsOneWidget);

      await harness.background(AppLifecycleState.paused);
      expect(lockScreen, findsOneWidget);
      expect(find.text('Alice'), findsNothing,
          reason: 'no data while re-locked in the background');

      await harness.background(AppLifecycleState.resumed);
      expect(lockScreen, findsOneWidget,
          reason: 'warm resume gates first — no auto-bypass after re-lock');

      await harness.unlockViaButton();
      expect(find.text('Alice'), findsOneWidget);
      await harness.dispose();
    });

    testWidgets('hidden (app switcher) re-locks the same way', (tester) async {
      final harness = Harness(tester, seed: (db) async {
        await seedTwoProfiles(db, 0);
      });
      await harness.pump();
      await harness.background(AppLifecycleState.hidden);
      expect(lockScreen, findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      await harness.dispose();
    });

    testWidgets('inactive (split-screen focus loss) also re-locks',
        (tester) async {
      final harness = Harness(tester, seed: (db) async {
        await seedTwoProfiles(db, 0);
      });
      await harness.pump();
      await harness.background(AppLifecycleState.inactive);
      expect(lockScreen, findsOneWidget,
          reason: 'split-screen/multi-window unfocus is a departure');
      expect(find.text('Alice'), findsNothing);
      await harness.dispose();
    });

    testWidgets('background re-lock is not disabled by the inactivity toggle',
        (tester) async {
      final harness = Harness(tester, seed: (db) async {
        await seedTwoProfiles(db, 0);
        await DriftSettingsStore(db.storage)
            .set(SettingsKeys.relockEnabled, 'false');
      });
      await harness.pump();
      expect(find.text('Alice'), findsOneWidget);

      await harness.background(AppLifecycleState.paused);
      expect(lockScreen, findsOneWidget,
          reason: 'the toggle governs only the inactivity timeout');
      await harness.dispose();
    });
  });

  group('inactivity auto-relock (R7, default on)', () {
    testWidgets('timeout fires with no input → re-locks and hides data',
        (tester) async {
      final harness = Harness(tester, seed: (db) async {
        await seedTwoProfiles(db, 0);
      });
      await harness.pump();
      expect(find.text('Alice'), findsOneWidget);
      expect(harness.timers.anyActive, isTrue,
          reason: 'armed by default after unlock');

      harness.timers.fireActive();
      await tester.pumpAndSettle();
      expect(lockScreen, findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      await harness.dispose();
    });

    testWidgets('toggle off (persisted) disables the timeout re-lock',
        (tester) async {
      final harness = Harness(tester, seed: (db) async {
        await seedTwoProfiles(db, 0);
        await DriftSettingsStore(db.storage)
            .set(SettingsKeys.relockEnabled, 'false');
      });
      await harness.pump();
      expect(find.text('Alice'), findsOneWidget);
      expect(harness.timers.anyActive, isFalse,
          reason: 'no inactivity timer armed while the toggle is off');

      harness.timers.fireActive();
      await tester.pumpAndSettle();
      expect(lockScreen, findsNothing, reason: 'timeout re-lock disabled');
      expect(find.text('Alice'), findsOneWidget);
      await harness.dispose();
    });
  });

  group('snapshot suppression (R7)', () {
    testWidgets('un-gated platform still covers content when hidden '
        '(opaque overlay, cross-platform)', (tester) async {
      final harness = Harness(tester, seed: (db) async {
        await seedTwoProfiles(db, 0);
      });
      harness.gate.requiresUnlock = false;
      await harness.pump();

      await harness.background(AppLifecycleState.hidden);
      expect(privacyCover, findsOneWidget,
          reason: 'opaque cover replaces app-switcher snapshots');
      expect(find.text('Alice'), findsNothing);
      await harness.background(AppLifecycleState.resumed);
      expect(privacyCover, findsNothing);
      expect(find.text('Alice'), findsOneWidget);
      await harness.dispose();
    });
  });

  group('launch payload seam (notification routing, wired for real in U8)',
      () {
    testWidgets('payload routes through the gate, then opens the firing '
        "profile's overview", (tester) async {
      String? launchId;
      final harness = Harness(tester, seed: (db) async {
        await seedTwoProfiles(db, 0);
        final profiles = await DriftProfilesRepository(db.storage).list();
        launchId = profiles.last.id; // Barb
      });
      // launchId is assigned inside the seed closure; it must be read only
      // after the seed completes — call arguments are evaluated BEFORE
      // pump() awaits pendingSeed.
      await harness.pendingSeed;
      await harness.pump(grant: false, launchProfileId: launchId);

      expect(lockScreen, findsOneWidget);
      expect(find.text('Barb'), findsNothing,
          reason: 'payload never bypasses the gate');
      expect(find.byType(OverviewPanel), findsNothing);

      harness.gate.grantNext = true;
      await harness.unlockViaButton();

      expect(find.text('Barb'), findsOneWidget,
          reason: 'payload selected the firing profile');
      expect(find.text('Alice'), findsNothing,
          reason: 'not the previously active profile');
      expect(find.byType(OverviewPanel), findsOneWidget,
          reason: "opened on the firing profile's overview");
      expect(find.text('Calendar'), findsOneWidget,
          reason: 'the detail tabs are there — overview is just the start');
      await harness.dispose();
    });

    testWidgets('unknown payload id falls back to the normal home',
        (tester) async {
      final harness = Harness(tester, seed: (db) async {
        await seedTwoProfiles(db, 0);
      });
      await harness.pump(launchProfileId: 'no-such-profile');

      expect(lockScreen, findsNothing);
      expect(find.text('Alice'), findsOneWidget,
          reason: 'unknown payload id ignored, stored active profile used');
      await harness.dispose();
    });
  });

  group('link-failure surface after unlock (#2 U3; AE4, R7)', () {
    final linkFailure = find.byKey(const ValueKey('auth-link-failure'));
    const expiredCopy =
        'That sign-in link is no longer valid. Request a new one.';

    testWidgets('a latched expiredLink shows nothing while locked; after '
        'unlock the home shows the generic message once and consumes it; '
        'a later re-lock/unlock rebuild shows nothing', (tester) async {
      final auth = FakeAuthService()
        ..pendingLinkFailure = const AuthFailure.expiredLink();
      addTearDown(auth.dispose);
      final harness = Harness(tester, seed: (db) => seedTwoProfiles(db, 0));
      await harness.pump(grant: false, authService: auth);
      expect(lockScreen, findsOneWidget);
      expect(linkFailure, findsNothing);
      expect(find.text(expiredCopy), findsNothing);
      expect(auth.linkFailureConsumed, 0,
          reason: 'consumed only once the gate is unlocked');

      harness.gate.grantNext = true;
      await harness.unlockViaButton();
      expect(lockScreen, findsNothing);
      expect(find.text('Alice'), findsOneWidget, reason: 'home is showing');
      expect(linkFailure, findsOneWidget);
      expect(find.text(expiredCopy), findsOneWidget);
      expect(auth.linkFailureConsumed, 1);
      expect(auth.pendingLinkFailure, isNull);
      expect(expiredCopy, isNot(contains('@')));
      expect(expiredCopy.toLowerCase(), isNot(contains('http')));

      // Let the SnackBar retire, then force a full re-evaluation of the
      // home gate through a re-lock and unlock.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(linkFailure, findsNothing);
      await harness.background(AppLifecycleState.paused);
      await harness.background(AppLifecycleState.resumed);
      await harness.unlockViaButton();
      expect(find.text('Alice'), findsOneWidget);
      expect(linkFailure, findsNothing, reason: 'never repeats');
      expect(auth.linkFailureConsumed, 1);
      await harness.dispose();
    });

    testWidgets('a failure latched while re-locked (home offstage) waits '
        'for the unlock; a latched network failure shows the network copy',
        (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final harness = Harness(tester, seed: (db) => seedTwoProfiles(db, 0));
      await harness.pump(authService: auth);
      await harness.drainIsolateTraffic(tester);
      expect(find.text('Alice'), findsOneWidget);

      await harness.background(AppLifecycleState.paused);
      expect(lockScreen, findsOneWidget);
      auth.emitLinkFailure(const AuthFailure.network());
      await tester.pump();
      await tester.pumpAndSettle();
      expect(linkFailure, findsNothing);
      expect(auth.linkFailureConsumed, 0);

      await harness.background(AppLifecycleState.resumed);
      await harness.unlockViaButton();
      expect(linkFailure, findsOneWidget);
      expect(
          find.text(
              'Could not reach the server. Check your connection and try again.'),
          findsOneWidget);
      expect(auth.linkFailureConsumed, 1);
      await harness.dispose();
    });
  });

  group('fail-closed startup screen (replaces U4 StartupErrorApp)', () {
    testWidgets('quarantine failure gets its own message; single Close; no '
        'destructive actions; no data', (tester) async {
      final harness = Harness(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      await tester.pumpWidget(LunarLogRoot(
        gate: harness.gate,
        dbOpener: () async =>
            throw DatabaseQuarantineError('lunarlog.db', Exception('bad page')),
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('fail-closed-title')), findsOneWidget);
      expect(find.text('lunarlog could not open your data'), findsOneWidget);
      expect(find.textContaining('left exactly as it was'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.textContaining('Delete'), findsNothing,
          reason: 'fail-closed posture: no destructive actions');
      expect(find.textContaining('Reset'), findsNothing);
      expect(find.textContaining('Wipe'), findsNothing);
      expect(find.text('Alice'), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fail-closed-title')), findsOneWidget,
          reason: 'Close never reveals data or wipes anything');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('malformed key failure gets the key-specific message',
        (tester) async {
      await tester.pumpWidget(LunarLogRoot(
        gate: FakeGate(),
        dbOpener: () async => throw const CorruptDatabaseKeyError(),
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('lunarlog could not read its unlock key'),
          findsOneWidget);
      expect(find.text('lunarlog could not open your data'), findsNothing,
          reason: 'distinct message per failure class');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('missing encryption support gets its own message',
        (tester) async {
      await tester.pumpWidget(LunarLogRoot(
        gate: FakeGate(),
        dbOpener: () async => throw const EncryptionUnavailableError(),
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('This build cannot protect data'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('generic failures get the generic message and the operator '
        'detail is selectable', (tester) async {
      await tester.pumpWidget(LunarLogRoot(
        gate: FakeGate(),
        dbOpener: () async => throw Exception('mystery startup fault'),
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('lunarlog could not start'), findsOneWidget);
      expect(find.textContaining('mystery startup fault'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget,
          reason: 'operator-facing diagnostics are copyable');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('sync engine wiring (U5, KTD11)', () {
    testWidgets('null collaborators build nothing: no builder call, no '
        'SyncStatusController, the tree is the pre-U5 one', (tester) async {
      var builderCalls = 0;
      final harness = Harness(tester, seed: (db) async {
        await seedTwoProfiles(db, 0);
      });
      await harness.pump(
        syncEngineBuilder: ({
          required db,
          required authService,
          required transport,
          required gate,
        }) {
          builderCalls++;
          return FakeSyncEngine();
        },
      );
      expect(find.text('Alice'), findsOneWidget);
      expect(builderCalls, 0);
      expect(
          tester
              .element(find.byType(ProfileHomeGate))
              .read<SyncStatusController?>(),
          isNull);
      await harness.dispose();
    });

    testWidgets('the engine is built and started only after the first '
        'unlock, provided as a SyncStatusController, and disposed before the '
        'database closes', (tester) async {
      final engine = FakeSyncEngine();
      var builderCalls = 0;
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final transport = FakeSyncTransport();
      final harness = Harness(tester, seed: (db) async {
        await seedTwoProfiles(db, 0);
      });
      await harness.pump(
        grant: false,
        authService: auth,
        syncTransport: transport,
        syncEngineBuilder: ({
          required db,
          required authService,
          required transport,
          required gate,
        }) {
          builderCalls++;
          expect(identical(db, harness.db), isTrue);
          expect(identical(authService, auth), isTrue);
          expect(gate.unlocked, isTrue,
              reason: 'built after the credential was accepted');
          return engine;
        },
      );
      expect(lockScreen, findsOneWidget);
      expect(builderCalls, 0, reason: 'nothing before the first unlock');
      expect(engine.startCalls, 0);

      harness.gate.grantNext = true;
      await harness.unlockViaButton();
      expect(builderCalls, 1);
      expect(engine.startCalls, 1);
      final controller = tester
          .element(find.byType(ProfileHomeGate))
          .read<SyncStatusController?>();
      expect(controller, isNotNull);
      expect(controller!.snapshot, SyncSnapshot.initial);
      engine.emitPhase(SyncPhase.pulling);
      await tester.pump();
      expect(controller.phase, SyncPhase.pulling);

      // Re-lock and unlock again: still the same single engine.
      await harness.background(AppLifecycleState.paused);
      await harness.background(AppLifecycleState.resumed);
      await harness.unlockViaButton();
      expect(builderCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.disposeCalls, 1,
          reason: 'root disposal disposes the engine before the DB closes');
      await harness.db.close();
    });

    testWidgets('the default builder wires a real SupabaseSyncEngine: '
        'transport calls only after unlock; its timers die with the root',
        (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
      addTearDown(auth.dispose);
      final transport = FakeSyncTransport();
      final harness = Harness(tester);
      await harness.pump(
          grant: false, authService: auth, syncTransport: transport);
      expect(transport.pullCount, 0);
      expect(transport.pushCount, 0);

      harness.gate.grantNext = true;
      await harness.unlockViaButton();
      await harness.drainIsolateTraffic(tester);
      expect(transport.pullCount, greaterThanOrEqualTo(2),
          reason: 'empty database binds silently and pulls both tables');
      final controller = tester
          .element(find.byType(ProfileHomeGate))
          .read<SyncStatusController?>();
      expect(controller, isNotNull);
      expect(controller!.snapshot.boundUserId, 'u1');
      expect(controller.phase, SyncPhase.idle);

      // Root disposal cancels the periodic timer; a leaked one would fail
      // this test as a pending timer.
      await harness.dispose();
    });
  });

  group('settings screen (v1: exactly one control)', () {
    testWidgets('relock toggle persists via SettingsStore and shows the '
        'fixed 2-minute timeout', (tester) async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      final store = DriftSettingsStore(db.storage);

      await tester.pumpWidget(Provider<SettingsStore>.value(
        value: store,
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('relock-toggle'));
      expect(toggle, findsOneWidget);
      expect(find.textContaining('2 minutes'), findsOneWidget,
          reason: 'timeout display (fixed in v1)');
      expect((tester.widget(toggle) as SwitchListTile).value, isTrue,
          reason: 'defaults on with no stored value');

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(await store.get(SettingsKeys.relockEnabled), 'false');
      expect((tester.widget(toggle) as SwitchListTile).value, isFalse);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(await store.get(SettingsKeys.relockEnabled), 'true');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets('reachable from the profile picker', (tester) async {
      final harness = Harness(tester, seed: (db) async {
        await DriftSettingsStore(db.storage)
            .set(SettingsKeys.firstRunNoticeShown, 'true');
        await DriftProfilesRepository(db.storage)
            .create(displayName: 'Alice', isMinor: false);
      });
      await harness.pump();
      expect(find.text('Profiles'), findsOneWidget,
          reason: 'no active profile → picker is home');

      expect(find.byTooltip('Settings'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('relock-toggle')), findsOneWidget);
      await harness.dispose();
    });
  });
}
