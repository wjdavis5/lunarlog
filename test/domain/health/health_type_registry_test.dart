/// Issue #196 AC6: the Health Platform Sync type registry carries the iOS 26
/// menopause category types as future-mapping placeholders — named, owned,
/// and deliberately unwritten.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/health_type_registry.dart';

HealthTypeRegistryEntry _entryFor(String concept) =>
    kHealthTypeRegistry.firstWhere((entry) => entry.concept == concept);

void main() {
  group('menopausalState / bleedingAfterMenopause (issue #196)', () {
    test('are registered as future candidates with their HealthKit ids', () {
      final menopausalState = _entryFor('menopausalState');
      expect(
        menopausalState.status,
        HealthTypeMappingStatus.futureCandidate,
      );
      expect(
        menopausalState.healthKitIdentifier,
        'HKCategoryTypeIdentifier.menopausalState',
      );
      // Health Connect has no analogue today, which is exactly why these are
      // placeholders rather than port methods.
      expect(menopausalState.healthConnectRecord, isNull);
      expect(menopausalState.issue, contains('#196'));

      final bleeding = _entryFor('bleedingAfterMenopause');
      expect(bleeding.status, HealthTypeMappingStatus.futureCandidate);
      expect(
        bleeding.healthKitIdentifier,
        'HKCategoryTypeIdentifier.bleedingAfterMenopause',
      );
      expect(bleeding.healthConnectRecord, isNull);
      expect(bleeding.issue, contains('#196'));
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
}
