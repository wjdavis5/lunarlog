/// Unit tests for `lib/domain/import/account_import.dart` (Issue #140):
/// parseAccountImport (valid documents, malformed inputs), previewImport,
/// writeBlockReasonFor, and planImport's merge/create/skip decisions.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/export/account_export.dart';
import 'package:lunarlog/domain/import/account_import.dart';
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/logging/tracking_preferences.dart';
import 'package:lunarlog/domain/models/cycle_override.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';

Map<String, Object?> _rawDayEntry(
  String id,
  String localDate, {
  String flow = 'medium',
  List<String> tags = const [],
  String? note,
  bool pms = false,
}) =>
    {
      'id': id,
      'localDate': localDate,
      'tz': 'UTC',
      'flow': flow,
      'tags': tags,
      'note': note,
      'pms': pms,
      'source': 'manual',
      'sourceId': null,
      'importId': null,
      'updatedAt': '2026-01-02T00:00:00.000Z',
    };

Map<String, Object?> _rawObservation(
  String id,
  String localDate, {
  String category = 'pain',
  String? code = 'cramps',
  int? intensity,
  Object? raw,
}) =>
    {
      'id': id,
      'dayEntryId': 'de-$id',
      'localDate': localDate,
      'observedAt': null,
      'tz': 'UTC',
      'category': category,
      'code': code,
      'valueNum': null,
      'valueText': null,
      'unit': null,
      'intensity': intensity,
      'excluded': false,
      'source': 'manual',
      'sourceId': null,
      'importId': null,
      'raw': raw,
      'updatedAt': '2026-01-02T00:00:00.000Z',
    };

Map<String, Object?> _rawProfile(
  String id, {
  String displayName = 'Riley',
  List<Map<String, Object?>> dayEntries = const [],
  List<Map<String, Object?>> observations = const [],
  List<Map<String, Object?>> cycleOverrides = const [],
  List<Map<String, Object?>> customTags = const [],
}) =>
    {
      'id': id,
      'displayName': displayName,
      'isMinor': true,
      'mode': 'standard',
      'sortOrder': 0,
      'archivedAt': null,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
      'dayEntries': dayEntries,
      'observations': observations,
      'cycleOverrides': cycleOverrides,
      'customTags': customTags,
    };

/// A `profiles[].customTags[]` element (Issue #824).
Map<String, Object?> _rawCustomTag(
  String id,
  String code,
  String displayName, {
  String category = 'custom',
  bool intensityEnabled = false,
  String? hiddenAt,
  int? sortOrder,
}) =>
    {
      'id': id,
      'code': code,
      'displayName': displayName,
      'category': category,
      'intensityEnabled': intensityEnabled,
      'hiddenAt': hiddenAt,
      'sortOrder': sortOrder,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
    };

/// A `profiles[].cycleOverrides[]` element (Issue #140 review, LLA-084).
Map<String, Object?> _rawCycleOverride(
  String id,
  String cycleStartDate, {
  bool excludedFromAverage = false,
  bool manualStart = false,
  String? noteId,
}) =>
    {
      'id': id,
      'cycleStartDate': cycleStartDate,
      'excludedFromAverage': excludedFromAverage,
      'manualStart': manualStart,
      'noteId': noteId,
    };

Map<String, Object?> _rawDocument({
  int schemaVersion = kAccountExportSchemaVersion,
  List<Map<String, Object?>> profiles = const [],
}) =>
    {
      'schemaVersion': schemaVersion,
      'exportedAt': '2026-01-03T00:00:00.000Z',
      'app': {'name': 'lunarlog', 'version': '1.0.0+1'},
      'profiles': profiles,
    };

List<int> _bytes(Map<String, Object?> document) => utf8.encode(jsonEncode(document));

Profile _profile(String id, {DateTime? archivedAt}) => Profile(
      id: id,
      displayName: 'Riley',
      isMinor: true,
      archivedAt: archivedAt,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

DayEntry _entry(
  String id,
  String profileId,
  String isoDate, {
  FlowLevel flow = FlowLevel.light,
  List<String> tags = const [],
  String? note,
  bool pms = false,
  DayEntrySource source = DayEntrySource.manual,
  String? sourceId,
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
      source: source,
      sourceId: sourceId,
      updatedAt: DateTime.utc(2026, 1, 2),
    );

Observation _observation(
  String id,
  String profileId,
  String isoDate, {
  String category = 'pain',
  String? code = 'cramps',
}) =>
    Observation(
      id: id,
      dayEntryId: 'de-$id',
      profileId: profileId,
      localDate: LocalDate.fromIso(isoDate),
      tz: 'UTC',
      category: category,
      code: code,
      updatedAt: DateTime.utc(2026, 1, 2),
    );

String? _neverBlocked(Profile p) => null;

// Issue #140 review round 2, item 1: fixture ids must be syntactically
// valid ULIDs now that parseAccountImport enforces the format at parse
// time. Plain zero-padded digits are valid Crockford base32 characters, so
// these are cheap, distinct, and still readable at a glance.
const String _p1 = '00000000000000000000000001';
const String _p2 = '00000000000000000000000002';
const String _e1 = '00000000000000000000000011';
const String _e2 = '00000000000000000000000012';
const String _e3 = '00000000000000000000000013';
const String _o1 = '00000000000000000000000021';
const String _o2 = '00000000000000000000000022';
const String _co1 = '00000000000000000000000031';
const String _ct1 = '00000000000000000000000051';
const String _ct2 = '00000000000000000000000052';
String _obsId(int i) => (900000 + i).toString().padLeft(26, '0');

void main() {
  group('parseAccountImport — valid documents', () {
    test('a minimal, well-formed document parses', () {
      final result = parseAccountImport(_bytes(_rawDocument(
        profiles: [
          _rawProfile(_p1, dayEntries: [_rawDayEntry(_e1, '2026-01-05')]),
        ],
      )));
      expect(result, isA<AccountImportParsed>());
      final document = (result as AccountImportParsed).document;
      expect(document.schemaVersion, kAccountExportSchemaVersion);
      expect(document.profiles, hasLength(1));
      expect(document.profiles.single.dayEntries.single.localDate,
          LocalDate.fromIso('2026-01-05'));
    });

    test('every accepted schema version (1-6) parses', () {
      for (var v = kAccountImportMinSchemaVersion;
          v <= kAccountImportMaxSchemaVersion;
          v++) {
        final result = parseAccountImport(_bytes(_rawDocument(schemaVersion: v)));
        expect(result, isA<AccountImportParsed>(), reason: 'schemaVersion $v');
      }
    });

    test(
        'a v5 file with a super_heavy flow value imports (Issue #247, '
        'review follow-up PR #335: kAccountExportSchemaVersion bumped to '
        '5 for the super_heavy/not_bleeding wire values)', () {
      final result = parseAccountImport(_bytes(_rawDocument(
        schemaVersion: 5,
        profiles: [
          _rawProfile(_p1, dayEntries: [
            _rawDayEntry(_e1, '2026-01-05', flow: 'super_heavy'),
          ]),
        ],
      )));
      expect(result, isA<AccountImportParsed>());
      final document = (result as AccountImportParsed).document;
      expect(document.schemaVersion, 5);
      expect(document.profiles.single.dayEntries.single.flow,
          FlowLevel.superHeavy);
    });

    test('a v6 file carrying careNotes/visitPrepItems parses with those '
        'keys ignored (Issue #128: restore stays additive over profiles, '
        'day entries, and observations — shared care content is sync-owned, '
        'never file-merged)', () {
      final profile = _rawProfile(_p1, dayEntries: [
        _rawDayEntry(_e1, '2026-01-05'),
      ])
        ..['careNotes'] = [
          {
            'id': '00000000000000000000000031',
            'body': 'Prefers the blue inhaler.',
            'updatedAt': '2026-01-02T00:00:00.000Z',
          },
        ]
        ..['visitPrepItems'] = [
          {
            'id': '00000000000000000000000032',
            'body': 'Ask about iron levels.',
            'isChecked': true,
            'checkedAt': '2026-01-02T00:00:00.000Z',
            'updatedAt': '2026-01-02T00:00:00.000Z',
          },
        ];
      final result = parseAccountImport(_bytes(_rawDocument(
        schemaVersion: 6,
        profiles: [profile],
      )));
      expect(result, isA<AccountImportParsed>());
      final document = (result as AccountImportParsed).document;
      expect(document.schemaVersion, 6);
      expect(document.profiles.single.dayEntries, hasLength(1));
    });

    test('an explicit "none" flow value parses as FlowLevel.none', () {
      final result = parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', flow: 'none'),
        ]),
      ])));
      final document = (result as AccountImportParsed).document;
      expect(document.profiles.single.dayEntries.single.flow, FlowLevel.none);
    });

    test('a document with no profiles list defaults to empty, not an error '
        '(schemaVersion 1 exports predate observations/provenance)', () {
      final raw = _rawDocument();
      final result = parseAccountImport(_bytes(raw));
      expect(result, isA<AccountImportParsed>());
    });
  });

  group('parseAccountImport — malformed inputs (nothing is written for any '
      'of these)', () {
    test('truncated JSON is rejected', () {
      final bytes = _bytes(_rawDocument());
      final truncated = bytes.sublist(0, bytes.length - 10);
      final result = parseAccountImport(truncated);
      expect(result, isA<AccountImportParseFailed>());
    });

    test('a wrong schemaVersion is rejected', () {
      final result = parseAccountImport(_bytes(_rawDocument(schemaVersion: 99)));
      expect(result, isA<AccountImportParseFailed>());
      expect((result as AccountImportParseFailed).error.message,
          contains('schema version'));
    });

    test('a schemaVersion below the accepted range is rejected', () {
      final result = parseAccountImport(_bytes(_rawDocument(schemaVersion: 0)));
      expect(result, isA<AccountImportParseFailed>());
    });

    test('an over-length note is rejected', () {
      final result = parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', note: 'x' * (kMaxNoteLength + 1)),
        ]),
      ])));
      expect(result, isA<AccountImportParseFailed>());
    });

    test('an oversize tag array is rejected', () {
      final result = parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05',
              tags: List.generate(kMaxTagCount + 1, (i) => 'tag$i')),
        ]),
      ])));
      expect(result, isA<AccountImportParseFailed>());
    });

    test('a single over-length tag is rejected', () {
      final result = parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', tags: ['x' * (kMaxTagLength + 1)]),
        ]),
      ])));
      expect(result, isA<AccountImportParseFailed>());
    });

    test('a malformed date is rejected', () {
      final result = parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [_rawDayEntry(_e1, 'not-a-date')]),
      ])));
      expect(result, isA<AccountImportParseFailed>());
    });

    test('an out-of-range calendar date is rejected', () {
      final result = parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [_rawDayEntry(_e1, '2026-02-30')]),
      ])));
      expect(result, isA<AccountImportParseFailed>());
    });

    test('a profile missing its id is rejected', () {
      final raw = _rawDocument(profiles: [
        {'displayName': 'No id'},
      ]);
      final result = parseAccountImport(_bytes(raw));
      expect(result, isA<AccountImportParseFailed>());
    });

    test('a profile display name over the server bound is rejected', () {
      final result = parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, displayName: 'x' * (kMaxDisplayNameLength + 1)),
      ])));
      expect(result, isA<AccountImportParseFailed>());
    });

    test('an invalid observation intensity is rejected', () {
      final result = parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, observations: [
          _rawObservation(_o1, '2026-01-05', intensity: 99),
        ]),
      ])));
      expect(result, isA<AccountImportParseFailed>());
    });

    test(
        'a nonfinite valueNum literal (e.g. 1e400, which overflows to '
        'Infinity) is rejected (Issue #140 review, LLA-092)', () {
      // jsonEncode cannot itself serialize Infinity/NaN -- `1e400` has to be
      // spliced into the JSON text as a bare numeral, exactly as an
      // untrusted file would carry it, rather than round-tripped through a
      // Dart double (which would throw building the fixture, not exercise
      // the parser under test).
      final encoded = jsonEncode(_rawDocument(profiles: [
        _rawProfile(_p1, observations: [_rawObservation(_o1, '2026-01-05')]),
      ]));
      final poisoned = encoded.replaceFirst('"valueNum":null', '"valueNum":1e400');
      expect(poisoned, isNot(encoded)); // the splice actually matched
      final result = parseAccountImport(utf8.encode(poisoned));
      expect(result, isA<AccountImportParseFailed>());
    });

    test('an oversize observation raw payload is rejected', () {
      final result = parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, observations: [
          _rawObservation(_o1, '2026-01-05',
              raw: {'blob': 'x' * kMaxObservationRawLength}),
        ]),
      ])));
      expect(result, isA<AccountImportParseFailed>());
    });

    test('the top-level document is not a JSON object', () {
      final result = parseAccountImport(utf8.encode(jsonEncode([1, 2, 3])));
      expect(result, isA<AccountImportParseFailed>());
    });

    // Issue #140 review, item 8: an unrecognised flow value is now
    // REJECTED, not silently degraded to `none`.
    test('an unrecognised flow value is rejected', () {
      final result = parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', flow: 'super_heavy_future_value'),
        ]),
      ])));
      expect(result, isA<AccountImportParseFailed>());
    });

    // Issue #140 review, item 3: a wrong-typed field must not throw a raw
    // TypeError out of parseAccountImport — each is a clean, typed
    // rejection instead.
    test('a non-string note is rejected, not a raw TypeError', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          {..._rawDayEntry(_e1, '2026-01-05'), 'note': 123},
        ]),
      ]);
      expect(() => parseAccountImport(_bytes(raw)), returnsNormally);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('a non-string tz is rejected, not a raw TypeError', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          {..._rawDayEntry(_e1, '2026-01-05'), 'tz': 5},
        ]),
      ]);
      expect(() => parseAccountImport(_bytes(raw)), returnsNormally);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('a non-string mode is rejected, not a raw TypeError', () {
      final raw = _rawDocument(profiles: [
        {..._rawProfile(_p1), 'mode': 7},
      ]);
      expect(() => parseAccountImport(_bytes(raw)), returnsNormally);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    // Issue #140 review, item 4: bounds mirroring the server's remaining
    // CHECK constraints.
    test('a tz longer than the server bound is rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          {..._rawDayEntry(_e1, '2026-01-05'), 'tz': 'x' * (kMaxTzLength + 1)},
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('a tz that is not a recognised IANA zone is rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          {..._rawDayEntry(_e1, '2026-01-05'), 'tz': 'Not/A_Real_Zone'},
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    // Issue #458: a Health Connect import stores a record's raw zoneOffset as
    // a fixed-offset designator; the export/import round-trip must accept it.
    test('a fixed-offset zone designator is accepted', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          {..._rawDayEntry(_e1, '2026-01-05'), 'tz': 'UTC+05:30'},
        ]),
      ]);
      final parsed = parseAccountImport(_bytes(raw));
      expect(parsed, isNot(isA<AccountImportParseFailed>()));
    });

    test('a day entry id longer than the server bound is rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          {
            ..._rawDayEntry(_e1, '2026-01-05'),
            'id': 'x' * (kMaxDayEntrySourceIdLength + 1),
          },
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('an observation id longer than the server bound is rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          {
            ..._rawObservation(_o1, '2026-01-05'),
            'id': 'x' * (kMaxObservationSourceIdLength + 1),
          },
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('an unrecognised profile mode is rejected', () {
      final raw = _rawDocument(profiles: [
        {..._rawProfile(_p1), 'mode': 'not_a_real_mode'},
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    // Issue #255: the display-unit preferences get mode's closed-set
    // treatment — an unrecognised value is rejected outright, an absent
    // key (a pre-v8 export) parses to null and the importer falls back to
    // the column default.
    test('a non-string bbtUnit is rejected, not a raw TypeError', () {
      final raw = _rawDocument(profiles: [
        {..._rawProfile(_p1), 'bbtUnit': 7},
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('an unrecognised bbtUnit or weightUnit is rejected', () {
      final raw = _rawDocument(profiles: [
        {..._rawProfile(_p1), 'bbtUnit': 'kelvin'},
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
      final raw2 = _rawDocument(profiles: [
        {..._rawProfile(_p1), 'weightUnit': 'stone'},
      ]);
      expect(parseAccountImport(_bytes(raw2)), isA<AccountImportParseFailed>());
    });

    test('a v8 document carries bbtUnit/weightUnit through the parse; an '
        'older document without the keys parses to nulls', () {
      final v8 = parseAccountImport(_bytes(_rawDocument(profiles: [
        {..._rawProfile(_p1), 'bbtUnit': 'fahrenheit', 'weightUnit': 'lb'},
      ])));
      final profile =
          ((v8 as AccountImportParsed).document).profiles.single;
      expect(profile.bbtUnit, 'fahrenheit');
      expect(profile.weightUnit, 'lb');

      final preV8 = parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1),
      ])));
      final absent = ((preV8 as AccountImportParsed).document).profiles.single;
      expect(absent.bbtUnit, isNull);
      expect(absent.weightUnit, isNull);
    });

    test('more than kMaxObservationsPerDay observations on one '
        '(profile, date) are rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          for (var i = 0; i < kMaxObservationsPerDay + 1; i++)
            _rawObservation(_obsId(i), '2026-01-05', code: 'code$i'),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    // Issue #140 review, item 9: a "crafted file" case (two day entries for
    // the same profile+date) must not silently double-count.
    test('two day entries for the same profile and date are rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
          _rawDayEntry(_e2, '2026-01-05'),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('an observation whose date has no matching day entry is rejected',
        () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, observations: [
          _rawObservation(_o1, '2026-01-05'),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('a file over the byte cap is rejected before JSON decoding', () {
      final oversized = Uint8List(kMaxImportFileBytes + 1);
      final result = parseAccountImport(oversized);
      expect(result, isA<AccountImportParseFailed>());
    });
  });

  group('parseAccountImport — portable state validation (Issue #140 '
      'review, LLA-084)', () {
    test('an out-of-range birthYear is rejected', () {
      final raw = _rawDocument(profiles: [
        {..._rawProfile(_p1), 'birthYear': 1800},
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('an unrecognised relationship is rejected', () {
      final raw = _rawDocument(profiles: [
        {..._rawProfile(_p1), 'relationship': 'stranger'},
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('an out-of-range typicalCycleLengthDays is rejected', () {
      final raw = _rawDocument(profiles: [
        {..._rawProfile(_p1), 'typicalCycleLengthDays': 400},
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('an out-of-range typicalPeriodLengthDays is rejected', () {
      final raw = _rawDocument(profiles: [
        {..._rawProfile(_p1), 'typicalPeriodLengthDays': 90},
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('a malformed lastPeriodStart is rejected', () {
      final raw = _rawDocument(profiles: [
        {..._rawProfile(_p1), 'lastPeriodStart': 'not-a-date'},
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('an unrecognised profileMode.mode is rejected', () {
      final raw = _rawDocument(profiles: [
        {
          ..._rawProfile(_p1),
          'profileMode': {'mode': 'not-a-mode'},
        },
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('an over-length profileMode.birthControlMethod is rejected', () {
      final raw = _rawDocument(profiles: [
        {
          ..._rawProfile(_p1),
          'profileMode': {
            'mode': 'tracking',
            'birthControlMethod': 'x' * (kMaxBirthControlMethodLength + 1),
          },
        },
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('a malformed profileMode.birthControlStartedOn is rejected', () {
      final raw = _rawDocument(profiles: [
        {
          ..._rawProfile(_p1),
          'profileMode': {'mode': 'tracking', 'birthControlStartedOn': 'nope'},
        },
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('a non-ULID cycle override id is rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, cycleOverrides: [
          {..._rawCycleOverride('not-a-ulid', '2026-01-01')},
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('a malformed cycleStartDate is rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, cycleOverrides: [
          _rawCycleOverride(_co1, 'not-a-date'),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('an over-length cycle override noteId is rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, cycleOverrides: [
          _rawCycleOverride(_co1, '2026-01-01',
              noteId: 'x' * (kMaxCycleOverrideNoteIdLength + 1)),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('two cycle overrides sharing an id in one profile are rejected',
        () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, cycleOverrides: [
          _rawCycleOverride(_co1, '2026-01-01'),
          _rawCycleOverride(_co1, '2026-02-01'),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('the same cycle override id under two DIFFERENT profiles is fine '
        '— the composite (id, profile_id) key means this is not a '
        'collision', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, cycleOverrides: [_rawCycleOverride(_co1, '2026-01-01')]),
        _rawProfile(_p2, cycleOverrides: [_rawCycleOverride(_co1, '2026-01-01')]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParsed>());
    });

    test('a well-formed profile carries every new field through parsing',
        () {
      final raw = _rawDocument(profiles: [
        {
          ..._rawProfile(_p1, cycleOverrides: [
            _rawCycleOverride(_co1, '2026-01-01',
                excludedFromAverage: true, manualStart: true, noteId: 'n1'),
          ]),
          'birthYear': 2012,
          'relationship': 'daughter',
          'lastPeriodStart': '2026-08-01',
          'typicalCycleLengthDays': 28,
          'typicalPeriodLengthDays': 5,
          'profileMode': {
            'mode': 'conceive',
            'birthControlMethod': 'pill',
            'birthControlStartedOn': '2026-06-01',
            'birthControlStoppedOn': null,
          },
        },
      ]);
      final result = parseAccountImport(_bytes(raw));
      expect(result, isA<AccountImportParsed>());
      final profile = (result as AccountImportParsed).document.profiles.single;
      expect(profile.birthYear, 2012);
      expect(profile.relationship, ProfileRelationship.daughter);
      expect(profile.lastPeriodStart?.iso, '2026-08-01');
      expect(profile.typicalCycleLengthDays, 28);
      expect(profile.typicalPeriodLengthDays, 5);
      expect(profile.profileMode?.mode, LifecycleMode.conceive);
      expect(profile.profileMode?.birthControlMethod, 'pill');
      expect(profile.profileMode?.birthControlStartedOn, '2026-06-01');
      expect(profile.profileMode?.birthControlStoppedOn, isNull);
      expect(profile.cycleOverrides, hasLength(1));
      expect(profile.cycleOverrides.single.cycleStartDate.iso, '2026-01-01');
      expect(profile.cycleOverrides.single.excludedFromAverage, isTrue);
      expect(profile.cycleOverrides.single.manualStart, isTrue);
      expect(profile.cycleOverrides.single.noteId, 'n1');
    });
  });

  group('parseAccountImport — trackingPreferences (Issue #648, import v10)',
      () {
    test('an absent trackingPreferences key parses to null (an older '
        'export)', () {
      final raw = _rawDocument(profiles: [_rawProfile(_p1)]);
      final result = parseAccountImport(_bytes(raw));
      expect(result, isA<AccountImportParsed>());
      final profile = (result as AccountImportParsed).document.profiles.single;
      expect(profile.trackingPreferences, isNull);
    });

    test('a well-formed trackingPreferences document round-trips through '
        'parsing', () {
      final raw = _rawDocument(profiles: [
        {
          ..._rawProfile(_p1),
          'trackingPreferences': {
            'mood': {'enabled': false, 'sort_order': 2},
          },
        },
      ]);
      final result = parseAccountImport(_bytes(raw));
      expect(result, isA<AccountImportParsed>());
      final profile = (result as AccountImportParsed).document.profiles.single;
      final prefs = profile.trackingPreferences;
      expect(prefs, isNotNull);
      expect(prefs!.entries['mood']?.enabled, isFalse);
      expect(prefs.entries['mood']?.sortOrder, 2);
    });

    test('a non-object trackingPreferences value is rejected outright — not '
        'a shape a genuine export could ever produce', () {
      final raw = _rawDocument(profiles: [
        {..._rawProfile(_p1), 'trackingPreferences': 'not-an-object'},
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('a malformed entry inside an otherwise well-formed document '
        'degrades tolerantly (dropped, category resolves to default) rather '
        'than rejecting the whole file — the same degrade the sync engine '
        'already gives a corrupt document off the wire', () {
      final raw = _rawDocument(profiles: [
        {
          ..._rawProfile(_p1),
          'trackingPreferences': {
            'mood': {'enabled': false, 'sort_order': 2},
            'garbage': {'enabled': 'not-a-bool', 'sort_order': 1},
          },
        },
      ]);
      final result = parseAccountImport(_bytes(raw));
      expect(result, isA<AccountImportParsed>());
      final profile = (result as AccountImportParsed).document.profiles.single;
      expect(profile.trackingPreferences!.entries.containsKey('garbage'),
          isFalse);
      expect(profile.trackingPreferences!.entries['mood']?.enabled, isFalse);
    });
  });

  group('parseAccountImport — customTags (Issue #824, import v12)', () {
    test('an absent customTags key parses to empty list (an older export)', () {
      final raw = _rawDocument(profiles: [_rawProfile(_p1)]);
      final result = parseAccountImport(_bytes(raw));
      expect(result, isA<AccountImportParsed>());
      final profile = (result as AccountImportParsed).document.profiles.single;
      expect(profile.customTags, isEmpty);
    });

    test('a non-ULID custom tag id is rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, customTags: [
          _rawCustomTag('not-a-ulid', 'cramps_severe', 'Severe Cramps'),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('an empty custom tag code is rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, customTags: [
          _rawCustomTag(_ct1, '   ', 'Severe Cramps'),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('an over-length custom tag code (>32 chars) is rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, customTags: [
          _rawCustomTag(_ct1, 'x' * (kMaxTagLength + 1), 'Severe Cramps'),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('an over-length custom tag displayName (>40 chars) is rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, customTags: [
          _rawCustomTag(_ct1, 'cramps_severe', 'x' * (kMaxCustomTagLabelLength + 1)),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('an empty custom tag displayName is rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, customTags: [
          _rawCustomTag(_ct1, 'cramps_severe', '   '),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('an over-length custom tag category (>32 chars) is rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, customTags: [
          _rawCustomTag(_ct1, 'cramps_severe', 'Severe Cramps',
              category: 'x' * (kMaxTagLength + 1)),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('two custom tags sharing an id in one profile are rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, customTags: [
          _rawCustomTag(_ct1, 'cramps_severe', 'Severe Cramps'),
          _rawCustomTag(_ct1, 'herbal_tea', 'Herbal Tea'),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('two custom tags sharing a code in one profile are rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, customTags: [
          _rawCustomTag(_ct1, 'cramps_severe', 'Severe Cramps'),
          _rawCustomTag(_ct2, 'cramps_severe', 'Another Cramps'),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('more than 100 custom tags in one profile are rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, customTags: [
          for (var i = 0; i < 101; i++)
            _rawCustomTag(
              (950000 + i).toString().padLeft(26, '0'),
              'tag_$i',
              'Tag $i',
            ),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('the same custom tag id under two DIFFERENT profiles is fine', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, customTags: [_rawCustomTag(_ct1, 'tag_1', 'Tag 1')]),
        _rawProfile(_p2, customTags: [_rawCustomTag(_ct1, 'tag_1', 'Tag 1')]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParsed>());
    });

    test('a well-formed custom tag parses correctly', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, customTags: [
          _rawCustomTag(
            _ct1,
            'cramps_severe',
            'Severe Cramps',
            intensityEnabled: true,
            sortOrder: 1,
            hiddenAt: '2026-01-15T00:00:00.000Z',
          ),
        ]),
      ]);
      final result = parseAccountImport(_bytes(raw));
      expect(result, isA<AccountImportParsed>());
      final profile = (result as AccountImportParsed).document.profiles.single;
      expect(profile.customTags, hasLength(1));
      final tag = profile.customTags.single;
      expect(tag.id, _ct1);
      expect(tag.code, 'cramps_severe');
      expect(tag.displayName, 'Severe Cramps');
      expect(tag.category, 'custom');
      expect(tag.intensityEnabled, isTrue);
      expect(tag.sortOrder, 1);
      expect(tag.hiddenAt?.toIso8601String(), '2026-01-15T00:00:00.000Z');
    });
  });

  group('parseAccountImport — id validation (Issue #140 review round 2, '
      'item 1)', () {
    test('a non-ULID profile id ("riley") is rejected', () {
      final raw = _rawDocument(profiles: [_rawProfile('riley')]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('a 100 KB profile id is rejected', () {
      final raw = _rawDocument(profiles: [_rawProfile('x' * 100000)]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('a lowercase/invalid-alphabet profile id is rejected', () {
      // Right length (26), but Crockford base32 has no lowercase and no
      // I/L/O/U — this is what a ULID's own text looks like lowercased,
      // which a hand-crafted or corrupted file could plausibly carry.
      final raw =
          _rawDocument(profiles: [_rawProfile('01arz3ndektsv4rrffq69g5fav')]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('a non-ULID day entry id is rejected — it would otherwise become '
        'the row\'s sourceId (or, per item 3, its row id) and later blow up '
        'row_codec.dart\'s encodeDayEntry on every sync cycle', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [_rawDayEntry('riley', '2026-01-05')]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });

    test('a non-ULID observation id is rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          _rawObservation('riley', '2026-01-05'),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParseFailed>());
    });
  });

  group('parseAccountImport — duplicate provenance (Issue #140 review round '
      '2, item 2)', () {
    test('two day entries in one profile sharing (source, sourceId) on '
        'different dates are rejected — the second would otherwise revive '
        'the first\'s freshly-inserted row onto its own date mid-apply', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          {
            ..._rawDayEntry(_e1, '2026-01-05'),
            'source': 'clue_import',
            'sourceId': 'clue-abc',
          },
          {
            ..._rawDayEntry(_e2, '2026-01-06'),
            'source': 'clue_import',
            'sourceId': 'clue-abc',
          },
        ]),
      ]);
      final result = parseAccountImport(_bytes(raw));
      expect(result, isA<AccountImportParseFailed>());
    });

    test('two day entries sharing a source but each with a null sourceId '
        'are NOT a collision (the server index only applies when sourceId '
        'is not null)', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
          _rawDayEntry(_e2, '2026-01-06'),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParsed>());
    });
  });

  group('parseAccountImport — duplicate ids across the whole document '
      '(round-3 review, item 2)', () {
    test('a duplicate profile id is rejected, even across two distinct '
        'profile entries', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1),
        _rawProfile(_p1, displayName: 'Also Riley'),
      ]);
      final result = parseAccountImport(_bytes(raw));
      expect(result, isA<AccountImportParseFailed>());
      expect((result as AccountImportParseFailed).error.message,
          contains('Duplicate profile id'));
    });

    test('a day entry id reused across two different profiles is rejected '
        '— identity is document-wide, not per profile', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [_rawDayEntry(_e1, '2026-01-05')]),
        _rawProfile(_p2, dayEntries: [_rawDayEntry(_e1, '2026-01-06')]),
      ]);
      final result = parseAccountImport(_bytes(raw));
      expect(result, isA<AccountImportParseFailed>());
      expect((result as AccountImportParseFailed).error.message,
          contains('Duplicate day entry id'));
    });

    test('the same entry id used twice within one profile, on different '
        'dates and with different provenance, is still rejected as a '
        'duplicate id — not to be confused with '
        '_rejectDuplicateEntryDates/_rejectDuplicateProvenance, which check '
        'a different shape of collision', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          {
            ..._rawDayEntry(_e1, '2026-01-05'),
            'source': 'clue_import',
            'sourceId': 'clue-abc',
          },
          {
            ..._rawDayEntry(_e1, '2026-01-06'),
            'source': 'apple_health',
            'sourceId': 'ah-xyz',
          },
        ]),
      ]);
      final result = parseAccountImport(_bytes(raw));
      expect(result, isA<AccountImportParseFailed>());
      expect((result as AccountImportParseFailed).error.message,
          contains('Duplicate day entry id'));
    });

    test('an observation id reused across two different profiles is '
        'rejected', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          _rawObservation(_o1, '2026-01-05', category: 'pain', code: 'cramps'),
        ]),
        _rawProfile(_p2, dayEntries: [
          _rawDayEntry(_e2, '2026-01-06'),
        ], observations: [
          _rawObservation(_o1, '2026-01-06', category: 'mood', code: 'anxious'),
        ]),
      ]);
      final result = parseAccountImport(_bytes(raw));
      expect(result, isA<AccountImportParseFailed>());
      expect((result as AccountImportParseFailed).error.message,
          contains('Duplicate observation id'));
    });

    test('the rejection message truncates a long id rather than '
        'interpolating it verbatim', () {
      // Ids are already ULID-validated to exactly 26 characters by this
      // point, so this exercises the truncate call defensively rather than
      // reachably — matching item 5's own truncate-before-interpolating
      // rule.
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1),
        _rawProfile(_p1),
      ]);
      final result = parseAccountImport(_bytes(raw));
      final message = (result as AccountImportParseFailed).error.message;
      expect(message.length, lessThan(200));
    });

    test('distinct profile, entry, and observation ids never collide with '
        'each other (each namespace is checked independently)', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          _rawObservation(_o1, '2026-01-05'),
        ]),
        _rawProfile(_p2, dayEntries: [
          _rawDayEntry(_e2, '2026-01-05'),
        ], observations: [
          _rawObservation(_o2, '2026-01-05'),
        ]),
      ]);
      expect(parseAccountImport(_bytes(raw)), isA<AccountImportParsed>());
    });
  });

  group('parseAccountImport — importId (Issue #140 review, LLA-087)', () {
    test('a malformed importId is dropped (null), never rejects the '
        'document', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          {..._rawDayEntry(_e1, '2026-01-05'), 'importId': 'not-a-uuid'},
        ]),
      ]);
      final result = parseAccountImport(_bytes(raw));
      expect(result, isA<AccountImportParsed>());
      final document = (result as AccountImportParsed).document;
      expect(document.profiles.single.dayEntries.single.importId, isNull);
    });

    // Issue #140 review, LLA-087: a well-formed UUID importId is NEVER
    // round-tripped, unlike source/sourceId — it points at an import_jobs
    // row on the EXPORTING device/account, which a restore has no reason to
    // expect still exists. Round-tripping it risked a later sync_push
    // rejection (day_entries_import_id_fkey) against a job that was never,
    // and cannot be, restored alongside the entry.
    test('a well-formed UUID importId is always cleared, even alongside '
        'explicit file provenance', () {
      const uuid = '3fa85f64-5717-4562-b3fc-2c963f66afa6';
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          {
            ..._rawDayEntry(_e1, '2026-01-05'),
            'source': 'clue_import',
            'sourceId': 'clue-abc',
            'importId': uuid,
          },
        ]),
      ]);
      final result = parseAccountImport(_bytes(raw));
      final document = (result as AccountImportParsed).document;
      final entry = document.profiles.single.dayEntries.single;
      expect(entry.importId, isNull);
      // source/sourceId are the portable identity and still round-trip.
      expect(entry.source, 'clue_import');
      expect(entry.sourceId, 'clue-abc');
    });

    test('a manual/null entry always nulls importId regardless (the item 7 '
        'fallback)', () {
      const uuid = '3fa85f64-5717-4562-b3fc-2c963f66afa6';
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          {..._rawDayEntry(_e1, '2026-01-05'), 'importId': uuid},
        ]),
      ]);
      final result = parseAccountImport(_bytes(raw));
      final document = (result as AccountImportParsed).document;
      expect(document.profiles.single.dayEntries.single.importId, isNull);
    });
  });

  group('parseAccountImport — rejection message truncation (Issue #140 '
      'review round 2, item 5)', () {
    test('an unrecognised flow value of 5 MB does not blow up the '
        'rejection message', () {
      final huge = 'x' * (5 * 1024 * 1024);
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [_rawDayEntry(_e1, '2026-01-05', flow: huge)]),
      ]);
      final result = parseAccountImport(_bytes(raw));
      expect(result, isA<AccountImportParseFailed>());
      final message = (result as AccountImportParseFailed).error.message;
      expect(message.length, lessThan(200));
      expect(message, isNot(contains(huge)));
    });
  });

  group('flowNameFromWire (round-3 review, item 4)', () {
    test('converts a snake_case wire value to camelCase', () {
      expect(flowNameFromWire('not_bleeding'), 'notBleeding');
    });

    test('a value with no underscore is unchanged', () {
      expect(flowNameFromWire('heavy'), 'heavy');
    });

    test('multiple underscores each convert their following letter', () {
      expect(flowNameFromWire('super_extra_heavy'), 'superExtraHeavy');
    });
  });

  group('previewImport', () {
    test('an empty document previews as all zeros with no date range', () {
      final document =
          (parseAccountImport(_bytes(_rawDocument())) as AccountImportParsed)
              .document;
      final preview = previewImport(document);
      expect(preview.profileCount, 0);
      expect(preview.entryCount, 0);
      expect(preview.observationCount, 0);
      expect(preview.earliestDate, isNull);
      expect(preview.latestDate, isNull);
    });

    test('counts entries/observations across profiles and finds the full '
        'date range', () {
      final raw = _rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-10'),
          _rawDayEntry(_e2, '2026-01-05'),
        ]),
        _rawProfile(_p2, dayEntries: [
          _rawDayEntry(_e3, '2026-02-01'),
        ], observations: [
          _rawObservation(_o1, '2026-02-01'),
        ]),
      ]);
      final document =
          (parseAccountImport(_bytes(raw)) as AccountImportParsed).document;
      final preview = previewImport(document);
      expect(preview.profileCount, 2);
      expect(preview.entryCount, 3);
      expect(preview.observationCount, 1);
      expect(preview.earliestDate, LocalDate.fromIso('2026-01-05'));
      expect(preview.latestDate, LocalDate.fromIso('2026-02-01'));
    });
  });

  group('writeBlockReasonFor', () {
    test('an archived profile is blocked', () {
      final reason = writeBlockReasonFor(
        profile: _profile(_p1, archivedAt: DateTime.utc(2026, 1, 1)),
      );
      expect(reason, isNotNull);
    });

    test('a viewer-role guardian is blocked', () {
      final reason = writeBlockReasonFor(
        profile: _profile(_p1),
        currentUserId: 'u1',
        guardians: [
          ProfileGuardian(
            id: 'g1',
            profileId: _p1,
            userId: 'u1',
            role: GuardianRole.viewer,
            status: GuardianStatus.accepted,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      expect(reason, isNotNull);
    });

    test('a caregiver-role guardian is not blocked', () {
      final reason = writeBlockReasonFor(
        profile: _profile(_p1),
        currentUserId: 'u1',
        guardians: [
          ProfileGuardian(
            id: 'g1',
            profileId: _p1,
            userId: 'u1',
            role: GuardianRole.caregiver,
            status: GuardianStatus.accepted,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      expect(reason, isNull);
    });

    test('no guardian rows and no currentUserId both fail open', () {
      expect(writeBlockReasonFor(profile: _profile(_p1)), isNull);
    });
  });

  group('planImport — first-class PMS marker (Issue #220)', () {
    test('an added entry carries the file\'s PMS marker verbatim', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', pms: true),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingEntriesByProfileId: const {_p1: []},
        writeBlockReason: _neverBlocked,
      );

      final entryPlan = plan.profiles.single.entries.single;
      expect(entryPlan.outcome, DayEntryImportOutcome.add);
      expect(entryPlan.pms, isTrue);
    });

    test('a merge ORs the marker: either side carrying it keeps it (the '
        'boolean analogue of the tags union)', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', pms: true),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final existing = _entry('local1', _p1, '2026-01-05', pms: false);
      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingEntriesByProfileId: {
          _p1: [existing],
        },
        writeBlockReason: _neverBlocked,
      );
      expect(plan.profiles.single.entries.single.pms, isTrue,
          reason: 'file says PMS, device does not — the marker survives');

      final document2 = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', pms: false),
        ]),
      ]))) as AccountImportParsed)
          .document;
      final existing2 = _entry('local2', _p1, '2026-01-05', pms: true);
      final plan2 = planImport(
        document: document2,
        existingProfiles: [_profile(_p1)],
        existingEntriesByProfileId: {
          _p1: [existing2],
        },
        writeBlockReason: _neverBlocked,
      );
      expect(plan2.profiles.single.entries.single.pms, isTrue,
          reason: 'device says PMS, file does not — the marker survives');
    });

    test('an old v6 file without the pms key imports as false', () {
      final raw = _rawDayEntry(_e1, '2026-01-05')..remove('pms');
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [raw]),
      ]))) as AccountImportParsed)
          .document;
      expect(document.profiles.single.dayEntries.single.pms, isFalse);
    });
  });

  group('planImport — profile create/match/skip', () {
    test('a profile id absent locally is created, and every entry/'
        'observation is an add', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          _rawObservation(_o1, '2026-01-05'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: const [],
        writeBlockReason: _neverBlocked,
      );

      final profilePlan = plan.profiles.single;
      expect(profilePlan.outcome, ProfileImportOutcome.created);
      expect(profilePlan.entries.single.outcome, DayEntryImportOutcome.add);
      expect(profilePlan.entries.single.source, DayEntrySource.fileImport.toDb());
      expect(profilePlan.entries.single.sourceId, _e1);
      expect(profilePlan.observations.single.outcome, ObservationImportOutcome.add);
      expect(plan.summary.profilesCreated, 1);
      expect(plan.summary.profilesMatched, 0);
      expect(plan.summary.entriesAdded, 1);
      expect(plan.summary.observationsAdded, 1);
    });

    test('a matched profile that cannot be written is skipped with a '
        'reason, and no entries/observations are planned for it', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [_rawDayEntry(_e1, '2026-01-05')]),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1, archivedAt: DateTime.utc(2026, 1, 1))],
        writeBlockReason: (p) => writeBlockReasonFor(profile: p),
      );

      final profilePlan = plan.profiles.single;
      expect(profilePlan.outcome, ProfileImportOutcome.skipped);
      expect(profilePlan.entries, isEmpty);
      expect(plan.summary.skippedProfiles, hasLength(1));
      expect(plan.summary.skippedProfiles.single.reason, isNotEmpty);
    });

    test('a writable matched profile is matched, not created', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        writeBlockReason: _neverBlocked,
      );

      expect(plan.profiles.single.outcome, ProfileImportOutcome.matched);
      expect(plan.summary.profilesMatched, 1);
      expect(plan.summary.profilesCreated, 0);
    });
  });

  group('planImport — portable state (Issue #140 review, LLA-084)', () {
    test('a created profile carries the file\'s subject metadata and '
        'profileMode through to the plan', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        {
          ..._rawProfile(_p1),
          'birthYear': 2012,
          'relationship': 'daughter',
          'lastPeriodStart': '2026-08-01',
          'typicalCycleLengthDays': 28,
          'typicalPeriodLengthDays': 5,
          'profileMode': {'mode': 'conceive', 'birthControlMethod': 'pill'},
        },
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: const [],
        writeBlockReason: _neverBlocked,
      );

      final profilePlan = plan.profiles.single;
      expect(profilePlan.outcome, ProfileImportOutcome.created);
      expect(profilePlan.birthYear, 2012);
      expect(profilePlan.relationship, ProfileRelationship.daughter);
      expect(profilePlan.lastPeriodStart?.iso, '2026-08-01');
      expect(profilePlan.typicalCycleLengthDays, 28);
      expect(profilePlan.typicalPeriodLengthDays, 5);
      expect(profilePlan.profileMode?.mode, LifecycleMode.conceive);
      expect(profilePlan.profileMode?.birthControlMethod, 'pill');
    });

    test('a MATCHED profile never carries the file\'s subject metadata or '
        'profileMode — only a created profile does, mirroring mode/'
        'bbtUnit/weightUnit\'s own create-only treatment', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        {
          ..._rawProfile(_p1),
          'birthYear': 2012,
          'profileMode': {'mode': 'conceive'},
        },
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        writeBlockReason: _neverBlocked,
      );

      final profilePlan = plan.profiles.single;
      expect(profilePlan.outcome, ProfileImportOutcome.matched);
      expect(profilePlan.birthYear, isNull);
      expect(profilePlan.profileMode, isNull);
    });

    test('a created profile carries the file\'s trackingPreferences through '
        'to the plan; a MATCHED profile never does (Issue #648, same '
        'create-only treatment as profileMode)', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        {
          ..._rawProfile(_p1),
          'trackingPreferences': {
            'mood': {'enabled': false, 'sort_order': 2},
          },
        },
      ]))) as AccountImportParsed)
          .document;

      final createdPlan = planImport(
        document: document,
        existingProfiles: const [],
        writeBlockReason: _neverBlocked,
      );
      final TrackingPreferences? created =
          createdPlan.profiles.single.trackingPreferences;
      expect(createdPlan.profiles.single.outcome, ProfileImportOutcome.created);
      expect(created?.entries['mood']?.enabled, isFalse);

      final matchedPlan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        writeBlockReason: _neverBlocked,
      );
      expect(matchedPlan.profiles.single.outcome, ProfileImportOutcome.matched);
      expect(matchedPlan.profiles.single.trackingPreferences, isNull);
    });

    test('cycleOverrides are additive for a CREATED profile: two distinct '
        'dates both add', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, cycleOverrides: [
          _rawCycleOverride(_co1, '2026-01-01'),
          _rawCycleOverride('00000000000000000000000032', '2026-02-01'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: const [],
        writeBlockReason: _neverBlocked,
      );

      final overridePlans = plan.profiles.single.cycleOverrides;
      expect(overridePlans, hasLength(2));
      expect(overridePlans.every((o) => o.outcome == CycleOverrideImportOutcome.add),
          isTrue);
      expect(plan.summary.cycleOverridesAdded, 2);
      expect(plan.summary.cycleOverridesSkipped, 0);
    });

    test('cycleOverrides are additive for a MATCHED profile too — unlike '
        'subject metadata/profileMode, this is not create-only', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, cycleOverrides: [
          _rawCycleOverride(_co1, '2026-01-01'), // collides with existing
          _rawCycleOverride('00000000000000000000000032', '2026-02-01'), // new
        ]),
      ]))) as AccountImportParsed)
          .document;

      final existingOverride = CycleOverride(
        id: 'local-co-1',
        profileId: _p1,
        cycleStartDate: '2026-01-01',
        excludedFromAverage: true,
      );

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingCycleOverridesByProfileId: {
          _p1: [existingOverride],
        },
        writeBlockReason: _neverBlocked,
      );

      final overridePlans = plan.profiles.single.cycleOverrides;
      expect(overridePlans[0].outcome, CycleOverrideImportOutcome.skip,
          reason: 'a live override already occupies 2026-01-01');
      expect(overridePlans[1].outcome, CycleOverrideImportOutcome.add);
      expect(plan.summary.cycleOverridesAdded, 1);
      expect(plan.summary.cycleOverridesSkipped, 1);
    });
  });

  group('planImport — customTags merge policy (Issue #824)', () {
    test(
        'customTags are additive for a CREATED profile: two distinct tags both add',
        () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, customTags: [
          _rawCustomTag(_ct1, 'cramps_severe', 'Severe Cramps'),
          _rawCustomTag(_ct2, 'herbal_tea', 'Herbal Tea'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: const [],
        writeBlockReason: _neverBlocked,
      );

      final tagPlans = plan.profiles.single.customTags;
      expect(tagPlans, hasLength(2));
      expect(
          tagPlans.every((t) => t.outcome == CustomTagImportOutcome.add), isTrue);
      expect(plan.summary.customTagsAdded, 2);
      expect(plan.summary.customTagsSkipped, 0);
    });

    test(
        'customTags are additive for a MATCHED profile: colliding code or id skips, new adds',
        () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, customTags: [
          _rawCustomTag(_ct1, 'cramps_severe', 'Severe Cramps'), // collides with code
          _rawCustomTag(_ct2, 'herbal_tea', 'Herbal Tea'), // new
        ]),
      ]))) as AccountImportParsed)
          .document;

      final existingTag = CustomTag(
        id: 'local-tag-1',
        profileId: _p1,
        code: 'cramps_severe',
        displayName: 'Cramps',
        category: 'custom',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingCustomTagsByProfileId: {
          _p1: [existingTag],
        },
        writeBlockReason: _neverBlocked,
      );

      final tagPlans = plan.profiles.single.customTags;
      expect(tagPlans[0].outcome, CustomTagImportOutcome.skip,
          reason: 'a live tag already has code cramps_severe');
      expect(tagPlans[1].outcome, CustomTagImportOutcome.add);
      expect(plan.summary.customTagsAdded, 1);
      expect(plan.summary.customTagsSkipped, 1);
    });

    test('customTags skip when profile already has max 100 tags', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, customTags: [
          _rawCustomTag(_ct1, 'new_tag', 'New Tag'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final existingTags = [
        for (var i = 0; i < 100; i++)
          CustomTag(
            id: (960000 + i).toString().padLeft(26, '0'),
            profileId: _p1,
            code: 'existing_$i',
            displayName: 'Tag $i',
            category: 'custom',
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
      ];

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingCustomTagsByProfileId: {
          _p1: existingTags,
        },
        writeBlockReason: _neverBlocked,
      );

      final tagPlans = plan.profiles.single.customTags;
      expect(tagPlans.single.outcome, CustomTagImportOutcome.skip,
          reason: 'profile has hit max 100 tags');
      expect(plan.summary.customTagsAdded, 0);
      expect(plan.summary.customTagsSkipped, 1);
    });
  });

  group('planImport — day entry merge policy', () {
    test('no existing entry at that date: added verbatim with file-import '
        'provenance', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', flow: 'heavy', tags: ['cramps']),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingEntriesByProfileId: const {_p1: []},
        writeBlockReason: _neverBlocked,
      );

      final entryPlan = plan.profiles.single.entries.single;
      expect(entryPlan.outcome, DayEntryImportOutcome.add);
      expect(entryPlan.flow, FlowLevel.heavy);
      expect(entryPlan.tags, ['cramps']);
    });

    test('a collision unions tags, keeps the heavier flow, and keeps the '
        'existing non-empty note — preserving the existing row\'s own '
        'provenance rather than overwriting it', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05',
              flow: 'light', tags: ['acne'], note: 'from file'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final existing = _entry('local1', _p1, '2026-01-05',
          flow: FlowLevel.heavy,
          tags: ['cramps'],
          note: 'from device',
          source: DayEntrySource.clueImport,
          sourceId: 'clue-1');

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingEntriesByProfileId: {
          _p1: [existing],
        },
        writeBlockReason: _neverBlocked,
      );

      final entryPlan = plan.profiles.single.entries.single;
      expect(entryPlan.outcome, DayEntryImportOutcome.merge);
      expect(entryPlan.flow, FlowLevel.heavy, reason: 'heavier flow wins');
      expect(entryPlan.tags, ['acne', 'cramps'], reason: 'tags are unioned and sorted');
      expect(entryPlan.note, 'from device',
          reason: 'existing non-empty note is kept');
      expect(entryPlan.source, DayEntrySource.clueImport.toDb(),
          reason: 'existing provenance is preserved on merge');
      expect(entryPlan.sourceId, 'clue-1');
      expect(plan.summary.entriesMerged, 1);
      expect(plan.summary.entriesAdded, 0);
    });

    test('a collision with an empty existing note adopts the imported '
        'note', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', note: 'from file'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final existing = _entry('local1', _p1, '2026-01-05', note: null);

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingEntriesByProfileId: {
          _p1: [existing],
        },
        writeBlockReason: _neverBlocked,
      );

      expect(plan.profiles.single.entries.single.note, 'from file');
    });

    test(
        'existingUpdatedAt carries the merge target\'s snapshot; an add '
        'carries none (Issue #140 review, LLA-085)', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
          _rawDayEntry(_e2, '2026-01-06'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final existing = _entry('local1', _p1, '2026-01-05');

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingEntriesByProfileId: {
          _p1: [existing],
        },
        writeBlockReason: _neverBlocked,
      );

      final byDate = {
        for (final e in plan.profiles.single.entries) e.localDate.iso: e,
      };
      expect(byDate['2026-01-05']!.outcome, DayEntryImportOutcome.merge);
      expect(byDate['2026-01-05']!.existingUpdatedAt, existing.updatedAt);
      expect(byDate['2026-01-06']!.outcome, DayEntryImportOutcome.add);
      expect(byDate['2026-01-06']!.existingUpdatedAt, isNull);
    });
  });

  group('planImport — observation dedup', () {
    // Every fixture here carries a day entry for the observation's own
    // date — parseAccountImport now requires it (Issue #140 review, item
    // 9: an observation with no matching day entry is rejected outright).
    test('no existing observation at (date, category, code): added', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          _rawObservation(_o1, '2026-01-05', category: 'pain', code: 'cramps'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingObservationsByProfileId: const {_p1: []},
        writeBlockReason: _neverBlocked,
      );

      expect(plan.profiles.single.observations.single.outcome,
          ObservationImportOutcome.add);
      expect(plan.summary.observationsAdded, 1);
      expect(plan.summary.observationsSkipped, 0);
    });

    test('a colliding (profileId, localDate, category, code) is skipped, '
        'never overwriting the existing row', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          _rawObservation(_o1, '2026-01-05', category: 'pain', code: 'cramps'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final existing = _observation('local-o1', _p1, '2026-01-05',
          category: 'pain', code: 'cramps');

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingObservationsByProfileId: {
          _p1: [existing],
        },
        writeBlockReason: _neverBlocked,
      );

      expect(plan.profiles.single.observations.single.outcome,
          ObservationImportOutcome.skip);
      expect(plan.summary.observationsAdded, 0);
      expect(plan.summary.observationsSkipped, 1);
    });

    test('a different code on the same date is not a collision', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          _rawObservation(_o1, '2026-01-05', category: 'pain', code: 'headache'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final existing = _observation('local-o1', _p1, '2026-01-05',
          category: 'pain', code: 'cramps');

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingObservationsByProfileId: {
          _p1: [existing],
        },
        writeBlockReason: _neverBlocked,
      );

      expect(plan.profiles.single.observations.single.outcome,
          ObservationImportOutcome.add);
    });
  });

  group(
      'planImport — per-day observation cap (Issue #140 review, LLA-091)',
      () {
    /// [n] pre-existing, distinct (by code) live observations on
    /// [isoDate] for [_p1] — enough to probe the [kMaxObservationsPerDay]
    /// boundary without a colliding (date, category, code) key ever
    /// masking the cap decision.
    List<Observation> liveObservations(int n, String isoDate) => [
          for (var i = 0; i < n; i++)
            _observation('local-o$i', _p1, isoDate, code: 'code-$i'),
        ];

    test('199 existing + 1 distinct new: added (right at the cap)', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          _rawObservation(_o1, '2026-01-05', category: 'pain', code: 'new'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingObservationsByProfileId: {
          _p1: liveObservations(kMaxObservationsPerDay - 1, '2026-01-05'),
        },
        writeBlockReason: _neverBlocked,
      );

      expect(plan.profiles.single.observations.single.outcome,
          ObservationImportOutcome.add);
      expect(plan.summary.observationsAdded, 1);
      expect(plan.summary.observationsSkipped, 0);
    });

    test('200 existing + 1 distinct new: skipped (would exceed the cap)', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          _rawObservation(_o1, '2026-01-05', category: 'pain', code: 'new'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingObservationsByProfileId: {
          _p1: liveObservations(kMaxObservationsPerDay, '2026-01-05'),
        },
        writeBlockReason: _neverBlocked,
      );

      expect(plan.profiles.single.observations.single.outcome,
          ObservationImportOutcome.skip);
      expect(plan.summary.observationsAdded, 0);
      expect(plan.summary.observationsSkipped, 1);
    });

    test(
        '200 existing + 1 duplicate new: still skipped for the ordinary '
        'dedup reason, not double-counted against the cap', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          _rawObservation(_o1, '2026-01-05', category: 'pain', code: 'code-0'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingObservationsByProfileId: {
          _p1: liveObservations(kMaxObservationsPerDay, '2026-01-05'),
        },
        writeBlockReason: _neverBlocked,
      );

      expect(plan.profiles.single.observations.single.outcome,
          ObservationImportOutcome.skip);
      expect(plan.summary.observationsSkipped, 1);
    });

    test(
        'two distinct new rows on an already-full day: only the cap gap is '
        'filled, the rest skip against each other within the same document',
        () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05'),
        ], observations: [
          _rawObservation(_o1, '2026-01-05', category: 'pain', code: 'new-1'),
          _rawObservation(_o2, '2026-01-05', category: 'pain', code: 'new-2'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingObservationsByProfileId: {
          _p1: liveObservations(kMaxObservationsPerDay - 1, '2026-01-05'),
        },
        writeBlockReason: _neverBlocked,
      );

      final outcomes =
          plan.profiles.single.observations.map((o) => o.outcome).toList();
      expect(outcomes, [
        ObservationImportOutcome.add,
        ObservationImportOutcome.skip,
      ]);
      expect(plan.summary.observationsAdded, 1);
      expect(plan.summary.observationsSkipped, 1);
    });
  });

  group('planImport — day entry provenance (Issue #140 review, item 7)', () {
    test('an entry with its own file provenance round-trips as-is on add',
        () {
      final raw = _rawDayEntry(_e1, '2026-01-05')
        ..['source'] = 'clue_import'
        ..['sourceId'] = 'abc';
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [raw]),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: const [],
        writeBlockReason: _neverBlocked,
      );

      final entryPlan = plan.profiles.single.entries.single;
      expect(entryPlan.source, 'clue_import');
      expect(entryPlan.sourceId, 'abc');
    });

    test('an entry lacking provenance (manual/null) falls back to '
        'file_import/<entry id>', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [_rawDayEntry(_e1, '2026-01-05')]),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: const [],
        writeBlockReason: _neverBlocked,
      );

      final entryPlan = plan.profiles.single.entries.single;
      expect(entryPlan.source, DayEntrySource.fileImport.toDb());
      expect(entryPlan.sourceId, _e1);
    });
  });

  group('planImport — report honesty (Issue #140 review, item 9)', () {
    test('a merge that drops a non-empty file note counts as '
        'notesDiscarded', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', note: 'from file'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final existing = _entry('local1', _p1, '2026-01-05', note: 'from device');

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingEntriesByProfileId: {
          _p1: [existing],
        },
        writeBlockReason: _neverBlocked,
      );

      expect(plan.profiles.single.entries.single.noteDiscarded, isTrue);
      expect(plan.summary.notesDiscarded, 1);
    });

    test('a merge that adopts the file note (existing was empty) does not '
        'count as notesDiscarded', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [
          _rawDayEntry(_e1, '2026-01-05', note: 'from file'),
        ]),
      ]))) as AccountImportParsed)
          .document;

      final existing = _entry('local1', _p1, '2026-01-05', note: null);

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        existingEntriesByProfileId: {
          _p1: [existing],
        },
        writeBlockReason: _neverBlocked,
      );

      expect(plan.profiles.single.entries.single.noteDiscarded, isFalse);
      expect(plan.summary.notesDiscarded, 0);
    });
  });

  group('planImport — shared-guardian disclosure (Issue #140 review, item '
      '10)', () {
    test('sharesWithOtherGuardians is true when a matched profile has an '
        'accepted guardian other than the caller', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        writeBlockReason: _neverBlocked,
        hasOtherGuardians: (p) => true,
      );

      expect(plan.sharesWithOtherGuardians, isTrue);
    });

    test('sharesWithOtherGuardians is false by default (no guardian info '
        'supplied)', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: [_profile(_p1)],
        writeBlockReason: _neverBlocked,
      );

      expect(plan.sharesWithOtherGuardians, isFalse);
    });

    test('sharesWithOtherGuardians is false for a created (not matched) '
        'profile even if hasOtherGuardians would say otherwise', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: const [],
        writeBlockReason: _neverBlocked,
        hasOtherGuardians: (p) => true,
      );

      expect(plan.sharesWithOtherGuardians, isFalse);
    });
  });

  group('planImport — tombstoned profile revival (Issue #140 review round '
      '2, item 6)', () {
    test('a file id matching a tombstoned (not live) local profile plans '
        'as matched + restoredFromTombstone, not created', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1, dayEntries: [_rawDayEntry(_e1, '2026-01-05')]),
      ]))) as AccountImportParsed)
          .document;

      final tombstoned = _profile(_p1);
      final plan = planImport(
        document: document,
        existingProfiles: const [],
        tombstonedProfilesById: {_p1: tombstoned},
        writeBlockReason: _neverBlocked,
      );

      final profilePlan = plan.profiles.single;
      expect(profilePlan.outcome, ProfileImportOutcome.matched);
      expect(profilePlan.restoredFromTombstone, isTrue);
      expect(profilePlan.entries.single.outcome, DayEntryImportOutcome.add);
      expect(plan.summary.profilesMatched, 1);
      expect(plan.summary.profilesCreated, 0);
      expect(plan.summary.profilesRestored, 1);
    });

    test('the write-block check still runs against the tombstoned '
        'profile\'s own stored state', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1),
      ]))) as AccountImportParsed)
          .document;

      final archivedTombstone =
          _profile(_p1, archivedAt: DateTime.utc(2026, 1, 1));
      final plan = planImport(
        document: document,
        existingProfiles: const [],
        tombstonedProfilesById: {_p1: archivedTombstone},
        writeBlockReason: (p) => writeBlockReasonFor(profile: p),
      );

      final profilePlan = plan.profiles.single;
      expect(profilePlan.outcome, ProfileImportOutcome.skipped);
      expect(profilePlan.skipReason, isNotNull);
    });

    test('a live match wins over a same-id tombstone entry, if both were '
        'somehow supplied', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1),
      ]))) as AccountImportParsed)
          .document;

      final live = _profile(_p1);
      final plan = planImport(
        document: document,
        existingProfiles: [live],
        tombstonedProfilesById: {_p1: _profile(_p1, archivedAt: DateTime.utc(2026, 1, 1))},
        writeBlockReason: _neverBlocked,
      );

      final profilePlan = plan.profiles.single;
      expect(profilePlan.outcome, ProfileImportOutcome.matched);
      expect(profilePlan.restoredFromTombstone, isFalse);
    });

    test('an id absent from both live profiles and tombstonedProfilesById '
        'still plans as an ordinary create', () {
      final document = (parseAccountImport(_bytes(_rawDocument(profiles: [
        _rawProfile(_p1),
      ]))) as AccountImportParsed)
          .document;

      final plan = planImport(
        document: document,
        existingProfiles: const [],
        writeBlockReason: _neverBlocked,
      );

      final profilePlan = plan.profiles.single;
      expect(profilePlan.outcome, ProfileImportOutcome.created);
      expect(profilePlan.restoredFromTombstone, isFalse);
      expect(plan.summary.profilesRestored, 0);
    });
  });
}
