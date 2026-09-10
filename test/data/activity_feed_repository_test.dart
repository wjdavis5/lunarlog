/// Repository tests for the derived activity feed (issue #124): the
/// combined snapshot stream, live re-emission when sync applies land (no
/// restart — AC3's plumbing), and the device-local last-seen stamp.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/repositories/activity_feed_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/activity/activity_feed.dart';
import 'package:lunarlog/domain/activity/activity_feed_snapshot.dart';
import 'package:lunarlog/domain/activity/merge_events.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late LunarLogStorage storage;
  late ActivityFeedRepository repository;
  final t0 = DateTime.utc(2026, 1, 15, 8);

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    storage = LunarLogStorage(db, clock: () => t0);
    repository = ActivityFeedRepository(storage);
  });

  /// Lets Drift's stream notifications (async, microtask-delivered) settle.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Collects snapshots until [until] returns true (called after each
  /// emission and once after [settle]), then cancels — the repository's
  /// stream never closes on its own.
  Future<List<ActivityFeedSnapshot>> collect(
      String profileId, bool Function(List<ActivityFeedSnapshot>) until,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final emitted = <ActivityFeedSnapshot>[];
    final done = Completer<void>();
    final subscription = repository.watch(profileId).listen(emitted.add);
    unawaited(() async {
      while (!done.isCompleted) {
        await settle();
        if (until(emitted)) {
          done.complete();
          return;
        }
      }
    }());
    await done.future.timeout(timeout);
    await subscription.cancel();
    return emitted;
  }

  RemoteProfileGuardianRow guardianRow(
    String profileId,
    String userId, {
    String role = 'co_parent',
    String status = 'accepted',
    String? displayName,
    DateTime? updatedAt,
  }) =>
      RemoteProfileGuardianRow(
        id: 'g-$userId',
        profileId: profileId,
        userId: userId,
        role: role,
        status: status,
        displayName: displayName,
        invitedBy: null,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
      );

  RemoteDayEntryRow entryRow(
    String profileId,
    String id,
    String localDate, {
    required DateTime updatedAt,
    String? loggedByUserId,
    String? lastModifiedByUserId,
    DateTime? deletedAt,
  }) =>
      RemoteDayEntryRow(
        id: id,
        profileId: profileId,
        localDate: localDate,
        tz: 'UTC',
        flow: FlowLevel.medium,
        tags: const [],
        note: null,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        loggedByUserId: loggedByUserId,
        lastModifiedByUserId: lastModifiedByUserId,
      );

  test('watch emits one full snapshot once every source has reported',
      () async {
    final profile =
        await storage.upsertProfile(displayName: 'A', isMinor: true);
    await storage.applyRemoteRows([
      guardianRow(profile.id, 'mom', displayName: 'Mom'),
      guardianRow(profile.id, 'dad', displayName: 'Dad'),
      entryRow(profile.id, '01JENTRY00000000000000000A', '2026-01-15',
          updatedAt: DateTime.utc(2026, 1, 15),
          loggedByUserId: 'dad',
          lastModifiedByUserId: 'dad'),
    ]);
    final emitted = await collect(profile.id, (list) => list.isNotEmpty);
    // Sources may interleave, but every emission is a complete snapshot —
    // the first one already carries all four inputs' effects.
    expect(emitted, isNotEmpty);
    final snapshot = emitted.last;
    expect(snapshot.isShared, isTrue);
    expect(snapshot.lastSeen, isNull);
    expect(snapshot.items, hasLength(1));
    expect(snapshot.items.single.kind, ActivityKind.logged);
    expect(snapshot.items.single.actorId, 'dad');
    expect(snapshot.guardians, hasLength(2));
    expect(snapshot.hasNewItems, isFalse, reason: 'never opened: no baseline');
  });

  test('a synced change re-emits without resubscribing (AC3 plumbing)',
      () async {
    final profile =
        await storage.upsertProfile(displayName: 'A', isMinor: true);
    await storage.applyRemoteRows([
      guardianRow(profile.id, 'mom', displayName: 'Mom'),
      guardianRow(profile.id, 'dad', displayName: 'Dad'),
    ]);
    final emitted = <ActivityFeedSnapshot>[];
    final subscription = repository.watch(profile.id).listen(emitted.add);
    await settle();
    expect(emitted, isNotEmpty);
    expect(emitted.last.items, isEmpty);
    final baseline = emitted.length;

    // Another guardian's write lands via the sync apply path; the open
    // subscription re-emits with the new row — no restart, no resubscribe.
    await storage.applyRemoteRows([
      entryRow(profile.id, '01JENTRY00000000000000000A', '2026-01-15',
          updatedAt: DateTime.utc(2026, 1, 16),
          loggedByUserId: 'dad',
          lastModifiedByUserId: 'dad'),
    ]);
    await settle();
    expect(emitted.length, greaterThan(baseline));
    expect(emitted.last.items, hasLength(1));
    expect(emitted.last.items.single.actorId, 'dad');
    await subscription.cancel();
  });

  test('markSeen stamps the device-local key and the stream re-emits it',
      () async {
    final profile =
        await storage.upsertProfile(displayName: 'A', isMinor: true);
    await storage.applyRemoteRows([
      guardianRow(profile.id, 'mom', displayName: 'Mom'),
      guardianRow(profile.id, 'dad', displayName: 'Dad'),
      entryRow(profile.id, '01JENTRY00000000000000000A', '2026-01-15',
          updatedAt: DateTime.utc(2026, 1, 15),
          loggedByUserId: 'dad',
          lastModifiedByUserId: 'dad'),
    ]);
    // An old baseline: the Jan-15 row is newer than it.
    await storage.setSetting(
      key: activityLastSeenKey(profile.id),
      value: DateTime.utc(2026, 1, 10).toIso8601String(),
    );
    final before =
        await collect(profile.id, (list) => list.isNotEmpty);
    expect(before.last.lastSeen, DateTime.utc(2026, 1, 10));
    expect(before.last.hasNewItems, isTrue);

    await repository.markSeen(profile.id);
    final after = await collect(profile.id,
        (list) => list.isNotEmpty && list.last.lastSeen != DateTime.utc(2026, 1, 10));
    expect(after.last.lastSeen, isNotNull);
    final raw = await storage.getSetting(activityLastSeenKey(profile.id));
    expect(raw, isNotNull);
    expect(after.last.lastSeen, DateTime.parse(raw!));
    // The Jan-15 row predates the fresh (real-clock) stamp: nothing new.
    expect(after.last.hasNewItems, isFalse);
  });

  test('merge events recorded by the storage layer surface as feed rows',
      () async {
    final profile =
        await storage.upsertProfile(displayName: 'A', isMinor: true);
    await storage.applyRemoteRows([
      guardianRow(profile.id, 'mom', displayName: 'Mom'),
      guardianRow(profile.id, 'dad', displayName: 'Dad'),
      entryRow(profile.id, '01JENTRY00000000000000000A', '2026-01-15',
          updatedAt: DateTime.utc(2026, 1, 15),
          loggedByUserId: 'mom',
          lastModifiedByUserId: 'mom'),
    ]);
    // Dad's newer copy for the same date collides and discards mom's
    // (null-note vs 'dad note') values.
    await storage.applyRemoteDayEntry(RemoteDayEntryRow(
      id: '01JENTRY00000000000000000B',
      profileId: profile.id,
      localDate: '2026-01-15',
      tz: 'UTC',
      flow: FlowLevel.heavy,
      tags: const [],
      note: 'dad note',
      updatedAt: DateTime.utc(2026, 1, 16),
      deletedAt: null,
      loggedByUserId: 'dad',
      lastModifiedByUserId: 'dad',
    ));
    final emitted = await collect(profile.id, (list) => list.isNotEmpty);
    final items = emitted.last.items;
    expect(
      items.any((item) =>
          item.kind == ActivityKind.mergeOutcome &&
          item.actorId == 'dad' &&
          item.secondaryActorId == 'mom' &&
          item.discardedNote),
      isTrue,
    );
  });

  test('single-guardian and guardian-less profiles are not shared',
      () async {
    final profile =
        await storage.upsertProfile(displayName: 'A', isMinor: true);
    final none = await collect(profile.id, (list) => list.isNotEmpty);
    expect(none.single.isShared, isFalse);

    await storage.applyRemoteRows([guardianRow(profile.id, 'mom')]);
    final one = await collect(profile.id,
        (list) => list.isNotEmpty && list.last.guardians.isNotEmpty);
    expect(one.last.isShared, isFalse);
    expect(one.last.guardians, hasLength(1));
  });
}
