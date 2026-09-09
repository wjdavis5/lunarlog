/// Issue #128: the row codec's care_notes/visit_prep_items halves — encode
/// (drift row → `sync_push` JSON), decode (server JSON →
/// [RemoteCareNoteRow]/[RemoteVisitPrepItemRow]), the table-name map, and
/// `decodeResolvedRow`'s dispatch on the `table` key. Mirrors
/// `modes_row_codec_test.dart`'s shape.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/data/sync/row_codec.dart';

const profileId = '01J8ZQ9K7MC2X3V4B5N6P7Q8R9';
const noteId = '01J8ZQ9K7MC2X3V4B5N6P7Q8T1';
const itemId = '01J8ZQ9K7MC2X3V4B5N6P7Q8T2';

final DateTime t0 = DateTime.utc(2026, 9, 2, 10);

CareNoteData noteRow({
  String idOf = noteId,
  String profileIdOf = profileId,
  String body = 'Prefers the blue inhaler.',
  DateTime? updatedAt,
  DateTime? deletedAt,
}) =>
    CareNoteData(
      id: idOf,
      profileId: profileIdOf,
      body: body,
      updatedAt: updatedAt ?? t0,
      deletedAt: deletedAt,
      dirty: true,
      localRev: 2,
    );

VisitPrepItemData itemRow({
  String idOf = itemId,
  String profileIdOf = profileId,
  String body = 'Ask about iron levels.',
  bool isChecked = false,
  String? checkedByUserId,
  DateTime? checkedAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) =>
    VisitPrepItemData(
      id: idOf,
      profileId: profileIdOf,
      body: body,
      isChecked: isChecked,
      checkedByUserId: checkedByUserId,
      checkedAt: checkedAt,
      updatedAt: updatedAt ?? t0,
      deletedAt: deletedAt,
      dirty: true,
      localRev: 2,
    );

void main() {
  group('encodeCareNote', () {
    test('emits exactly the p_care_notes shape', () {
      expect(encodeCareNote(noteRow()), {
        'id': noteId,
        'profile_id': profileId,
        'body': 'Prefers the blue inhaler.',
        'updated_at': '2026-09-02T10:00:00.000Z',
        'deleted_at': null,
      });
    });

    test('a non-ULID id is a typed invalidId, never sent', () {
      expect(
        () => encodeCareNote(noteRow(idOf: 'nope')),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidId)
            .having((e) => e.table, 'table', SyncTable.careNotes)),
      );
    });

    test('a non-ULID profile_id is a typed invalidId, never sent', () {
      expect(
        () => encodeCareNote(noteRow(profileIdOf: 'nope')),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidId)
            .having((e) => e.table, 'table', SyncTable.careNotes)),
      );
    });
  });

  group('encodeVisitPrepItem', () {
    test('emits exactly the p_visit_prep_items shape (no check stamp)',
        () {
      expect(encodeVisitPrepItem(itemRow()), {
        'id': itemId,
        'profile_id': profileId,
        'body': 'Ask about iron levels.',
        'is_checked': false,
        'updated_at': '2026-09-02T10:00:00.000Z',
        'deleted_at': null,
      });
    });

    test('a checked row still emits no checked_by/checked_at (server-stamped)',
        () {
      final json = encodeVisitPrepItem(itemRow(
        isChecked: true,
        checkedByUserId: 'user-dad',
        checkedAt: t0,
      ));
      expect(json['is_checked'], isTrue);
      expect(json.containsKey('checked_by_user_id'), isFalse,
          reason: 'the stamp is never client-sent, even when locally known');
      expect(json.containsKey('checked_at'), isFalse);
    });

    test('a non-ULID id is a typed invalidId, never sent', () {
      expect(
        () => encodeVisitPrepItem(itemRow(idOf: 'nope')),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidId)
            .having((e) => e.table, 'table', SyncTable.visitPrepItems)),
      );
    });
  });

  group('decodeCareNote', () {
    test('round-trips every column', () {
      final row = decodeCareNote({
        'id': noteId,
        'profile_id': profileId,
        'body': 'Prefers the blue inhaler.',
        'updated_at': '2026-09-02T10:00:00+00:00',
        'deleted_at': null,
        'server_version': 42,
        'logged_by_user_id': 'user-mom',
        'last_modified_by_user_id': 'user-dad',
      });
      expect(row.id, noteId);
      expect(row.profileId, profileId);
      expect(row.body, 'Prefers the blue inhaler.');
      expect(row.updatedAt, t0);
      expect(row.deletedAt, isNull);
      expect(row.serverVersion, 42);
      expect(row.loggedByUserId, 'user-mom');
      expect(row.lastModifiedByUserId, 'user-dad');
      expect(row.table, SyncTable.careNotes);
      expect(row.isTombstone, isFalse);
    });

    test('a tombstone decodes with its sentinel body', () {
      final row = decodeCareNote({
        'id': noteId,
        'profile_id': profileId,
        'body': '',
        'updated_at': '2026-09-02T10:00:00+00:00',
        'deleted_at': '2026-09-03T10:00:00+00:00',
      });
      expect(row.isTombstone, isTrue);
      expect(row.body, isEmpty);
    });

    test('a missing body is a typed missing error, never a null smuggle',
        () {
      expect(
        () => decodeCareNote({
          'id': noteId,
          'profile_id': profileId,
          'updated_at': '2026-09-02T10:00:00+00:00',
        }),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.missing)),
      );
    });
  });

  group('decodeVisitPrepItem', () {
    test('round-trips every column including the check stamp', () {
      final row = decodeVisitPrepItem({
        'id': itemId,
        'profile_id': profileId,
        'body': 'Ask about iron levels.',
        'is_checked': true,
        'checked_by_user_id': 'user-dad',
        'checked_at': '2026-09-02T12:00:00+00:00',
        'updated_at': '2026-09-02T12:00:00+00:00',
        'deleted_at': null,
        'server_version': 7,
      });
      expect(row.id, itemId);
      expect(row.isChecked, isTrue);
      expect(row.checkedByUserId, 'user-dad');
      expect(row.checkedAt, DateTime.utc(2026, 9, 2, 12));
      expect(row.serverVersion, 7);
      expect(row.table, SyncTable.visitPrepItems);
    });

    test('an absent is_checked degrades to unchecked, never throws', () {
      final row = decodeVisitPrepItem({
        'id': itemId,
        'profile_id': profileId,
        'body': 'Ask about iron levels.',
        'updated_at': '2026-09-02T10:00:00+00:00',
      });
      expect(row.isChecked, isFalse);
      expect(row.checkedByUserId, isNull);
    });
  });

  group('table names (Issue #128)', () {
    test('syncTableName covers both new tables', () {
      expect(syncTableName(SyncTable.careNotes), 'care_notes');
      expect(syncTableName(SyncTable.visitPrepItems), 'visit_prep_items');
    });

    test('syncTableFromName inverts both new tables', () {
      expect(syncTableFromName('care_notes'), SyncTable.careNotes);
      expect(
          syncTableFromName('visit_prep_items'), SyncTable.visitPrepItems);
      expect(syncTableFromName('care_notes_typo'), isNull);
    });

    test('decodeResolvedRow dispatches on both new table keys', () {
      final note = decodeResolvedRow({
        'table': 'care_notes',
        'id': noteId,
        'profile_id': profileId,
        'body': 'Hi.',
        'updated_at': '2026-09-02T10:00:00+00:00',
      });
      expect(note, isA<RemoteCareNoteRow>());

      final item = decodeResolvedRow({
        'table': 'visit_prep_items',
        'id': itemId,
        'profile_id': profileId,
        'body': 'Hi.',
        'updated_at': '2026-09-02T10:00:00+00:00',
      });
      expect(item, isA<RemoteVisitPrepItemRow>());
    });
  });
}
