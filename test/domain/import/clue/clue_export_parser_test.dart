/// Unit tests for the Clue `measurements.json` parser (Issue #190):
/// category/option mapping table coverage, both date formats, every `bbt`
/// value-key variant, the four negative assertions, the escape hatch for
/// an unrecognised `type`/`value` shape, and malformed rows that skip
/// rather than abort the whole parse. Fixtures are hand-built under
/// `test/fixtures/clue/` (no real Clue export exists or may be committed —
/// see `docs/import/clue-mapping.md`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/import/clue/clue_datapoint.dart';
import 'package:lunarlog/domain/import/clue/clue_export_parser.dart';
import 'package:lunarlog/domain/models/local_date.dart';

List<int> _fixtureBytes(String name) =>
    File('test/fixtures/clue/$name').readAsBytesSync();

LocalDate _d(String iso) => LocalDate.fromIso(iso);

void main() {
  group('mapping table (every attested/medium-confidence type)', () {
    late ClueExportParseResult result;

    setUp(() {
      result = parseClueDatapoints(_fixtureBytes('mapping_table.json'));
    });

    test('no rows are skipped', () {
      expect(result.skipped, isEmpty);
    });

    test('produces one datapoint per selected option', () {
      // 30 fixture rows; the partying row is multi-select with two
      // options, so 31 datapoints total.
      expect(result.datapoints, hasLength(31));
    });

    test('period maps to a flow level, not an observation', () {
      final dp = result.datapoints[0] as CluePeriodDatapoint;
      expect(dp.date, _d('2026-01-01'));
      expect(dp.level, ClueFlowLevel.light);
    });

    test('bbt maps to a numeric datapoint', () {
      final dp = result.datapoints[9] as ClueNumericDatapoint;
      expect(dp.date, _d('2026-01-10'));
      expect(dp.category, 'bbt');
      expect(dp.valueNum, 36.6);
      expect(dp.unit, 'celsius');
      expect(dp.excluded, isFalse);
    });

    // (clueType, category, expected code) for every remaining row, in
    // fixture order (index 1 and 9 — spotting comes right after period,
    // bbt is handled above — are covered by the two tests above and
    // skipped here via the index offsets below).
    const expectedObservations = [
      (1, 'spotting', 'spotting', 'light'),
      (2, 'pain', 'pain', 'cramps'), // period_cramps -> cramps
      (3, 'feelings', 'feelings', 'happy'),
      (4, 'sex_life', 'sex_life', 'withdrawal'),
      (5, 'energy', 'energy', 'tired'), // fatigue -> tired (issue #249)
      (6, 'pms', 'pms', 'irritability'),
      (7, 'digestion', 'digestion', 'bloating'), // bloated -> bloating
      (8, 'discharge', 'discharge', 'creamy'),
      (10, 'collection_method', 'collection_method', 'tampon'),
      (11, 'social_life', 'social_life', 'sociable'),
      (12, 'craving', 'craving', 'chocolate'),
      (13, 'mind', 'mind', 'calm'),
      (14, 'motivation', 'motivation', 'motivated'),
      (15, 'sleep', 'sleep', '6_to_9_hours'),
      (16, 'exercise', 'exercise', 'yoga'),
      (17, 'stool', 'stool', 'normal'),
      (18, 'leisure', 'leisure', 'reading'),
      (19, 'hair', 'hair', 'good'),
      (20, 'skin', 'skin', 'acne'),
      (21, 'medication', 'medication', 'antihistamine'),
      (22, 'appointments', 'appointments', 'doctor_appt'),
      // Issue #252: `cold_flu` renames onto the category-qualified
      // ailments code (the option is attested under both medication and
      // ailments; the flat tag namespace qualifies each instance).
      (23, 'ailments', 'ailments', 'cold_flu_ailments'),
      (24, 'tags', 'tags', 'My Vacation Trip!'),
      (25, 'birth_control', 'birth_control', 'pill'),
      (26, 'mucus', 'mucus', 'egg_white'),
      (27, 'tests', 'tests', 'negative'),
      // Issue #251's additions: meditation passes through; partying's
      // multi-select row yields one datapoint per option, with the
      // attested "big night" (two words in the export) remapped to the
      // snake_case tag-namespace code.
      (28, 'meditation', 'meditation', 'meditated_10_min'),
      (29, 'partying', 'partying', 'drinks'),
      (30, 'partying', 'partying', 'big_night'),
    ];

    for (final (index, clueType, category, code) in expectedObservations) {
      test('row $index ($clueType) maps to category=$category code=$code', () {
        final dp = result.datapoints[index] as ClueObservationDatapoint;
        expect(dp.clueType, clueType);
        expect(dp.category, category);
        expect(dp.code, code);
        expect(dp.isNegativeAssertion, isFalse);
      });
    }

    test('tags free text is never normalised', () {
      final dp = result.datapoints[24] as ClueObservationDatapoint;
      expect(dp.code, 'My Vacation Trip!');
    });

    test('issue #249 mapping table on synthetic Clue-shaped input: '
        'period_cramps->cramps, lower_back->back_pain, bloated->bloating, '
        'fatigue->tired', () {
      final result = parseClueDatapoints(
        utf8.encode(
          '['
          '{"date": "2026-02-01", "type": "pain", '
          '"value": {"option": "period_cramps"}},'
          '{"date": "2026-02-02", "type": "pain", '
          '"value": {"option": "lower_back"}},'
          '{"date": "2026-02-03", "type": "digestion", '
          '"value": {"option": "bloated"}},'
          '{"date": "2026-02-04T00:00:00.000Z", "type": "energy", '
          '"value": {"option": "fatigue"}}'
          ']',
        ),
      );
      expect(result.skipped, isEmpty);
      expect(result.datapoints, hasLength(4));
      expect(
        [
          for (final dp in result.datapoints)
            (dp as ClueObservationDatapoint).code,
        ],
        ['cramps', 'back_pain', 'bloating', 'tired'],
      );
    });

    test('issue #251 mapping table on synthetic Clue-shaped input: '
        'leisure unknown options pass through verbatim (never rejected or '
        'coerced), partying "big night" snake_cases to big_night, '
        'meditation passes through', () {
      final result = parseClueDatapoints(
        utf8.encode(
          '['
          '{"date": "2026-03-01", "type": "leisure", '
          '"value": [{"option": "Reading a Novel"}, '
          '{"option": "totally undocumented option"}]},'
          '{"date": "2026-03-02", "type": "partying", '
          '"value": [{"option": "big night"}, {"option": "hangover"}]},'
          '{"date": "2026-03-03T00:00:00.000Z", "type": "meditation", '
          '"value": {"option": "ten minutes"}}'
          ']',
        ),
      );
      expect(result.skipped, isEmpty, reason: 'unknown-never-drop');
      expect(result.datapoints, hasLength(5));
      expect(
        [
          for (final dp in result.datapoints)
            ((dp as ClueObservationDatapoint).category, dp.code),
        ],
        [
          ('leisure', 'Reading a Novel'),
          // No source enumerates leisure's real option set (A1-45):
          // anything an export carries must survive byte-for-byte.
          ('leisure', 'totally undocumented option'),
          ('partying', 'big_night'),
          ('partying', 'hangover'),
          ('meditation', 'ten minutes'),
        ],
      );
    });

    test('issue #252 mapping table on synthetic Clue-shaped input: '
        'the cold/flu collision category-qualifies under both medication '
        'and ailments (both spellings), collection_method and exercise '
        'options pass through as picker codes, and appointments options '
        'pass through verbatim (unknown-never-drop)', () {
      final result = parseClueDatapoints(
        utf8.encode(
          '['
          '{"date": "2026-04-01", "type": "medication", '
          '"value": [{"option": "cold/flu"}, {"option": "antibiotic"}]},'
          '{"date": "2026-04-02", "type": "ailments", '
          '"value": {"option": "cold/flu"}},'
          '{"date": "2026-04-03", "type": "ailments", '
          '"value": {"option": "cold_flu"}},'
          '{"date": "2026-04-04", "type": "collection_method", '
          '"value": {"option": "menstrual_cup"}},'
          '{"date": "2026-04-05", "type": "exercise", '
          '"value": [{"option": "walking"}, {"option": "rest_day"}]},'
          '{"date": "2026-04-06T00:00:00.000Z", "type": "appointments", '
          '"value": {"option": "not_publicly_enumerated"}}'
          ']',
        ),
      );
      expect(result.skipped, isEmpty, reason: 'unknown-never-drop');
      expect(result.datapoints, hasLength(8));
      expect(
        [
          for (final dp in result.datapoints)
            ((dp as ClueObservationDatapoint).category, dp.code),
        ],
        [
          ('medication', 'cold_flu_medication'),
          ('medication', 'antibiotic'),
          ('ailments', 'cold_flu_ailments'),
          // Both documented spellings land on the same qualified code.
          ('ailments', 'cold_flu_ailments'),
          ('collection_method', 'menstrual_cup'),
          ('exercise', 'walking'),
          ('exercise', 'rest_day'),
          // Appointments' exact option strings are not publicly
          // enumerated (issue #252): whatever an export carries survives
          // verbatim, never rejected or coerced.
          ('appointments', 'not_publicly_enumerated'),
        ],
      );
    });

    test('both documented date formats parse to the same civil date shape', () {
      // Bare date (row 0) and a Z-suffixed ISO datetime (row 1) on
      // consecutive calendar days.
      expect(result.datapoints[0].date, _d('2026-01-01'));
      expect(result.datapoints[1].date, _d('2026-01-02'));
    });
  });

  group('bbt numeric value-key variants', () {
    late List<ClueDatapoint> datapoints;

    setUp(() {
      datapoints = parseClueDatapoints(_fixtureBytes('bbt_variants.json'))
          .datapoints;
    });

    test('celsius', () {
      final dp = datapoints[0] as ClueNumericDatapoint;
      expect(dp.unit, 'celsius');
      expect(dp.valueNum, 36.4);
    });

    test('fahrenheit', () {
      final dp = datapoints[1] as ClueNumericDatapoint;
      expect(dp.unit, 'fahrenheit');
      expect(dp.valueNum, 97.9);
    });

    test('temperature key', () {
      final dp = datapoints[2] as ClueNumericDatapoint;
      expect(dp.unit, 'temperature');
      expect(dp.valueNum, 36.5);
    });

    test('value key', () {
      final dp = datapoints[3] as ClueNumericDatapoint;
      expect(dp.unit, 'value');
      expect(dp.valueNum, 36.6);
    });

    test('excluded flag decodes 1:1', () {
      final dp = datapoints[4] as ClueNumericDatapoint;
      expect(dp.excluded, isTrue);
    });

    test('type: temperature is an alias for bbt', () {
      final dp = datapoints[5] as ClueNumericDatapoint;
      expect(dp.clueType, 'temperature');
      expect(dp.category, 'bbt');
      expect(dp.unit, 'celsius');
    });

    test('a numeric string value is parsed defensively', () {
      final dp = datapoints[6] as ClueNumericDatapoint;
      expect(dp.valueNum, 36.9);
    });
  });

  group('negative assertions never become symptoms', () {
    late List<ClueDatapoint> datapoints;

    setUp(() {
      datapoints = parseClueDatapoints(
        _fixtureBytes('negative_assertions.json'),
      ).datapoints;
    });

    test('period/none decodes as an explicit not-bleeding flow level', () {
      final dp = datapoints[0] as CluePeriodDatapoint;
      expect(dp.level, ClueFlowLevel.notBleeding);
    });

    test('pain/pain_free is a negative assertion, not a symptom', () {
      final dp = datapoints[1] as ClueObservationDatapoint;
      expect(dp.category, 'pain');
      expect(dp.code, 'pain_free');
      expect(dp.isNegativeAssertion, isTrue);
    });

    test('sex_life/no_sex_today is a negative assertion', () {
      final dp = datapoints[2] as ClueObservationDatapoint;
      expect(dp.category, 'sex_life');
      expect(dp.code, 'no_sex_today');
      expect(dp.isNegativeAssertion, isTrue);
    });

    test('discharge/none is a negative assertion', () {
      final dp = datapoints[3] as ClueObservationDatapoint;
      expect(dp.category, 'discharge');
      expect(dp.code, 'none');
      expect(dp.isNegativeAssertion, isTrue);
    });
  });

  group('unknown type/option escape hatch (Issue #199)', () {
    late List<ClueDatapoint> datapoints;

    setUp(() {
      datapoints = parseClueDatapoints(
        _fixtureBytes('unknown_type_and_option.json'),
      ).datapoints;
    });

    test('an unrecognised type escapes to raw, preserving the whole row', () {
      final dp = datapoints[0] as ClueUnknownDatapoint;
      expect(dp.reason, ClueUnknownReason.unknownType);
      expect(dp.raw['type'], 'hot_flashes');
      expect(dp.raw['value'], {'option': 'moderate'});
    });

    test('an unrecognised option within a known type passes through verbatim, '
        'never escaping to raw', () {
      final dp = datapoints[1] as ClueObservationDatapoint;
      expect(dp.category, 'pain');
      expect(dp.code, 'mystery_symptom');
      expect(dp.isNegativeAssertion, isFalse);
    });

    test('a multi-select value produces one datapoint per option', () {
      final headache = datapoints[2] as ClueObservationDatapoint;
      final migraine = datapoints[3] as ClueObservationDatapoint;
      expect(headache.date, migraine.date);
      expect(headache.code, 'headache');
      expect(migraine.code, 'migraine');
    });

    test('bbt with none of the attested numeric keys escapes as an unknown '
        'value shape', () {
      final dp = datapoints[4] as ClueUnknownDatapoint;
      expect(dp.reason, ClueUnknownReason.unknownValueShape);
      expect(dp.raw['type'], 'bbt');
    });

    test('a non-object, non-list value escapes as an unknown value shape', () {
      final dp = datapoints[5] as ClueUnknownDatapoint;
      expect(dp.reason, ClueUnknownReason.unknownValueShape);
    });

    test('an unrecognised period option escapes as an unknown value shape, '
        'never a bleed level', () {
      final dp = datapoints[6] as ClueUnknownDatapoint;
      expect(dp.clueType, 'period');
      expect(dp.reason, ClueUnknownReason.unknownValueShape);
    });

    test('a non-object bbt value escapes as an unknown value shape', () {
      final dp = datapoints[7] as ClueUnknownDatapoint;
      expect(dp.clueType, 'bbt');
      expect(dp.reason, ClueUnknownReason.unknownValueShape);
    });
  });

  group('malformed rows skip without aborting the parse', () {
    test('a non-object row, missing type, missing date, and a bad date '
        'format are all skipped; the one well-formed row still parses', () {
      final result = parseClueDatapoints(_fixtureBytes('malformed_rows.json'));
      expect(result.skipped, hasLength(4));
      expect(result.datapoints, hasLength(1));
      expect(result.skipped[0].index, 0);
      expect(result.skipped[1].index, 1);
      expect(result.skipped[2].index, 2);
      expect(result.skipped[3].index, 3);
      expect(result.skipped[3].reason, contains('date'));
      final ok = result.datapoints.single as ClueObservationDatapoint;
      expect(ok.code, 'headache');
    });
  });

  group('empty multi-select is recorded, not silently dropped', () {
    test('"value": [] is a skipped row (emptySelection), not zero '
        'datapoints; the sibling well-formed row still parses', () {
      final result = parseClueDatapoints(_fixtureBytes('empty_selection.json'));
      expect(result.skipped, hasLength(1));
      expect(result.skipped.single.index, 0);
      expect(result.skipped.single.reason, 'emptySelection');
      final ok = result.datapoints.single as ClueObservationDatapoint;
      expect(ok.code, 'headache');
    });
  });

  group('root-level failures', () {
    test('invalid JSON throws ClueImportException', () {
      expect(
        () => parseClueDatapoints('not json'.codeUnits),
        throwsA(isA<ClueImportException>()),
      );
    });

    test('a non-array root throws ClueImportException', () {
      expect(
        () => parseClueDatapoints('{"not": "an array"}'.codeUnits),
        throwsA(isA<ClueImportException>()),
      );
    });

    test('toString carries the message', () {
      expect(ClueImportException('boom').toString(), contains('boom'));
    });

    test('toString with an offset appends it, never a source fragment', () {
      final message = ClueImportException('boom', offset: 42).toString();
      expect(message, contains('boom'));
      expect(message, contains('42'));
    });

    test('invalid JSON never embeds a fragment of the source bytes — '
        'FormatException.toString() would, but ClueImportException must '
        'not (Issue #190 review: the source is the user\'s own health '
        'data, and lib/domain/import/ exceptions are not scrubbed by '
        'lib/observability/scrub.dart)', () {
      final bytes = _fixtureBytes('corrupt_json_with_health_token.json');
      // Prove the fixture is actually malformed and does contain the
      // token, so this test would fail loudly if the fixture stopped
      // reproducing a real jsonDecode FormatException.
      expect(utf8.decode(bytes), contains('oncology'));
      try {
        parseClueDatapoints(bytes);
        fail('expected ClueImportException');
      } on ClueImportException catch (e) {
        expect(e.toString(), isNot(contains('oncology')));
        expect(e.message, isNot(contains('oncology')));
      }
    });
  });

  group('UTF-8 decoding tolerance (Issue #190 review)', () {
    test('a leading UTF-8 BOM is stripped before JSON decoding', () {
      final bomPrefixed = [
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(
          '[{"date": "2026-01-01", "type": "period", '
          '"value": {"option": "light"}}]',
        ),
      ];
      final result = parseClueDatapoints(bomPrefixed);
      expect(result.datapoints, hasLength(1));
      final dp = result.datapoints.single as CluePeriodDatapoint;
      expect(dp.level, ClueFlowLevel.light);
    });

    test('bytes with no BOM decode exactly as before', () {
      final noBom = utf8.encode(
        '[{"date": "2026-01-01", "type": "period", '
        '"value": {"option": "light"}}]',
      );
      final result = parseClueDatapoints(noBom);
      expect(result.datapoints, hasLength(1));
    });

    test('a malformed UTF-8 byte inside a tags value does not fail the '
        'whole decode', () {
      final good = utf8.encode(
        '[{"date": "2026-01-01", "type": "tags", "value": [{"option": "',
      );
      final malformed = [0xC3, 0x28]; // invalid 2-byte sequence
      final tail = utf8.encode('trip"}]}]');
      final bytes = [...good, ...malformed, ...tail];
      final result = parseClueDatapoints(bytes);
      expect(result.datapoints, hasLength(1));
      final dp = result.datapoints.single as ClueObservationDatapoint;
      expect(dp.code, isNotEmpty);
    });
  });
}
