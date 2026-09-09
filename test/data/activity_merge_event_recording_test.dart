/// Storage-level tests for the device-local merge-outcome recording hooks
/// (issue #124, AC4): a same-date collision or push resolution that
/// discards a `flow`/`note` value records exactly one bounded,
/// content-free event — and nothing else does.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/domain/activity/merge_events.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late LunarLogStorage storage;
  // t0 stamps every local write; remote rows carry explicit stamps.
  final t0 = DateTime.utc(2026, 1, 15, 8);

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    storage = LunarLogStorage(db, clock: () => t0);
  });

  Future<String> seedProfile(String name) async {
    final profile = await storage.upsertProfile(displayName: name, isMinor: true);
    return profile.id;
  }

  RemoteDayEntryRow remoteRow(
    String id,
    String profileId, {
    String localDate = '2026-01-15',
    FlowLevel flow = FlowLevel.medium,
    List<String> tags = const ['remote'],
    String? note = 'from remote',
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
        flow: flow,
        tags: tags,
        note: note,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        loggedByUserId: loggedByUserId,
        lastModifiedByUserId: lastModifiedByUserId,
      );

  Future<List<MergeEvent>> eventsFor(String profileId) async =>
      decodeMergeEvents(
          await storage.getSetting(activityMergeEventsKey(profileId)));

  group('same-date resolver, local loser', () {
    test('differing note and flow records one event; winner attributed, '
        'loser honestly null (offline-created local row)', () async {
      final profileId = await seedProfile('A');
      await storage.upsertDayEntry(
        profileId: profileId,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.heavy,
        tags: const ['local'],
        note: 'local note',
      );
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        flow: FlowLevel.light,
        note: 'remote note',
        updatedAt: DateTime.utc(2026, 1, 16),
        loggedByUserId: 'dad',
        lastModifiedByUserId: 'dad',
      ));
      final events = await eventsFor(profileId);
      expect(events, hasLength(1));
      final event = events.single;
      expect(event.winnerActorId, 'dad');
      // Local writes never stamp attribution (the server does, on push), so
      // the local loser has no actor — rendered without a name, not faked.
      expect(event.loserActorId, isNull);
      expect(event.discardedNote, isTrue);
      expect(event.discardedFlow, isTrue);
      expect(event.localDateIso, '2026-01-15');
      expect(event.occurredAt, DateTime.utc(2026, 1, 16));
      // Idempotency key: loser entry id @ resolution stamp.
      expect(event.id, contains('@2026-01-16T00:00:00.000Z'));
    });

    test('identical payload records nothing (nothing was discarded)', () async {
      final profileId = await seedProfile('A');
      await storage.upsertDayEntry(
        profileId: profileId,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.medium,
        note: 'same note',
      );
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        flow: FlowLevel.medium,
        note: 'same note',
        updatedAt: DateTime.utc(2026, 1, 16),
      ));
      expect(await eventsFor(profileId), isEmpty);
    });

    test('tags-only difference records nothing (tags are unioned)', () async {
      final profileId = await seedProfile('A');
      await storage.upsertDayEntry(
        profileId: profileId,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.medium,
        tags: const ['a'],
        note: 'same note',
      );
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        flow: FlowLevel.medium,
        tags: const ['b'],
        note: 'same note',
        updatedAt: DateTime.utc(2026, 1, 16),
      ));
      expect(await eventsFor(profileId), isEmpty);
    });

    test('flow-only and note-only differences set exactly one flag each',
        () async {
      final profileId = await seedProfile('A');
      // Two attributed remote rows for one date: mom's copy lands first,
      // dad's newer copy collides with it. Only the flow differs.
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        flow: FlowLevel.heavy,
        note: 'same note',
        updatedAt: DateTime.utc(2026, 1, 15),
        loggedByUserId: 'mom',
        lastModifiedByUserId: 'mom',
      ));
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000B',
        profileId,
        flow: FlowLevel.light,
        note: 'same note',
        updatedAt: DateTime.utc(2026, 1, 16),
        loggedByUserId: 'dad',
        lastModifiedByUserId: 'dad',
      ));
      var events = await eventsFor(profileId);
      expect(events, hasLength(1));
      expect(events.single.discardedFlow, isTrue);
      expect(events.single.discardedNote, isFalse);
      expect(events.single.winnerActorId, 'dad');
      expect(events.single.loserActorId, 'mom');
      expect(events.single.id, startsWith('01JREMOTE00000000000000000A@'));

      // A second date where only the note differs (text vs null).
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000C',
        profileId,
        localDate: '2026-01-16',
        note: 'a note',
        updatedAt: DateTime.utc(2026, 1, 16),
        loggedByUserId: 'mom',
        lastModifiedByUserId: 'mom',
      ));
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000D',
        profileId,
        localDate: '2026-01-16',
        note: null,
        updatedAt: DateTime.utc(2026, 1, 17),
        loggedByUserId: 'dad',
        lastModifiedByUserId: 'dad',
      ));
      events = await eventsFor(profileId);
      expect(events, hasLength(2));
      // Newest first: the Jan-17 note-only event.
      expect(events.first.discardedNote, isTrue);
      expect(events.first.discardedFlow, isFalse);
    });
  });

  group('same-date resolver, remote loser', () {
    test('an older incoming copy losing to the local row records the discard',
        () async {
      final profileId = await seedProfile('A');
      // The local row (stamped at t0, Jan 15 08:00) is newer than the Jan 14
      // incoming copy and carries different values.
      await storage.upsertDayEntry(
        profileId: profileId,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.heavy,
        note: 'kept note',
      );
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        flow: FlowLevel.spotting,
        note: 'discarded note',
        updatedAt: DateTime.utc(2026, 1, 14),
        loggedByUserId: 'dad',
        lastModifiedByUserId: 'dad',
      ));
      final events = await eventsFor(profileId);
      expect(events, hasLength(1));
      // The local winner has no attribution stamps (offline-created); the
      // losing remote copy was dad's.
      expect(events.single.winnerActorId, isNull);
      expect(events.single.loserActorId, 'dad');
      expect(events.single.discardedNote, isTrue);
      expect(events.single.discardedFlow, isTrue);
      // Stamped with the surviving local winner's timestamp, per the rule.
      expect(events.single.occurredAt, t0);
    });

    test('an identical older incoming copy records nothing', () async {
      final profileId = await seedProfile('A');
      await storage.upsertDayEntry(
        profileId: profileId,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.medium,
        tags: const ['x'],
        note: 'same note',
      );
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        flow: FlowLevel.medium,
        tags: const ['x'],
        note: 'same note',
        updatedAt: DateTime.utc(2026, 1, 14),
      ));
      expect(await eventsFor(profileId), isEmpty);
    });
  });

  group('applyResolved overwrites', () {
    test('a differing resolved copy records exactly one idempotent event',
        () async {
      final profileId = await seedProfile('A');
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        note: 'mom note',
        updatedAt: DateTime.utc(2026, 1, 15),
        loggedByUserId: 'mom',
        lastModifiedByUserId: 'mom',
      ));
      final resolved = remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        note: 'dad note',
        flow: FlowLevel.light,
        updatedAt: DateTime.utc(2026, 1, 16),
        loggedByUserId: 'mom',
        lastModifiedByUserId: 'dad',
      );
      // The server's resolution keeps dad's copy over the stored mom copy.
      await storage.applyResolved([resolved]);
      var events = await eventsFor(profileId);
      expect(events, hasLength(1));
      expect(events.single.winnerActorId, 'dad');
      expect(events.single.loserActorId, 'mom');
      expect(events.single.discardedNote, isTrue);
      expect(events.single.discardedFlow, isTrue);

      // Re-delivering the same resolved row (the per-id rule re-applies on
      // ties) must not duplicate the event.
      await storage.applyResolved([resolved]);
      events = await eventsFor(profileId);
      expect(events, hasLength(1));
    });

    test('an identical resolved copy records nothing', () async {
      final profileId = await seedProfile('A');
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        note: 'same note',
        updatedAt: DateTime.utc(2026, 1, 15),
      ));
      await storage.applyResolved([
        remoteRow(
          '01JREMOTE00000000000000000A',
          profileId,
          note: 'same note',
          updatedAt: DateTime.utc(2026, 1, 16),
        ),
      ]);
      expect(await eventsFor(profileId), isEmpty);
    });

    test('an ordinary (non-resolved) pull overwrite records nothing',
        () async {
      final profileId = await seedProfile('A');
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        note: 'old note',
        updatedAt: DateTime.utc(2026, 1, 15),
      ));
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        note: 'new note', // differing value, but via the normal pull path
        updatedAt: DateTime.utc(2026, 1, 16),
      ));
      expect(await eventsFor(profileId), isEmpty);
    });

    test('a tombstone resolution records nothing (the removed feed row '
        'covers it)', () async {
      final profileId = await seedProfile('A');
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000A',
        profileId,
        note: 'note',
        updatedAt: DateTime.utc(2026, 1, 15),
      ));
      await storage.applyResolved([
        remoteRow(
          '01JREMOTE00000000000000000A',
          profileId,
          note: 'note',
          updatedAt: DateTime.utc(2026, 1, 16),
          deletedAt: DateTime.utc(2026, 1, 16),
        ),
      ]);
      expect(await eventsFor(profileId), isEmpty);
    });
  });

  test('the stored event payload carries no note text and no tag codes',
      () async {
    final profileId = await seedProfile('A');
    await storage.upsertDayEntry(
      profileId: profileId,
      localDate: '2026-01-15',
      tz: 'UTC',
      flow: FlowLevel.heavy,
      tags: const ['private-tag'],
      note: 'private note text',
    );
    await storage.applyRemoteDayEntry(remoteRow(
      '01JREMOTE00000000000000000A',
      profileId,
      note: 'other private text',
      updatedAt: DateTime.utc(2026, 1, 16),
    ));
    final raw = await storage.getSetting(activityMergeEventsKey(profileId));
    expect(raw, isNotNull);
    expect(raw!, isNot(contains('private')));
    expect(raw, isNot(contains('private-tag')));
  });

  test('events accumulate per profile without crossing keys', () async {
    final a = await seedProfile('A');
    final b = await seedProfile('B');
    var n = 0;
    for (final profileId in [a, b]) {
      await storage.upsertDayEntry(
        profileId: profileId,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.heavy,
        note: 'local note',
      );
      await storage.applyRemoteDayEntry(remoteRow(
        '01JREMOTE00000000000000000$n',
        profileId,
        note: 'different',
        updatedAt: DateTime.utc(2026, 1, 16),
      ));
      n++;
    }
    final eventsA = await eventsFor(a);
    final eventsB = await eventsFor(b);
    expect(eventsA, hasLength(1));
    expect(eventsB, hasLength(1));
    expect(eventsA.single.profileId, a);
    expect(eventsB.single.profileId, b);
  });
}
