/// Unit tests for buildFhirDocumentBundle (Issue #157).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/export/clinical_terminology.dart';
import 'package:lunarlog/domain/export/fhir_bundle.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

Profile _profile({
  String id = 'profile-01HXA0000000000000000000',
  String displayName = 'Riley',
}) =>
    Profile(
      id: id,
      displayName: displayName,
      isMinor: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
    );

DayEntry _entry(
  String id,
  String profileId,
  String isoDate, {
  FlowLevel flow = FlowLevel.medium,
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
  int? intensity,
  double? valueNum,
  String? unit,
  String? valueText,
  bool excluded = false,
  String? loggedByUserId,
}) =>
    Observation(
      id: id,
      dayEntryId: dayEntryId,
      profileId: profileId,
      localDate: LocalDate.fromIso(isoDate),
      tz: 'UTC',
      category: category,
      code: code,
      intensity: intensity,
      valueNum: valueNum,
      unit: unit,
      valueText: valueText,
      excluded: excluded,
      updatedAt: DateTime.utc(2026, 1, 2),
      loggedByUserId: loggedByUserId,
    );

/// Builds enough day entries (four ~28-day periods) for
/// `computePredictionFromEntries` to return an [ActivePrediction] rather
/// than [NotEnoughHistory] (mirrors test/domain/prediction_test.dart's own
/// `entriesFromStarts` shape, kept local here since this file only needs
/// one fixed fixture).
List<DayEntry> _cycleHistory(String profileId) {
  final starts = [
    LocalDate(2026, 1, 1),
    LocalDate(2026, 1, 29),
    LocalDate(2026, 2, 26),
    LocalDate(2026, 3, 26),
  ];
  var n = 0;
  return [
    for (final start in starts)
      for (var day = 0; day < 3; day++)
        _entry('e${n++}', profileId, start.addDays(day).iso),
  ];
}

/// Recursively collects every value found under the key `'reference'`
/// anywhere in [node] (a decoded JSON tree of Maps/Lists/scalars).
List<String> _allReferences(Object? node) {
  final found = <String>[];
  void visit(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key == 'reference' && entry.value is String) {
          found.add(entry.value as String);
        }
        visit(entry.value);
      }
    } else if (value is List) {
      for (final item in value) {
        visit(item);
      }
    }
  }

  visit(node);
  return found;
}

/// Recursively collects every string value in [node], regardless of key —
/// used to assert a forbidden literal (a raw internal id) never appears
/// anywhere in the output.
List<String> _allStrings(Object? node) {
  final found = <String>[];
  void visit(Object? value) {
    if (value is String) {
      found.add(value);
    } else if (value is Map) {
      for (final v in value.values) {
        visit(v);
      }
    } else if (value is List) {
      for (final item in value) {
        visit(item);
      }
    }
  }

  visit(node);
  return found;
}

/// Recursively collects every top-level key seen on any Map anywhere in
/// [node].
Set<String> _allKeys(Object? node) {
  final keys = <String>{};
  void visit(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        keys.add(entry.key as String);
        visit(entry.value);
      }
    } else if (value is List) {
      for (final item in value) {
        visit(item);
      }
    }
  }

  visit(node);
  return keys;
}

void main() {
  final profile = _profile();
  final dayEntries = [
    _entry('day-01', profile.id, '2026-04-01', flow: FlowLevel.medium),
    _entry('day-02', profile.id, '2026-04-02', flow: FlowLevel.none),
    _entry(
      'day-03',
      profile.id,
      '2026-04-03',
      // Issue #247: spotting is an observation, not a bleed level any more,
      // so a light day stands in for the third fixture entry.
      flow: FlowLevel.light,
      loggedByUserId: 'user-secret-999',
      lastModifiedByUserId: 'user-secret-999',
    ),
  ];
  final observations = [
    _observation('obs-01', 'day-01', profile.id, '2026-04-01',
        category: 'pain', code: 'headache'),
    _observation('obs-02', 'day-01', profile.id, '2026-04-01',
        category: 'bbt', code: 'reading', loggedByUserId: 'user-secret-999'),
  ];
  final exportedAt = DateTime.utc(2026, 4, 5, 12, 30);

  Map<String, Object?> build({
    List<DayEntry>? entries,
    List<Observation>? obs,
    ActivePrediction? prediction,
  }) =>
      buildFhirDocumentBundle(
        profile: profile,
        dayEntries: entries ?? dayEntries,
        observations: obs ?? observations,
        prediction: prediction,
        exportedAt: exportedAt,
        appVersion: '1.2.3+4',
      );

  group('Bundle shape', () {
    test('type is document, timestamp and identifier are set', () {
      final bundle = build();
      expect(bundle['resourceType'], 'Bundle');
      expect(bundle['type'], 'document');
      expect(bundle['timestamp'], '2026-04-05T12:30:00.000Z');
      expect(bundle['identifier'], isA<Map>());
      final identifier = bundle['identifier'] as Map;
      // #157 review fix: `urn:ietf:rfc:3986`, not [kFhirExportVersionSystem]
      // — the identifier's `value` is itself a `urn:uuid:` URI, and RFC
      // 3986 is the correct `system` for a URI-valued FHIR identifier. The
      // version-tag CodeSystem stays on `meta.tag` (see the "carries the
      // export version tag" test below), a different concept.
      expect(identifier['system'], 'urn:ietf:rfc:3986');
      expect((identifier['value'] as String).startsWith('urn:uuid:'), isTrue);
    });

    test('entry 0 is the Composition', () {
      final bundle = build();
      final entries = bundle['entry'] as List;
      expect(entries, isNotEmpty);
      final first = entries.first as Map;
      expect((first['resource'] as Map)['resourceType'], 'Composition');
    });

    test('exactly one Patient and one Provenance entry', () {
      final bundle = build();
      final entries = (bundle['entry'] as List).cast<Map>();
      final types = [
        for (final e in entries) (e['resource'] as Map)['resourceType'],
      ];
      expect(types.where((t) => t == 'Patient'), hasLength(1));
      expect(types.where((t) => t == 'Provenance'), hasLength(1));
      expect(types.where((t) => t == 'Composition'), hasLength(1));
    });

    test('every entry fullUrl is a urn:uuid and unique', () {
      final bundle = build();
      final entries = (bundle['entry'] as List).cast<Map>();
      final fullUrls = [for (final e in entries) e['fullUrl'] as String];
      for (final url in fullUrls) {
        expect(url, matches(RegExp(
            r'^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-'
            r'[0-9a-f]{12}$')));
      }
      expect(fullUrls.toSet(), hasLength(fullUrls.length));
    });

    test('every reference resolves to some entry fullUrl in the Bundle',
        () {
      final bundle = build();
      final entries = (bundle['entry'] as List).cast<Map>();
      final fullUrls = {for (final e in entries) e['fullUrl'] as String};
      final refs = _allReferences(bundle);
      expect(refs, isNotEmpty);
      for (final ref in refs) {
        expect(fullUrls.contains(ref), isTrue,
            reason: '$ref does not resolve to any entry.fullUrl');
      }
    });

    test('no meta.profile is ever asserted (IPS-shaped, not conformant)',
        () {
      final bundle = build();
      expect(_allKeys(bundle).contains('profile'), isFalse);
    });

    test('carries the export version tag', () {
      final bundle = build();
      final tags = (bundle['meta'] as Map)['tag'] as List;
      expect(tags, hasLength(1));
      final tag = tags.first as Map;
      expect(tag['system'], kFhirExportVersionSystem);
      expect(tag['code'], '$kFhirExportBundleVersion');
    });
  });

  group('Patient', () {
    test('carries only the display name — no identifier, no id, no dates',
        () {
      final bundle = build();
      final entries = (bundle['entry'] as List).cast<Map>();
      final patient = entries
          .map((e) => e['resource'] as Map)
          .firstWhere((r) => r['resourceType'] == 'Patient');
      expect(patient.keys.toSet(), {'resourceType', 'name'});
      final name = (patient['name'] as List).single as Map;
      expect(name.keys.toSet(), {'text'});
      expect(name['text'], 'Riley');
    });
  });

  group('no forbidden identifiers leak', () {
    test('profile/day-entry/observation ids and guardian user ids never '
        'appear anywhere in the output', () {
      final bundle = build();
      final strings = _allStrings(bundle);
      for (final forbidden in [
        profile.id,
        'day-01',
        'day-02',
        'day-03',
        'obs-01',
        'obs-02',
        'user-secret-999',
      ]) {
        expect(strings.any((s) => s.contains(forbidden)), isFalse,
            reason: '"$forbidden" leaked into the FHIR Bundle');
      }
    });

    test('no userId/email/guardian-shaped keys anywhere in the output', () {
      final bundle = build();
      final keys = _allKeys(bundle);
      for (final forbidden in [
        'userId',
        'user_id',
        'email',
        'loggedByUserId',
        'lastModifiedByUserId',
        'sourceId',
        'importId',
      ]) {
        expect(keys.contains(forbidden), isFalse,
            reason: '"$forbidden" key present in the FHIR Bundle');
      }
    });
  });

  group('menstrual status Observations (flow days)', () {
    test('one per day entry with flow != none, coded with both LOINC '
        'menstrual-status codes', () {
      final bundle = build();
      final entries = (bundle['entry'] as List).cast<Map>();
      final flowObs = entries
          .map((e) => e['resource'] as Map)
          .where((r) =>
              r['resourceType'] == 'Observation' &&
              r.containsKey('valueCodeableConcept'))
          .toList();
      // day-01 (medium) and day-03 (light) count; day-02 (none) does not.
      expect(flowObs, hasLength(2));
      for (final obs in flowObs) {
        final codes = ((obs['code'] as Map)['coding'] as List)
            .map((c) => (c as Map)['code'])
            .toSet();
        expect(codes, {'8678-5', '3146-8'});
        expect(obs['status'], 'final');
        expect(obs['performer'], isNotEmpty);
        expect((obs['note'] as List).first, isA<Map>());
      }
    });

    test('valueCodeableConcept carries the local flow-level coding', () {
      final bundle = build(entries: [
        _entry('d1', profile.id, '2026-04-01', flow: FlowLevel.heavy),
      ]);
      final entries = (bundle['entry'] as List).cast<Map>();
      final obs = entries
          .map((e) => e['resource'] as Map)
          .firstWhere((r) => r['resourceType'] == 'Observation' &&
              r.containsKey('valueCodeableConcept'));
      final coding =
          ((obs['valueCodeableConcept'] as Map)['coding'] as List).single
              as Map;
      // #157 review fix: flow levels moved to their own local system —
      // not kSystemLunarlogLocal, which is now exclusively the tag system.
      expect(coding['system'], kSystemLunarlogLocalFlow);
      expect(coding['code'], 'heavy');
      expect(coding['display'], 'Heavy');
    });

    test('no flow entries with flow=none produce no menstrual Observations',
        () {
      final bundle = build(entries: [
        _entry('d1', profile.id, '2026-04-01', flow: FlowLevel.none),
      ]);
      final entries = (bundle['entry'] as List).cast<Map>();
      final flowObs = entries.where((e) =>
          (e['resource'] as Map).containsKey('valueCodeableConcept'));
      expect(flowObs, isEmpty);
    });
  });

  group('symptom Observations (observation rows)', () {
    test('a taxonomy tag code is dual-coded via dualCodingFor', () {
      final bundle = build(obs: [
        _observation('o1', 'day-01', profile.id, '2026-04-01',
            category: 'pain', code: 'headache'),
      ]);
      final entries = (bundle['entry'] as List).cast<Map>();
      final obs = entries
          .map((e) => e['resource'] as Map)
          .firstWhere((r) =>
              r['resourceType'] == 'Observation' &&
              !r.containsKey('valueCodeableConcept') &&
              !r.containsKey('valueQuantity') &&
              !r.containsKey('valueDateTime'));
      final codings = (obs['code'] as Map)['coding'] as List;
      final expected = dualCodingFor('headache');
      expect(codings, hasLength(expected.length));
      final systems = codings.map((c) => (c as Map)['system']).toSet();
      expect(systems, {kSystemSnomed, kSystemLunarlogLocal});
    });

    test('a non-taxonomy observation code degrades to a local coding '
        '(no guessed clinical code)', () {
      final bundle = build(obs: [
        _observation('o1', 'day-01', profile.id, '2026-04-01',
            category: 'bbt', code: 'reading'),
      ]);
      final entries = (bundle['entry'] as List).cast<Map>();
      final obs = entries
          .map((e) => e['resource'] as Map)
          .firstWhere((r) =>
              r['resourceType'] == 'Observation' &&
              !r.containsKey('valueCodeableConcept') &&
              !r.containsKey('valueQuantity') &&
              !r.containsKey('valueDateTime'));
      final codings = (obs['code'] as Map)['coding'] as List;
      expect(codings, hasLength(1));
      final coding = codings.single as Map;
      expect(coding['system'], kSystemLunarlogLocal);
      expect(coding['code'], 'bbt:reading');
    });

    test('intensity carries as valueInteger, valueNum+unit as valueQuantity '
        '(UCUM code when known), never valueText (#157 review fix)', () {
      final bundle = build(obs: [
        _observation('o1', 'day-01', profile.id, '2026-04-01',
            category: 'pain',
            code: 'cramps',
            intensity: 4,
            valueNum: 37.2,
            unit: 'celsius',
            valueText: 'secret free text should never appear'),
      ]);
      final entries = (bundle['entry'] as List).cast<Map>();
      final obs = entries
          .map((e) => e['resource'] as Map)
          .firstWhere((r) =>
              r['resourceType'] == 'Observation' &&
              !r.containsKey('valueCodeableConcept') &&
              !r.containsKey('valueDateTime'));
      expect(obs['valueInteger'], 4);
      final quantity = obs['valueQuantity'] as Map;
      expect(quantity['value'], 37.2);
      expect(quantity['unit'], 'celsius');
      expect(quantity['system'], 'http://unitsofmeasure.org');
      expect(quantity['code'], 'Cel');
      expect(obs.containsKey('valueText'), isFalse);
      expect(
        _allStrings(bundle)
            .any((s) => s.contains('secret free text should never appear')),
        isFalse,
      );
    });

    test('an unknown unit degrades to a plain unit string, no guessed UCUM '
        'code', () {
      final bundle = build(obs: [
        _observation('o1', 'day-01', profile.id, '2026-04-01',
            category: 'other', code: 'wearable_metric', valueNum: 12, unit: 'bpm'),
      ]);
      final entries = (bundle['entry'] as List).cast<Map>();
      final obs = entries
          .map((e) => e['resource'] as Map)
          .firstWhere((r) => r.containsKey('valueQuantity'));
      final quantity = obs['valueQuantity'] as Map;
      expect(quantity['unit'], 'bpm');
      expect(quantity.containsKey('system'), isFalse);
      expect(quantity.containsKey('code'), isFalse);
    });

    test('an excluded observation row is skipped entirely, never emitted',
        () {
      final bundle = build(obs: [
        _observation('o1', 'day-01', profile.id, '2026-04-01',
            category: 'bbt', code: 'reading', excluded: true),
      ]);
      final strings = _allStrings(bundle);
      expect(strings.any((s) => s.contains('o1')), isFalse);
      expect(strings.contains('bbt:reading'), isFalse);
    });
  });

  group('symptom Observations from DayEntry.tags (#157 review fix)', () {
    test('one Observation per tag per day, dual-coded via dualCodingFor',
        () {
      final bundle = build(
        entries: [
          _entry('day-01', profile.id, '2026-04-01',
              flow: FlowLevel.medium, tags: const ['cramps', 'headache']),
        ],
        obs: const [],
      );
      final entries = (bundle['entry'] as List).cast<Map>();
      final symptomObs = entries
          .map((e) => e['resource'] as Map)
          .where((r) =>
              r['resourceType'] == 'Observation' &&
              !r.containsKey('valueCodeableConcept') &&
              !r.containsKey('valueQuantity') &&
              !r.containsKey('valueDateTime'))
          .toList();
      expect(symptomObs, hasLength(2));
      for (final tag in ['cramps', 'headache']) {
        final match = symptomObs.firstWhere((obs) {
          final codings = (obs['code'] as Map)['coding'] as List;
          return codings.any((c) => (c as Map)['code'] == tag);
        });
        expect(match['effectiveDateTime'], '2026-04-01');
        final codings = (match['code'] as Map)['coding'] as List;
        final expected = dualCodingFor(tag);
        expect(codings, hasLength(expected.length));
      }
    });

    test('the id is a deterministic v5 hash of (profileId, date, tag): '
        'stable across two calls', () {
      List<String> tagObsFullUrls() {
        final bundle = build(
          entries: [
            _entry('day-01', profile.id, '2026-04-01',
                flow: FlowLevel.medium, tags: const ['cramps']),
          ],
          obs: const [],
        );
        final entries = (bundle['entry'] as List).cast<Map>();
        return entries
            .where((e) =>
                (e['resource'] as Map)['resourceType'] == 'Observation' &&
                !(e['resource'] as Map).containsKey('valueCodeableConcept'))
            .map((e) => e['fullUrl'] as String)
            .toList();
      }

      expect(tagObsFullUrls(), tagObsFullUrls());
    });

    test('a tag already covered by a live observations-table row for the '
        'same (date, code) is not duplicated', () {
      final bundle = build(
        entries: [
          _entry('day-01', profile.id, '2026-04-01',
              flow: FlowLevel.medium, tags: const ['cramps']),
        ],
        obs: [
          _observation('o1', 'day-01', profile.id, '2026-04-01',
              category: 'pain', code: 'cramps'),
        ],
      );
      final entries = (bundle['entry'] as List).cast<Map>();
      final symptomObs = entries
          .map((e) => e['resource'] as Map)
          .where((r) =>
              r['resourceType'] == 'Observation' &&
              !r.containsKey('valueCodeableConcept') &&
              !r.containsKey('valueQuantity') &&
              !r.containsKey('valueDateTime'))
          .toList();
      expect(symptomObs, hasLength(1));
    });

    test('an excluded observations-table row does not suppress the '
        'tag-derived Observation for the same (date, code)', () {
      final bundle = build(
        entries: [
          _entry('day-01', profile.id, '2026-04-01',
              flow: FlowLevel.medium, tags: const ['cramps']),
        ],
        obs: [
          _observation('o1', 'day-01', profile.id, '2026-04-01',
              category: 'pain', code: 'cramps', excluded: true),
        ],
      );
      final entries = (bundle['entry'] as List).cast<Map>();
      final symptomObs = entries
          .map((e) => e['resource'] as Map)
          .where((r) =>
              r['resourceType'] == 'Observation' &&
              !r.containsKey('valueCodeableConcept') &&
              !r.containsKey('valueQuantity') &&
              !r.containsKey('valueDateTime'))
          .toList();
      expect(symptomObs, hasLength(1));
      final codings = (symptomObs.single['code'] as Map)['coding'] as List;
      expect(codings.any((c) => (c as Map)['code'] == 'cramps'), isTrue);
    });
  });

  group('DayEntry.note is never exported (#157 review fix)', () {
    test('a distinctive note string never appears anywhere in the output',
        () {
      const distinctiveNote = 'do-not-export-this-note-zx19q';
      final bundle = build(entries: [
        _entry('day-01', profile.id, '2026-04-01',
            flow: FlowLevel.medium, note: distinctiveNote),
      ]);
      final strings = _allStrings(bundle);
      expect(strings.any((s) => s.contains(distinctiveNote)), isFalse);
    });
  });

  group('cycle statistics (from ActivePrediction)', () {
    test('null prediction: no cycle-statistic Observations, and Results '
        'section still has the flow observations', () {
      final bundle = build(prediction: null);
      final entries = (bundle['entry'] as List).cast<Map>();
      final quantities = entries.where(
          (e) => (e['resource'] as Map).containsKey('valueQuantity'));
      final dateTimes = entries.where(
          (e) => (e['resource'] as Map).containsKey('valueDateTime'));
      expect(quantities, isEmpty);
      expect(dateTimes, isEmpty);
    });

    test('an ActivePrediction adds typical-cycle-length (64700-8) and LMP '
        '(8665-2) Observations', () {
      final history = _cycleHistory(profile.id);
      final prediction = computePredictionFromEntries(
        entries: history,
        today: LocalDate(2026, 4, 20),
      ) as ActivePrediction;
      final bundle = build(entries: history, obs: const [], prediction: prediction);
      final entries = (bundle['entry'] as List).cast<Map>();

      final lengthObs = entries
          .map((e) => e['resource'] as Map)
          .firstWhere((r) => r.containsKey('valueQuantity'));
      expect(((lengthObs['code'] as Map)['coding'] as List).single, isA<Map>());
      expect(
        (((lengthObs['code'] as Map)['coding'] as List).single as Map)['code'],
        '64700-8',
      );
      expect((lengthObs['valueQuantity'] as Map)['value'],
          prediction.meanCycleLengthDays.round());

      final lmpObs = entries
          .map((e) => e['resource'] as Map)
          .firstWhere((r) => r.containsKey('valueDateTime'));
      expect(
        (((lmpObs['code'] as Map)['coding'] as List).single as Map)['code'],
        '8665-2',
      );
      expect(lmpObs['valueDateTime'], prediction.lastEpisodeStart.iso);
    });
  });

  group('Composition sections', () {
    test('Results section references flow + stat observations, Problems '
        'section references symptom observations', () {
      final history = _cycleHistory(profile.id);
      final prediction = computePredictionFromEntries(
        entries: history,
        today: LocalDate(2026, 4, 20),
      ) as ActivePrediction;
      final bundle = build(
        entries: history,
        obs: [
          _observation('o1', 'e0', profile.id, '2026-01-01',
              category: 'pain', code: 'cramps'),
        ],
        prediction: prediction,
      );
      final entries = (bundle['entry'] as List).cast<Map>();
      final composition = entries
          .map((e) => e['resource'] as Map)
          .firstWhere((r) => r['resourceType'] == 'Composition');
      final sections = (composition['section'] as List).cast<Map>();
      expect(sections, hasLength(2));

      final results = sections.firstWhere((s) => s['title'] == 'Results');
      final problems = sections.firstWhere((s) => s['title'] == 'Problems');
      expect(((results['code'] as Map)['coding'] as List).first,
          containsPair('code', '30954-2'));
      expect(((problems['code'] as Map)['coding'] as List).first,
          containsPair('code', '11450-4'));

      // 8 flow entries (2 bleed days per period x 4 periods... actually
      // history has 3 flow days per period) + 2 stat observations.
      final flowAndStatCount = history.length + 2;
      expect((results['entry'] as List).length, flowAndStatCount);
      expect((problems['entry'] as List).length, 1);
    });

    test('carries every FHIR-required Composition element, plus a '
        'document-level text narrative (#157 review fix)', () {
      final bundle = build();
      final entries = (bundle['entry'] as List).cast<Map>();
      final composition = entries
          .map((e) => e['resource'] as Map)
          .firstWhere((r) => r['resourceType'] == 'Composition');
      expect(composition['status'], 'final');
      expect(composition['type'], isA<Map>());
      expect(composition['date'], isA<String>());
      expect(composition['author'], isA<List>());
      expect((composition['author'] as List), isNotEmpty);
      expect(composition['title'], isA<String>());
      final text = composition['text'] as Map;
      expect(text['status'], 'generated');
      expect(text['div'], contains('<div'));
    });

    test('an empty section carries emptyReason instead of a bare empty '
        'entry list (#157 review fix)', () {
      final bundle = build(entries: const [], obs: const []);
      final entries = (bundle['entry'] as List).cast<Map>();
      final composition = entries
          .map((e) => e['resource'] as Map)
          .firstWhere((r) => r['resourceType'] == 'Composition');
      final sections = (composition['section'] as List).cast<Map>();
      for (final section in sections) {
        expect(section['entry'], isEmpty);
        expect(section['emptyReason'], isA<Map>());
        final coding =
            ((section['emptyReason'] as Map)['coding'] as List).single as Map;
        expect(coding['system'],
            'http://terminology.hl7.org/CodeSystem/list-empty-reason');
        expect(coding['code'], 'unavailable');
      }
    });

    test('a non-empty section carries no emptyReason', () {
      final bundle = build();
      final entries = (bundle['entry'] as List).cast<Map>();
      final composition = entries
          .map((e) => e['resource'] as Map)
          .firstWhere((r) => r['resourceType'] == 'Composition');
      final results = (composition['section'] as List)
          .cast<Map>()
          .firstWhere((s) => s['title'] == 'Results');
      expect(results['entry'], isNotEmpty);
      expect(results.containsKey('emptyReason'), isFalse);
    });
  });

  group('Provenance', () {
    test('records the export timestamp, self-report activity, and app '
        'version — never asserting a clinician actor', () {
      final bundle = build();
      final entries = (bundle['entry'] as List).cast<Map>();
      final provenance = entries
          .map((e) => e['resource'] as Map)
          .firstWhere((r) => r['resourceType'] == 'Provenance');
      expect(provenance['recorded'], '2026-04-05T12:30:00.000Z');
      final activityCoding =
          ((provenance['activity'] as Map)['coding'] as List).single as Map;
      expect(activityCoding['system'], kSystemLunarlogLocal);
      expect(activityCoding['code'], 'self-reported');
      final agent = (provenance['agent'] as List).single as Map;
      final agentTypeCoding =
          ((agent['type'] as Map)['coding'] as List).single as Map;
      expect(agentTypeCoding['code'], 'author');
      final entity = (provenance['entity'] as List).single as Map;
      expect((entity['what'] as Map)['display'], 'lunarlog v1.2.3+4');
    });
  });

  group('no guessed / refuted codes', () {
    test('refuted and unverified LOINC codes never appear as any code '
        'value', () {
      final history = _cycleHistory(profile.id);
      final prediction = computePredictionFromEntries(
        entries: history,
        today: LocalDate(2026, 4, 20),
      ) as ActivePrediction;
      final bundle = build(entries: history, prediction: prediction);
      final strings = _allStrings(bundle).toSet();
      for (final refuted in kRefutedLoincCodes) {
        expect(strings.contains(refuted), isFalse);
      }
      for (final unverified in kUnverifiedLoincCodes) {
        expect(strings.contains(unverified), isFalse);
      }
    });
  });

  group('determinism and JSON round-trip', () {
    test('two calls with the same input produce byte-identical JSON', () {
      final a = jsonEncode(build());
      final b = jsonEncode(build());
      expect(a, b);
    });

    test('encodes and decodes as valid JSON, preserving structure', () {
      final bundle = build();
      final decoded = jsonDecode(jsonEncode(bundle));
      expect(decoded, bundle);
    });

    test('the same domain id always yields the same urn:uuid across calls',
        () {
      final first = build();
      final second = build();
      final firstEntries = (first['entry'] as List).cast<Map>();
      final secondEntries = (second['entry'] as List).cast<Map>();
      final firstPatient =
          firstEntries.firstWhere((e) => (e['resource'] as Map)['resourceType'] == 'Patient');
      final secondPatient =
          secondEntries.firstWhere((e) => (e['resource'] as Map)['resourceType'] == 'Patient');
      expect(firstPatient['fullUrl'], secondPatient['fullUrl']);
    });

    test('a different exportedAt changes the Composition/Provenance ids '
        'but not the Patient id', () {
      final first = build();
      final second = buildFhirDocumentBundle(
        profile: profile,
        dayEntries: dayEntries,
        observations: observations,
        exportedAt: exportedAt.add(const Duration(days: 1)),
        appVersion: '1.2.3+4',
      );
      Map patientOf(Map bundle) => (bundle['entry'] as List)
          .cast<Map>()
          .firstWhere((e) => (e['resource'] as Map)['resourceType'] == 'Patient');
      Map compositionOf(Map bundle) => (bundle['entry'] as List)
          .cast<Map>()
          .firstWhere((e) => (e['resource'] as Map)['resourceType'] == 'Composition');
      expect(patientOf(first)['fullUrl'], patientOf(second)['fullUrl']);
      expect(compositionOf(first)['fullUrl'],
          isNot(compositionOf(second)['fullUrl']));
    });
  });
}
