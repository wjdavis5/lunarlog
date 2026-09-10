/// Sanity tests for the Clue mapping tables themselves (Issue #190):
/// every attested/medium-confidence `type` from the issue's mapping table
/// has an entry (or is one of the two specially-parsed types), and the
/// documented negative-assertion options are flagged.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/import/clue/clue_datapoint.dart';
import 'package:lunarlog/domain/import/clue/clue_option_map.dart';

void main() {
  group('kClueTypeMap', () {
    const attestedTypes = [
      'spotting',
      'pain',
      'feelings',
      'sex_life',
      'energy',
      'pms',
      'digestion',
      'discharge',
      'collection_method',
      'social_life',
      'craving',
      'mind',
      'exercise',
      'stool',
      'leisure',
      // Issue #251's additions.
      'meditation',
      'partying',
      'hair',
      'skin',
      'medication',
      'appointments',
      'ailments',
      'tags',
    ];

    const mediumConfidenceTypes = [
      'birth_control',
      'motivation',
      'sleep',
      'tests',
    ];

    for (final type in [...attestedTypes, ...mediumConfidenceTypes]) {
      test('$type has a mapping entry', () {
        expect(kClueTypeMap.containsKey(type), isTrue,
            reason: '$type is missing from kClueTypeMap');
      });
    }

    test('period and bbt are not in kClueTypeMap (dedicated parsing)', () {
      expect(kClueTypeMap.containsKey('period'), isFalse);
      expect(kClueTypeMap.containsKey('bbt'), isFalse);
    });

    test('mucus is present in the mapping table (own category, not folded '
        'into discharge — Issue #190 review)', () {
      expect(kClueTypeMap.containsKey('mucus'), isTrue);
      expect(kClueTypeMap['mucus']!.category, 'mucus');
    });

    test('negative-assertion options are flagged', () {
      expect(kClueTypeMap['pain']!.options['pain_free']!.negative, isTrue);
      expect(
          kClueTypeMap['sex_life']!.options['no_sex_today']!.negative, isTrue);
      expect(kClueTypeMap['discharge']!.options['none']!.negative, isTrue);
    });

    test('renamed options carry their target code', () {
      expect(kClueTypeMap['pain']!.options['period_cramps']!.code, 'cramps');
      expect(kClueTypeMap['pain']!.options['lower_back']!.code, 'back_pain');
      expect(kClueTypeMap['digestion']!.options['bloated']!.code, 'bloating');
      expect(kClueTypeMap['digestion']!.options['nauseous']!.code, 'nausea');
      expect(kClueTypeMap['digestion']!.options['nauseated']!.code, 'nausea');
      // Issue #249: Clue's legacy `fatigue` energy option maps onto the
      // graduated taxonomy's `tired`.
      expect(kClueTypeMap['energy']!.options['fatigue']!.code, 'tired');
      // Issue #251: the attested "big night" partying option snake_cases
      // for the flat tag namespace; drinks/cigarettes/hangover pass
      // through with no entry at all.
      expect(
          kClueTypeMap['partying']!.options['big night']!.code, 'big_night');
      expect(kClueTypeMap['partying']!.options.containsKey('drinks'), isFalse);
      expect(
          kClueTypeMap['partying']!.options.containsKey('hangover'), isFalse);
    });

    test('an option absent from a type\'s spec passes through (no entry)',
        () {
      expect(kClueTypeMap['pain']!.options.containsKey('headache'), isFalse);
    });
  });

  group('kCluePeriodLevels', () {
    test('covers all four bleed levels plus the not-bleeding assertion', () {
      expect(kCluePeriodLevels.keys.toSet(),
          {'none', 'light', 'medium', 'heavy', 'very_heavy'});
    });

    test('very_heavy maps to superHeavy (Clue\'s "Super heavy")', () {
      expect(kCluePeriodLevels['very_heavy'], ClueFlowLevel.superHeavy);
    });

    test('none maps to notBleeding, a positive assertion', () {
      expect(kCluePeriodLevels['none'], ClueFlowLevel.notBleeding);
    });
  });

  group('kClueNumericTypes / kClueBbtValueKeys', () {
    test('bbt and its temperature alias are both numeric types', () {
      expect(kClueNumericTypes, {'bbt', 'temperature'});
    });

    test('value-key variants are tried celsius first', () {
      expect(kClueBbtValueKeys.first, 'celsius');
      expect(kClueBbtValueKeys,
          containsAll(['celsius', 'fahrenheit', 'temperature', 'value']));
    });
  });
}
