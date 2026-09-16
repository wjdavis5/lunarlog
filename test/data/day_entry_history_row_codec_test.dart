/// Codec tests for Issue #170's `day_entry_history` rows: the
/// PostgREST/`sync_pull` decode, matching the merge-event codec tests'
/// posture. The table is PULL-ONLY — there is no encoder by design (rows
/// are server-trigger-written), so only the decode half exists.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/data/sync/row_codec.dart';

const String _id = '01ARZ3NDEKTSV4RRFFQ69G5MEA';
const String _entryId = '01ARZ3NDEKTSV4RRFFQ69G5MEC';

Map<String, Object?> historyJson({
  String? changeKind,
  Object? changedFields,
}) =>
    {
      'id': _id,
      'entry_id': _entryId,
      'profile_id': '01ARZ3NDEKTSV4RRFFQ69G5MEB',
      'changed_by_user_id': 'user-a',
      'changed_at': '2026-01-16T05:00:00.000Z',
      'change_kind': changeKind ?? 'logged',
      'changed_fields': changedFields ?? const ['local_date', 'note'],
      'server_version': 9,
    };

void main() {
  test('decodes every field of a pulled row', () {
    final row = decodeDayEntryHistory(historyJson());
    expect(row.id, _id);
    expect(row.entryId, _entryId);
    expect(row.profileId, '01ARZ3NDEKTSV4RRFFQ69G5MEB');
    expect(row.changedByUserId, 'user-a');
    expect(row.changedAt, DateTime.utc(2026, 1, 16, 5));
    expect(row.changeKind, 'logged');
    expect(row.changedFields, ['local_date', 'note']);
    expect(row.serverVersion, 9);
    expect(row.table, SyncTable.dayEntryHistory);
    expect(syncTableName(row.table), 'day_entry_history');
    // The RemoteRow plumbing maps the immutable-row shape.
    expect(row.updatedAt, row.changedAt);
    expect(row.deletedAt, isNull);
    expect(row.isTombstone, isFalse);
  });

  test('normalises each change_kind against the closed set and degrades an '
      'unknown value to updated', () {
    expect(decodeDayEntryHistory(historyJson(changeKind: 'logged')).changeKind,
        'logged');
    expect(decodeDayEntryHistory(historyJson(changeKind: 'updated')).changeKind,
        'updated');
    expect(
        decodeDayEntryHistory(historyJson(changeKind: 'tombstoned'))
            .changeKind,
        'tombstoned');
    expect(
        decodeDayEntryHistory(historyJson(changeKind: 'merged_discard'))
            .changeKind,
        'merged_discard');
    expect(
        decodeDayEntryHistory(historyJson(changeKind: 'nonsense'))
            .changeKind,
        'updated',
        reason: 'a broken writer must not fail a pull over display metadata');
  });

  test('decodeRemoteRow dispatches the table', () {
    final row = decodeRemoteRow(
        SyncTable.dayEntryHistory, historyJson(changeKind: 'updated'));
    expect(row, isA<RemoteDayEntryHistoryRow>());
  });

  test('rejects a malformed row with a typed error', () {
    expect(
      () => decodeDayEntryHistory(historyJson(changedFields: 'note')),
      throwsA(isA<RowCodecError>()),
      reason: 'changed_fields must be an array of column names',
    );
    expect(
      () => decodeDayEntryHistory({...historyJson(), 'id': 'nope'}),
      throwsA(isA<RowCodecError>()),
      reason: 'the row id must be a ULID',
    );
  });
}
