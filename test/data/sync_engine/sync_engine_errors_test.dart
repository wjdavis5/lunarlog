/// auth expiry, transport errors, and backoff — issue #437 split of `test/data/sync_engine_test.dart`.
/// Shared fixtures live in `sync_engine_support.dart`. Nothing here
/// touches Supabase.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/sync/supabase_sync_engine.dart';
import 'package:lunarlog/data/sync/sync_transport.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';

import 'sync_engine_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('errors', () {
    test('AE9: expired yields error(auth); local writes stay dirty; a later '
        'signedIn for the same uid resumes without consent', () async {
      final rig = Rig(authState: AuthSessionState.expired, uid: null);
      addTearDown(rig.dispose);
      await rig.bind(uidA);

      await rig.start();
      expect(rig.engine.snapshot.phase, SyncPhase.error);
      expect(rig.engine.snapshot.lastError, SyncErrorKind.auth);
      expect(rig.transport.pullCount, 0);
      expect((await rig.state()).lastError, 'auth');

      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      expect(p.dirty, isTrue);
      await rig.engine.flush();
      expect(rig.transport.pushCount, 0);

      rig.auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: uidA));
      await Future<void>.delayed(Duration.zero);
      await rig.engine.flush();
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
      expect(rig.transport.pushes, hasLength(1));
      expect(await rig.storage.dirtyCount(), 0);
      expect((await rig.state()).lastError, isNull);
    });

    test('an auth transport error yields error(auth) and no backoff timer',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      rig.transport.persistentError = const SyncTransportError.auth();
      await rig.start();
      expect(rig.engine.snapshot.phase, SyncPhase.error);
      expect(rig.engine.snapshot.lastError, SyncErrorKind.auth);
      expect(rig.timers.oneShots.where((t) => t.active), isEmpty);
    });

    test('network errors back off with the injected schedule and recover',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      rig.transport.persistentError = const SyncTransportError.network();

      await rig.start();
      expect(rig.engine.snapshot.phase, SyncPhase.error);
      expect(rig.engine.snapshot.lastError, SyncErrorKind.network);
      expect((await rig.state()).lastError, 'network');
      var backoffs = rig.timers.oneShots.where((t) => t.active).toList();
      expect(backoffs, hasLength(1));
      expect(backoffs.single.delay, const Duration(seconds: 1));

      backoffs.single.fire();
      await rig.engine.flush();
      backoffs = rig.timers.oneShots.where((t) => t.active).toList();
      expect(backoffs, hasLength(1));
      expect(backoffs.single.delay, const Duration(seconds: 2),
          reason: 'second consecutive failure');

      rig.transport.persistentError = null;
      backoffs.single.fire();
      await rig.engine.flush();
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
      expect(rig.timers.oneShots.where((t) => t.active), isEmpty);
    });

    test('the default backoff is exponential with jitter and capped at 10 '
        'minutes', () {
      expect(defaultSyncBackoff(1), greaterThanOrEqualTo(const Duration(seconds: 30)));
      expect(defaultSyncBackoff(1), lessThan(const Duration(seconds: 40)));
      expect(defaultSyncBackoff(3), greaterThanOrEqualTo(const Duration(minutes: 2)));
      expect(defaultSyncBackoff(20), lessThanOrEqualTo(const Duration(minutes: 10)));
      expect(defaultSyncBackoff(20), greaterThan(const Duration(minutes: 8)));
    });
  });
}
