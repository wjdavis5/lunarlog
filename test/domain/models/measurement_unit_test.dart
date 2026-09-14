/// Issue #255: the numeric-measurement display-unit enums and their pure
/// conversion helpers. A stored value always keeps the unit it was
/// entered/imported in; the per-profile preference only decides how it
/// renders, and `convertTemperature`/`convertWeight` are the only place
/// that translation happens.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';

void main() {
  group('BbtUnit', () {
    test('toDb produces the wire strings the CHECK constraint pins', () {
      expect(BbtUnit.celsius.toDb(), 'celsius');
      expect(BbtUnit.fahrenheit.toDb(), 'fahrenheit');
    });

    test('fromDb round-trips both values', () {
      for (final unit in BbtUnit.values) {
        expect(BbtUnit.fromDb(unit.toDb()), unit);
      }
    });

    test('fromDb degrades null, absent and unrecognised values to celsius',
        () {
      expect(BbtUnit.fromDb(null), BbtUnit.celsius);
      expect(BbtUnit.fromDb('kelvin'), BbtUnit.celsius);
      expect(BbtUnit.fromDb(''), BbtUnit.celsius);
    });
  });

  group('WeightUnit', () {
    test('toDb produces the wire strings the CHECK constraint pins', () {
      expect(WeightUnit.kg.toDb(), 'kg');
      expect(WeightUnit.lb.toDb(), 'lb');
    });

    test('fromDb round-trips both values', () {
      for (final unit in WeightUnit.values) {
        expect(WeightUnit.fromDb(unit.toDb()), unit);
      }
    });

    test('fromDb degrades null, absent and unrecognised values to kg', () {
      expect(WeightUnit.fromDb(null), WeightUnit.kg);
      expect(WeightUnit.fromDb('stone'), WeightUnit.kg);
      expect(WeightUnit.fromDb(''), WeightUnit.kg);
    });
  });

  group('convertTemperature', () {
    test('identical units return the value unchanged (no drift)', () {
      expect(convertTemperature(36.72, from: BbtUnit.celsius, to: BbtUnit.celsius),
          36.72);
      expect(
          convertTemperature(98.1,
              from: BbtUnit.fahrenheit, to: BbtUnit.fahrenheit),
          98.1);
    });

    test('celsius to fahrenheit', () {
      expect(
          convertTemperature(36.72,
              from: BbtUnit.celsius, to: BbtUnit.fahrenheit),
          closeTo(98.096, 1e-9));
      expect(convertTemperature(0, from: BbtUnit.celsius, to: BbtUnit.fahrenheit),
          32);
      expect(convertTemperature(100, from: BbtUnit.celsius, to: BbtUnit.fahrenheit),
          212);
    });

    test('fahrenheit to celsius', () {
      expect(
          convertTemperature(98.096,
              from: BbtUnit.fahrenheit, to: BbtUnit.celsius),
          closeTo(36.72, 1e-9));
      expect(convertTemperature(32, from: BbtUnit.fahrenheit, to: BbtUnit.celsius),
          0);
    });

    test('a celsius round trip through fahrenheit returns the origin', () {
      const origin = 36.55;
      final roundTrip = convertTemperature(
          convertTemperature(origin,
              from: BbtUnit.celsius, to: BbtUnit.fahrenheit),
          from: BbtUnit.fahrenheit,
          to: BbtUnit.celsius);
      expect(roundTrip, closeTo(origin, 1e-9));
    });
  });

  group('convertWeight', () {
    test('identical units return the value unchanged (no drift)', () {
      expect(convertWeight(61.2, from: WeightUnit.kg, to: WeightUnit.kg), 61.2);
      expect(convertWeight(134.9, from: WeightUnit.lb, to: WeightUnit.lb), 134.9);
    });

    test('kg to lb uses the exact 1959 pound definition', () {
      expect(convertWeight(1, from: WeightUnit.kg, to: WeightUnit.lb),
          closeTo(2.2046226218, 1e-9));
      expect(convertWeight(61.2, from: WeightUnit.kg, to: WeightUnit.lb),
          closeTo(134.9229044, 1e-6));
    });

    test('lb to kg', () {
      expect(convertWeight(1, from: WeightUnit.lb, to: WeightUnit.kg),
          closeTo(0.45359237, 1e-9));
      expect(convertWeight(134.9, from: WeightUnit.lb, to: WeightUnit.kg),
          closeTo(61.1896107, 1e-6));
    });
  });
}
