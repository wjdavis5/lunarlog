import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/export/clinical_terminology.dart';
import 'package:lunarlog/domain/tags.dart';

/// Compile-time proof that [kTagClinicalCodes] is a `const` map (item 6):
/// this top-level `const` declaration only compiles if the right-hand
/// side is a compile-time constant expression.
const Map<String, ClinicalCode> _kTagClinicalCodesIsConst = kTagClinicalCodes;

void main() {
  test('kTagClinicalCodes is a compile-time constant', () {
    // The real check already happened at compile time (the top-level
    // `const` declaration above would fail to compile otherwise); this
    // assertion just gives the check a visible place in the test report.
    expect(_kTagClinicalCodesIsConst, same(kTagClinicalCodes));
  });

  group('kLoincCodes', () {
    test('is exactly the seven verified LOINC codes from #152', () {
      expect(kLoincCodes, hasLength(7));
      expect(kLoincCodes.map((c) => c.code).toSet(), {
        '8665-2',
        '8678-5',
        '3146-8',
        '92656-8',
        '63888-2',
        '64700-8',
        '11778-8',
      });
    });

    test('every code appears exactly once', () {
      final codes = kLoincCodes.map((c) => c.code).toList();
      expect(codes.toSet(), hasLength(codes.length));
    });

    test(
      'every row uses the LOINC system and an https loinc.org provenance',
      () {
        for (final row in kLoincCodes) {
          expect(row.system, kSystemLoinc, reason: row.code);
          expect(
            row.provenanceUrl,
            startsWith('https://loinc.org/'),
            reason: row.code,
          );
          expect(row.display.trim(), isNotEmpty, reason: row.code);
        }
      },
    );
  });

  group('kLoincCodes — golden table (BLOCKING: fails loudly on any edit to '
      'a verified LOINC row)', () {
    test('matches the full expected seven rows, in order, with the exact '
        'verified display for each', () {
      // (code, display) as literals - a re-verified copy of the LOINC
      // designations, not derived from the source module. `64700-8`'s
      // display is the real LOINC SHORTNAME (tx.fhir.org, 2026-09-09),
      // not #152's original editorial elision.
      const expected = <(String, String)>[
        ('8665-2', 'Last menstrual period start date'),
        ('8678-5', 'Menstrual status - Reported'),
        ('3146-8', 'Menstrual status'),
        ('92656-8', 'Number of menstrual periods per year'),
        ('63888-2', 'Age at first menstrual period'),
        ('64700-8', 'Menstrual cycle typical days PhenX'),
        ('11778-8', 'Delivery date Estimated'),
      ];
      expect(kLoincCodes, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        final (code, display) = expected[i];
        expect(kLoincCodes[i].code, code, reason: 'row $i code');
        expect(kLoincCodes[i].display, display, reason: 'row $i display');
        expect(kLoincCodes[i].system, 'http://loinc.org', reason: code);
      }
    });
  });

  group('refuted and unverified LOINC codes are never referenced', () {
    test('kRefutedLoincCodes contains exactly 3141-9', () {
      expect(kRefutedLoincCodes, ['3141-9']);
    });

    test(
      'kUnverifiedLoincCodes contains exactly the five unresolved codes',
      () {
        expect(kUnverifiedLoincCodes.toSet(), {
          '49033-4',
          '63871-7',
          '21840-4',
          '8708-3',
          '3151-8',
        });
      },
    );

    test('no refuted or unverified code appears in kLoincCodes', () {
      final forbidden = {...kRefutedLoincCodes, ...kUnverifiedLoincCodes};
      for (final row in kLoincCodes) {
        expect(
          forbidden.contains(row.code),
          isFalse,
          reason: '${row.code} must never be a usable LOINC row',
        );
      }
    });

    test('no refuted or unverified code appears anywhere in '
        'kTagClinicalCodes', () {
      final forbidden = {...kRefutedLoincCodes, ...kUnverifiedLoincCodes};
      for (final entry in kTagClinicalCodes.entries) {
        expect(
          forbidden.contains(entry.value.code),
          isFalse,
          reason: '${entry.key} must not carry a refuted/unverified code',
        );
      }
    });

    test('no refuted or unverified code appears in dualCodingFor output for '
        'any taxonomy tag', () {
      final forbidden = {...kRefutedLoincCodes, ...kUnverifiedLoincCodes};
      for (final tag in kTagTaxonomy) {
        for (final coding in dualCodingFor(tag.code)) {
          expect(
            forbidden.contains(coding.code),
            isFalse,
            reason: '${tag.code} must not carry a refuted/unverified code',
          );
        }
      }
    });

    test('no refuted or unverified code appears in menstrualStatusCodes or '
        'cycleLengthCodes', () {
      final forbidden = {...kRefutedLoincCodes, ...kUnverifiedLoincCodes};
      for (final coding in [...menstrualStatusCodes, ...cycleLengthCodes]) {
        expect(
          forbidden.contains(coding.code),
          isFalse,
          reason: '${coding.code} must not be refuted/unverified',
        );
      }
    });

    test('the two lists never overlap each other', () {
      expect(
        kRefutedLoincCodes.toSet().intersection(kUnverifiedLoincCodes.toSet()),
        isEmpty,
      );
    });
  });

  group('kTagClinicalCodes covers every kTagTaxonomy code exactly once', () {
    test('every taxonomy code has a row', () {
      for (final tag in kTagTaxonomy) {
        expect(
          kTagClinicalCodes.containsKey(tag.code),
          isTrue,
          reason:
              '${tag.code} has no clinical-terminology mapping row and '
              'no explicit local decision',
        );
      }
    });

    test('no row exists for a code outside the taxonomy', () {
      final taxonomyCodes = kTagTaxonomy.map((t) => t.code).toSet();
      for (final code in kTagClinicalCodes.keys) {
        expect(
          taxonomyCodes.contains(code),
          isTrue,
          reason: '$code in kTagClinicalCodes is not a known tag code',
        );
      }
    });

    test('row count matches taxonomy size exactly (108, issue #253)', () {
      expect(kTagClinicalCodes, hasLength(108));
      expect(kTagTaxonomy, hasLength(108));
    });
  });

  group('kTagClinicalCodes — golden table (BLOCKING: fails loudly on any '
      'edit to a verified tag mapping)', () {
    test('matches the full expected (system, code, display) triple for all '
        '108 tags', () {
      const snomed = 'http://snomed.info/sct';
      const local =
          'https://github.com/wjdavis5/lunarlog/fhir/CodeSystem/'
          'tag';
      // (system, code, display) as literals for every taxonomy tag - a
      // re-verified copy of each mapping decision, not derived from the
      // source module.
      const expected = <String, (String, String, String)>{
        // pain
        'cramps': (snomed, '266599000', 'Dysmenorrhea'),
        'headache': (snomed, '25064002', 'Headache'),
        'back_pain': (snomed, '161891005', 'Backache'),
        'breast_tenderness': (snomed, '55222007', 'Tenderness of breast'),
        // body
        'bloating': (snomed, '116289008', 'Abdominal bloating'),
        'acne': (snomed, '11381005', 'Acne'),
        'nausea': (snomed, '422587007', 'Nausea'),
        'fatigue': (snomed, '84229001', 'Fatigue'),
        'dizziness': (snomed, '404640003', 'Dizziness'),
        // mood
        'irritable': (local, 'irritable', 'Irritable'),
        'sad': (local, 'sad', 'Sad'),
        'anxious': (snomed, '48694002', 'Anxiety'),
        'calm': (local, 'calm', 'Calm'),
        'energetic': (local, 'energetic', 'Energetic'),
        'sensitive': (local, 'sensitive', 'Sensitive'),
        // other
        'sleep_trouble': (snomed, '301345002', 'Difficulty sleeping'),
        'cravings': (snomed, '248132003', 'Craving for food or drink'),
        // issue #249's 28 new codes - every one an explicit local decision
        // (no SNOMED concept fetch-verified yet; see
        // docs/clinical/terminology.md's #249 section).
        'ovulation': (local, 'ovulation', 'Ovulation pain'),
        'migraine': (local, 'migraine', 'Migraine'),
        'migraine_with_aura': (
          local,
          'migraine_with_aura',
          'Migraine with aura',
        ),
        'pain_free': (local, 'pain_free', 'Pain free'),
        'fully_energized': (local, 'fully_energized', 'Fully energized'),
        'tired': (local, 'tired', 'Tired'),
        'exhausted': (local, 'exhausted', 'Exhausted'),
        '0_to_3_hours': (local, '0_to_3_hours', '0-3 hours'),
        '3_to_6_hours': (local, '3_to_6_hours', '3-6 hours'),
        '6_to_9_hours': (local, '6_to_9_hours', '6-9 hours'),
        '9_or_more_hours': (local, '9_or_more_hours', '9+ hours'),
        'good_skin': (local, 'good_skin', 'Good skin'),
        'oily_skin': (local, 'oily_skin', 'Oily skin'),
        'dry_skin': (local, 'dry_skin', 'Dry skin'),
        'good_hair': (local, 'good_hair', 'Good hair'),
        'bad_hair': (local, 'bad_hair', 'Bad hair'),
        'oily_hair': (local, 'oily_hair', 'Oily hair'),
        'dry_hair': (local, 'dry_hair', 'Dry hair'),
        'gassy': (local, 'gassy', 'Gassy'),
        'great_digestion': (local, 'great_digestion', 'Great digestion'),
        'normal': (local, 'normal', 'Normal'),
        'constipated': (local, 'constipated', 'Constipated'),
        'great_stool': (local, 'great_stool', 'Great stool'),
        'diarrhea': (local, 'diarrhea', 'Diarrhea'),
        'sweet': (local, 'sweet', 'Sweet'),
        'salty': (local, 'salty', 'Salty'),
        'carbs': (local, 'carbs', 'Carbs'),
        'chocolate': (local, 'chocolate', 'Chocolate'),
        // issue #251's 22 new codes - every one an explicit local decision
        // (no SNOMED concept fetch-verified yet; see
        // docs/clinical/terminology.md's #251 section). The re-parented
        // mood codes above are unchanged.
        'happy': (local, 'happy', 'Happy'),
        'angry': (local, 'angry', 'Angry'),
        'indifferent': (local, 'indifferent', 'Indifferent'),
        'mood_swings': (local, 'mood_swings', 'Mood swings'),
        'excited': (local, 'excited', 'Excited'),
        'insecure': (local, 'insecure', 'Insecure'),
        'grateful': (local, 'grateful', 'Grateful'),
        'distracted': (local, 'distracted', 'Distracted'),
        'focused': (local, 'focused', 'Focused'),
        'stressed': (local, 'stressed', 'Stressed'),
        'motivated': (local, 'motivated', 'Motivated'),
        'unmotivated': (local, 'unmotivated', 'Unmotivated'),
        'productive': (local, 'productive', 'Productive'),
        'unproductive': (local, 'unproductive', 'Unproductive'),
        'sociable': (local, 'sociable', 'Sociable'),
        'withdrawn': (local, 'withdrawn', 'Withdrawn'),
        'supportive': (local, 'supportive', 'Supportive'),
        'conflict': (local, 'conflict', 'Conflict'),
        'drinks': (local, 'drinks', 'Drinks'),
        'cigarettes': (local, 'cigarettes', 'Cigarettes'),
        'big_night': (local, 'big_night', 'Big night'),
        'hangover': (local, 'hangover', 'Hangover'),
        // issue #252's 19 new codes - every one an explicit local decision
        // (no SNOMED concept fetch-verified yet; see
        // docs/clinical/terminology.md's #252 section).
        'pad': (local, 'pad', 'Pad'),
        'tampon': (local, 'tampon', 'Tampon'),
        'panty_liner': (local, 'panty_liner', 'Panty liner'),
        'menstrual_cup': (local, 'menstrual_cup', 'Menstrual cup'),
        'running': (local, 'running', 'Running'),
        'yoga': (local, 'yoga', 'Yoga'),
        'biking': (local, 'biking', 'Biking'),
        'swimming': (local, 'swimming', 'Swimming'),
        'walking': (local, 'walking', 'Walking'),
        'pilates': (local, 'pilates', 'Pilates'),
        'rest_day': (local, 'rest_day', 'Rest day'),
        'pain': (local, 'pain', 'Pain (medication)'),
        'cold_flu_medication': (
          local,
          'cold_flu_medication',
          'Cold/flu (medication)',
        ),
        'antihistamine': (local, 'antihistamine', 'Antihistamine'),
        'antibiotic': (local, 'antibiotic', 'Antibiotic'),
        'cold_flu_ailments': (
          local,
          'cold_flu_ailments',
          'Cold/flu (ailments)',
        ),
        'allergy': (local, 'allergy', 'Allergy'),
        'injury': (local, 'injury', 'Injury'),
        'fever': (local, 'fever', 'Fever'),
        // issue #253's 22 new codes - every one an explicit local decision
        // (no SNOMED concept fetch-verified yet; see
        // docs/clinical/terminology.md's #253 section).
        'no_sex_today': (local, 'no_sex_today', 'No sex today'),
        'low_sex_drive': (local, 'low_sex_drive', 'Low sex drive'),
        'high_sex_drive': (local, 'high_sex_drive', 'High sex drive'),
        'masturbation': (local, 'masturbation', 'Masturbation'),
        'withdrawal': (local, 'withdrawal', 'Withdrawal'),
        'protected_sex': (local, 'protected_sex', 'Protected sex'),
        'unprotected_sex': (local, 'unprotected_sex', 'Unprotected sex'),
        'sex_toys': (local, 'sex_toys', 'Sex toys'),
        'orgasm': (local, 'orgasm', 'Orgasm'),
        'no_orgasm': (local, 'no_orgasm', 'No orgasm'),
        'fantasies': (local, 'fantasies', 'Fantasies'),
        'painful_intercourse': (
          local,
          'painful_intercourse',
          'Painful intercourse',
        ),
        'none': (local, 'none', 'No discharge'),
        'sticky': (local, 'sticky', 'Sticky'),
        'creamy': (local, 'creamy', 'Creamy'),
        'egg_white': (local, 'egg_white', 'Egg white'),
        'atypical': (local, 'atypical', 'Atypical'),
        'ovulation_negative': (
          local,
          'ovulation_negative',
          'Ovulation · negative',
        ),
        'ovulation_positive': (
          local,
          'ovulation_positive',
          'Ovulation · positive',
        ),
        'ovulation_peak': (local, 'ovulation_peak', 'Ovulation · peak'),
        'pregnancy_negative': (
          local,
          'pregnancy_negative',
          'Pregnancy · negative',
        ),
        'pregnancy_positive': (
          local,
          'pregnancy_positive',
          'Pregnancy · positive',
        ),
      };
      expect(kTagClinicalCodes, hasLength(expected.length));
      expect(kTagClinicalCodes.keys.toSet(), expected.keys.toSet());
      for (final entry in expected.entries) {
        final row = kTagClinicalCodes[entry.key];
        expect(row, isNotNull, reason: entry.key);
        final (system, code, display) = entry.value;
        expect(row!.system, system, reason: '${entry.key} system');
        expect(row.code, code, reason: '${entry.key} code');
        expect(row.display, display, reason: '${entry.key} display');
      }
    });
  });

  group('mood tags — the four expected-local ones stay local', () {
    test('irritable, calm, energetic, sensitive are local-coded', () {
      for (final code in ['irritable', 'calm', 'energetic', 'sensitive']) {
        expect(
          kTagClinicalCodes[code]!.system,
          kSystemLunarlogLocal,
          reason: code,
        );
      }
    });
  });

  group('every SNOMED row is verifiably sourced', () {
    test('every SNOMED row has a non-empty https provenanceUrl', () {
      for (final entry in kTagClinicalCodes.entries) {
        if (entry.value.system == kSystemSnomed) {
          expect(
            entry.value.provenanceUrl,
            startsWith('https://'),
            reason: entry.key,
          );
          expect(entry.value.code, isNotEmpty, reason: entry.key);
          expect(entry.value.display.trim(), isNotEmpty, reason: entry.key);
        }
      }
    });

    test('every local row cites the exact local-code-policy doc anchor', () {
      for (final entry in kTagClinicalCodes.entries) {
        if (entry.value.system == kSystemLunarlogLocal) {
          expect(
            entry.value.provenanceUrl,
            'docs/clinical/terminology.md#local-code-policy',
            reason: entry.key,
          );
        }
      }
    });

    test('localTagCoding cites the same exact anchor', () {
      expect(
        localTagCoding('cramps').provenanceUrl,
        'docs/clinical/terminology.md#local-code-policy',
      );
    });
  });

  group('system URIs are the canonical FHIR ones', () {
    test('constants match the FHIR-registered / lunarlog-controlled URIs', () {
      expect(kSystemLoinc, 'http://loinc.org');
      expect(kSystemSnomed, 'http://snomed.info/sct');
      expect(
        kSystemLunarlogLocal,
        'https://github.com/wjdavis5/lunarlog/fhir/CodeSystem/tag',
      );
    });

    test('every kTagClinicalCodes row uses one of the three known systems', () {
      const known = {kSystemLoinc, kSystemSnomed, kSystemLunarlogLocal};
      for (final entry in kTagClinicalCodes.entries) {
        expect(known.contains(entry.value.system), isTrue, reason: entry.key);
      }
    });

    test('every kLoincCodes row uses kSystemLoinc', () {
      for (final row in kLoincCodes) {
        expect(row.system, kSystemLoinc, reason: row.code);
      }
    });
  });

  group('localTagCoding', () {
    test('builds a local coding from the taxonomy code and display', () {
      final coding = localTagCoding('cramps');
      expect(coding.system, kSystemLunarlogLocal);
      expect(coding.code, 'cramps');
      expect(coding.display, tagByCode('cramps')!.display);
    });

    test('throws for an unknown tag code', () {
      expect(() => localTagCoding('not-a-tag'), throwsArgumentError);
    });
  });

  group('dualCodingFor', () {
    test('always includes the local coding, for every taxonomy tag', () {
      for (final tag in kTagTaxonomy) {
        final codings = dualCodingFor(tag.code);
        final hasLocal = codings.any(
          (c) =>
              c.system == kSystemLunarlogLocal &&
              c.code == tag.code &&
              c.display == tag.display,
        );
        expect(
          hasLocal,
          isTrue,
          reason:
              '${tag.code} dual coding must always carry the local '
              'coding for round-trip fidelity',
        );
      }
    });

    test('a SNOMED-mapped tag returns [clinical, local] in that order', () {
      final codings = dualCodingFor('headache');
      expect(codings, hasLength(2));
      expect(codings[0].system, kSystemSnomed);
      expect(codings[0].code, '25064002');
      expect(codings[1].system, kSystemLunarlogLocal);
      expect(codings[1].code, 'headache');
    });

    test('a local-only tag returns a single coding, not a duplicate pair', () {
      final codings = dualCodingFor('calm');
      expect(codings, hasLength(1));
      expect(codings.single.system, kSystemLunarlogLocal);
      expect(codings.single.code, 'calm');
    });

    test('throws for an unknown tag code', () {
      expect(() => dualCodingFor('not-a-tag'), throwsArgumentError);
    });

    test('degrades to the local coding (not a throw) when a taxonomy tag '
        'has no row in clinicalCodes', () {
      final codings = dualCodingFor(
        'cramps',
        clinicalCodes: const <String, ClinicalCode>{},
      );
      expect(codings, hasLength(1));
      expect(codings.single, localTagCoding('cramps'));
      expect(codings.single.system, kSystemLunarlogLocal);
    });

    test('still throws for a code outside the taxonomy even with an empty '
        'clinicalCodes override', () {
      expect(
        () => dualCodingFor(
          'not-a-tag',
          clinicalCodes: const <String, ClinicalCode>{},
        ),
        throwsArgumentError,
      );
    });

    test('an explicit clinicalCodes override is honored over the default '
        'table', () {
      final codings = dualCodingFor(
        'headache',
        clinicalCodes: const {
          'headache': ClinicalCode(
            system: kSystemSnomed,
            code: '999999',
            display: 'Overridden',
            provenanceUrl: 'https://example.test/999999',
          ),
        },
      );
      expect(codings, hasLength(2));
      expect(codings[0].code, '999999');
      expect(codings[1].system, kSystemLunarlogLocal);
    });
  });

  group('loincByCode', () {
    test('finds a known code', () {
      expect(
        loincByCode('8665-2')!.display,
        'Last menstrual period start date',
      );
    });

    test('returns null for an unknown code', () {
      expect(loincByCode('0000-0'), isNull);
    });

    test('returns null for a refuted or unverified code', () {
      expect(loincByCode('3141-9'), isNull);
      expect(loincByCode('49033-4'), isNull);
    });
  });

  group('menstrualStatusCodes and cycleLengthCodes (#157 helpers)', () {
    test('menstrualStatusCodes exposes 8678-5 and 3146-8', () {
      expect(menstrualStatusCodes.map((c) => c.code).toSet(), {
        '8678-5',
        '3146-8',
      });
      for (final row in menstrualStatusCodes) {
        expect(row.system, kSystemLoinc);
      }
    });

    test('cycleLengthCodes exposes 64700-8', () {
      expect(cycleLengthCodes.map((c) => c.code).toList(), ['64700-8']);
      expect(cycleLengthCodes.single.system, kSystemLoinc);
    });
  });

  group('ClinicalCode value semantics', () {
    test('equal fields compare equal', () {
      const a = ClinicalCode(
        system: kSystemSnomed,
        code: '25064002',
        display: 'Headache',
        provenanceUrl: 'https://example.test/25064002',
      );
      const b = ClinicalCode(
        system: kSystemSnomed,
        code: '25064002',
        display: 'Headache',
        provenanceUrl: 'https://example.test/25064002',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing fields compare unequal', () {
      const a = ClinicalCode(
        system: kSystemSnomed,
        code: '25064002',
        display: 'Headache',
        provenanceUrl: 'https://example.test/25064002',
      );
      const b = ClinicalCode(
        system: kSystemSnomed,
        code: '84229001',
        display: 'Fatigue',
        provenanceUrl: 'https://example.test/84229001',
      );
      expect(a == b, isFalse);
    });
  });
}
