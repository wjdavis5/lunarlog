import { describe, expect, it } from 'vitest';

import {
  bbtRangeIn,
  convertTemperature,
  convertWeight,
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
});
