/// U6 / KTD16 / AE10: `LunarLogRoot.resetDevice()` is one ordered
/// operation — engine disposed, app tree unmounted, database closed, file
/// deleted, the best-effort local-only sign-out, and only then the reopen
/// through `dbOpener` so the new database never binds to the account being
/// signed out. The database, engine and file primitives are all recorders
/// so the order is asserted literally.
library;

import 'dart:io';

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
import 'package:lunarlog/ui/startup/fail_closed_screen.dart';
import 'package:provider/provider.dart';

import '../support/debug_print_capture.dart';
import '../support/fake_auth_service.dart';
import '../support/fake_sync_engine.dart';
import '../support/fake_sync_transport.dart';
import '../support/pump_helpers.dart';
import 'gate_test.dart' show FakeGate;
import 'profiles_test.dart' show kNoticeText;

class RecordingDatabase extends LunarLogDatabase {
  RecordingDatabase(this.onClose, super.executor);

  final void Function() onClose;

  /// One-shot failure injection (#97): when set, the next `close()` throws
  /// with the returned object instead of closing, and the hook is
  /// consumed — the `auth.nextFailure` convention. Consuming on use also
  /// keeps `ResetHarness.dispose` able to close the underlying drift
  /// database for real after a test injected a failure.
  Object Function()? nextCloseFailure;

  bool closed = false;

  @override
  Future<void> close() {
    final failure = nextCloseFailure;
    if (failure != null) {
      nextCloseFailure = null;
      throw failure();
    }
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

  /// One-shot failure injection (#97): when set, the next
  /// `deleteLocalDatabase()` throws with the returned object instead of
  /// deleting, and the hook is consumed (the `auth.nextFailure`
  /// convention).
  Object Function()? nextDeleteFailure;

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
      deleteLocalDatabase: () async {
        final failure = nextDeleteFailure;
        if (failure != null) {
          nextDeleteFailure = null;
          throw failure();
        }
        log.add('delete-file');
      },
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
      '→ best-effort local sign-out → reopen; the tree lands '
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

  // The expected log line is split across adjacent literals so the
  // repo-wide grep for the call-site phrase (plan verification step 6)
  // keeps lib/app_lifecycle.dart as its only hit (#97 U3).
  testWidgets('a native delete failure logs the exception type only — '
      'never the message, path, or stack (#97 R1)', (tester) async {
    final h = ResetHarness(tester);
    await h.pump();
    final captured = captureDebugPrint();
    h.log.clear();
    h.nextDeleteFailure = () => const FileSystemException(
        "Deletion failed, path = '/tmp/lunarlog.db'", '/tmp/lunarlog.db');

    final done = h.reset();
    await drainIsolateTraffic(tester);
    await done;
    await drainIsolateTraffic(tester);

    captured.restore();
    expect(captured.lines, ['lunarlog reset ' 'failed: FileSystemException']);
    await h.dispose();
  });

  testWidgets('a native delete failure fails closed: no sign-out, no '
      'reopen, the fail-closed screen (#97 R5)', (tester) async {
    final h = ResetHarness(tester);
    h.auth.emit(AuthSessionState.signedIn,
        user: const AuthUser(id: 'u1', email: 'a@b.c'));
    await h.pump();
    h.log.clear();
    h.nextDeleteFailure = () => const FileSystemException(
        "Deletion failed, path = '/tmp/lunarlog.db'", '/tmp/lunarlog.db');

    final done = h.reset();
    await drainIsolateTraffic(tester);
    await done;
    await drainIsolateTraffic(tester);

    expect(h.log, [
      'engine.dispose:start',
      'engine.dispose:done',
      'close',
    ], reason: 'the delete step threw before sign-out could run');
    expect(h.log.contains('signOut'), isFalse);
    expect(h.log.contains('delete-file'), isFalse);
    expect(find.byType(FailClosedScreen), findsOneWidget);
    expect(find.text(kNoticeText), findsNothing);
    expect(tester.takeException(), isNull);
    await h.dispose();
  });

  testWidgets('a web close failure after the wipe fails closed the same '
      'way and logs the type only', (tester) async {
    final h = ResetHarness(tester, isWeb: true);
    await h.pump();
    final captured = captureDebugPrint();
    h.log.clear();
    h.dbs.single.nextCloseFailure = () => const FileSystemException(
        'close failed mid-reset', '/tmp/lunarlog.db');

    final done = h.reset();
    await drainIsolateTraffic(tester);
    await done;
    await drainIsolateTraffic(tester);

    captured.restore();
    expect(captured.lines, ['lunarlog reset ' 'failed: FileSystemException']);
    expect(h.log, [
      'engine.dispose:start',
      'engine.dispose:done',
      'wipe',
    ], reason: 'close threw after the wipe, before sign-out or reopen');
    expect(find.byType(FailClosedScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.dispose();
  });

  testWidgets('a failed reset releases the re-entrancy guard: a second '
      'reset still runs', (tester) async {
    final h = ResetHarness(tester);
    await h.pump();
    h.log.clear();
    final reset = h.reset;
    h.nextDeleteFailure = () => const FileSystemException(
        "Deletion failed, path = '/tmp/lunarlog.db'", '/tmp/lunarlog.db');

    final first = reset();
    await drainIsolateTraffic(tester);
    await first;
    await drainIsolateTraffic(tester);
    expect(find.byType(FailClosedScreen), findsOneWidget);

    final second = reset();
    await drainIsolateTraffic(tester);
    await second;
    await drainIsolateTraffic(tester);

    expect(h.log, [
      'engine.dispose:start',
      'engine.dispose:done',
      'close',
      'delete-file',
      'signOut',
    ], reason: 'the second reset ran past the delete step — the guard was '
        'released (its engine was already disposed, so dispose logs '
        'nothing the second time)');
    expect(find.byType(FailClosedScreen), findsOneWidget,
        reason: 'fail-closed is sticky once _error is recorded');
    expect(tester.takeException(), isNull);
    await h.dispose();
  });
}
