/// Codec tests for Issue #130's `day_entry_merge_events` rows: the
/// `p_merge_events` element and the PostgREST/`sync_pull` decode, matching
/// the care-content codec tests' posture.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/data/sync/row_codec.dart';

DayEntryMergeEventData eventRow({
  String id = '01ARZ3NDEKTSV4RRFFQ69G5MEA',
  String losingValueText = 'a discarded note',
  String field = 'note',
}) =>
    DayEntryMergeEventData(
      id: id,
      profileId: '01ARZ3NDEKTSV4RRFFQ69G5MEB',
      localDate: '2026-01-15',
      winningRowId: '01ARZ3NDEKTSV4RRFFQ69G5MEC',
      losingRowId: '01ARZ3NDEKTSV4RRFFQ69G5MED',
      field: field,
      losingValueText: losingValueText,
      losingAuthorUserId: 'user-loser',
      winningAuthorUserId: 'user-winner',
      createdAt: DateTime.utc(2026, 1, 16, 5),
      updatedAt: DateTime.utc(2026, 1, 16, 5),
      dirty: true,
      localRev: 1,
    );

void main() {
  group('encodeDayEntryMergeEvent', () {
    test('emits exactly the keys sync_push allows (created_at excluded)',
        () async {
      expect(encodeDayEntryMergeEvent(eventRow()), {
        'id': '01ARZ3NDEKTSV4RRFFQ69G5MEA',
        'profile_id': '01ARZ3NDEKTSV4RRFFQ69G5MEB',
        'local_date': '2026-01-15',
        'winning_row_id': '01ARZ3NDEKTSV4RRFFQ69G5MEC',
        'losing_row_id': '01ARZ3NDEKTSV4RRFFQ69G5MED',
        'field': 'note',
        'losing_value_text': 'a discarded note',
        'losing_author_user_id': 'user-loser',
        'winning_author_user_id': 'user-winner',
        'updated_at': '2026-01-16T05:00:00.000Z',
      });
    });

    test('rejects a non-ULID id and a malformed date with a typed error',
        () async {
      expect(
        () => encodeDayEntryMergeEvent(eventRow(id: 'nope')),
        throwsA(isA<RowCodecError>()),
      );
      final malformed = DayEntryMergeEventData(
        id: '01ARZ3NDEKTSV4RRFFQ69G5MEA',
        profileId: '01ARZ3NDEKTSV4RRFFQ69G5MEB',
        localDate: '2026-1-5',
        winningRowId: '01ARZ3NDEKTSV4RRFFQ69G5MEC',
        losingRowId: '01ARZ3NDEKTSV4RRFFQ69G5MED',
        field: 'note',
        losingValueText: 'x',
        createdAt: DateTime.utc(2026, 1, 16),
        updatedAt: DateTime.utc(2026, 1, 16),
        dirty: false,
        localRev: 0,
      );
      expect(
        () => encodeDayEntryMergeEvent(malformed),
        throwsA(isA<RowCodecError>()),
      );
    });
  });

  group('decodeDayEntryMergeEvent', () {
    test('round-trips a server row, normalising field and defaulting '
        'created_at to updated_at', () async {
      final decoded = decodeDayEntryMergeEvent({
        'id': '01ARZ3NDEKTSV4RRFFQ69G5MEA',
        'profile_id': '01ARZ3NDEKTSV4RRFFQ69G5MEB',
        'local_date': '2026-01-15',
        'winning_row_id': '01ARZ3NDEKTSV4RRFFQ69G5MEC',
        'losing_row_id': '01ARZ3NDEKTSV4RRFFQ69G5MED',
        'field': 'flow',
        'losing_value_text': 'heavy',
        'losing_author_user_id': null,
        'winning_author_user_id': null,
        'created_at': '2026-01-16 05:00:00+00',
        'updated_at': '2026-01-16T05:00:00Z',
        'server_version': 41,
      });
      expect(decoded.id, '01ARZ3NDEKTSV4RRFFQ69G5MEA');
      expect(decoded.field, 'flow');
      expect(decoded.losingValueText, 'heavy');
      expect(decoded.createdAt, DateTime.utc(2026, 1, 16, 5));
      expect(decoded.serverVersion, 41);
      expect(decoded.table, SyncTable.dayEntryMergeEvents);
      expect(decoded.deletedAt, isNull,
          reason: 'the table has no tombstone');
    });

    test('an unrecognised field degrades to note, never throws', () async {
      final decoded = decodeDayEntryMergeEvent({
        'id': '01ARZ3NDEKTSV4RRFFQ69G5MEA',
        'profile_id': '01ARZ3NDEKTSV4RRFFQ69G5MEB',
        'local_date': '2026-01-15',
        'winning_row_id': '01ARZ3NDEKTSV4RRFFQ69G5MEC',
        'losing_row_id': '01ARZ3NDEKTSV4RRFFQ69G5MED',
        'field': 'tags',
        'losing_value_text': '[]',
        'updated_at': '2026-01-16T05:00:00Z',
      });
      expect(decoded.field, 'note');
    });
  });

  test('syncTableName covers the new table', () {
    expect(syncTableName(SyncTable.dayEntryMergeEvents),
        'day_entry_merge_events');
    expect(syncTableFromName('day_entry_merge_events'),
        SyncTable.dayEntryMergeEvents);
  });
}
