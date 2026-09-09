/// Issue #128: the sync engine's care_notes/visit_prep_items wiring —
/// dirty rows of both new tables ride the push keyset chain in
/// `p_care_notes`/`p_visit_prep_items`, pulls advance each table's own
/// cursor, a rejected row stays dirty and is retried after a local edit,
/// and a `resolved` row (a declined older push) is applied not-dirty. A
/// compact mirror of `sync/modes_engine_test.dart`'s Rig.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/sync/supabase_sync_engine.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';

import '../../support/fake_auth_service.dart';
import '../../support/fake_sync_transport.dart';

final t0 = DateTime.utc(2026, 9, 2, 10);

/// Valid Crockford ULIDs (the codec rejects anything else).
const profileId = '01J8ZQ9K7MC2X3V4B5N6P7Q8R9';
const noteId = '01J8ZQ9K7MC2X3V4B5N6P7Q8T1';
const itemId = '01J8ZQ9K7MC2X3V4B5N6P7Q8T2';
const ghostId = '01J8ZQ9K7MC2X3V4B5N6P7Q8T3';
const uid = 'user-a';

class FixedClock {
  FixedClock(this.now);

  DateTime now;

  DateTime call() => now;
}

class FakeGateSignal extends ChangeNotifier {
  bool unlocked = true;
}

class FakeTimers {
  Timer oneShot(Duration delay, void Function() callback) =>
      Timer(delay, callback);

  Timer periodic(Duration delay, void Function() callback) =>
      Timer.periodic(delay, (_) => callback());
}

class Rig {
  Rig() {
    db = LunarLogDatabase(NativeDatabase.memory());
    clock = FixedClock(t0);
    storage = LunarLogStorage(db, clock: clock.call);
    transport = FakeSyncTransport(serverClock: () => clock.now);
    auth = FakeAuthService();
    auth.emit(AuthSessionState.signedIn, user: AuthUser(id: uid));
    engine = SupabaseSyncEngine(
      storage: storage,
      transport: transport,
      auth: auth,
      gate: gate,
      gateUnlocked: () => gate.unlocked,
      clock: clock.call,
      timerFactory: timers.oneShot,
      periodicTimerFactory: timers.periodic,
      backoff: (failures) => Duration(seconds: failures),
      writeDebounce: Duration.zero,
    );
  }

  late final LunarLogDatabase db;
  late final FixedClock clock;
  late final LunarLogStorage storage;
  late final FakeSyncTransport transport;
  late final FakeAuthService auth;
  late final SupabaseSyncEngine engine;
  final FakeGateSignal gate = FakeGateSignal();
  final FakeTimers timers = FakeTimers();

  Future<void> start() async {
    await storage.writeSyncState(
      kDefaultSyncState.copyWith(
        boundUserId: const Value(uid),
        deviceId: 'device-1',
        lastFullPullAt: Value(t0),
      ),
    );
    engine.start();
    await engine.flush();
  }

  Future<void> sync() async {
    engine.requestSync();
    await engine.flush();
  }

  Future<SyncStateRow> state() => storage.readSyncState();

  Future<void> dispose() async {
    await engine.dispose();
    await auth.dispose();
    await db.close();
  }
}

RemoteCareNoteRow remoteNote(
  String id, {
  String profileIdOf = profileId,
  String body = 'Prefers the blue inhaler.',
  required DateTime updatedAt,
  DateTime? deletedAt,
  int serverVersion = 0,
}) => RemoteCareNoteRow(
  id: id,
  profileId: profileIdOf,
  body: body,
  updatedAt: updatedAt,
  deletedAt: deletedAt,
  serverVersion: serverVersion,
);

RemoteVisitPrepItemRow remoteItem(
  String id, {
  String profileIdOf = profileId,
  String body = 'Ask about iron levels.',
  bool isChecked = false,
  String? checkedByUserId,
  DateTime? checkedAt,
  required DateTime updatedAt,
  DateTime? deletedAt,
  int serverVersion = 0,
}) => RemoteVisitPrepItemRow(
  id: id,
  profileId: profileIdOf,
  body: body,
  isChecked: isChecked,
  checkedByUserId: checkedByUserId,
  checkedAt: checkedAt,
  updatedAt: updatedAt,
  deletedAt: deletedAt,
  serverVersion: serverVersion,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('dirty care notes and prep items push in their own arrays and '
      'clear dirty', () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await rig.storage.upsertProfile(
      id: profileId,
      displayName: 'Riley',
      isMinor: true,
      updatedAt: t0,
    );
    await rig.storage.upsertCareNote(
      profileId: profileId,
      body: 'Prefers the blue inhaler.',
    );
    await rig.storage.addVisitPrepItem(
      profileId: profileId,
      body: 'Ask about iron levels.',
    );

    await rig.start();

    final batch = rig.transport.pushes.single;
    expect(batch.careNotes, hasLength(1));
    expect(batch.careNotes.single['body'], 'Prefers the blue inhaler.');
    expect(batch.careNotes.single['profile_id'], profileId);
    expect(batch.visitPrepItems, hasLength(1));
    expect(batch.visitPrepItems.single['body'], 'Ask about iron levels.');
    expect(batch.visitPrepItems.single['is_checked'], isFalse);
    expect(
      batch.profiles,
      isNotEmpty,
      reason: 'the profile itself still rides the same batch',
    );

    expect(await rig.storage.dirtyCount(), 0);
    expect(
      (await rig.storage.getCareNotesForProfile(
        profileId,
        includeTombstones: true,
      )).single.dirty,
      isFalse,
    );
    expect(
      (await rig.storage.getVisitPrepItemsForProfile(
        profileId,
        includeTombstones: true,
      )).single.dirty,
      isFalse,
    );
  });

  test(
    'pull pages apply per table and advance each table cursor alone',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.storage.upsertProfile(
        id: profileId,
        displayName: 'Riley',
        isMinor: true,
        updatedAt: t0,
      );
      await rig.start();

      rig.transport.scriptPage(SyncTable.careNotes, [
        remoteNote(noteId, updatedAt: t0, serverVersion: 30),
      ]);
      rig.transport.scriptPage(SyncTable.visitPrepItems, [
        remoteItem(itemId,
            isChecked: true,
            checkedByUserId: 'user-dad',
            checkedAt: t0,
            updatedAt: t0,
            serverVersion: 31),
      ]);
      await rig.sync();

      final notes = await rig.storage.getCareNotesForProfile(profileId);
      expect(notes, hasLength(1));
      expect(notes.single.id, noteId);
      expect(notes.single.dirty, isFalse);

      final items = await rig.storage.getVisitPrepItemsForProfile(profileId);
      expect(items, hasLength(1));
      expect(items.single.id, itemId);
      expect(items.single.isChecked, isTrue);
      expect(items.single.checkedByUserId, 'user-dad');

      final state = await rig.state();
      expect(state.cursorCareNotes, 30);
      expect(state.cursorVisitPrepItems, 31);
      expect(state.cursorProfiles, 0,
          reason: 'no profiles page was scripted, so that cursor alone '
              'stays put');
      expect(state.cursorDayEntries, 0);
    },
  );

  test('a rejected care note stays dirty and is retried after a local edit',
      () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await rig.storage.upsertProfile(
      id: profileId,
      displayName: 'Riley',
      isMinor: true,
      updatedAt: t0,
    );
    final note = await rig.storage.upsertCareNote(
        profileId: profileId, body: 'First.');
    rig.transport.scriptPushResult(rejectedIds: [note.id]);
    await rig.start();

    // Still dirty: the rejection did not clear it.
    expect(
      (await rig.storage.getCareNotesForProfile(
        profileId,
        includeTombstones: true,
      )).single.dirty,
      isTrue,
    );

    // A local edit bumps local_rev past the rejected one, so the row is
    // pushable again on the next cycle.
    await rig.storage.upsertCareNote(
        id: note.id, profileId: profileId, body: 'Retried.');
    await rig.sync();
    final batch = rig.transport.pushes.last;
    expect(
      batch.careNotes.map((row) => row['id']),
      contains(note.id),
    );
  });

  test('a resolved (declined) prep item applies not-dirty without inserting',
      () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await rig.storage.upsertProfile(
      id: profileId,
      displayName: 'Riley',
      isMinor: true,
      updatedAt: t0,
    );
    final item = await rig.storage.addVisitPrepItem(
        profileId: profileId, body: 'Local text.');
    rig.transport.scriptPushResult(resolved: [
      remoteItem(item.id,
          body: 'Server text.',
          updatedAt: t0,
          serverVersion: 50),
    ]);
    await rig.start();

    final stored =
        (await rig.storage.getVisitPrepItemsForProfile(profileId)).single;
    expect(stored.body, 'Server text.');
    expect(stored.dirty, isFalse);

    // A resolved row for an id never held locally inserts nothing.
    rig.transport.scriptPushResult(resolved: [
      remoteItem(ghostId, updatedAt: t0, serverVersion: 51),
    ]);
    await rig.sync();
    expect(await rig.storage.getVisitPrepItemsForProfile(profileId),
        hasLength(1));
  });
}
