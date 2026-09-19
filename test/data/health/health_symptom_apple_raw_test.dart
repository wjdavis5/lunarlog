/// Issue #238: pins the canonical Apple `HKCategoryValueSeverity` raw-value
/// table this repo has no automated way to check `AppDelegate.swift`'s
/// `SymptomSeverityRawValue` enum against — see
/// `kHealthSymptomSeverityAppleRawValue`'s doc comment in
/// `health_channel_codec.dart` for why (no Swift XCTest target runs in CI).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_channel_codec.dart';
import 'package:lunarlog/domain/health/health_platform.dart';

void main() {
  test(
    'every HealthSymptomSeverity has exactly one canonical Apple raw value',
    () {
      expect(
        kHealthSymptomSeverityAppleRawValue.keys.toSet(),
        HealthSymptomSeverity.values.toSet(),
      );
    },
  );

  test('the canonical values match HKCategoryValueSeverity rather than being '
      'assumed from memory', () {
    expect(kHealthSymptomSeverityAppleRawValue[HealthSymptomSeverity.mild], 1);
    expect(
      kHealthSymptomSeverityAppleRawValue[HealthSymptomSeverity.moderate],
      2,
    );
    expect(
      kHealthSymptomSeverityAppleRawValue[HealthSymptomSeverity.severe],
      3,
    );
    expect(
      kHealthSymptomSeverityAppleRawValue[HealthSymptomSeverity.unspecified],
      4,
    );
  });

  test(
    'every raw value is unique and none is 0 — HKCategoryValue.notApplicable, '
    'a different shared "no value" concept, is never written',
    () {
      final values = kHealthSymptomSeverityAppleRawValue.values.toList();
      expect(values.toSet().length, values.length);
      expect(values, isNot(contains(0)));
    },
  );

  test('the wire strings round-trip and an unknown string parses to null', () {
    for (final severity in HealthSymptomSeverity.values) {
      expect(HealthSymptomSeverity.fromWire(severity.toWire()), severity);
    }
    expect(HealthSymptomSeverity.fromWire('notARealSeverity'), isNull);
    expect(HealthSymptomSeverity.fromWire(null), isNull);
  });
}
