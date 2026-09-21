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

    test('pregnancy and lactation are mapped future candidates owned by #246',
        () {
      // #246 landed the documented mappings
      // (lib/data/health/health_mode_interval_mapping.dart): the Modes
      // epic's pregnancy/perimenopause modes exist, so the entries moved
      // back from deliberatelyUnsupported to future candidates — mapped,
      // still unwritten, because the adapter has no platform plugin.
      for (final concept in ['pregnancy', 'lactation']) {
        final entry = _entryFor(concept);
        expect(
          entry.status,
          HealthTypeMappingStatus.futureCandidate,
          reason: concept,
        );
        expect(entry.issue, '#246', reason: concept);
        // The reason field is a deliberately-unsupported-only contract;
        // a future candidate documents through its mapping module instead.
        expect(entry.reason, isNull, reason: concept);
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
