/// Issue #238: the pure tag → HealthKit symptom mapping. The load-bearing
/// assertion is the completeness partition — every live tag code in
/// `tags.dart` must be mapped, explicitly unsupported, or explicitly
/// not-exported, so a future taxonomy addition fails this suite instead of
/// silently vanishing from the Health export.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_symptom_mapping.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/tags.dart';

void main() {
  group('the mapping table is the full, live taxonomy partition', () {
    test('mapped + unsupported + not-exported covers every live tag code', () {
      final classified = <String>{
        ...kSymptomHealthKitTypeIdentifiers.keys,
        ...kUnsupportedHealthKitSymptoms.keys,
        ...kNotExportedTagCodes,
      };
      expect(
        classified,
        kTagTaxonomy.map((tag) => tag.code).toSet(),
        reason:
            'a tag added to tags.dart without a mapping decision must '
            'fail here rather than vanish from the Health export',
      );
    });

    test('the three sets are pairwise disjoint', () {
      final mapped = kSymptomHealthKitTypeIdentifiers.keys.toSet();
      final unsupported = kUnsupportedHealthKitSymptoms.keys.toSet();
      expect(mapped.intersection(unsupported), isEmpty);
      expect(mapped.intersection(kNotExportedTagCodes), isEmpty);
      expect(unsupported.intersection(kNotExportedTagCodes), isEmpty);
    });

    test('every mapped code is a real live taxonomy code', () {
      final live = kTagTaxonomy.map((tag) => tag.code).toSet();
      expect(mappedCodesAreLive(live), isTrue);
    });
  });

  group('direct 1:1 mappings', () {
    const expected = {
      'cramps': 'abdominalCramps',
      'headache': 'headache',
      'back_pain': 'lowerBackPain',
      'breast_tenderness': 'breastPain',
      'bloating': 'bloating',
      'acne': 'acne',
      'nausea': 'nausea',
      'fatigue': 'fatigue',
      'dizziness': 'dizziness',
    };

    for (final entry in expected.entries) {
      test('${entry.key} -> ${entry.value}', () {
        expect(kSymptomHealthKitTypeIdentifiers[entry.key], entry.value);
      });
    }
  });

  group('lossy mappings', () {
    test('every feelings-category tag collapses to moodChanges', () {
      const feelingsCodes = [
        'irritable',
        'happy',
        'sad',
        'angry',
        'anxious',
        'indifferent',
        'sensitive',
        'mood_swings',
        'excited',
        'insecure',
        'grateful',
      ];
      for (final code in feelingsCodes) {
        expect(
          kSymptomHealthKitTypeIdentifiers[code],
          'moodChanges',
          reason: '$code must map to moodChanges (HealthKit has no valence)',
        );
      }
    });

    test('sleep_trouble -> sleepChanges and cravings -> appetiteChanges', () {
      expect(kSymptomHealthKitTypeIdentifiers['sleep_trouble'], 'sleepChanges');
      expect(kSymptomHealthKitTypeIdentifiers['cravings'], 'appetiteChanges');
    });
  });

  group('deliberately unsupported tags', () {
    test('calm and energetic are unsupported with a documented reason', () {
      for (final code in ['calm', 'energetic']) {
        final reason = kUnsupportedHealthKitSymptoms[code];
        expect(reason, isNotNull, reason: '$code must be explicitly handled');
        expect(reason, contains('HKStateOfMind'));
        expect(kSymptomHealthKitTypeIdentifiers.containsKey(code), isFalse);
      }
    });
  });

  group('classifySymptomHealthKitExport', () {
    test('a mapped code returns its type identifier', () {
      final result = classifySymptomHealthKitExport('cramps');
      expect(result, isA<SymptomHealthKitMapped>());
      expect(
        (result as SymptomHealthKitMapped).typeIdentifier,
        'abdominalCramps',
      );
    });

    test('an unsupported code carries its reason', () {
      final result = classifySymptomHealthKitExport('calm');
      expect(result, isA<SymptomHealthKitUnsupported>());
      expect((result as SymptomHealthKitUnsupported).reason, isNotEmpty);
    });

    test('a live non-symptom code is not exported', () {
      expect(
        classifySymptomHealthKitExport('running'),
        isA<SymptomHealthKitNotExported>(),
      );
    });

    test('an unknown code is not exported, never an error', () {
      expect(
        classifySymptomHealthKitExport('a_custom_registry_tag'),
        isA<SymptomHealthKitNotExported>(),
      );
    });
  });

  group('severityForPainIntensity', () {
    test('null (no grade recorded) is unspecified — the common case', () {
      expect(severityForPainIntensity(null), HealthSymptomSeverity.unspecified);
    });

    test('1 is mild', () {
      expect(severityForPainIntensity(1), HealthSymptomSeverity.mild);
    });

    test('2-3 is moderate', () {
      expect(severityForPainIntensity(2), HealthSymptomSeverity.moderate);
      expect(severityForPainIntensity(3), HealthSymptomSeverity.moderate);
    });

    test('4-5 is severe (the caregiver high-severity threshold)', () {
      expect(severityForPainIntensity(4), HealthSymptomSeverity.severe);
      expect(severityForPainIntensity(5), HealthSymptomSeverity.severe);
    });
  });

  group('resolveHealthKitSymptoms', () {
    test('maps each tag and carries the tag\'s graded severity', () {
      final resolved = resolveHealthKitSymptoms(
        tags: const ['cramps', 'headache'],
        gradedPainIntensities: const {'cramps': 5, 'headache': 2},
      );
      expect(
        resolved,
        containsAll(const [
          ResolvedHealthKitSymptom(
            tagCode: 'cramps',
            typeIdentifier: 'abdominalCramps',
            severity: HealthSymptomSeverity.severe,
          ),
          ResolvedHealthKitSymptom(
            tagCode: 'headache',
            typeIdentifier: 'headache',
            severity: HealthSymptomSeverity.moderate,
          ),
        ]),
      );
    });

    test('a tag with no grade is unspecified', () {
      final resolved = resolveHealthKitSymptoms(
        tags: const ['cramps'],
        gradedPainIntensities: const {},
      );
      expect(resolved.single.severity, HealthSymptomSeverity.unspecified);
    });

    test(
      'mood tags dedupe to one moodChanges sample, highest severity wins',
      () {
        final resolved = resolveHealthKitSymptoms(
          tags: const ['sad', 'anxious'],
          gradedPainIntensities: const {},
        );
        expect(resolved, hasLength(1));
        expect(resolved.single.typeIdentifier, 'moodChanges');
        expect(resolved.single.severity, HealthSymptomSeverity.unspecified);
      },
    );

    test('unsupported and not-exported tags contribute nothing', () {
      final resolved = resolveHealthKitSymptoms(
        tags: const ['calm', 'running', 'unknown_code'],
        gradedPainIntensities: const {},
      );
      expect(resolved, isEmpty);
    });

    test('an empty tag list resolves to nothing', () {
      expect(
        resolveHealthKitSymptoms(
          tags: const [],
          gradedPainIntensities: const {},
        ),
        isEmpty,
      );
    });
  });
}

/// Helper for the "mapped codes are live" assertion — keeps the test body
/// readable and gives the CRAP gate a single simple function.
bool mappedCodesAreLive(Set<String> live) =>
    kSymptomHealthKitTypeIdentifiers.keys.every(live.contains) &&
    kUnsupportedHealthKitSymptoms.keys.every(live.contains) &&
    kNotExportedTagCodes.every(live.contains);
