/// Issue #801: the row codec's guardian_notes half — encode (drift row →
/// `sync_push` JSON), decode (server JSON → [RemoteGuardianNoteRow]), the
/// table-name map, and `decodeResolvedRow`'s dispatch on the `table` key.
/// Mirrors `care_content_row_codec_test.dart`'s shape.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/data/sync/row_codec.dart';

const profileId = '01J8ZQ9K7MC2X3V4B5N6P7Q8R9';
const noteId = '01J8ZQ9K7MC2X3V4B5N6P7Q8T3';

final DateTime t0 = DateTime.utc(2026, 9, 12, 10);

GuardianNoteData noteRow({
  String idOf = noteId,
  String profileIdOf = profileId,
  String localDate = '2026-09-12',
  String tz = 'America/New_York',
  String body = 'Seemed withdrawn this week.',
  DateTime? updatedAt,
  DateTime? deletedAt,
  String? loggedByUserId,
}) =>
    GuardianNoteData(
      id: idOf,
      profileId: profileIdOf,
      localDate: localDate,
      tz: tz,
      body: body,
      updatedAt: updatedAt ?? t0,
      deletedAt: deletedAt,
      dirty: true,
      localRev: 2,
      loggedByUserId: loggedByUserId,
    );

void main() {
  group('encodeGuardianNote', () {
    test('emits exactly the p_guardian_notes shape', () {
      expect(encodeGuardianNote(noteRow()), {
        'id': noteId,
        'profile_id': profileId,
        'local_date': '2026-09-12',
        'tz': 'America/New_York',
        'body': 'Seemed withdrawn this week.',
        'updated_at': '2026-09-12T10:00:00.000Z',
        'deleted_at': null,
      });
    });

    test('never emits logged_by_user_id (the server stamps the author)', () {
      final json = encodeGuardianNote(noteRow(loggedByUserId: 'user-mom'));
      expect(json.containsKey('logged_by_user_id'), isFalse,
          reason: 'a client must never forge or re-attribute an author');
    });

    test('a non-ULID id is a typed invalidId, never sent', () {
      expect(
        () => encodeGuardianNote(noteRow(idOf: 'nope')),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidId)
            .having((e) => e.table, 'table', SyncTable.guardianNotes)),
      );
    });

    test('a non-ULID profile_id is a typed invalidId, never sent', () {
      expect(
        () => encodeGuardianNote(noteRow(profileIdOf: 'nope')),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidId)
            .having((e) => e.table, 'table', SyncTable.guardianNotes)),
      );
    });
  });

  group('decodeGuardianNote', () {
    test('round-trips every column, including the author stamps', () {
      final row = decodeGuardianNote({
        'id': noteId,
        'profile_id': profileId,
        'local_date': '2026-09-12',
        'tz': 'America/New_York',
        'body': 'Seemed withdrawn this week.',
        'updated_at': '2026-09-12T10:00:00+00:00',
        'deleted_at': null,
        'server_version': 42,
        'logged_by_user_id': 'user-mom',
        'last_modified_by_user_id': 'user-dad',
      });
      expect(row.id, noteId);
      expect(row.profileId, profileId);
      expect(row.localDate, '2026-09-12');
      expect(row.tz, 'America/New_York');
      expect(row.body, 'Seemed withdrawn this week.');
      expect(row.updatedAt, t0);
      expect(row.deletedAt, isNull);
      expect(row.serverVersion, 42);
      expect(row.loggedByUserId, 'user-mom');
      expect(row.lastModifiedByUserId, 'user-dad');
      expect(row.table, SyncTable.guardianNotes);
      expect(row.isTombstone, isFalse);
    });

    test('a tombstone decodes with its sentinel body', () {
      final row = decodeGuardianNote({
        'id': noteId,
        'profile_id': profileId,
        'local_date': '2026-09-12',
        'tz': 'UTC',
        'body': '',
        'updated_at': '2026-09-12T10:00:00+00:00',
        'deleted_at': '2026-09-13T10:00:00+00:00',
      });
      expect(row.isTombstone, isTrue);
      expect(row.body, isEmpty);
    });

    test('a missing local_date is a typed missing error', () {
      expect(
        () => decodeGuardianNote({
          'id': noteId,
          'profile_id': profileId,
          'tz': 'UTC',
          'body': 'Hi.',
          'updated_at': '2026-09-12T10:00:00+00:00',
        }),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.missing)),
      );
    });
  });

  group('table names (Issue #801)', () {
    test('syncTableName covers guardian_notes', () {
      expect(syncTableName(SyncTable.guardianNotes), 'guardian_notes');
    });

    test('syncTableFromName inverts guardian_notes', () {
      expect(syncTableFromName('guardian_notes'), SyncTable.guardianNotes);
      expect(syncTableFromName('guardian_notes_typo'), isNull);
    });

    test('decodeResolvedRow dispatches on the guardian_notes table key', () {
      final row = decodeResolvedRow({
        'table': 'guardian_notes',
        'id': noteId,
        'profile_id': profileId,
        'local_date': '2026-09-12',
        'tz': 'UTC',
        'body': 'Hi.',
        'updated_at': '2026-09-12T10:00:00+00:00',
      });
      expect(row, isA<RemoteGuardianNoteRow>());
    });
  });
}
