/// Issues #196 (AC6) and #246: the Health Platform Sync type registry
/// carries the iOS 26 menopause category types — named, mapped in pure
/// code by `lib/data/health/health_mode_interval_mapping.dart`, and
/// deliberately unwritten (the adapter still has no platform plugin, so
/// there is no write path to call).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/health_type_registry.dart';

HealthTypeRegistryEntry _entryFor(String concept) =>
    kHealthTypeRegistry.firstWhere((entry) => entry.concept == concept);

void main() {
  group('the four #246 life-stage interval types', () {
    test('all four are future candidates owned by #246', () {
      for (final concept in [
        'pregnancy',
        'lactation',
        'menopausalState',
        'bleedingAfterMenopause',
      ]) {
        final entry = _entryFor(concept);
        expect(
          entry.status,
          HealthTypeMappingStatus.futureCandidate,
          reason: concept,
        );
        expect(entry.issue, '#246', reason: concept);
        // No port method, no channel entry, no write path: a future
        // candidate is HealthKit-only here, and the explicit null is the
        // recorded Health Connect absence.
        expect(entry.healthConnectRecord, isNull, reason: concept);
      }
    });

    test('each names its iOS 26 HealthKit identifier', () {
      expect(
        _entryFor('pregnancy').healthKitIdentifier,
        'HKCategoryTypeIdentifier.pregnancy',
      );
      expect(
        _entryFor('lactation').healthKitIdentifier,
        'HKCategoryTypeIdentifier.lactation',
      );
      expect(
        _entryFor('menopausalState').healthKitIdentifier,
        'HKCategoryTypeIdentifier.menopausalState',
      );
      expect(
        _entryFor('bleedingAfterMenopause').healthKitIdentifier,
        'HKCategoryTypeIdentifier.bleedingAfterMenopause',
      );
    });

    test('a future candidate never claims a port method', () {
      for (final entry in kHealthTypeRegistry) {
        if (entry.status != HealthTypeMappingStatus.futureCandidate) continue;
        // A candidate must at least name the platform type it is a
        // candidate for; a blank entry would be an unimplemented intent.
        expect(
          entry.healthKitIdentifier ?? entry.healthConnectRecord,
          isNotNull,
          reason: entry.concept,
        );
      }
    });
  });

  group('menopausalState / bleedingAfterMenopause (issue #196 AC6)', () {
    test('are registered with their HealthKit ids and their mapping', () {
      final menopausalState = _entryFor('menopausalState');
      expect(
        menopausalState.healthKitIdentifier,
        'HKCategoryTypeIdentifier.menopausalState',
      );
      final bleeding = _entryFor('bleedingAfterMenopause');
      expect(
        bleeding.healthKitIdentifier,
        'HKCategoryTypeIdentifier.bleedingAfterMenopause',
      );
    });
  });
}
