import { describe, expect, it } from 'vitest';

import {
  bbtRangeIn,
  convertTemperature,
  convertWeight,
  formatMeasurementValue,
  isValidBbt,
  isValidWeight,
  weightRangeIn,
} from '../src/lib/day/measurements';

/**
 * The measurement sanity ranges (issue #1254) — the web port of the app's
 * #457 `measurement_validation.dart`. The same physical range must bite
 * identically in either unit; the conversions are the exact constants the
 * app uses (°F = °C×9/5+32; 1 lb = 0.45359237 kg).
 */
describe('measurements (issue #457, web port)', () => {
  it('accepts the generous human BBT range in Celsius', () => {
    expect(isValidBbt(34.0, 'celsius')).toBe(true);
    expect(isValidBbt(36.8, 'celsius')).toBe(true);
    expect(isValidBbt(42.0, 'celsius')).toBe(true);
    expect(isValidBbt(33.9, 'celsius')).toBe(false);
    expect(isValidBbt(42.1, 'celsius')).toBe(false);
  });

  it('validates the same physical range in Fahrenheit', () => {
    expect(isValidBbt(93.2, 'fahrenheit')).toBe(true); // 34.0 °C
    expect(isValidBbt(107.6, 'fahrenheit')).toBe(true); // 42.0 °C
    expect(isValidBbt(93.1, 'fahrenheit')).toBe(false);
    expect(isValidBbt(98.6, 'fahrenheit')).toBe(true); // a normal fever-free morning
  });

  it('accepts the weight range in kilograms', () => {
    expect(isValidWeight(10, 'kg')).toBe(true);
    expect(isValidWeight(65.5, 'kg')).toBe(true);
    expect(isValidWeight(300, 'kg')).toBe(true);
    expect(isValidWeight(9.9, 'kg')).toBe(false);
    expect(isValidWeight(300.1, 'kg')).toBe(false);
  });

  it('validates the same physical range in pounds', () => {
    expect(isValidWeight(22.05, 'lb')).toBe(true); // 10.0017 kg
    expect(isValidWeight(660, 'lb')).toBe(true); // 299.37 kg
    expect(isValidWeight(21.9, 'lb')).toBe(false); // 9.93 kg
    expect(isValidWeight(661.4, 'lb')).toBe(false); // 300.006 kg — a hair over
  });

  it('converts temperature both ways with the exact constants', () => {
    expect(convertTemperature(0, 'celsius', 'fahrenheit')).toBe(32);
    expect(convertTemperature(100, 'celsius', 'fahrenheit')).toBe(212);
    expect(convertTemperature(32, 'fahrenheit', 'celsius')).toBe(0);
    expect(convertTemperature(36.6, 'celsius', 'celsius')).toBe(36.6);
  });

  // Issue #1372: the conversion must be grouped exactly as the app's
  // `convertTemperature` groups it (lib/domain/models/measurement_unit.dart:74-75,
  // `value * 9 / 5 + 32` / `(value - 32) * 5 / 9`, left to right). Grouping
  // the division first — `value * (9 / 5)` — rounds 9/5 to a double that is
  // not the rational 9/5, sent the 42.0 °C ceiling to 107.60000000000001 °F,
  // and its back-conversion landed at 42.00000000000001 °C: over
  // MAX_BBT_CELSIUS, so a stored ceiling row read under a fahrenheit
  // profile failed isValidBbt and blocked every save of that day. The app
  // saves the same row fine; left-to-right grouping is bit-exact at the
  // bound, as the app's is.
  describe('the 42.0 °C boundary round trip (#1372)', () => {
    it('converts the ceiling bit-identically to the app grouping and back', () => {
      // `42 * 9 / 5 + 32` below is the app's own expression
      // (measurement_unit.dart:74) — toBe compares the exact doubles.
      expect(convertTemperature(42.0, 'celsius', 'fahrenheit')).toBe((42 * 9) / 5 + 32);
      expect(convertTemperature(42.0, 'celsius', 'fahrenheit')).not.toBe(42.0 * (9 / 5) + 32);
      expect(
        convertTemperature(
          convertTemperature(42.0, 'celsius', 'fahrenheit'),
          'fahrenheit',
          'celsius',
        ),
      ).toBe(42.0);
    });

    it('keeps a seeded ceiling row valid in fahrenheit', () => {
      // The exact value DayPage's editFromView seeds for a stored 42.0 °C
      // row on a fahrenheit profile — the value that used to fail.
      expect(isValidBbt(convertTemperature(42.0, 'celsius', 'fahrenheit'), 'fahrenheit')).toBe(
        true,
      );
      // And a ceiling typed in fahrenheit by hand.
      expect(isValidBbt(107.6, 'fahrenheit')).toBe(true);
    });

    it('keeps the 34.0 °C floor bit-exact through the round trip too', () => {
      expect(
        convertTemperature(
          convertTemperature(34.0, 'celsius', 'fahrenheit'),
          'fahrenheit',
          'celsius',
        ),
      ).toBe(34.0);
    });
  });

  it('converts weight with the 1959 pound agreement constant', () => {
    expect(convertWeight(1, 'kg', 'lb')).toBeCloseTo(2.2046226218487757, 12);
    expect(convertWeight(2.2046226218487757, 'lb', 'kg')).toBeCloseTo(1, 12);
    expect(convertWeight(70, 'kg', 'kg')).toBe(70);
  });

  it('renders the bounds in the entered unit', () => {
    expect(bbtRangeIn('fahrenheit').min).toBeCloseTo(93.2, 6);
    expect(bbtRangeIn('fahrenheit').max).toBeCloseTo(107.6, 6);
    expect(bbtRangeIn('celsius')).toEqual({ min: 34.0, max: 42.0 });
    expect(weightRangeIn('lb').min).toBeCloseTo(22.0462, 3);
    expect(weightRangeIn('kg')).toEqual({ min: 10, max: 300 });
  });

  // Issue #1339: the web port of the app's #457 formatMeasurementValue
  // (lib/ui/logging/day_sheet.dart:174) — a converted seed must never show
  // more spurious precision than a person would type by hand.
  describe('formatMeasurementValue', () => {
    it('rounds the raw conversion doubles to two decimals, trimming zeros', () => {
      // The exact doubles the issue names: 36.6 °C and 68 kg converted with
      // the real constants produce IEEE garbage digits; the display must not.
      expect(formatMeasurementValue((36.6 * 9) / 5 + 32)).toBe('97.88'); // 97.88000000000001
      expect(formatMeasurementValue((37 * 9) / 5 + 32)).toBe('98.6'); // 98.59999999999999
      expect(formatMeasurementValue(68 / 0.45359237)).toBe('149.91'); // 149.91433828571675
      expect(formatMeasurementValue(150 * 0.45359237)).toBe('68.04'); // 68.0388555
    });

    it('renders whole and one-decimal values without padding', () => {
      expect(formatMeasurementValue(37)).toBe('37');
      expect(formatMeasurementValue(61)).toBe('61');
      expect(formatMeasurementValue(36.7)).toBe('36.7');
      expect(formatMeasurementValue(36.75)).toBe('36.75');
    });

    it('breaks exact-half ties away from zero, matching Dart roundToDouble', () => {
      // 0.125 is exactly representable, so 0.125 × 100 = 12.5 is a true tie.
      expect(formatMeasurementValue(0.125)).toBe('0.13');
      // Math.round alone would round -12.5 toward +infinity (-12); the port
      // mirrors Dart's away-from-zero instead.
      expect(formatMeasurementValue(-0.125)).toBe('-0.13');
    });
  });
});
