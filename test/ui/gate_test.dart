/// Widget tests for U7: the device-credential gate (R7, flow F3, AE4) —
/// lock-first startup, decline/retry, background re-lock, inactivity
/// re-lock with its settings toggle, snapshot suppression, the launch
/// payload seam, and the fail-closed startup screen that replaces U4's
/// basic StartupErrorApp. The authenticator is always a fake; real
/// biometrics are verified manually on-device (U9 checklist).
library;

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
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:provider/provider.dart';

class FakeGate implements AppGate {
  FakeGate({this.grantNext = true, this.requiresUnlock = true});

  bool grantNext;
  int requests = 0;

  @override
  bool requiresUnlock;

  @override
  Future<bool> requestAccess() async {
    requests++;
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
