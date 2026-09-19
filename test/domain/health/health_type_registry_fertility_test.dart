/// Issue #228: the type registry's fertility/measurement entries. The
/// deliberately-unsupported entries carry a recorded reason so a future
/// reader can see the absence is a decision, not an oversight.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/health_type_registry.dart';

HealthTypeRegistryEntry _entryFor(String concept) =>
    kHealthTypeRegistry.firstWhere((entry) => entry.concept == concept);

void main() {
  group('implemented fertility/measurement entries (issue #228)', () {
    test('cervicalMucus is implemented on both platforms', () {
      final entry = _entryFor('cervicalMucus');
      expect(entry.status, HealthTypeMappingStatus.implemented);
      expect(
        entry.healthKitIdentifier,
        'HKCategoryTypeIdentifier.cervicalMucusQuality',
      );
      expect(entry.healthConnectRecord, 'CervicalMucusRecord');
      expect(entry.issue, '#228');
    });

    test('ovulationTest is implemented on both platforms', () {
      final entry = _entryFor('ovulationTest');
      expect(entry.status, HealthTypeMappingStatus.implemented);
      expect(
        entry.healthKitIdentifier,
        'HKCategoryTypeIdentifier.ovulationTestResult',
      );
      expect(entry.healthConnectRecord, 'OvulationTestRecord');
      expect(entry.issue, '#228');
    });

    test('basalBodyTemperature is implemented as a quantity type', () {
      final entry = _entryFor('basalBodyTemperature');
      expect(entry.status, HealthTypeMappingStatus.implemented);
      expect(
        entry.healthKitIdentifier,
        'HKQuantityTypeIdentifier.basalBodyTemperature',
      );
      expect(entry.healthConnectRecord, 'BasalBodyTemperatureRecord');
      expect(entry.issue, '#228');
    });
  });

  group('deliberately unsupported entries', () {
    test('pregnancyTestResult and progesteroneTestResult carry a reason', () {
      for (final concept in ['pregnancyTestResult', 'progesteroneTestResult']) {
        final entry = _entryFor(concept);
        expect(
          entry.status,
          HealthTypeMappingStatus.deliberatelyUnsupported,
          reason: concept,
        );
        expect(entry.issue, '#228', reason: concept);
        expect(entry.reason, isNotEmpty, reason: concept);
      }
    });

    test('pregnancy and lactation are sequenced behind the Modes epic', () {
      for (final concept in ['pregnancy', 'lactation']) {
        final entry = _entryFor(concept);
        expect(
          entry.status,
          HealthTypeMappingStatus.deliberatelyUnsupported,
          reason: concept,
        );
        expect(entry.issue, '#246', reason: concept);
        expect(entry.reason, contains('Modes'), reason: concept);
      }
    });

    test('every deliberately-unsupported entry records a reason', () {
      for (final entry in kHealthTypeRegistry) {
        if (entry.status != HealthTypeMappingStatus.deliberatelyUnsupported) {
          continue;
        }
        expect(
          entry.reason,
          isNotNull,
          reason: '${entry.concept} must record why it is not mapped',
        );
        expect(entry.reason, isNotEmpty, reason: entry.concept);
      }
    });

    test('a deliberately-unsupported entry never claims a port method', () {
      // Kept distinct from futureCandidate: unsupported means "not now, by
      // decision", but it must still name the platform type the decision is
      // about where one exists.
      for (final entry in kHealthTypeRegistry) {
        if (entry.status != HealthTypeMappingStatus.deliberatelyUnsupported) {
          continue;
        }
        expect(entry.healthKitIdentifier ?? entry.healthConnectRecord, isNotNull,
            reason: entry.concept);
      }
    });
  });
}
