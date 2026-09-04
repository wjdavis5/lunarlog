/// U10 (KTD2, KTD3, KTD5): the wire codec between drift rows and the
/// `sync_push` / PostgREST JSON shape. Every column round-trips with
/// microsecond precision, the server-only `day_entries.created_at` is
/// neither emitted nor read, and malformed payloads fail with a typed
/// [RowCodecError] that never carries the row.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/sync/conflict_rules.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/data/sync/row_codec.dart';

const profileId = '01J0000000000000000000000A';
const entryId = '01J0000000000000000000000B';

void main() {
  final micro = DateTime.utc(2026, 9, 1, 10, 0, 0, 123, 456);
  final later = DateTime.utc(2026, 9, 2, 8, 30, 15, 999, 999);

  Profile makeProfile({DateTime? deletedAt, DateTime? archivedAt}) => Profile(
        id: profileId,
        displayName: deletedAt == null ? 'Kid' : '',
        isMinor: true,
        sortOrder: 3,
        archivedAt: archivedAt,
        createdAt: micro,
        updatedAt: later,
        deletedAt: deletedAt,
        dirty: true,
        localRev: 7,
      );

  DayEntry makeEntry({
    List<String> tags = const ['cramps', 'headache'],
    String? note = 'a note',
    DateTime? deletedAt,
  }) =>
      DayEntry(
        id: entryId,
        profileId: profileId,
        localDate: '2026-09-01',
        tz: 'America/New_York',
        flow: FlowLevel.medium,
        tags: tags,
        note: note,
        updatedAt: micro,
        deletedAt: deletedAt,
        dirty: true,
        localRev: 2,
      );

  group('timestamps', () {
    test('encode renders UTC ISO-8601 with microseconds', () {
      expect(encodeTimestamp(micro), '2026-09-01T10:00:00.123456Z');
      expect(
        encodeTimestamp(DateTime.utc(2026, 9, 1, 10).toLocal()),
        '2026-09-01T10:00:00.000Z',
      );
    });

    test('.123+00:00 decodes equal to .123000Z', () {
      final remote = decodeTimestamp('2026-09-01T10:00:00.123+00:00');
      final local = decodeTimestamp('2026-09-01T10:00:00.123000Z');
      expect(remote, local);
      expect(remote.isUtc, isTrue);
      expect(sameInstant(remote, local), isTrue);
      expect(remote.microsecond, 0);
      expect(remote.millisecond, 123);
    });

    test('keeps microsecond precision and non-UTC offsets', () {
      expect(
        decodeTimestamp('2026-09-01T10:00:00.123456+00:00'),
        micro,
      );
      expect(
        decodeTimestamp('2026-09-01T05:00:00.123456-05:00'),
        micro,
      );
    });

    test('accepts the Postgres text rendering (space, short offset)', () {
      expect(decodeTimestamp('2026-09-01 10:00:00.123456+00'), micro);
      expect(decodeTimestamp('2026-09-01 10:00:00+00'),
          DateTime.utc(2026, 9, 1, 10));
    });

    test('rejects garbage with a typed error', () {
      expect(() => decodeTimestamp('yesterday'), throwsA(isA<RowCodecError>()));
      expect(() => decodeTimestamp('yesterday'),
          throwsA(isNot(isA<FormatException>())));
    });
  });

  group('profiles', () {
    test('encode emits exactly the RPC keys', () {
      final json = encodeProfile(makeProfile(archivedAt: micro));
      expect(json, {
        'id': profileId,
        'display_name': 'Kid',
        'is_minor': true,
        'sort_order': 3,
        'archived_at': '2026-09-01T10:00:00.123456Z',
        'created_at': '2026-09-01T10:00:00.123456Z',
        'updated_at': '2026-09-02T08:30:15.999999Z',
        'deleted_at': null,
      });
      expect(json.keys, isNot(contains('dirty')));
      expect(json.keys, isNot(contains('local_rev')));
    });

    test('round-trips every column including microseconds', () {
      final row = makeProfile(archivedAt: micro);
      final decoded = decodeProfile({...encodeProfile(row), 'server_version': 12});
      expect(decoded.id, row.id);
      expect(decoded.displayName, row.displayName);
      expect(decoded.isMinor, row.isMinor);
      expect(decoded.sortOrder, row.sortOrder);
      expect(decoded.archivedAt, row.archivedAt);
      expect(decoded.createdAt, row.createdAt);
      expect(decoded.updatedAt, row.updatedAt);
      expect(decoded.deletedAt, isNull);
      expect(decoded.serverVersion, 12);
      expect(decoded.table, SyncTable.profiles);
      expect(decoded.isTombstone, isFalse);
    });

    test('round-trips a tombstone', () {
      final row = makeProfile(deletedAt: later);
      final json = encodeProfile(row);
      expect(json['display_name'], '');
      expect(json['deleted_at'], '2026-09-02T08:30:15.999999Z');
      final decoded = decodeProfile(json);
      expect(decoded.isTombstone, isTrue);
      expect(decoded.deletedAt, later);
      expect(decoded.serverVersion, 0, reason: 'absent server_version → 0');
    });

    test('decode ignores server-only keys', () {
      final decoded = decodeProfile({
        ...encodeProfile(makeProfile()),
        'user_id': '00000000-0000-0000-0000-000000000000',
        'server_version': 3,
      });
      expect(decoded.serverVersion, 3);
    });

    test('decode of a Postgres-rendered row equals the local instant', () {
      final decoded = decodeProfile({
        'id': profileId,
        'display_name': 'Kid',
        'is_minor': false,
        'sort_order': 0,
        'archived_at': null,
        'created_at': '2026-09-01T10:00:00.123+00:00',
        'updated_at': '2026-09-01T10:00:00.123+00:00',
        'deleted_at': null,
        'server_version': 1,
      });
      expect(decoded.updatedAt, DateTime.parse('2026-09-01T10:00:00.123000Z'));
    });

    test('non-ULID id is a typed error on decode and encode', () {
      final bad = {...encodeProfile(makeProfile()), 'id': 'not-a-ulid'};
      expect(
        () => decodeProfile(bad),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidId)
            .having((e) => e.field, 'field', 'id')
            .having((e) => e.table, 'table', SyncTable.profiles)),
      );
      expect(() => decodeProfile(bad), throwsA(isNot(isA<FormatException>())));
      final badRow = Profile(
        id: 'not-a-ulid',
        displayName: 'x',
        isMinor: false,
        sortOrder: 0,
        createdAt: micro,
        updatedAt: micro,
        dirty: true,
        localRev: 1,
      );
      expect(() => encodeProfile(badRow), throwsA(isA<RowCodecError>()));
    });

    test('missing and mistyped keys are typed errors', () {
      final base = encodeProfile(makeProfile());
      expect(
        () => decodeProfile({...base}..remove('updated_at')),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.missing)
            .having((e) => e.field, 'field', 'updated_at')),
      );
      expect(
        () => decodeProfile({...base, 'is_minor': 'yes'}),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.wrongType)
            .having((e) => e.field, 'field', 'is_minor')),
      );
      expect(
        () => decodeProfile({...base, 'updated_at': 'soon'}),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidTimestamp)
            .having((e) => e.field, 'field', 'updated_at')),
      );
    });

    test('error text never carries the payload', () {
      final bad = {...encodeProfile(makeProfile()), 'display_name': 42};
      try {
        decodeProfile(bad);
        fail('expected RowCodecError');
      } on RowCodecError catch (e) {
        expect(e.toString(), isNot(contains('42')));
        expect(e.toString(), isNot(contains(profileId)));
        expect(e.toString(), contains('display_name'));
      }
    });
  });

  group('day entries', () {
    test('encode emits exactly the RPC keys and never created_at', () {
      final json = encodeDayEntry(makeEntry());
      expect(json, {
        'id': entryId,
        'profile_id': profileId,
        'local_date': '2026-09-01',
        'tz': 'America/New_York',
        'flow': 'medium',
        'tags': ['cramps', 'headache'],
        'note': 'a note',
        'updated_at': '2026-09-01T10:00:00.123456Z',
        'deleted_at': null,
      });
      expect(json.keys, isNot(contains('created_at')));
    });

    test('round-trips every column including microseconds', () {
      final row = makeEntry();
      final decoded =
          decodeDayEntry({...encodeDayEntry(row), 'server_version': 99});
      expect(decoded.id, row.id);
      expect(decoded.profileId, row.profileId);
      expect(decoded.localDate, row.localDate);
      expect(decoded.tz, row.tz);
      expect(decoded.flow, FlowLevel.medium);
      expect(decoded.tags, ['cramps', 'headache']);
      expect(decoded.note, 'a note');
      expect(decoded.updatedAt, micro);
      expect(decoded.deletedAt, isNull);
      expect(decoded.serverVersion, 99);
      expect(decoded.table, SyncTable.dayEntries);
    });

    test('round-trips an empty tags list and a null note', () {
      final row = makeEntry(tags: const [], note: null);
      final json = encodeDayEntry(row);
      expect(json['tags'], <String>[]);
      expect(json['note'], isNull);
      final decoded = decodeDayEntry(json);
      expect(decoded.tags, isEmpty);
      expect(decoded.note, isNull);
    });

    test('round-trips a tombstone', () {
      final row = makeEntry(tags: const [], note: null, deletedAt: later);
      final json = encodeDayEntry(row);
      expect(json['deleted_at'], '2026-09-02T08:30:15.999999Z');
      final decoded = decodeDayEntry(json);
      expect(decoded.isTombstone, isTrue);
      expect(decoded.deletedAt, later);
      expect(decoded.updatedAt, micro);
    });

    test('decode ignores created_at and user_id', () {
      final decoded = decodeDayEntry({
        ...encodeDayEntry(makeEntry()),
        'created_at': '2020-01-01T00:00:00+00:00',
        'user_id': '00000000-0000-0000-0000-000000000000',
      });
      expect(decoded.id, entryId);
    });

    test('unknown flow is a typed error, not a FormatException', () {
      final bad = {...encodeDayEntry(makeEntry()), 'flow': 'torrential'};
      expect(
        () => decodeDayEntry(bad),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.unknownFlow)
            .having((e) => e.field, 'field', 'flow')
            .having((e) => e.table, 'table', SyncTable.dayEntries)),
      );
      expect(() => decodeDayEntry(bad), throwsA(isNot(isA<FormatException>())));
      try {
        decodeDayEntry(bad);
      } on RowCodecError catch (e) {
        expect(e.toString(), isNot(contains('torrential')));
      }
    });

    test('non-ULID ids are typed errors', () {
      final base = encodeDayEntry(makeEntry());
      expect(
        () => decodeDayEntry({...base, 'id': '01J0000000000000000000000I'}),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidId)
            .having((e) => e.field, 'field', 'id')),
      );
      expect(
        () => decodeDayEntry({...base, 'profile_id': 'short'}),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidId)
            .having((e) => e.field, 'field', 'profile_id')),
      );
    });

    test('bad date, tags and types are typed errors', () {
      final base = encodeDayEntry(makeEntry());
      expect(
        () => decodeDayEntry({...base, 'local_date': '2026/09/01'}),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidDate)
            .having((e) => e.field, 'field', 'local_date')),
      );
      expect(
        () => decodeDayEntry({...base, 'tags': 'cramps'}),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidTags)),
      );
      expect(
        () => decodeDayEntry({
          ...base,
          'tags': ['cramps', 3]
        }),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidTags)),
      );
      expect(
        () => decodeDayEntry({...base, 'note': 5}),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.wrongType)
            .having((e) => e.field, 'field', 'note')),
      );
      expect(
        () => decodeDayEntry({...base}..remove('profile_id')),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.missing)),
      );
    });

    test('encode validates the local row too', () {
      final bad = DayEntry(
        id: entryId,
        profileId: profileId,
        localDate: '1 Sep 2026',
        tz: 'UTC',
        flow: FlowLevel.none,
        tags: const [],
        updatedAt: micro,
        dirty: true,
        localRev: 1,
      );
      expect(
        () => encodeDayEntry(bad),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidDate)),
      );
    });
    test('decodes attribution fields when present', () {
      final decoded = decodeDayEntry({
        ...encodeDayEntry(makeEntry()),
        'server_version': 1,
        'logged_by_user_id': 'user-123',
        'last_modified_by_user_id': 'user-456',
      });
      expect(decoded.loggedByUserId, 'user-123');
      expect(decoded.lastModifiedByUserId, 'user-456');
    });
  });

  group('profile guardians', () {
    test('round-trips profile guardian row', () {
      final json = {
        'id': 'g1-uuid',
        'profile_id': profileId,
        'user_id': 'u1-uuid',
        'role': 'co_parent',
        'status': 'accepted',
        'display_name': 'Dad',
        'invited_by': 'mom-uuid',
        'created_at': '2026-09-01T10:00:00.123456Z',
        'updated_at': '2026-09-01T10:00:00.123456Z',
        'server_version': 5,
      };
      final decoded = decodeProfileGuardian(json);
      expect(decoded.id, 'g1-uuid');
      expect(decoded.profileId, profileId);
      expect(decoded.userId, 'u1-uuid');
      expect(decoded.role, 'co_parent');
      expect(decoded.status, 'accepted');
      expect(decoded.displayName, 'Dad');
      expect(decoded.invitedBy, 'mom-uuid');
      expect(decoded.serverVersion, 5);
      expect(decoded.table, SyncTable.profileGuardians);
    });
  });

  group('table dispatch', () {
    test('table names match the remote schema', () {
      expect(syncTableName(SyncTable.profiles), 'profiles');
      expect(syncTableName(SyncTable.dayEntries), 'day_entries');
      expect(syncTableName(SyncTable.profileGuardians), 'profile_guardians');
      expect(syncTableFromName('profiles'), SyncTable.profiles);
      expect(syncTableFromName('day_entries'), SyncTable.dayEntries);
      expect(syncTableFromName('profile_guardians'), SyncTable.profileGuardians);
      expect(syncTableFromName('settings'), isNull);
    });

    test('decodeRemoteRow decodes by table', () {
      final p = decodeRemoteRow(SyncTable.profiles, encodeProfile(makeProfile()));
      expect(p, isA<RemoteProfileRow>());
      final d = decodeRemoteRow(SyncTable.dayEntries, encodeDayEntry(makeEntry()));
      expect(d, isA<RemoteDayEntryRow>());
      final g = decodeRemoteRow(SyncTable.profileGuardians, {
        'id': 'g1',
        'profile_id': profileId,
        'user_id': 'u1',
        'role': 'caregiver',
        'status': 'accepted',
        'created_at': '2026-09-01T10:00:00Z',
        'updated_at': '2026-09-01T10:00:00Z',
      });
      expect(g, isA<RemoteProfileGuardianRow>());
    });

    test('decodeResolvedRow dispatches on the "table" key', () {
      final p = decodeResolvedRow(
          {...encodeProfile(makeProfile()), 'table': 'profiles'});
      expect(p, isA<RemoteProfileRow>());
      final d = decodeResolvedRow(
          {...encodeDayEntry(makeEntry()), 'table': 'day_entries'});
      expect(d, isA<RemoteDayEntryRow>());
      expect(
        () => decodeResolvedRow({...encodeProfile(makeProfile())}),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.unknownTable)),
      );
      expect(
        () => decodeResolvedRow(
            {...encodeProfile(makeProfile()), 'table': 'settings'}),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.unknownTable)),
      );
    });
  });
}
