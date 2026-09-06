/// U6 / KTD16 / AE10: `LunarLogRoot.resetDevice()` is one ordered
/// operation — engine disposed, app tree unmounted, database closed, file
/// deleted before key, the best-effort server sign-out, and only then the
/// reopen through `dbOpener` (fresh key) so the new database never binds to
/// the account being signed out. The database, engine, file and
/// key primitives are all recorders so the order is asserted literally.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/ui/profiles/profile_home_gate.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_sync_engine.dart';
import '../support/fake_sync_transport.dart';
import '../support/pump_helpers.dart';
import 'gate_test.dart' show FakeGate;
import 'profiles_test.dart' show kNoticeText;

class RecordingDatabase extends LunarLogDatabase {
  RecordingDatabase(this.onClose, super.executor);

  final void Function() onClose;

  bool closed = false;

  @override
  Future<void> close() {
    closed = true;
    onClose();
    return super.close();
  }

  @override
  Future<void> wipeAllData() {
    onWipe?.call();
    return super.wipeAllData();
  }

  void Function()? onWipe;
}

class RecordingAuth extends FakeAuthService {
  RecordingAuth(this.log);

  final List<String> log;

  @override
  Future<void> signOut({AuthSignOutScope scope = AuthSignOutScope.local}) {
    log.add('signOut');
    return super.signOut(scope: scope);
  }
}

class RecordingEngine extends FakeSyncEngine {
  RecordingEngine(this.log);

  final List<String> log;

  @override
  Future<void> dispose() async {
    log.add('engine.dispose:start');
    await Future<void>.value();
    await super.dispose();
    log.add('engine.dispose:done');
  }
}

class ResetHarness {
  ResetHarness(this.tester, {this.isWeb = false});

  final WidgetTester tester;
  final bool isWeb;
  final List<String> log = [];
  final List<RecordingDatabase> dbs = [];
  final List<RecordingEngine> engines = [];
  late final RecordingAuth auth = RecordingAuth(log);
  final FakeGate gate = FakeGate(requiresUnlock: false);

  Future<RecordingDatabase> openDb() async {
    final db = RecordingDatabase(() {
      final appMounted = find.byType(LunarLogApp).evaluate().isNotEmpty;
      log.add(appMounted ? 'close:APP STILL MOUNTED' : 'close');
    }, NativeDatabase.memory())
      ..onWipe = () => log.add('wipe');
    dbs.add(db);
    log.add('open');
    return db;
  }

  Future<void> pump() async {
    await tester.pumpWidget(LunarLogRoot(
      gate: gate,
      dbOpener: openDb,
      authService: auth,
      syncTransport: FakeSyncTransport(),
      syncEngineBuilder: ({
        required db,
        required authService,
        required transport,
        required gate,
      }) {
        final engine = RecordingEngine(log);
        engines.add(engine);
        return engine;
      },
      deleteLocalDatabase: () async => log.add('delete-file'),
      deleteDbKey: () async => log.add('delete-key'),
      isWeb: isWeb,
    ));
    await tester.pump();
    await tester.pumpAndSettle();
    await drainIsolateTraffic(tester);
  }

  DeviceResetCallback get reset =>
      tester.element(find.byType(ProfileHomeGate)).read<DeviceResetCallback>();

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    for (final db in dbs) {
      if (!db.closed) await db.close();
    }
    await auth.dispose();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('native reset: engine dispose → unmount → close → delete file '
      '→ delete key → best-effort server sign-out → reopen; the tree lands '
      'on first-run', (tester) async {
    final h = ResetHarness(tester);
    h.auth.emit(AuthSessionState.signedIn,
        user: const AuthUser(id: 'u1', email: 'a@b.c'));
    await h.pump();
    await DriftProfilesRepository(h.dbs.single.storage)
        .create(displayName: 'Alice', isMinor: false);
    await drainIsolateTraffic(tester);
    expect(find.text('Alice'), findsOneWidget);
    expect(h.engines.length, 1);
    h.log.clear();

    final done = h.reset();
    await drainIsolateTraffic(tester);
    await done;
    await drainIsolateTraffic(tester);

    expect(h.log, [
      'engine.dispose:start',
      'engine.dispose:done',
      'close',
      'delete-file',
      'delete-key',
      'signOut',
      'open',
    ]);
    expect(h.dbs.length, 2, reason: 'reopened through dbOpener');
    expect(h.engines.length, 2, reason: 'a fresh engine over the new database');
    expect(h.engines.first.disposeCalls, 1);
    expect(h.engines.last.startCalls, 1);
    expect(h.auth.signOutCalls, [AuthSignOutScope.local]);
    expect(find.text(kNoticeText), findsOneWidget,
        reason: 'AE10: first-run, never the fail-closed screen');
    expect(find.text('Alice'), findsNothing);
    expect(h.auth.state, AuthSessionState.signedOut);
    expect((await h.dbs.last.storage.readSyncState()).boundUserId, isNull,
        reason: 'a reset that ends signed out leaves the fresh database '
            'unbound');
    await h.dispose();
  });

  testWidgets('a failing remote sign-out skips no local step', (tester) async {
    final h = ResetHarness(tester);
    h.auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
    await h.pump();
    h.auth.nextFailure = const AuthFailure.network();
    h.log.clear();

    final done = h.reset();
    await drainIsolateTraffic(tester);
    await done;
    await drainIsolateTraffic(tester);

    expect(h.log, [
      'engine.dispose:start',
      'engine.dispose:done',
      'close',
      'delete-file',
      'delete-key',
      'signOut',
      'open',
    ]);
    expect(h.auth.signOutCalls, [AuthSignOutScope.local]);
    expect(find.text(kNoticeText), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.dispose();
  });

  testWidgets('web reset wipes every table instead of deleting a file or key',
      (tester) async {
    final h = ResetHarness(tester, isWeb: true);
    await h.pump();
    await DriftProfilesRepository(h.dbs.single.storage)
        .create(displayName: 'Alice', isMinor: false);
    await drainIsolateTraffic(tester);
    h.log.clear();

    final done = h.reset();
    await drainIsolateTraffic(tester);
    await done;
    await drainIsolateTraffic(tester);

    expect(h.log, [
      'engine.dispose:start',
      'engine.dispose:done',
      'wipe',
      'close',
      'signOut',
      'open',
    ], reason: 'wipeAllData runs on the old database before it closes');
    expect(find.text(kNoticeText), findsOneWidget);
    await h.dispose();
  });

  testWidgets('a reset clears the process-global breadcrumb log so a support '
      'ticket filed after the next sign-in never carries the previous '
      'account\'s entries', (tester) async {
    addTearDown(defaultBreadcrumbLog.clear);
    final h = ResetHarness(tester);
    h.auth.emit(AuthSessionState.signedIn,
        user: const AuthUser(id: 'u1', email: 'a@b.c'));
    await h.pump();
    defaultBreadcrumbLog.record('nav', 'overview');
    expect(defaultBreadcrumbLog.snapshot(), isNotEmpty);

    final done = h.reset();
    await drainIsolateTraffic(tester);
    await done;
    await drainIsolateTraffic(tester);

    expect(defaultBreadcrumbLog.snapshot(), isEmpty);
    await h.dispose();
  });

  testWidgets('a second reset while one is running is ignored',
      (tester) async {
    final h = ResetHarness(tester);
    await h.pump();
    h.log.clear();
    final first = h.reset();
    final second = h.reset();
    await drainIsolateTraffic(tester);
    await first;
    await second;
    expect(h.log.where((e) => e == 'open').length, 1);
    await h.dispose();
  });
}
