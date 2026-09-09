/// Issue #188: the row codec's profile_modes/cycle_overrides halves —
/// encode (drift row → `sync_push` JSON), decode (server JSON →
/// [RemoteProfileModeRow]/[RemoteCycleOverrideRow], including the
/// closed-set `LifecycleMode` normalisation), the table-name map, and
/// `decodeResolvedRow`'s dispatch on the `table` key. Mirrors
/// `row_codec_test.dart`/`observation_row_codec_test.dart`'s shape.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/data/sync/row_codec.dart';

const profileId = '01J8ZQ9K7MC2X3V4B5N6P7Q8R9';
const overrideId = '01J8ZQ9K7MC2X3V4B5N6P7Q8S0';

final DateTime t0 = DateTime.utc(2026, 9, 2, 10);

ProfileModeData modeRow({
  String profileIdOf = profileId,
  String mode = 'perimenopause',
  String? modeStartedOn = '2026-09-02',
  String? birthControlMethod = 'copper_iud',
  String? birthControlStartedOn = '2026-01-10',
  String? birthControlStoppedOn,
  bool healthSyncConsent = true,
  DateTime? updatedAt,
}) =>
    ProfileModeData(
      profileId: profileIdOf,
      mode: mode,
      modeStartedOn: modeStartedOn,
      birthControlMethod: birthControlMethod,
      birthControlStartedOn: birthControlStartedOn,
      birthControlStoppedOn: birthControlStoppedOn,
      healthSyncConsent: healthSyncConsent,
      updatedAt: updatedAt ?? t0,
      dirty: true,
      localRev: 3,
    );

CycleOverrideData overrideRow({
  String cycleStartDate = '2026-08-14',
  bool excludedFromAverage = true,
  bool manualStart = false,
  String? noteId = 'note-1',
  DateTime? updatedAt,
  DateTime? deletedAt,
}) =>
    CycleOverrideData(
      id: overrideId,
      profileId: profileId,
      cycleStartDate: cycleStartDate,
      excludedFromAverage: excludedFromAverage,
      manualStart: manualStart,
      noteId: noteId,
      updatedAt: updatedAt ?? t0,
      deletedAt: deletedAt,
      dirty: true,
      localRev: 2,
    );

void main() {
  group('encodeProfileMode', () {
    test('emits exactly the p_profile_modes shape', () {
      expect(encodeProfileMode(modeRow()), {
        'profile_id': profileId,
        'mode': 'perimenopause',
        'mode_started_on': '2026-09-02',
        'birth_control_method': 'copper_iud',
        'birth_control_started_on': '2026-01-10',
        'birth_control_stopped_on': null,
        'health_sync_consent': true,
        'updated_at': '2026-09-02T10:00:00.000Z',
      });
    });

    test('a non-ULID profile_id is a typed invalidId, never sent', () {
      expect(
        () => encodeProfileMode(modeRow(profileIdOf: 'nope')),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidId)
            .having((e) => e.table, 'table', SyncTable.profileModes)),
      );
    });
  });

  group('decodeProfileMode', () {
    test('round-trips every column', () {
      final row = decodeProfileMode({
        'profile_id': profileId,
        'mode': 'conceive',
        'mode_started_on': '2026-09-02',
        'birth_control_method': 'pill',
        'birth_control_started_on': '2026-01-01',
        'birth_control_stopped_on': '2026-06-01',
        'health_sync_consent': true,
        'updated_at': '2026-09-02T10:00:00+00:00',
        'server_version': 42,
      });
      expect(row, isA<RemoteProfileModeRow>());
      expect(row.profileId, profileId);
      expect(row.mode, 'conceive');
      expect(row.modeStartedOn, '2026-09-02');
      expect(row.birthControlMethod, 'pill');
      expect(row.birthControlStartedOn, '2026-01-01');
      expect(row.birthControlStoppedOn, '2026-06-01');
      expect(row.healthSyncConsent, isTrue);
      expect(row.serverVersion, 42);
      expect(row.deletedAt, isNull, reason: 'the table has no tombstone');
      expect(row.table, SyncTable.profileModes);
      expect(row.id, profileId, reason: 'the profile id is the row id');
    });

    test('an absent or unrecognised mode normalises to tracking (the '
        'profiles.mode precedent — never crash a pull)', () {
      for (final raw in <String?>[null, 'perimenopaus', 'future_mode']) {
        final row = decodeProfileMode({
          'profile_id': profileId,
          'mode': raw,
          'updated_at': '2026-09-02T10:00:00+00:00',
        });
        expect(row.mode, 'tracking', reason: 'mode raw value: $raw');
      }
    });

    test('absent optional columns default; a malformed date is a typed '
        'invalidDate', () {
      final row = decodeProfileMode({
        'profile_id': profileId,
        'mode': 'tracking',
        'updated_at': '2026-09-02T10:00:00+00:00',
      });
      expect(row.modeStartedOn, isNull);
      expect(row.birthControlMethod, isNull);
      expect(row.healthSyncConsent, isFalse);

      expect(
        () => decodeProfileMode({
          'profile_id': profileId,
          'updated_at': '2026-09-02T10:00:00+00:00',
          'birth_control_started_on': '2026/01/01',
        }),
        throwsA(isA<RowCodecError>()
            .having((e) => e.field, 'field', 'birth_control_started_on')),
      );
    });
  });

  group('encodeCycleOverride', () {
    test('emits exactly the p_cycle_overrides shape, tombstone included',
        () {
      final at = DateTime.utc(2026, 9, 6, 11);
      expect(encodeCycleOverride(overrideRow(updatedAt: at)), {
        'id': overrideId,
        'profile_id': profileId,
        'cycle_start_date': '2026-08-14',
        'excluded_from_average': true,
        'manual_start': false,
        'note_id': 'note-1',
        'updated_at': '2026-09-06T11:00:00.000Z',
        'deleted_at': null,
      });
      expect(
        encodeCycleOverride(overrideRow(
            updatedAt: at, deletedAt: at))['deleted_at'],
        '2026-09-06T11:00:00.000Z',
      );
    });

    test('bad id, profile_id and cycle_start_date are typed errors', () {
      expect(
        () => encodeCycleOverride(CycleOverrideData(
          id: 'nope',
          profileId: profileId,
          cycleStartDate: '2026-08-14',
          excludedFromAverage: false,
          manualStart: false,
          updatedAt: t0,
          dirty: true,
          localRev: 1,
        )),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidId)),
      );
      expect(
        () => encodeCycleOverride(CycleOverrideData(
          id: overrideId,
          profileId: 'nope',
          cycleStartDate: '2026-08-14',
          excludedFromAverage: false,
          manualStart: false,
          updatedAt: t0,
          dirty: true,
          localRev: 1,
        )),
        throwsA(isA<RowCodecError>()),
      );
      expect(
        () => encodeCycleOverride(CycleOverrideData(
          id: overrideId,
          profileId: profileId,
          cycleStartDate: 'Aug 14',
          excludedFromAverage: false,
          manualStart: false,
          updatedAt: t0,
          dirty: true,
          localRev: 1,
        )),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.invalidDate)),
      );
    });
  });

  group('decodeCycleOverride', () {
    test('round-trips every column, tombstone included', () {
      final row = decodeCycleOverride({
        'id': overrideId,
        'profile_id': profileId,
        'cycle_start_date': '2026-08-14',
        'excluded_from_average': true,
        'manual_start': true,
        'note_id': 'note-1',
        'updated_at': '2026-09-02T10:00:00+00:00',
        'deleted_at': null,
        'server_version': 7,
      });
      expect(row.id, overrideId);
      expect(row.profileId, profileId);
      expect(row.cycleStartDate, '2026-08-14');
      expect(row.excludedFromAverage, isTrue);
      expect(row.manualStart, isTrue);
      expect(row.noteId, 'note-1');
      expect(row.serverVersion, 7);
      expect(row.isTombstone, isFalse);

      final tombstone = decodeCycleOverride({
        'id': overrideId,
        'profile_id': profileId,
        'cycle_start_date': '2026-08-14',
        'excluded_from_average': false,
        'manual_start': false,
        'note_id': null,
        'updated_at': '2026-09-06T11:00:00+00:00',
        'deleted_at': '2026-09-06T11:00:00+00:00',
      });
      expect(tombstone.isTombstone, isTrue);
    });

    test('absent booleans default to false and the table name maps',
        () {
      final row = decodeCycleOverride({
        'id': overrideId,
        'profile_id': profileId,
        'cycle_start_date': '2026-08-14',
        'updated_at': '2026-09-02T10:00:00+00:00',
      });
      expect(row.excludedFromAverage, isFalse);
      expect(row.manualStart, isFalse);
      expect(row.noteId, isNull);
      expect(row.table, SyncTable.cycleOverrides);
    });
  });

  group('table dispatch', () {
    test('syncTableName/syncTableFromName cover both new tables', () {
      expect(syncTableName(SyncTable.profileModes), 'profile_modes');
      expect(syncTableName(SyncTable.cycleOverrides), 'cycle_overrides');
      expect(syncTableFromName('profile_modes'), SyncTable.profileModes);
      expect(syncTableFromName('cycle_overrides'), SyncTable.cycleOverrides);
      expect(syncTableFromName('modes'), isNull);
    });

    test('decodeRemoteRow dispatches per table', () {
      final mode = decodeRemoteRow(SyncTable.profileModes, {
        'profile_id': profileId,
        'mode': 'pregnancy',
        'updated_at': '2026-09-02T10:00:00+00:00',
      });
      expect(mode, isA<RemoteProfileModeRow>());

      final override = decodeRemoteRow(SyncTable.cycleOverrides, {
        'id': overrideId,
        'profile_id': profileId,
        'cycle_start_date': '2026-08-14',
        'updated_at': '2026-09-02T10:00:00+00:00',
      });
      expect(override, isA<RemoteCycleOverrideRow>());
    });

    test('decodeResolvedRow dispatches on the table key and rejects unknowns',
        () {
      final mode = decodeResolvedRow({
        'table': 'profile_modes',
        'profile_id': profileId,
        'mode': 'postpartum',
        'updated_at': '2026-09-02T10:00:00+00:00',
      });
      expect(mode, isA<RemoteProfileModeRow>());

      final override = decodeResolvedRow({
        'table': 'cycle_overrides',
        'id': overrideId,
        'profile_id': profileId,
        'cycle_start_date': '2026-08-14',
        'updated_at': '2026-09-02T10:00:00+00:00',
      });
      expect(override, isA<RemoteCycleOverrideRow>());

      expect(
        () => decodeResolvedRow({'table': 'nope'}),
        throwsA(isA<RowCodecError>()
            .having((e) => e.kind, 'kind', RowCodecErrorKind.unknownTable)),
      );
    });
  });
}
