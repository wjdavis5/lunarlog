/// Unit tests for buildAccountExport (Issue #17, Unit U5; AE4, R9, KTD5,
/// KTD6).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/export/account_export.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart';
import 'package:lunarlog/domain/import/account_import.dart' show kMaxImportFileBytes;
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/logging/tracking_preferences.dart';
import 'package:lunarlog/domain/models/care_note.dart';
import 'package:lunarlog/domain/models/cycle_override.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/guardian_note.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';
import 'package:lunarlog/domain/models/visit_prep_item.dart';

import '../../support/fake_account_export_remote_source.dart';

Profile _profile(
  String id, {
  String displayName = 'Riley',
  bool isMinor = true,
  ProfileMode mode = ProfileMode.standard,
  BbtUnit bbtUnit = BbtUnit.celsius,
  WeightUnit weightUnit = WeightUnit.kg,
  int sortOrder = 0,
  DateTime? archivedAt,
  int? birthYear,
  ProfileRelationship? relationship,
  LocalDate? lastPeriodStart,
  int? typicalCycleLengthDays,
  int? typicalPeriodLengthDays,
  TrackingPreferences? trackingPreferences,
}) =>
    Profile(
      id: id,
      displayName: displayName,
      isMinor: isMinor,
      mode: mode,
      bbtUnit: bbtUnit,
      weightUnit: weightUnit,
      sortOrder: sortOrder,
      archivedAt: archivedAt,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      birthYear: birthYear,
      relationship: relationship,
      lastPeriodStart: lastPeriodStart,
      typicalCycleLengthDays: typicalCycleLengthDays,
      typicalPeriodLengthDays: typicalPeriodLengthDays,
      trackingPreferences: trackingPreferences,
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
  DayEntrySource source = DayEntrySource.manual,
  String? sourceId,
  String? importId,
  bool pms = false,
}) =>
    DayEntry(
      id: id,
      profileId: profileId,
      localDate: LocalDate.fromIso(isoDate),
      tz: 'UTC',
      flow: flow,
      tags: tags,
      note: note,
      pms: pms,
      updatedAt: DateTime.utc(2026, 1, 2),
      loggedByUserId: loggedByUserId,
      lastModifiedByUserId: lastModifiedByUserId,
      source: source,
      sourceId: sourceId,
      importId: importId,
    );

Observation _observation(
  String id,
  String dayEntryId,
  String profileId,
  String isoDate, {
  ObservationCategory category = ObservationCategory.pain,
  String? code = 'headache',
  double? valueNum,
  int? intensity,
  String? raw,
  String? importId,
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
      importId: importId,
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
        // Issue #548 (strict-casts): `as` binds looser than `+`, so the
        // original `sum + (p as Map)['dayEntries'].length as int` cast the
        // *sum* of a num and a dynamic, not the dynamic length alone —
        // parenthesized so the length is cast to int before adding.
        (sum, p) => sum + ((p as Map)['dayEntries'] as List).length,
      );
      expect(totalEntries, 5);
    });
  });

  group('flow wire strings (Issue #247)', () {
    test(
        'superHeavy/notBleeding export as their wire strings, not their '
        'Dart enum names', () {
      final profile = _profile('p-a');
      final doc = buildAccountExport(
        profiles: [profile],
        entriesByProfile: {
          'p-a': [
            _entry('e1', 'p-a', '2026-09-01', flow: FlowLevel.superHeavy),
            _entry('e2', 'p-a', '2026-09-02', flow: FlowLevel.notBleeding),
          ],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );
      final entries =
          (((doc['profiles'] as List).single as Map)['dayEntries'] as List)
              .cast<Map>();
      expect(entries[0]['flow'], 'super_heavy');
      expect(entries[1]['flow'], 'not_bleeding');
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

  group('first-class PMS marker (Issue #220, export v7)', () {
    test('the dayEntries[].pms key round-trips, defaulting false', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: {
          'p-1': [
            _entry('e1', 'p-1', '2026-09-01'),
            _entry('e2', 'p-1', '2026-09-02', pms: true),
          ],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      expect(kAccountExportSchemaVersion, greaterThanOrEqualTo(8));
      final profile = (doc['profiles'] as List).single as Map;
      final entries = (profile['dayEntries'] as List).map((e) => e as Map);
      final byId = {for (final e in entries) e['id'] as String: e};
      expect(byId['e1']!['pms'], false);
      expect(byId['e2']!['pms'], true);
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

      expect(kAccountExportSchemaVersion, greaterThanOrEqualTo(8),
          reason: 'profiles[].mode was v2''s shape change; the constant has '
              'since moved to v6 for profiles[].observations (Issue #240), '
              'dayEntries[].source/sourceId/importId (Issue #159), the '
              'super_heavy/not_bleeding flow wire values (Issue #247), '
              'profiles[].careNotes/visitPrepItems (Issue #128), to v7 for '
              'dayEntries[].pms (Issue #220), and to v8 for '
              'profiles[].bbtUnit/weightUnit (Issue #255)');
      final profiles = doc['profiles'] as List;
      expect((profiles[0] as Map)['mode'], 'standard');
      expect((profiles[1] as Map)['mode'], 'teen');
    });
  });

  group('display-unit preferences (Issue #255, export v8)', () {
    test('each exported profile carries its bbtUnit/weightUnit, and the '
        'schema version was bumped for the new keys', () {
      final doc = buildAccountExport(
        profiles: [
          _profile('p-1'),
          _profile('p-2', bbtUnit: BbtUnit.fahrenheit, weightUnit: WeightUnit.lb),
        ],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      expect(kAccountExportSchemaVersion, greaterThanOrEqualTo(8),
          reason: 'profiles[].bbtUnit/weightUnit is a v8 shape change; a '
              'reader of an older export treats an absent key as the metric '
              'default');
      final profiles = doc['profiles'] as List;
      expect((profiles[0] as Map)['bbtUnit'], 'celsius');
      expect((profiles[0] as Map)['weightUnit'], 'kg');
      expect((profiles[1] as Map)['bbtUnit'], 'fahrenheit');
      expect((profiles[1] as Map)['weightUnit'], 'lb');
    });
  });

  group(
      'portable state: subject metadata, profileMode, cycleOverrides '
      '(Issue #140 review, LLA-084, export v9)', () {
    test('schema version was bumped to 9 for the new keys (since moved to '
        '10 for profiles[].trackingPreferences, Issue #648, 11 for '
        'profiles[].mergeEvents, Issue #130, 12 for profiles[].customTags, '
        'Issue #824, and 13 for profiles[].guardianNotes, Issue #870)', () {
      expect(kAccountExportSchemaVersion, 13);
    });

    test('each exported profile carries its subject metadata and '
        'onboarding cycle facts', () {
      final doc = buildAccountExport(
        profiles: [
          _profile(
            'p-1',
            birthYear: 2012,
            relationship: ProfileRelationship.daughter,
            lastPeriodStart: LocalDate.fromIso('2026-08-01'),
            typicalCycleLengthDays: 28,
            typicalPeriodLengthDays: 5,
          ),
          _profile('p-2'),
        ],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final profiles = doc['profiles'] as List;
      final p1 = profiles[0] as Map;
      expect(p1['birthYear'], 2012);
      expect(p1['relationship'], 'daughter');
      expect(p1['lastPeriodStart'], '2026-08-01');
      expect(p1['typicalCycleLengthDays'], 28);
      expect(p1['typicalPeriodLengthDays'], 5);

      final p2 = profiles[1] as Map;
      expect(p2['birthYear'], isNull);
      expect(p2['relationship'], isNull);
      expect(p2['lastPeriodStart'], isNull);
      expect(p2['typicalCycleLengthDays'], isNull);
      expect(p2['typicalPeriodLengthDays'], isNull);
    });

    test('profileMode is null when no profile_modes row was ever written, '
        'and never carries a health_sync_consent key even when a row '
        'exists', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1'), _profile('p-2')],
        entriesByProfile: const {},
        profileModesByProfile: {
          'p-1': (
            mode: LifecycleMode.conceive,
            modeStartedOn: null,
            estimatedDueDate: null,
            postpartumBirthDate: null,
            birthControlMethod: 'pill',
            birthControlStartedOn: '2026-06-01',
            birthControlStoppedOn: null,
          ),
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final profiles = doc['profiles'] as List;
      final p1Mode = (profiles[0] as Map)['profileMode'] as Map;
      expect(p1Mode['mode'], 'conceive');
      expect(p1Mode['birthControlMethod'], 'pill');
      expect(p1Mode['birthControlStartedOn'], '2026-06-01');
      expect(p1Mode['birthControlStoppedOn'], isNull);
      // Device-specific, safety-sensitive consent is deliberately never
      // exported (this file's R9 boundary) -- there is no key for it at
      // all, not even a false/null placeholder.
      expect(p1Mode.containsKey('healthSyncConsent'), isFalse);
      expect(p1Mode.containsKey('health_sync_consent'), isFalse);

      expect((profiles[1] as Map)['profileMode'], isNull);
    });

    test('cycleOverrides round-trips full fidelity (id, manualStart, '
        'noteId), not just the excluded flag, sorted by cycleStartDate',
        () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: const {},
        cycleOverridesByProfile: {
          'p-1': [
            CycleOverride(
              id: 'co-2',
              profileId: 'p-1',
              cycleStartDate: '2026-08-01',
              excludedFromAverage: false,
              manualStart: true,
              noteId: 'note-1',
              updatedAt: DateTime.utc(2026, 8, 1),
            ),
            CycleOverride(
              id: 'co-1',
              profileId: 'p-1',
              cycleStartDate: '2026-07-01',
              excludedFromAverage: true,
              updatedAt: DateTime.utc(2026, 7, 1),
            ),
          ],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final profiles = doc['profiles'] as List;
      final overrides = (profiles[0] as Map)['cycleOverrides'] as List;
      expect(overrides, hasLength(2));
      // Sorted by cycleStartDate, not input order.
      expect((overrides[0] as Map)['cycleStartDate'], '2026-07-01');
      expect((overrides[0] as Map)['id'], 'co-1');
      expect((overrides[0] as Map)['excludedFromAverage'], isTrue);
      expect((overrides[0] as Map)['manualStart'], isFalse);
      expect((overrides[0] as Map)['noteId'], isNull);
      expect((overrides[1] as Map)['cycleStartDate'], '2026-08-01');
      expect((overrides[1] as Map)['id'], 'co-2');
      expect((overrides[1] as Map)['manualStart'], isTrue);
      expect((overrides[1] as Map)['noteId'], 'note-1');
    });

    test('a profile with none of the new state exports empty/null '
        'defaults, never throwing', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );
      final p1 = (doc['profiles'] as List)[0] as Map;
      expect(p1['profileMode'], isNull);
      expect(p1['cycleOverrides'], isEmpty);
    });
  });

  group('tracking preferences (Issue #648, export v10)', () {
    test('a customized profile carries its trackingPreferences document, '
        'decoded (not doubly-encoded text), and an uncustomized profile '
        'exports null', () {
      final doc = buildAccountExport(
        profiles: [
          _profile(
            'p-1',
            trackingPreferences: TrackingPreferences({
              'mood': const TrackingCategoryPreference(
                  enabled: false, sortOrder: 2),
              'sex_life': const TrackingCategoryPreference(
                  enabled: true, sortOrder: 0),
            }),
          ),
          _profile('p-2'),
        ],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final profiles = doc['profiles'] as List;
      final p1Prefs = (profiles[0] as Map)['trackingPreferences'] as Map;
      expect(p1Prefs['mood'], {'enabled': false, 'sort_order': 2});
      expect(p1Prefs['sex_life'], {'enabled': true, 'sort_order': 0});
      expect((profiles[1] as Map)['trackingPreferences'], isNull);
      expect(() => jsonEncode(doc), returnsNormally);
    });

    test('an explicitly empty (cleared-to-defaults) document exports as an '
        'empty object, distinguishable from never-customized null', () {
      final doc = buildAccountExport(
        profiles: [
          _profile('p-1', trackingPreferences: const TrackingPreferences.empty()),
        ],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final p1 = (doc['profiles'] as List)[0] as Map;
      expect(p1['trackingPreferences'], isA<Map>());
      expect((p1['trackingPreferences'] as Map).isEmpty, isTrue);
    });
  });

  group('same-date merge disclosures (Issue #130, export v11)', () {
    final eventA = DayEntryMergeEvent(
      id: '01JMERGEEVENT000000000000A',
      profileId: 'p-1',
      localDateIso: '2026-01-15',
      winningRowId: '01JMERGEWINNER00000000000W',
      losingRowId: '01JMERGELOSER000000000000L',
      field: DayEntryMergeEventField.note,
      losingValueText: 'she stayed home from school',
      losingAuthorUserId: 'user-loser',
      winningAuthorUserId: 'user-winner',
      createdAt: DateTime.utc(2026, 1, 16),
      updatedAt: DateTime.utc(2026, 1, 16),
    );
    final eventB = DayEntryMergeEvent(
      id: '01JMERGEEVENT000000000000B',
      profileId: 'p-1',
      localDateIso: '2026-01-15',
      winningRowId: '01JMERGEWINNER00000000000W',
      losingRowId: '01JMERGELOSER000000000000L',
      field: DayEntryMergeEventField.flow,
      losingValueText: 'heavy',
      createdAt: DateTime.utc(2026, 1, 16),
      updatedAt: DateTime.utc(2026, 1, 16),
    );

    test('the schema version was bumped to 11 and each profile carries a '
        'mergeEvents array (empty for a profile with none, the v3/v6 '
        'absence-reading precedent)', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1'), _profile('p-2')],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );
      expect(kAccountExportSchemaVersion, 13);
      final profiles = doc['profiles'] as List;
      expect((profiles[0] as Map)['mergeEvents'], isEmpty);
      expect((profiles[1] as Map)['mergeEvents'], isEmpty);
    });

    test('each event round-trips id/date/row-ids/field/losing text, sorted '
        'by id, with attribution ids excluded (R9)', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: const {},
        mergeEventsByProfile: {
          'p-1': [eventB, eventA],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );
      final events = ((doc['profiles'] as List)[0] as Map)['mergeEvents']
          as List;
      expect(events, hasLength(2));
      // Sorted by id regardless of input order.
      expect((events[0] as Map)['id'], eventA.id);
      expect((events[1] as Map)['id'], eventB.id);
      final noteEvent = events[0] as Map;
      expect(noteEvent['localDate'], '2026-01-15');
      expect(noteEvent['winningRowId'], eventA.winningRowId);
      expect(noteEvent['losingRowId'], eventA.losingRowId);
      expect(noteEvent['field'], 'note');
      expect(noteEvent['losingValueText'], 'she stayed home from school');
      expect(noteEvent['recordedAt'], '2026-01-16T00:00:00.000Z');
      // R9: guardian attribution ids never ride along.
      final encoded = jsonEncode(doc);
      expect(encoded, isNot(contains('user-loser')));
      expect(encoded, isNot(contains('user-winner')));
      expect(encoded, isNot(contains('losingAuthorUserId')));
      expect(encoded, isNot(contains('winningAuthorUserId')));
    });

    test('a flow discard exports its wire string as the losing value', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: const {},
        mergeEventsByProfile: {
          'p-1': [eventB],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );
      final flowEvent =
          (((doc['profiles'] as List)[0] as Map)['mergeEvents'] as List)[0]
              as Map;
      expect(flowEvent['field'], 'flow');
      expect(flowEvent['losingValueText'], 'heavy');
    });
  });

  group('profiles[].customTags (Issue #824, kAccountExportSchemaVersion v12)', () {
    final tagA = CustomTag(
      id: 'tag-1',
      profileId: 'p-1',
      code: 'cramps_severe',
      displayName: 'Severe Cramps',
      category: 'custom',
      intensityEnabled: true,
      hiddenAt: null,
      sortOrder: 1,
      createdAt: DateTime.utc(2026, 1, 10),
      updatedAt: DateTime.utc(2026, 1, 10),
    );
    final tagB = CustomTag(
      id: 'tag-2',
      profileId: 'p-1',
      code: 'herbal_tea',
      displayName: 'Herbal Tea',
      category: 'custom',
      intensityEnabled: false,
      hiddenAt: DateTime.utc(2026, 1, 15),
      sortOrder: 2,
      createdAt: DateTime.utc(2026, 1, 11),
      updatedAt: DateTime.utc(2026, 1, 12),
    );

    test('the schema version was bumped to 12 and each profile carries a '
        'customTags array (empty for a profile with none)', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1'), _profile('p-2')],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );
      expect(kAccountExportSchemaVersion, 13);
      final profiles = doc['profiles'] as List;
      expect((profiles[0] as Map)['customTags'], isEmpty);
      expect((profiles[1] as Map)['customTags'], isEmpty);
    });

    test('each custom tag round-trips id/code/displayName/category/intensity/hidden/sort/timestamps, '
        'sorted by id, with attribution ids excluded (R9)', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: const {},
        customTagsByProfile: {
          'p-1': [tagB, tagA],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );
      final tags = ((doc['profiles'] as List)[0] as Map)['customTags'] as List;
      expect(tags, hasLength(2));
      // Sorted by id regardless of input order.
      expect((tags[0] as Map)['id'], 'tag-1');
      expect((tags[1] as Map)['id'], 'tag-2');
      final t1 = tags[0] as Map;
      expect(t1['code'], 'cramps_severe');
      expect(t1['displayName'], 'Severe Cramps');
      expect(t1['category'], 'custom');
      expect(t1['intensityEnabled'], isTrue);
      expect(t1['hiddenAt'], isNull);
      expect(t1['sortOrder'], 1);
      expect(t1['createdAt'], '2026-01-10T00:00:00.000Z');
      expect(t1['updatedAt'], '2026-01-10T00:00:00.000Z');

      final t2 = tags[1] as Map;
      expect(t2['code'], 'herbal_tea');
      expect(t2['displayName'], 'Herbal Tea');
      expect(t2['category'], 'custom');
      expect(t2['intensityEnabled'], isFalse);
      expect(t2['hiddenAt'], '2026-01-15T00:00:00.000Z');
      expect(t2['sortOrder'], 2);

      // R9: attribution identifiers are never exported.
      final encoded = jsonEncode(doc);
      expect(encoded, isNot(contains('createdBy')));
      expect(encoded, isNot(contains('created_by')));
    });
  });

  group('profiles[].guardianNotes (Issue #870, kAccountExportSchemaVersion v13)', () {
    final noteA = GuardianNote(
      id: '01ARZ3NDEKTSV4RRFFQ69G5FAV',
      profileId: 'p-1',
      localDate: LocalDate(2026, 9, 2),
      tz: 'America/New_York',
      body: 'Note A body',
      updatedAt: DateTime.utc(2026, 9, 2, 9),
      loggedByUserId: 'user-a',
      lastModifiedByUserId: 'user-b',
    );
    final noteB = GuardianNote(
      id: '01ARZ3NDEKTSV4RRFFQ69G5FAW',
      profileId: 'p-1',
      localDate: LocalDate(2026, 9, 1),
      tz: 'America/New_York',
      body: 'Note B body',
      updatedAt: DateTime.utc(2026, 9, 1, 9),
      loggedByUserId: 'user-c',
    );

    test(
        'default export wires an empty '
        'guardianNotes array (empty for a profile with none)', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1'), _profile('p-2')],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );
      expect(kAccountExportSchemaVersion, 13);
      final profiles = doc['profiles'] as List;
      expect((profiles[0] as Map)['guardianNotes'], isEmpty);
      expect((profiles[1] as Map)['guardianNotes'], isEmpty);
    });

    test(
        'each guardian note round-trips id/localDate/tz/body/updatedAt, '
        'sorted by localDate then id, with attribution ids excluded (R9)', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: const {},
        guardianNotesByProfile: {
          'p-1': [noteA, noteB],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );
      final notes =
          ((doc['profiles'] as List)[0] as Map)['guardianNotes'] as List;
      expect(notes, hasLength(2));
      // Sorted by localDate then id (noteB is on 2026-09-01, noteA on 2026-09-02).
      expect((notes[0] as Map)['id'], '01ARZ3NDEKTSV4RRFFQ69G5FAW');
      expect((notes[1] as Map)['id'], '01ARZ3NDEKTSV4RRFFQ69G5FAV');

      final n0 = notes[0] as Map;
      expect(n0['localDate'], '2026-09-01');
      expect(n0['tz'], 'America/New_York');
      expect(n0['body'], 'Note B body');
      expect(n0['updatedAt'], '2026-09-01T09:00:00.000Z');

      // R9: attribution identifiers are never exported.
      final encoded = jsonEncode(doc);
      expect(encoded, isNot(contains('user-a')));
      expect(encoded, isNot(contains('user-b')));
      expect(encoded, isNot(contains('user-c')));
      expect(encoded, isNot(contains('loggedByUserId')));
      expect(encoded, isNot(contains('lastModifiedByUserId')));
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

    test('threads observationsByProfile through to the local document '
        '(Issue #240) — the same path AccountExportWriter.exportAndShare '
        'and its UI callers use end to end, not just buildAccountExport '
        'directly', () async {
      final doc = await buildMergedAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: {
          'p-1': [_entry('e1', 'p-1', '2026-09-01')],
        },
        observationsByProfile: {
          'p-1': [
            _observation('o1', 'e1', 'p-1', '2026-09-01', intensity: 4),
          ],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final profile = (doc['profiles'] as List).single as Map;
      final observations = profile['observations'] as List;
      expect(observations, hasLength(1));
      expect((observations.single as Map)['id'], 'o1');
      expect((observations.single as Map)['intensity'], 4);
    });

    test('threads customTagsByProfile through to the local document '
        '(Issue #824) — the same path AccountExportWriter.exportAndShare '
        'and its UI callers use end to end', () async {
      final doc = await buildMergedAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: const {},
        customTagsByProfile: {
          'p-1': [
            CustomTag(
              id: 'tag-1',
              profileId: 'p-1',
              code: 'cramps_severe',
              displayName: 'Severe Cramps',
              category: 'custom',
              intensityEnabled: true,
              hiddenAt: null,
              sortOrder: 1,
              createdAt: DateTime.utc(2026, 1, 10),
              updatedAt: DateTime.utc(2026, 1, 10),
            ),
          ],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final profile = (doc['profiles'] as List).single as Map;
      final tags = profile['customTags'] as List;
      expect(tags, hasLength(1));
      expect((tags.single as Map)['id'], 'tag-1');
      expect((tags.single as Map)['code'], 'cramps_severe');
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

      expect(kAccountExportSchemaVersion, greaterThanOrEqualTo(8),
          reason: 'adding profiles[].observations is a shape change; the '
              'constant has since moved to v6 for profiles[].careNotes/'
              'visitPrepItems (Issue #128), to v7 for dayEntries[].pms '
              '(Issue #220), and to v8 for profiles[].bbtUnit/weightUnit '
              '(Issue #255)');
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

  group('import provenance (Issue #159, kAccountExportSchemaVersion v4)', () {
    test('dayEntries carries source/sourceId/importId for an imported entry',
        () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: {
          'p-1': [
            _entry('e1', 'p-1', '2026-09-01',
                source: DayEntrySource.clueImport,
                sourceId: 'clue-42',
                importId: 'job-1'),
          ],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final profile = (doc['profiles'] as List).single as Map;
      final entry = (profile['dayEntries'] as List).single as Map;
      expect(entry['source'], 'clue_import');
      expect(entry['sourceId'], 'clue-42');
      expect(entry['importId'], 'job-1');
    });

    test('a manually-logged dayEntry exports source manual and null '
        'sourceId/importId', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: {
          'p-1': [_entry('e1', 'p-1', '2026-09-01')],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final profile = (doc['profiles'] as List).single as Map;
      final entry = (profile['dayEntries'] as List).single as Map;
      expect(entry['source'], 'manual');
      expect(entry['sourceId'], isNull);
      expect(entry['importId'], isNull);
    });

    test('observations carries importId', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: {
          'p-1': [_entry('e1', 'p-1', '2026-09-01')],
        },
        observationsByProfile: {
          'p-1': [
            _observation('o1', 'e1', 'p-1', '2026-09-01', importId: 'job-1'),
          ],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final profile = (doc['profiles'] as List).single as Map;
      final observation = (profile['observations'] as List).single as Map;
      expect(observation['importId'], 'job-1');
    });
  });

  group('shared care content (Issue #128, kAccountExportSchemaVersion v6)',
      () {
    test('a profile exports its care notes with bodies and no attribution ids',
        () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: const {},
        careNotesByProfile: {
          'p-1': [
            CareNote(
              id: 'n1',
              profileId: 'p-1',
              body: 'Prefers the blue inhaler.',
              updatedAt: DateTime.utc(2026, 9, 1),
              loggedByUserId: 'user-mom',
              lastModifiedByUserId: 'user-dad',
            ),
          ],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final profile = (doc['profiles'] as List).single as Map;
      final notes = profile['careNotes'] as List;
      expect(notes, hasLength(1));
      final note = notes.single as Map;
      expect(note['id'], 'n1');
      expect(note['body'], 'Prefers the blue inhaler.');
      expect(note.containsKey('loggedByUserId'), isFalse,
          reason: 'R9: guardian attribution ids stay out of the export');
      expect(note.containsKey('lastModifiedByUserId'), isFalse);
    });

    test('a profile exports its visit-prep list with check state but no '
        'checked-by user id', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: const {},
        visitPrepByProfile: {
          'p-1': [
            VisitPrepItem(
              id: 'i1',
              profileId: 'p-1',
              body: 'Ask about iron levels.',
              isChecked: true,
              checkedByUserId: 'user-dad',
              checkedAt: DateTime.utc(2026, 9, 2),
              updatedAt: DateTime.utc(2026, 9, 2),
            ),
            VisitPrepItem(
              id: 'i2',
              profileId: 'p-1',
              body: 'Bring the growth chart.',
              kind: VisitPrepItemKind.supply,
              updatedAt: DateTime.utc(2026, 9, 1),
            ),
          ],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final profile = (doc['profiles'] as List).single as Map;
      final items = profile['visitPrepItems'] as List;
      expect(items, hasLength(2));
      final first = items[0] as Map;
      expect(first['id'], 'i1');
      expect(first['body'], 'Ask about iron levels.');
      expect(first['kind'], 'visit_prep');
      expect(first['isChecked'], isTrue);
      expect(first['checkedAt'], '2026-09-02T00:00:00.000Z');
      expect(first.containsKey('checkedByUserId'), isFalse,
          reason: 'R9: an auth identifier is not family data');
      final second = items[1] as Map;
      expect(second['kind'], 'supply',
          reason: 'Issue #851: a supply item round-trips as a supply');
      expect(second['isChecked'], isFalse);
      expect(second['checkedAt'], isNull);
    });

    test('a profile with no care content still gets both keys, empty', () {
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: const {},
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );

      final profile = (doc['profiles'] as List).single as Map;
      expect(profile['careNotes'], isEmpty);
      expect(profile['visitPrepItems'], isEmpty);
    });
  });

  group('import ceiling vs export size (Issue #626, LLA-095)', () {
    test('kMaxImportFileBytes comfortably exceeds a legitimate worst-case '
        'export — five profiles, ten years of daily maxed-out entries each '
        '(the repro that exceeded the old 32 MiB ceiling: "28,28,28,56" is '
        'a different #612 finding; this is LLA-095\'s own numbers)', () {
      final maxNote = 'n' * kMaxNoteLength;
      final maxTags = [for (var i = 0; i < kMaxTagCount; i++) 't$i'.padRight(kMaxTagLength, 'x')];
      final doc = buildAccountExport(
        profiles: [_profile('p-1')],
        entriesByProfile: {
          'p-1': [_entry('e1', 'p-1', '2026-01-01', note: maxNote, tags: maxTags)],
        },
        exportedAt: fixedExportedAt,
        appVersion: '1.0.0+1',
      );
      final entries = ((doc['profiles'] as List).single as Map)['dayEntries'] as List;
      final maxEntryBytes = utf8.encode(jsonEncode(entries.single)).length;

      // The issue's own repro: five profiles, ten years of daily entries
      // (3650 days) each at every field's own maximum length.
      const profileCount = 5;
      const entriesPerProfile = 3650;
      final worstCaseEntriesBytes = maxEntryBytes * profileCount * entriesPerProfile;

      expect(worstCaseEntriesBytes, greaterThan(32 * 1024 * 1024),
          reason: 'sanity check: this is exactly the scenario that used to '
              'exceed the OLD 32 MiB ceiling — if this assertion ever '
              'fails, the repro itself has stopped reproducing the defect');
      expect(worstCaseEntriesBytes, lessThan(kMaxImportFileBytes),
          reason: 'a household that respects every one of this app\'s own '
              'row bounds must never produce a backup this app itself '
              'cannot restore (LLA-095) — dayEntries alone must fit '
              'comfortably under the import ceiling, leaving headroom for '
              'observations/cycleOverrides/profile metadata on top');
    });
  });
}
