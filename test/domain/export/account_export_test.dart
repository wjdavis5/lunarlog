/// Unit tests for buildAccountExport (Issue #17, Unit U5; AE4, R9, KTD5,
/// KTD6).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/export/account_export.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';

import '../../support/fake_account_export_remote_source.dart';

Profile _profile(
  String id, {
  String displayName = 'Riley',
  bool isMinor = true,
  ProfileMode mode = ProfileMode.standard,
  int sortOrder = 0,
  DateTime? archivedAt,
}) =>
    Profile(
      id: id,
      displayName: displayName,
      isMinor: isMinor,
      mode: mode,
      sortOrder: sortOrder,
      archivedAt: archivedAt,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
    );

DayEntry _entry(
  String id,
  String profileId,
  String isoDate, {
  FlowLevel flow = FlowLevel.light,
  List<String> tags = const [],
  String? note,
  String? loggedByUserId,
  String? lastModifiedByUserId,
}) =>
    DayEntry(
      id: id,
      profileId: profileId,
      localDate: LocalDate.fromIso(isoDate),
      tz: 'UTC',
      flow: flow,
      tags: tags,
      note: note,
      updatedAt: DateTime.utc(2026, 1, 2),
      loggedByUserId: loggedByUserId,
      lastModifiedByUserId: lastModifiedByUserId,
    );

Observation _observation(
  String id,
  String dayEntryId,
  String profileId,
  String isoDate, {
  String category = 'pain',
  String? code = 'headache',
  double? valueNum,
  int? intensity,
  String? raw,
}) =>
    Observation(
      id: id,
      dayEntryId: dayEntryId,
      profileId: profileId,
      localDate: LocalDate.fromIso(isoDate),
      tz: 'UTC',
      category: category,
      code: code,
      valueNum: valueNum,
      intensity: intensity,
      raw: raw,
      updatedAt: DateTime.utc(2026, 1, 2),
    );


void main() {
  final fixedExportedAt = DateTime.utc(2026, 9, 6, 12, 30);

  group('buildAccountExport (AE4)', () {
    test('a two-profile, five-entry fixture produces the documented '
        'top-level keys, correct counts, and correct nesting', () {
      final profileA = _profile('p-a', displayName: 'Alex');
      final profileB = _profile('p-b', displayName: 'Bailey');
      final entriesByProfile = {
        'p-a': [
          _entry('e1', 'p-a', '2026-09-01'),
          _entry('e2', 'p-a', '2026-09-02'),
          _entry('e3', 'p-a', '2026-09-03'),
        ],
        'p-b': [
          _entry('e4', 'p-b', '2026-09-01'),
          _entry('e5', 'p-b', '2026-09-02'),
        ],
      };

      final doc = buildAccountExport(
        profiles: [profileA, profileB],
        entriesByProfile: entriesByProfile,
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      expect(
        doc.keys,
        containsAll(['schemaVersion', 'exportedAt', 'app', 'profiles']),
      );
      expect(doc['schemaVersion'], kAccountExportSchemaVersion);
      expect(doc['exportedAt'], '2026-09-06T12:30:00.000Z');
      expect(doc['app'], {'name': 'lunarlog', 'version': '1.0.0+1'});

      final profiles = doc['profiles'] as List;
      expect(profiles, hasLength(2));
      final first = profiles[0] as Map;
      final second = profiles[1] as Map;
      expect(first['id'], 'p-a');
      expect(second['id'], 'p-b');
      expect((first['dayEntries'] as List), hasLength(3));
      expect((second['dayEntries'] as List), hasLength(2));

      final totalEntries = profiles.fold<int>(
        0,
        (sum, p) => sum + (p as Map)['dayEntries'].length as int,
      );
      expect(totalEntries, 5);
    });
  });

  group('determinism', () {
    test('the encoded output is byte-identical across two calls with the '
        'same input and a fixed exportedAt', () {
      final profiles = [_profile('p-1'), _profile('p-2')];
      final entriesByProfile = {
        'p-1': [_entry('e1', 'p-1', '2026-09-01')],
        'p-2': <DayEntry>[],
      };

      final first = jsonEncode(buildAccountExport(
        profiles: profiles,
        entriesByProfile: entriesByProfile,
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      ));
      final second = jsonEncode(buildAccountExport(
        profiles: profiles,
        entriesByProfile: entriesByProfile,
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      ));

      expect(first, second);
    });

    test('profile and entry order in the input does not change the '
        'encoded output (sorted by id / localDate)', () {
      final entriesByProfile = {
        'p-1': [
          _entry('e2', 'p-1', '2026-09-02'),
          _entry('e1', 'p-1', '2026-09-01'),
        ],
      };
      final inOrder = jsonEncode(buildAccountExport(
        profiles: [_profile('p-1'), _profile('p-2')],
        entriesByProfile: {
          ...entriesByProfile,
          'p-2': <DayEntry>[],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      ));
      final reversed = jsonEncode(buildAccountExport(
        profiles: [_profile('p-2'), _profile('p-1')],
        entriesByProfile: {
          'p-1': [
            _entry('e1', 'p-1', '2026-09-01'),
            _entry('e2', 'p-1', '2026-09-02'),
          ],
          'p-2': <DayEntry>[],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      ));

      expect(inOrder, reversed);
    });
  });

  group('R9: no excluded key leaks into the encoded output', () {
    test('sync bookkeeping, guardian attribution ids, tokens and emails '
        'never appear as keys anywhere in the document', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: {
          'p-1': [
            _entry(
              'e1',
              'p-1',
              '2026-09-01',
              loggedByUserId: 'user-abc',
              lastModifiedByUserId: 'user-def',
            ),
          ],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );
      final encoded = jsonEncode(doc);

      for (final excludedKey in [
        'user_id',
        'server_version',
        'logged_by_user_id',
        'last_modified_by_user_id',
        'loggedByUserId',
        'lastModifiedByUserId',
        'token',
        'email',
      ]) {
        expect(encoded, isNot(contains(excludedKey)),
            reason: '"$excludedKey" must not appear in the export');
      }
      // The values themselves (the actual guardian ids) must not leak
      // either, not just the key names.
      expect(encoded, isNot(contains('user-abc')));
      expect(encoded, isNot(contains('user-def')));
    });
  });

  group('empty account', () {
    test('no profiles produces a valid document with an empty profiles '
        'list, not an error', () {
      final doc = buildAccountExport(
        profiles: const [],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      expect(doc['profiles'], isEmpty);
      expect(() => jsonEncode(doc), returnsNormally);
    });
  });

  group('round-tripping unusual content', () {
    test('a note containing quotes, newlines and non-ASCII round-trips '
        'through jsonEncode/jsonDecode unchanged', () {
      const trickyNote = 'She said "ok" \n emoji: café ☃ \u{1F60A}';
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: {
          'p-1': [_entry('e1', 'p-1', '2026-09-01', note: trickyNote)],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final roundTripped =
          jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;
      final profile = (roundTripped['profiles'] as List).single as Map;
      final entry = (profile['dayEntries'] as List).single as Map;
      expect(entry['note'], trickyNote);
    });
  });

  group('exportedAt normalization', () {
    test('exportedAt is serialized in UTC regardless of the input zone',
        () {
      // A local (non-UTC) DateTime representing the same instant.
      final local = fixedExportedAt.toLocal();
      final doc = buildAccountExport(
        profiles: const [],
        entriesByProfile: const {},
        exportedAt: local,
        appVersion: '1.0.0+1',
      );

      expect(doc['exportedAt'], fixedExportedAt.toIso8601String());
      expect(doc['exportedAt'], endsWith('Z'));
    });
  });

  group('care mode (Issue #131)', () {
    test('each exported profile carries its mode, and the schema version '
        'was bumped for the new key', () {
      final doc = buildAccountExport(
        profiles: [
          _profile('p-1'),
          _profile('p-2', mode: ProfileMode.teen),
        ],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      expect(kAccountExportSchemaVersion, 2,
          reason: 'adding profiles[].mode is a shape change');
      final profiles = doc['profiles'] as List;
      expect((profiles[0] as Map)['mode'], 'standard');
      expect((profiles[1] as Map)['mode'], 'teen');
    });
  });

  group('mergeAccountExport (Issue #248)', () {
    test('a null server document falls back to local-only with '
        'serverIncluded: false and no server key', () {
      final local = buildAccountExport(
        profiles: const [],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final merged = mergeAccountExport(
        localDocument: local,
        serverDocument: null,
      );

      expect(merged['serverIncluded'], false);
      expect(merged.containsKey('server'), isFalse);
      // The local document's own shape is carried through unchanged.
      expect(merged['schemaVersion'], local['schemaVersion']);
      expect(merged['profiles'], local['profiles']);
    });

    test('a non-null server document is nested under `server` with '
        'serverIncluded: true, and the local shape is untouched', () {
      final local = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );
      final serverDoc = <String, Object?>{
        'profile_guardians': <Object?>[],
        'guardian_invitations': <Object?>[],
      };

      final merged = mergeAccountExport(
        localDocument: local,
        serverDocument: serverDoc,
      );

      expect(merged['serverIncluded'], true);
      expect(merged['server'], serverDoc);
      expect(merged['profiles'], local['profiles']);
      expect(() => jsonEncode(merged), returnsNormally);
    });
  });

  group('buildMergedAccountExport (Issue #248)', () {
    test('with no remote source, produces the local document plus '
        'serverIncluded: false', () async {
      final doc = await buildMergedAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      expect(doc['serverIncluded'], false);
      expect(doc.containsKey('server'), isFalse);
      expect((doc['profiles'] as List), hasLength(1));
    });

    test('with a remote source that resolves to null (signed out, '
        'offline, or a failed call), degrades exactly like no remote '
        'source at all', () async {
      final remoteSource = FakeAccountExportRemoteSource();

      final doc = await buildMergedAccountExport(
        profiles: const [],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
        remoteSource: remoteSource,
      );

      expect(remoteSource.callCount, 1);
      expect(doc['serverIncluded'], false);
      expect(doc.containsKey('server'), isFalse);
    });

    test('with a remote source that resolves to a document, merges it '
        'under `server` alongside the local document', () async {
      final remoteSource = FakeAccountExportRemoteSource(result: {
        'push_devices': <Object?>[
          {'id': 'd1', 'platform': 'ios', 'token_last4': '1234'},
        ],
      });

      final doc = await buildMergedAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
        remoteSource: remoteSource,
      );

      expect(doc['serverIncluded'], true);
      expect(doc['server'], remoteSource.result);
      expect((doc['profiles'] as List), hasLength(1));
      expect(() => jsonEncode(doc), returnsNormally);
    });
  });

  group('observations (Issue #240)', () {
    test('each exported profile carries its observations, and the schema '
        'version was bumped for the new key', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1'), _profile('p-2')],
        entriesByProfile: {
          'p-1': [_entry('e1', 'p-1', '2026-09-01')],
        },
        observationsByProfile: {
          'p-1': [
            _observation('o1', 'e1', 'p-1', '2026-09-01',
                intensity: 3, valueNum: 98.4),
          ],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      expect(kAccountExportSchemaVersion, 3,
          reason: 'adding profiles[].observations is a shape change');
      final profiles = doc['profiles'] as List;
      final p1 = profiles[0] as Map;
      final p2 = profiles[1] as Map;
      expect((p1['observations'] as List), hasLength(1));
      expect((p2['observations'] as List), isEmpty);
      final observation = (p1['observations'] as List).single as Map;
      expect(observation['category'], 'pain');
      expect(observation['code'], 'headache');
      expect(observation['intensity'], 3);
      expect(observation['valueNum'], 98.4);
      expect(observation['dayEntryId'], 'e1');
    });

    test('a profile with no key in observationsByProfile still gets an '
        'empty observations list, not a missing key', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final profile = (doc['profiles'] as List).single as Map;
      expect(profile['observations'], isEmpty);
    });

    test('observations.raw round-trips as decoded JSON, not a doubly-'
        'encoded string', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: {
          'p-1': [_entry('e1', 'p-1', '2026-09-01')],
        },
        observationsByProfile: {
          'p-1': [
            _observation('o1', 'e1', 'p-1', '2026-09-01',
                raw: '{"type":"bbt","value":36.5}'),
          ],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final profile = (doc['profiles'] as List).single as Map;
      final observation = (profile['observations'] as List).single as Map;
      expect(observation['raw'], {'type': 'bbt', 'value': 36.5});
      expect(() => jsonEncode(doc), returnsNormally);
    });
  });
}
