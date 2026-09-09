/// Unit tests for the derived activity feed domain module (issue #124):
/// row classification from attribution stamps, ordering, actor-label
/// resolution, the unread marker, relative ages, and the device-local
/// merge-event codec.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/activity/activity_feed.dart';
import 'package:lunarlog/domain/activity/merge_events.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';

ProfileGuardian guardian(
  String userId, {
  String? displayName,
  GuardianRole role = GuardianRole.coParent,
  GuardianStatus status = GuardianStatus.accepted,
  DateTime? updatedAt,
}) =>
    ProfileGuardian(
      id: 'g-$userId',
      profileId: 'p1',
      userId: userId,
      role: role,
      status: status,
      displayName: displayName,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
    );

DayEntry entry(
  String id,
  LocalDate date, {
  DateTime? updatedAt,
  String? loggedBy,
  String? modifiedBy,
  FlowLevel flow = FlowLevel.heavy,
  List<String> tags = const ['cramps'],
  String? note = 'a note',
  DateTime? deletedAt,
}) =>
    DayEntry(
      id: id,
      profileId: 'p1',
      localDate: date,
      tz: 'UTC',
      flow: flow,
      tags: tags,
      note: note,
      updatedAt: updatedAt ?? DateTime.utc(2026, 9, 1),
      deletedAt: deletedAt,
      loggedByUserId: loggedBy,
      lastModifiedByUserId: modifiedBy,
    );

void main() {
  final d1 = LocalDate(2026, 9, 1);
  final d2 = LocalDate(2026, 9, 2);

  group('buildActivityFeed', () {
    test('one row per entry, newest first, entry ids as row identity', () {
      final data = buildActivityFeed(
        entries: [
          entry('a', d1, updatedAt: DateTime.utc(2026, 9, 1)),
          entry('b', d2,
              updatedAt: DateTime.utc(2026, 9, 2), loggedBy: 'u1'),
        ],
        guardians: const [],
        mergeEvents: const [],
      );
      expect(data.items.map((i) => i.id), ['entry:b', 'entry:a']);
      final times = data.items.map((i) => i.occurredAt).toList();
      expect(times, equals([...times]..sort((a, b) => b.compareTo(a))));
    });

    test('classifier: fresh log, edit by another guardian, removal',
        () async {
      final data = buildActivityFeed(
        entries: [
          // Logger and modifier agree (or are both stamped by the same
          // writer): "logged".
          entry('fresh', d1, loggedBy: 'mom', modifiedBy: 'mom'),
          // Modifier differs from logger: "updated", logger is secondary.
          entry('edited', d1, loggedBy: 'mom', modifiedBy: 'dad'),
          // Tombstone: "removed", attributed to the last modifier.
          entry(
            'gone',
            d1,
            loggedBy: 'mom',
            modifiedBy: 'dad',
            deletedAt: DateTime.utc(2026, 9, 3),
          ),
          // No attribution at all: still a row, with a null actor.
          entry('legacy', d1),
        ],
        guardians: const [],
        mergeEvents: const [],
      );
      final byId = {for (final item in data.items) item.id: item};
      expect(byId['entry:fresh']!.kind, ActivityKind.logged);
      expect(byId['entry:fresh']!.actorId, 'mom');
      expect(byId['entry:edited']!.kind, ActivityKind.updated);
      expect(byId['entry:edited']!.actorId, 'dad');
      expect(byId['entry:edited']!.secondaryActorId, 'mom');
      expect(byId['entry:gone']!.kind, ActivityKind.removed);
      expect(byId['entry:gone']!.actorId, 'dad');
      expect(byId['entry:legacy']!.kind, ActivityKind.logged);
      expect(byId['entry:legacy']!.actorId, isNull);
    });

    test('content discretion: live rows carry glance facts, removed carry none',
        () {
      final data = buildActivityFeed(
        entries: [
          entry('live', d1,
              loggedBy: 'mom',
              flow: FlowLevel.light,
              tags: const ['cramps', 'headache'],
              note: 'secret text'),
          entry('gone', d1,
              loggedBy: 'mom',
              flow: FlowLevel.heavy,
              tags: const ['cramps'],
              note: 'secret text',
              deletedAt: DateTime.utc(2026, 9, 3)),
          entry('noNote', d1, loggedBy: 'mom', note: null),
          entry('emptyNote', d1, loggedBy: 'mom', note: ''),
        ],
        guardians: const [],
        mergeEvents: const [],
      );
      final byId = {for (final item in data.items) item.id: item};
      final live = byId['entry:live']!;
      expect(live.flow, FlowLevel.light);
      expect(live.tagCount, 2);
      expect(live.hasNote, isTrue);
      final gone = byId['entry:gone']!;
      expect(gone.flow, isNull);
      expect(gone.tagCount, 0);
      expect(gone.hasNote, isFalse);
      expect(byId['entry:noNote']!.hasNote, isFalse);
      expect(byId['entry:emptyNote']!.hasNote, isFalse);
    });

    test('merge events and revoked guardians join the feed, ordered by time',
        () {
      final data = buildActivityFeed(
        entries: [
          entry('e', d1, updatedAt: DateTime.utc(2026, 9, 2), loggedBy: 'mom'),
        ],
        guardians: [
          guardian('mom'),
          guardian('dad'),
          guardian('ex',
              status: GuardianStatus.revoked,
              updatedAt: DateTime.utc(2026, 9, 3)),
        ],
        mergeEvents: [
          MergeEvent(
            id: 'loser@2026-09-04T00:00:00.000Z',
            profileId: 'p1',
            localDateIso: '2026-09-01',
            occurredAt: DateTime.utc(2026, 9, 4),
            winnerActorId: 'dad',
            loserActorId: 'mom',
            discardedNote: true,
            discardedFlow: false,
          ),
        ],
      );
      expect(data.items.map((i) => i.kind), [
        ActivityKind.mergeOutcome, // 2026-09-04
        ActivityKind.accessRemoved, // 2026-09-03
        ActivityKind.logged, // 2026-09-02
      ]);
      final merge = data.items.first;
      expect(merge.localDateIso, '2026-09-01');
      expect(merge.actorId, 'dad');
      expect(merge.secondaryActorId, 'mom');
      expect(merge.discardedNote, isTrue);
      expect(merge.discardedFlow, isFalse);
    });

    test('accepted and pending guardian rows produce no feed rows', () {
      final data = buildActivityFeed(
        entries: const [],
        guardians: [
          guardian('mom', updatedAt: DateTime.utc(2026, 9, 1)),
          guardian('dad', updatedAt: DateTime.utc(2026, 9, 2)),
          guardian('pending', status: GuardianStatus.pending),
        ],
        mergeEvents: const [],
      );
      expect(data.items, isEmpty);
    });

    test('isShared: two or more accepted guardians, else not', () {
      final shared = buildActivityFeed(
        entries: const [],
        guardians: [guardian('mom'), guardian('dad')],
        mergeEvents: const [],
      );
      final single = buildActivityFeed(
        entries: const [],
        guardians: [guardian('mom')],
        mergeEvents: const [],
      );
      final revokedOnly = buildActivityFeed(
        entries: const [],
        guardians: [
          guardian('mom'),
          guardian('dad', status: GuardianStatus.revoked),
        ],
        mergeEvents: const [],
      );
      expect(shared.isShared, isTrue);
      expect(single.isShared, isFalse);
      expect(revokedOnly.isShared, isFalse);
    });

    test('limit caps the row count, keeping the newest', () {
      final data = buildActivityFeed(
        entries: [
          for (var i = 0; i < 5; i++)
            entry('e$i', d1, updatedAt: DateTime.utc(2026, 9, i + 1)),
        ],
        guardians: const [],
        mergeEvents: const [],
        limit: 3,
      );
      expect(data.items.length, 3);
      expect(data.items.map((i) => i.id),
          ['entry:e4', 'entry:e3', 'entry:e2']);
    });
  });

  group('activityActorLabel', () {
    final guardians = [
      guardian('u1', displayName: 'Mom'),
      guardian('u2'), // no display name -> role label
      guardian('u3', displayName: ''), // empty display name -> role label
    ];

    test('null id stays null; never an invented actor', () {
      expect(activityActorLabel(null, 'me', guardians), isNull);
    });

    test('current user reads as "you"', () {
      expect(activityActorLabel('me', 'me', guardians), 'you');
      expect(activityActorLabel('me', 'me', const []), 'you');
    });

    test('display name, then role label, then "a guardian", never a uuid',
        () {
      expect(activityActorLabel('u1', 'me', guardians), 'Mom');
      expect(activityActorLabel('u2', 'me', guardians), 'Co-Parent');
      expect(activityActorLabel('u3', 'me', guardians), 'Co-Parent');
      expect(activityActorLabel('unknown-uuid', 'me', guardians),
          'a guardian');
      expect(activityActorLabel('unknown-uuid', 'me', const []),
          'a guardian');
    });

    test('a revoked guardian still resolves by name (historical rows)', () {
      final revoked = [
        guardian('ex', displayName: 'Ex', status: GuardianStatus.revoked),
      ];
      expect(activityActorLabel('ex', 'me', revoked), 'Ex');
    });
  });

  group('isActivityNew', () {
    final item = ActivityItem(
      id: 'x',
      kind: ActivityKind.logged,
      occurredAt: DateTime.utc(2026, 9, 2),
    );

    test('null lastSeen (never opened) marks nothing new', () {
      expect(isActivityNew(item, null), isFalse);
    });

    test('newer than the stamp is new; older or equal is not', () {
      expect(isActivityNew(item, DateTime.utc(2026, 9, 1)), isTrue);
      expect(isActivityNew(item, DateTime.utc(2026, 9, 2)), isFalse);
      expect(isActivityNew(item, DateTime.utc(2026, 9, 3)), isFalse);
    });
  });

  group('relativeActivityAge', () {
    final now = DateTime.utc(2026, 9, 7, 12);

    test('bucketing: just now, minutes, hours, days, absolute', () {
      expect(
          relativeActivityAge(now.subtract(const Duration(seconds: 30)),
              () => now),
          'just now');
      expect(
          relativeActivityAge(
              now.subtract(const Duration(minutes: 5)), () => now),
          '5m ago');
      expect(
          relativeActivityAge(
              now.subtract(const Duration(hours: 3)), () => now),
          '3h ago');
      expect(
          relativeActivityAge(
              now.subtract(const Duration(days: 2)), () => now),
          '2d ago');
      expect(
          relativeActivityAge(DateTime.utc(2026, 8, 20), () => now),
          isNot(contains('ago')));
    });

    test('a future stamp (clock skew) reads as just now, never negative',
        () {
      expect(
          relativeActivityAge(
              now.add(const Duration(minutes: 5)), () => now),
          'just now');
    });
  });

  group('merge-event codec', () {
    final event = MergeEvent(
      id: 'loser@2026-09-04T00:00:00.000Z',
      profileId: 'p1',
      localDateIso: '2026-09-01',
      occurredAt: DateTime.utc(2026, 9, 4),
      winnerActorId: 'dad',
      loserActorId: 'mom',
      discardedNote: true,
      discardedFlow: false,
    );

    test('encode/decode round-trips', () {
      final decoded = decodeMergeEvents(encodeMergeEvents([event]));
      expect(decoded, [event]);
    });

    test('keys are per-profile and the cap constant is set', () {
      expect(activityMergeEventsKey('p1'), 'activity_merge_events_p1');
      expect(activityLastSeenKey('p1'), 'activity_last_seen_p1');
      expect(kMergeEventCap, 200);
    });

    test('null, empty, non-list, and corrupt JSON decode to empty', () {
      expect(decodeMergeEvents(null), isEmpty);
      expect(decodeMergeEvents(''), isEmpty);
      expect(decodeMergeEvents('"just a string"'), isEmpty);
      expect(decodeMergeEvents('{not json'), isEmpty);
    });

    test('malformed elements drop out; good ones survive', () {
      final stored =
          '[{"id":"loser@x","profileId":"p1","localDate":"2026-09-01",'
          '"occurredAt":"2026-09-04T00:00:00.000Z","winner":null,"loser":"mom",'
          '"note":true,"flow":false},'
          '{"id":42},{"no":"fields"},"strings are not maps",'
          '{"id":"bad-date","profileId":"p1","localDate":"2026-09-01",'
          '"occurredAt":"not-a-date","note":true,"flow":false}]';
      final decoded = decodeMergeEvents(stored);
      expect(decoded, hasLength(1));
      expect(decoded.single.id, 'loser@x');
      expect(decoded.single.winnerActorId, isNull);
      expect(decoded.single.discardedNote, isTrue);
    });

    test('append is idempotent by id, newest-first, and capped', () {
      final older = MergeEvent(
        id: 'a@t0',
        profileId: 'p1',
        localDateIso: '2026-09-01',
        occurredAt: DateTime.utc(2026, 9, 1),
        discardedNote: true,
        discardedFlow: false,
      );
      final newer = MergeEvent(
        id: 'b@t1',
        profileId: 'p1',
        localDateIso: '2026-09-02',
        occurredAt: DateTime.utc(2026, 9, 2),
        discardedNote: false,
        discardedFlow: true,
      );
      final appended = appendMergeEvent([older], newer);
      expect(appended.map((e) => e.id), ['b@t1', 'a@t0']);
      // Re-append either event: unchanged (idempotent).
      expect(appendMergeEvent(appended, newer), same(appended));
      expect(appendMergeEvent(appended, older).map((e) => e.id),
          ['b@t1', 'a@t0']);

      // Cap evicts the oldest.
      var events = <MergeEvent>[older];
      for (var i = 0; i < 5; i++) {
        events = appendMergeEvent(events, MergeEvent(
          id: 'n$i@t',
          profileId: 'p1',
          localDateIso: '2026-09-01',
          occurredAt: DateTime.utc(2026, 9, 10 + i),
          discardedNote: true,
          discardedFlow: false,
        ), cap: 3);
      }
      expect(events, hasLength(3));
      expect(events.map((e) => e.id), isNot(contains('a@t0')));
    });
  });
}
