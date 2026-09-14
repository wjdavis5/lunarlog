/// Issue #457: the BBT/weight sanity-range validation this app's own
/// manual entry form gates against. Not a server-enforced range (see
/// `measurement_validation.dart`'s own doc comment) — these tests exercise
/// the boundaries and the unit-aware conversion, not a database constraint.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/measurement_validation.dart';

void main() {
  group('isValidBbt', () {
    test('accepts the inclusive Celsius bounds', () {
      expect(isValidBbt(kMinBbtCelsius, BbtUnit.celsius), isTrue);
      expect(isValidBbt(kMaxBbtCelsius, BbtUnit.celsius), isTrue);
    });

    test('rejects just outside the Celsius bounds', () {
      expect(isValidBbt(kMinBbtCelsius - 0.1, BbtUnit.celsius), isFalse);
      expect(isValidBbt(kMaxBbtCelsius + 0.1, BbtUnit.celsius), isFalse);
    });

    test('a typical BBT reading is valid in both units', () {
      expect(isValidBbt(36.7, BbtUnit.celsius), isTrue);
      expect(isValidBbt(98.1, BbtUnit.fahrenheit), isTrue);
    });

    test('validates a Fahrenheit-entered value against the same physical '
        'range as the Celsius bounds (converts before checking)', () {
      // kMaxBbtCelsius (42.0C) is 107.6F.
      expect(isValidBbt(107.6, BbtUnit.fahrenheit), isTrue);
      expect(isValidBbt(107.7, BbtUnit.fahrenheit), isFalse);
    });

    test('rejects an obvious typo-class value (an extra digit)', () {
      expect(isValidBbt(367.0, BbtUnit.celsius), isFalse);
    });
  });

  group('isValidWeight', () {
    test('accepts the inclusive kg bounds', () {
      expect(isValidWeight(kMinWeightKg, WeightUnit.kg), isTrue);
      expect(isValidWeight(kMaxWeightKg, WeightUnit.kg), isTrue);
    });

    test('rejects just outside the kg bounds', () {
      expect(isValidWeight(kMinWeightKg - 0.1, WeightUnit.kg), isFalse);
      expect(isValidWeight(kMaxWeightKg + 0.1, WeightUnit.kg), isFalse);
    });

    test('a typical adult weight is valid in both units', () {
      expect(isValidWeight(61.2, WeightUnit.kg), isTrue);
      expect(isValidWeight(135.0, WeightUnit.lb), isTrue);
    });

    test('rejects an obvious typo-class value (an extra digit)', () {
      expect(isValidWeight(3000.0, WeightUnit.kg), isFalse);
    });

    test('rejects a non-positive weight', () {
      expect(isValidWeight(0, WeightUnit.kg), isFalse);
      expect(isValidWeight(-5, WeightUnit.kg), isFalse);
    });
  });

  group('bbtRangeIn / weightRangeIn', () {
    test('bbtRangeIn(celsius) returns the raw canonical bounds unchanged',
        () {
      final (min, max) = bbtRangeIn(BbtUnit.celsius);
      expect(min, kMinBbtCelsius);
      expect(max, kMaxBbtCelsius);
    });

    test('bbtRangeIn(fahrenheit) converts both bounds', () {
      final (min, max) = bbtRangeIn(BbtUnit.fahrenheit);
      expect(min, closeTo(93.2, 1e-9));
      expect(max, closeTo(107.6, 1e-9));
    });

    test('weightRangeIn(kg) returns the raw canonical bounds unchanged', () {
      final (min, max) = weightRangeIn(WeightUnit.kg);
      expect(min, kMinWeightKg);
      expect(max, kMaxWeightKg);
    });

    test('weightRangeIn(lb) converts both bounds', () {
      final (min, max) = weightRangeIn(WeightUnit.lb);
      expect(min, closeTo(22.046226, 1e-4));
      expect(max, closeTo(661.386787, 1e-4));
    });
  });
}
