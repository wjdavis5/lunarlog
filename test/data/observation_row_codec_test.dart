/// Issue #240: the wire codec for `observations` — `encodeObservation`/
/// `decodeObservation`, unknown-field tolerance (category/code are never
/// validated against a closed set), tombstone handling, and `raw`'s
/// JSON-text <-> JSON-value round trip. Mirrors `row_codec_test.dart`'s
/// shape for the existing tables.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/data/sync/row_codec.dart';

const dayEntryId = '01J0000000000000000000000B';
const profileId = '01J0000000000000000000000A';
const observationId = '01J0000000000000000000000C';

Observation _observation({
  String? code = 'migraine',
  double? valueNum,
  String? valueText,
  String? unit,
  int? intensity = 3,
  bool excluded = false,
  String source = 'manual',
  String? sourceId,
  String? raw,
  DateTime? observedAt,
  DateTime? deletedAt,
  DateTime? exportedToPlatformAt,
}) =>
    Observation(
      id: observationId,
      dayEntryId: dayEntryId,
      profileId: profileId,
      localDate: '2026-09-01',
      observedAt: observedAt,
      tz: 'America/New_York',
      category: 'pain',
      code: code,
      valueNum: valueNum,
      valueText: valueText,
      unit: unit,
      intensity: intensity,
      excluded: excluded,
      source: source,
      sourceId: sourceId,
      raw: raw,
      exportedToPlatformAt: exportedToPlatformAt,
      updatedAt: DateTime.utc(2026, 9, 1, 10, 0, 0, 123, 456),
      deletedAt: deletedAt,
      dirty: true,
      localRev: 2,
    );

JsonRow _json({
  Object? id = observationId,
  Object? dayEntryIdValue = dayEntryId,
  Object? profileIdValue = profileId,
  Object? localDate = '2026-09-01',
  Object? category = 'pain',
  Object? code = 'migraine',
  Object? intensity = 3,
  Object? excluded = false,
  Object? source = 'manual',
  Object? raw,
  Object? exportedToPlatformAt,
  Object? updatedAt = '2026-09-01T10:00:00.123456Z',
  Object? deletedAt,
  Object? serverVersion,
  Map<String, Object?> extra = const {},
}) =>
    {
      'id': id,
      'day_entry_id': dayEntryIdValue,
      'profile_id': profileIdValue,
      'local_date': localDate,
      'observed_at': null,
      'tz': 'America/New_York',
      'category': category,
      'code': code,
      'value_num': null,
      'value_text': null,
      'unit': null,
      'intensity': intensity,
      'excluded': excluded,
      'source': source,
      'source_id': null,
      'exported_to_platform_at': exportedToPlatformAt,
      'raw': raw,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
      'server_version': serverVersion,
      ...extra,
    };

void main() {
  group('encodeObservation', () {
    test('emits every key sync_push accepts', () {
      final json = encodeObservation(_observation());
      expect(json['id'], observationId);
      expect(json['day_entry_id'], dayEntryId);
      expect(json['profile_id'], profileId);
      expect(json['local_date'], '2026-09-01');
      expect(json['category'], 'pain');
      expect(json['code'], 'migraine');
      expect(json['intensity'], 3);
      expect(json['excluded'], false);
      expect(json['source'], 'manual');
      expect(json['updated_at'], '2026-09-01T10:00:00.123456Z');
      expect(json['deleted_at'], isNull);
    });

    test('emits exported_to_platform_at (Issue #186 round-trip marker)', () {
      final exported = DateTime.utc(2026, 9, 2, 8);
      final json = encodeObservation(_observation(exportedToPlatformAt: exported));
      expect(json['exported_to_platform_at'], '2026-09-02T08:00:00.000Z');
      // Never exported -> null on the wire.
      expect(encodeObservation(_observation())['exported_to_platform_at'],
          isNull);
    });

    test('throws invalidId for a malformed id', () {
      final row = _observation().copyWith(id: 'not-a-ulid');
      expect(
        () => encodeObservation(row),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidId)
            .having((e) => e.field, 'field', 'id')),
      );
    });

    test('throws invalidDate for a malformed local_date', () {
      final row = _observation().copyWith(localDate: 'not-a-date');
      expect(
        () => encodeObservation(row),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidDate)),
      );
    });

    test('decodes stored JSON-text raw to a JSON value on the wire, not a '
        'doubly-encoded string', () {
      final json = encodeObservation(
          _observation(raw: '{"type":"bbt","value":36.5}'));
      expect(json['raw'], {'type': 'bbt', 'value': 36.5});
    });

    test('a raw value that is not valid JSON throws invalidRaw', () {
      expect(
        () => encodeObservation(_observation(raw: 'not json')),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidRaw)
            .having((e) => e.field, 'field', 'raw')),
      );
    });

    test('null raw stays null on the wire', () {
      expect(encodeObservation(_observation(raw: null))['raw'], isNull);
    });
  });

  group('decodeObservation', () {
    test('decodes a full row into a RemoteObservationRow', () {
      final row = decodeObservation(_json(serverVersion: 7));
      expect(row, isA<RemoteObservationRow>());
      expect(row.id, observationId);
      expect(row.dayEntryId, dayEntryId);
      expect(row.profileId, profileId);
      expect(row.localDate, '2026-09-01');
      expect(row.category, 'pain');
      expect(row.code, 'migraine');
      expect(row.intensity, 3);
      expect(row.excluded, false);
      expect(row.source, 'manual');
      expect(row.serverVersion, 7);
      expect(row.table, SyncTable.observations);
      expect(row.isTombstone, isFalse);
    });

    test('decodes exported_to_platform_at; an absent key decodes to null '
        '(Issue #186)', () {
      final row = decodeObservation(
          _json(exportedToPlatformAt: '2026-09-02T08:00:00Z'));
      expect(row.exportedToPlatformAt, DateTime.utc(2026, 9, 2, 8));
      // A pre-#186 server never sends the key — the pull must not fail.
      final absent = decodeObservation(_json(exportedToPlatformAt: null));
      expect(absent.exportedToPlatformAt, isNull);
    });

    test('server_version null (absent) defaults to 0', () {
      final row = decodeObservation(_json());
      expect(row.serverVersion, 0);
    });

    test('a category/code outside any known taxonomy round-trips '
        'unchanged (Issue #240 D-10: no closed-set validation here)', () {
      final row = decodeObservation(
          _json(category: 'a_brand_new_category', code: 'unknown_code_123'));
      expect(row.category, 'a_brand_new_category');
      expect(row.code, 'unknown_code_123');
    });

    test('a null code decodes to null (numeric-only category)', () {
      final row = decodeObservation(_json(code: null));
      expect(row.code, isNull);
    });

    test('deleted_at present marks the row a tombstone', () {
      final row = decodeObservation(_json(
          deletedAt: '2026-09-02T00:00:00Z', updatedAt: '2026-09-02T00:00:00Z'));
      expect(row.isTombstone, isTrue);
      expect(row.deletedAt, isNotNull);
    });

    test('a raw JSON value on the wire is re-encoded to JSON text for '
        'client-side storage', () {
      final row = decodeObservation(_json(raw: {'type': 'bbt', 'value': 36.5}));
      expect(row.raw, '{"type":"bbt","value":36.5}');
    });

    test('null raw stays null', () {
      final row = decodeObservation(_json(raw: null));
      expect(row.raw, isNull);
    });

    test('an unrecognised source string is tolerated as raw text (source '
        'normalisation, if any, happens later at the domain boundary)', () {
      final row = decodeObservation(_json(source: 'some_future_source'));
      expect(row.source, 'some_future_source');
    });

    test('a malformed id throws invalidId', () {
      expect(
        () => decodeObservation(_json(id: 'not-a-ulid')),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidId)),
      );
    });

    test('a missing category decodes as null (tombstones carry no category '
        'after the redaction fix; the server CHECK keeps live rows non-null)',
        () {
      final json = _json()..remove('category');
      expect(decodeObservation(json).category, isNull);
    });

    test('a non-numeric value_num throws wrongType', () {
      final json = _json(extra: {'value_num': 'not a number'});
      expect(
        () => decodeObservation(json),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.wrongType)),
      );
    });

    test('value_num accepts a numeric string (postgrest numeric rendering)',
        () {
      final json = _json(extra: {'value_num': '98.6'});
      final row = decodeObservation(json);
      expect(row.valueNum, 98.6);
    });
  });

  group('decodeRemoteRow dispatch', () {
    test('SyncTable.observations dispatches to decodeObservation', () {
      final row = decodeRemoteRow(SyncTable.observations, _json());
      expect(row, isA<RemoteObservationRow>());
    });
  });

  group('syncTableName / syncTableFromName', () {
    test('round-trips observations', () {
      expect(syncTableName(SyncTable.observations), 'observations');
      expect(syncTableFromName('observations'), SyncTable.observations);
    });
  });
}
