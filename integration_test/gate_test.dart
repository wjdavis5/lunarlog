/// U7 gate integration matrix (R7, flow F3, AE4), run on the host with a
/// fake authenticator: `flutter test integration_test/gate_test.dart`.
/// Real biometrics are verified manually on-device later (U9 checklist).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/gate/app_gate.dart';
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

  @override
  Future<bool> requestAccess() async {
    requests++;
    onPrompt?.call();
    return grantNext;
  }
}

class FakeInactivityTimer implements InactivityTimer {
  FakeInactivityTimer(this._onTimeout);

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
    final timer = FakeInactivityTimer(onTimeout);
    created.add(timer);
    return timer;
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

  Future<void> disposeDb(WidgetTester tester, LunarLogDatabase db) async {
    await tester.pumpWidget(const SizedBox.shrink());
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
    var to = path.indexOf(target);
    assert(from >= 0 && to >= 0, 'unsupported transition $start -> $target');
    while (from != to) {
      from += to > from ? 1 : -1;
      tester.binding.handleAppLifecycleStateChanged(path[from]);
      await tester.pump();
    }
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
    final db = await seededDb();
    final gate = FakeGate();
    await tester.pumpWidget(LunarLogRoot(
      gate: gate,
      dbOpener: () async => db,
    ));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lock-screen')), findsOneWidget);

    gate.onPrompt = () => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await unlockViaButton(tester);
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

    await tester.pumpWidget(LunarLogRoot(
      gate: gate,
      dbOpener: () async => db,
    ));
    await tester.pump();
    await tester.pumpAndSettle();
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
    expect(timers.anyActive, isFalse);

    timers.fireActive();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lock-screen')), findsNothing,
        reason: 'timeout re-lock disabled by the toggle');

    // Background re-lock still applies with the toggle off.
    await transitionTo(tester, AppLifecycleState.hidden);
    expect(find.byKey(const ValueKey('lock-screen')), findsOneWidget);
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
