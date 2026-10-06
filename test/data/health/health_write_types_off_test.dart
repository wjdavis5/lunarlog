// Issue #1581: which write types are switched off, from what the health
// store says is switched on. The write pass moves each such type's floor.

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_symptom_mapping.dart';
import 'package:lunarlog/data/health/health_written_types.dart';
import 'package:lunarlog/domain/health/health_platform.dart';

void main() {
  final symptomTypes = kSymptomHealthKitTypeIdentifiers.values.toSet();

  test('with every type on (no list at all), none is off', () {
    expect(healthWriteTypesOff(null), isEmpty);
  });

  test('with nothing on, every type is off: the five the pass names and '
      'each symptom type', () {
    expect(healthWriteTypesOff(const {}), {
      HealthWriteTypes.menstrualFlow,
      HealthWriteTypes.spotting,
      HealthWriteTypes.cervicalMucus,
      HealthWriteTypes.ovulationTest,
      HealthWriteTypes.basalBodyTemperature,
      ...symptomTypes,
    });
  });

  // Health Connect has no symptom types, so its list never names one.
  test('a list of the five named types leaves every symptom type off', () {
    expect(
      healthWriteTypesOff(const {
        HealthWriteTypes.menstrualFlow,
        HealthWriteTypes.spotting,
        HealthWriteTypes.cervicalMucus,
        HealthWriteTypes.ovulationTest,
        HealthWriteTypes.basalBodyTemperature,
      }),
      symptomTypes,
    );
  });

  test('a named type that is missing is off, and only that one', () {
    final off = healthWriteTypesOff({
      HealthWriteTypes.menstrualFlow,
      HealthWriteTypes.spotting,
      HealthWriteTypes.ovulationTest,
      HealthWriteTypes.basalBodyTemperature,
      HealthWriteTypes.symptoms,
    });
    expect(off, {HealthWriteTypes.cervicalMucus});
  });

  // HealthKit grants symptom types one by one; all of them at once reads
  // as the one name.
  test('symptom types are off one by one, unless all are on', () {
    final some = healthWriteTypesOff({
      HealthWriteTypes.menstrualFlow,
      'headache',
    });
    expect(some, contains('abdominalCramps'));
    expect(some, isNot(contains('headache')));

    final all = healthWriteTypesOff({HealthWriteTypes.symptoms});
    expect(all.intersection(symptomTypes), isEmpty);
    expect(all, isNot(contains(HealthWriteTypes.symptoms)));
  });
}
