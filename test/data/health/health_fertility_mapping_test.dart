/// Issue #228: the pure fertility-signal (cervical mucus, ovulation test)
/// and BBT → OS-health-store mapping. The load-bearing assertion is the
/// completeness partition — every live `discharge` and `tests` code must be
/// mapped, explicitly unsupported, or explicitly not-exported, so a future
/// taxonomy addition fails this suite instead of silently vanishing from
/// the health export. BBT's source separation is pinned here too: a
/// platform- or wearable-sourced value must never resolve to a write.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_fertility_mapping.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/tags.dart';

Set<String> _codesIn(TagCategory category) => {
  for (final tag in kTagTaxonomy)
    if (tag.category == category) tag.code,
};

Observation _bbt({
  double? value = 36.6,
  String? unit = 'celsius',
  bool excluded = false,
  ObservationSource source = ObservationSource.manual,
  String category = 'bbt',
}) => Observation(
  id: 'obs-1',
  dayEntryId: 'entry-1',
  profileId: 'p1',
  localDate: LocalDate(2026, 6, 2),
  tz: 'America/New_York',
  category: category,
  valueNum: value,
  unit: unit,
  excluded: excluded,
  source: source,
  updatedAt: DateTime.utc(2026, 6, 2),
);

void main() {
  group('the cervical-mucus mapping is the full, live discharge partition',
      () {
    test('mapped + unsupported + not-exported covers every discharge code',
        () {
      final classified = <String>{
        ...kCervicalMucusHealthKitValues.keys,
        ...kUnsupportedCervicalMucusTags.keys,
        ...kNotExportedCervicalMucusTags,
      };
      expect(
        classified,
        _codesIn(TagCategory.discharge),
        reason:
            'a discharge code added without a mapping decision must fail '
            'here rather than vanish from the Health export',
      );
    });

    test('the HealthKit and Health Connect tables cover the same codes', () {
      expect(
        kCervicalMucusHealthKitValues.keys.toSet(),
        kCervicalMucusHealthConnectAppearances.keys.toSet(),
      );
    });

    test('the three sets are pairwise disjoint', () {
      final mapped = kCervicalMucusHealthKitValues.keys.toSet();
      final unsupported = kUnsupportedCervicalMucusTags.keys.toSet();
      expect(mapped.intersection(unsupported), isEmpty);
      expect(mapped.intersection(kNotExportedCervicalMucusTags), isEmpty);
      expect(unsupported.intersection(kNotExportedCervicalMucusTags), isEmpty);
    });

    test('every mapped code is a real live discharge code', () {
      final live = _codesIn(TagCategory.discharge);
      expect(kCervicalMucusHealthKitValues.keys.every(live.contains), isTrue);
      expect(
        kCervicalMucusHealthConnectAppearances.keys.every(live.contains),
        isTrue,
      );
    });
  });

  group('cervical-mucus direct mappings', () {
    const expectedHealthKit = {
      'sticky': 'sticky',
      'creamy': 'creamy',
      'egg_white': 'eggWhite',
    };
    const expectedHealthConnect = {
      'sticky': 'APPEARANCE_STICKY',
      'creamy': 'APPEARANCE_CREAMY',
      'egg_white': 'APPEARANCE_EGG_WHITE',
    };

    for (final entry in expectedHealthKit.entries) {
      test('${entry.key} -> HealthKit ${entry.value}', () {
        expect(kCervicalMucusHealthKitValues[entry.key], entry.value);
      });
    }
    for (final entry in expectedHealthConnect.entries) {
      test('${entry.key} -> Health Connect ${entry.value}', () {
        expect(kCervicalMucusHealthConnectAppearances[entry.key], entry.value);
      });
    }
  });

  group('deliberately unsupported / not-exported cervical mucus', () {
    test('atypical is unsupported with a documented reason', () {
      final reason = kUnsupportedCervicalMucusTags['atypical'];
      expect(reason, isNotNull);
      expect(reason, contains('HealthKit'));
      expect(kCervicalMucusHealthKitValues.containsKey('atypical'), isFalse);
      expect(
        kCervicalMucusHealthConnectAppearances.containsKey('atypical'),
        isFalse,
      );
    });

    test('none is a positive assertion, not exported', () {
      expect(kNotExportedCervicalMucusTags, contains('none'));
      expect(kCervicalMucusHealthKitValues.containsKey('none'), isFalse);
    });
  });

  group('the ovulation mapping is the full, live tests partition', () {
    test('mapped + unsupported + not-exported covers every tests code', () {
      final classified = <String>{
        ...kOvulationTestHealthKitResults.keys,
        ...kUnsupportedOvulationTestTags.keys,
      };
      expect(
        classified,
        _codesIn(TagCategory.tests),
        reason:
            'a tests code added without a mapping decision must fail here '
            'rather than vanish from the Health export',
      );
    });

    test('the HealthKit and Health Connect tables cover the same codes', () {
      expect(
        kOvulationTestHealthKitResults.keys.toSet(),
        kOvulationTestHealthConnectResults.keys.toSet(),
      );
    });

    test('the mapped and unsupported sets are disjoint', () {
      final mapped = kOvulationTestHealthKitResults.keys.toSet();
      final unsupported = kUnsupportedOvulationTestTags.keys.toSet();
      expect(mapped.intersection(unsupported), isEmpty);
    });

    test('every mapped code is a real live tests code', () {
      final live = _codesIn(TagCategory.tests);
      expect(kOvulationTestHealthKitResults.keys.every(live.contains), isTrue);
      expect(
        kOvulationTestHealthConnectResults.keys.every(live.contains),
        isTrue,
      );
    });
  });

  group('ovulation-test direct mappings', () {
    const expectedHealthKit = {
      'ovulation_negative': 'negative',
      'ovulation_positive': 'luteinizingHormoneSurge',
      'ovulation_peak': 'luteinizingHormoneSurge',
    };
    const expectedHealthConnect = {
      'ovulation_negative': 'RESULT_NEGATIVE',
      'ovulation_positive': 'RESULT_POSITIVE',
      'ovulation_peak': 'RESULT_POSITIVE',
    };

    for (final entry in expectedHealthKit.entries) {
      test('${entry.key} -> HealthKit ${entry.value}', () {
        expect(kOvulationTestHealthKitResults[entry.key], entry.value);
      });
    }
    for (final entry in expectedHealthConnect.entries) {
      test('${entry.key} -> Health Connect ${entry.value}', () {
        expect(kOvulationTestHealthConnectResults[entry.key], entry.value);
      });
    }
  });

  group('deliberately unsupported ovulation values', () {
    test('pregnancy tests are unsupported with a documented reason', () {
      for (final code in ['pregnancy_negative', 'pregnancy_positive']) {
        final reason = kUnsupportedOvulationTestTags[code];
        expect(reason, isNotNull, reason: '$code must be explicitly handled');
        expect(reason, contains('pregnancyTestResult'));
        expect(kOvulationTestHealthKitResults.containsKey(code), isFalse);
      }
    });

    test('estrogenSurge / RESULT_HIGH have no live domain source', () {
      expect(kUnsupportedOvulationHealthKitResults, contains('estrogenSurge'));
      expect(
        kUnsupportedOvulationHealthConnectResults,
        contains('RESULT_HIGH'),
      );
      // No mapped live code ever produces them.
      expect(
        kOvulationTestHealthKitResults.values,
        isNot(contains('estrogenSurge')),
      );
      expect(
        kOvulationTestHealthConnectResults.values,
        isNot(contains('RESULT_HIGH')),
      );
    });
  });

  group('classifiers are total', () {
    test('classifyCervicalMucusExport', () {
      final mapped = classifyCervicalMucusExport('egg_white');
      expect(mapped, isA<CervicalMucusHealthMapped>());
      expect(
        (mapped as CervicalMucusHealthMapped).healthKitValue,
        'eggWhite',
      );
      expect(
        mapped.healthConnectAppearance,
        'APPEARANCE_EGG_WHITE',
      );
      expect(
        classifyCervicalMucusExport('atypical'),
        isA<CervicalMucusHealthUnsupported>(),
      );
      expect(
        classifyCervicalMucusExport('none'),
        isA<CervicalMucusHealthNotExported>(),
      );
      expect(
        classifyCervicalMucusExport('a_custom_registry_tag'),
        isA<CervicalMucusHealthNotExported>(),
      );
    });

    test('classifyOvulationTestExport', () {
      final mapped = classifyOvulationTestExport('ovulation_positive');
      expect(mapped, isA<OvulationTestHealthMapped>());
      expect(
        (mapped as OvulationTestHealthMapped).healthKitResult,
        'luteinizingHormoneSurge',
      );
      expect(mapped.healthConnectResult, 'RESULT_POSITIVE');
      expect(
        classifyOvulationTestExport('pregnancy_positive'),
        isA<OvulationTestHealthUnsupported>(),
      );
      expect(
        classifyOvulationTestExport('a_custom_registry_tag'),
        isA<OvulationTestHealthNotExported>(),
      );
    });
  });

  group('resolveCervicalMucus', () {
    test('maps the discharge code and ignores non-discharge tags', () {
      final resolved = resolveCervicalMucus(const ['cramps', 'creamy']);
      expect(resolved, isNotNull);
      expect(resolved!.tagCode, 'creamy');
      expect(resolved.healthKitValue, 'creamy');
      expect(resolved.healthConnectAppearance, 'APPEARANCE_CREAMY');
    });

    test('none/atypical and unknown tags produce no sample', () {
      expect(resolveCervicalMucus(const ['none', 'atypical']), isNull);
      expect(resolveCervicalMucus(const ['unknown_code']), isNull);
      expect(resolveCervicalMucus(const []), isNull);
    });
  });

  group('resolveOvulationTests', () {
    test('positive and peak dedupe to one luteinizingHormoneSurge sample',
        () {
      final resolved = resolveOvulationTests(
        const ['ovulation_positive', 'ovulation_peak'],
      );
      expect(resolved, hasLength(1));
      expect(resolved.single.healthKitResult, 'luteinizingHormoneSurge');
      expect(resolved.single.healthConnectResult, 'RESULT_POSITIVE');
    });

    test('negative and positive produce two distinct samples', () {
      final resolved = resolveOvulationTests(
        const ['ovulation_negative', 'ovulation_positive'],
      );
      expect(resolved, hasLength(2));
      expect(
        resolved.map((r) => r.healthKitResult).toSet(),
        {'negative', 'luteinizingHormoneSurge'},
      );
    });

    test('pregnancy and unexported tags contribute nothing', () {
      expect(
        resolveOvulationTests(
          const ['pregnancy_positive', 'running', 'unknown_code'],
        ),
        isEmpty,
      );
    });
  });

  group('resolveBasalBodyTemperature', () {
    test('a manual Celsius value resolves to Celsius with unknown location',
        () {
      final resolved = resolveBasalBodyTemperature(_bbt());
      expect(resolved, isNotNull);
      expect(resolved!.celsius, closeTo(36.6, 1e-9));
      expect(
        resolved.healthConnectMeasurementLocation,
        kBbtHealthConnectMeasurementLocationUnknown,
      );
      expect(resolved.source, ObservationSource.manual);
    });

    test('a Fahrenheit value is converted to Celsius', () {
      final resolved = resolveBasalBodyTemperature(
        _bbt(value: 98.6, unit: 'fahrenheit'),
      );
      expect(resolved!.celsius, closeTo(37.0, 1e-9));
    });

    test('a null/unknown unit degrades to Celsius (never mis-denominated)',
        () {
      expect(
        resolveBasalBodyTemperature(_bbt(value: 36.5, unit: null))!.celsius,
        closeTo(36.5, 1e-9),
      );
      expect(
        resolveBasalBodyTemperature(_bbt(value: 36.5, unit: 'kelvin'))!.celsius,
        closeTo(36.5, 1e-9),
      );
    });

    test('a clue-import value resolves (still manually tracked)', () {
      final resolved = resolveBasalBodyTemperature(
        _bbt(source: ObservationSource.clueImport),
      );
      expect(resolved, isNotNull);
      expect(resolved!.source, ObservationSource.clueImport);
    });

    test('a platform- or wearable-sourced value NEVER resolves', () {
      for (final source in [
        ObservationSource.appleHealth,
        ObservationSource.healthConnect,
        ObservationSource.wearable,
      ]) {
        expect(
          resolveBasalBodyTemperature(_bbt(source: source)),
          isNull,
          reason: '$source must be kept separate from manually tracked BBT',
        );
      }
    });

    test('an excluded point is not written (the operator marked an outlier)',
        () {
      expect(resolveBasalBodyTemperature(_bbt(excluded: true)), isNull);
    });

    test('a non-bbt category or missing value never resolves', () {
      expect(
        resolveBasalBodyTemperature(_bbt(category: 'weight')),
        isNull,
      );
      expect(resolveBasalBodyTemperature(_bbt(value: null)), isNull);
    });

    test('isManuallyTrackedBbtSource classifies the whole enum', () {
      expect(isManuallyTrackedBbtSource(ObservationSource.manual), isTrue);
      expect(isManuallyTrackedBbtSource(ObservationSource.clueImport), isTrue);
      expect(isManuallyTrackedBbtSource(ObservationSource.appleHealth), isFalse);
      expect(isManuallyTrackedBbtSource(ObservationSource.healthConnect), isFalse);
      expect(isManuallyTrackedBbtSource(ObservationSource.wearable), isFalse);
    });
  });

  group('resolved value equality', () {
    test('ResolvedCervicalMucus compares by value', () {
      const a = ResolvedCervicalMucus(
        tagCode: 'creamy',
        healthKitValue: 'creamy',
        healthConnectAppearance: 'APPEARANCE_CREAMY',
      );
      const b = ResolvedCervicalMucus(
        tagCode: 'creamy',
        healthKitValue: 'creamy',
        healthConnectAppearance: 'APPEARANCE_CREAMY',
      );
      const different = ResolvedCervicalMucus(
        tagCode: 'sticky',
        healthKitValue: 'sticky',
        healthConnectAppearance: 'APPEARANCE_STICKY',
      );
      expect(a == a, isTrue);
      expect(a == b, isTrue);
      expect(a == different, isFalse);
      expect(a == Object(), isFalse);
      expect(a.hashCode, b.hashCode);
    });

    test('ResolvedOvulationTest compares by value', () {
      const a = ResolvedOvulationTest(
        tagCode: 'ovulation_positive',
        healthKitResult: 'luteinizingHormoneSurge',
        healthConnectResult: 'RESULT_POSITIVE',
      );
      const b = ResolvedOvulationTest(
        tagCode: 'ovulation_positive',
        healthKitResult: 'luteinizingHormoneSurge',
        healthConnectResult: 'RESULT_POSITIVE',
      );
      const different = ResolvedOvulationTest(
        tagCode: 'ovulation_negative',
        healthKitResult: 'negative',
        healthConnectResult: 'RESULT_NEGATIVE',
      );
      expect(a == a, isTrue);
      expect(a == b, isTrue);
      expect(a == different, isFalse);
      expect(a == Object(), isFalse);
      expect(a.hashCode, b.hashCode);
    });

    test('ResolvedBasalBodyTemperature compares by value', () {
      const a = ResolvedBasalBodyTemperature(
        celsius: 36.6,
        healthConnectMeasurementLocation: 'MEASUREMENT_LOCATION_UNKNOWN',
        source: ObservationSource.manual,
      );
      const b = ResolvedBasalBodyTemperature(
        celsius: 36.6,
        healthConnectMeasurementLocation: 'MEASUREMENT_LOCATION_UNKNOWN',
        source: ObservationSource.manual,
      );
      const different = ResolvedBasalBodyTemperature(
        celsius: 37.0,
        healthConnectMeasurementLocation: 'MEASUREMENT_LOCATION_UNKNOWN',
        source: ObservationSource.manual,
      );
      expect(a == a, isTrue);
      expect(a == b, isTrue);
      expect(a == different, isFalse);
      expect(a == Object(), isFalse);
      expect(a.hashCode, b.hashCode);
    });
  });
}
