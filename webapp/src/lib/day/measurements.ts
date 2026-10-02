/**
 * Measurement sanity ranges for the day editor's BBT and weight fields
 * (issue #1254) — a faithful port of `lib/domain/models/measurement_validation.dart`
 * (issue #457) and its `measurement_unit.dart` conversions.
 *
 * The bounds are a UX floor/ceiling only — they catch the extra-digit
 * typo class before a value is written, never assert what is medically
 * normal. There is no server CHECK mirroring them: `observations.value_num`
 * accepts any numeric value by design, so an imported value outside these
 * bounds still round-trips untouched — only this form is gated.
 *
 * Bounds are defined in each measurement's canonical unit (Celsius,
 * kilograms) and validated after conversion, so a value typed in Fahrenheit
 * or pounds is validated exactly as strictly as the same physical value
 * typed in Celsius or kilograms.
 */

export type BbtUnit = 'celsius' | 'fahrenheit';
export type WeightUnit = 'kg' | 'lb';

/**
 * The unit a stored temperature value is denominated in (`observations.unit`
 * or `profiles.bbt_unit`) — an unrecognised or null value degrades to the
 * default (Celsius) rather than throwing, the same rule as the app's
 * `BbtUnit.fromDb` (lib/domain/models/measurement_unit.dart): a value this
 * build doesn't recognise must fall back, never crash a pull.
 */
export function bbtUnitFromDb(value: string | null | undefined): BbtUnit {
  return value === 'fahrenheit' ? 'fahrenheit' : 'celsius';
}

/** The weight counterpart of [bbtUnitFromDb] (default kilograms). */
export function weightUnitFromDb(value: string | null | undefined): WeightUnit {
  return value === 'lb' ? 'lb' : 'kg';
}

/** Basal body temperature sanity floor/ceiling, in Celsius (34.0-42.0 °C). */
export const MIN_BBT_CELSIUS = 34.0;
export const MAX_BBT_CELSIUS = 42.0;

/** Weight sanity floor/ceiling, in kilograms (10-300 kg). */
export const MIN_WEIGHT_KG = 10.0;
export const MAX_WEIGHT_KG = 300.0;

/**
 * Converts a temperature between the two BBT units. The arithmetic is
 * grouped exactly as the app's `convertTemperature` groups it
 * (lib/domain/models/measurement_unit.dart:74-75 — `value * 9 / 5 + 32`
 * and `(value - 32) * 5 / 9`, left to right), never as
 * `value * (9 / 5) + 32`: `9 / 5` rounds to a double that is not the
 * rational 9/5, so dividing first sent 42.0 °C to 107.60000000000001 °F
 * where the app produces 107.6, and the round trip back landed at
 * 42.00000000000001 °C — a hair over MAX_BBT_CELSIUS, so isValidBbt
 * rejected a stored boundary row and every save of that day, even a
 * tag-only change, threw the generic save-failed banner (issue #1372).
 * Same-shape grouping keeps each direction bit-identical to the app, so
 * the web and the phone always agree on what a stored row means.
 */
export function convertTemperature(value: number, from: BbtUnit, to: BbtUnit): number {
  if (from === to) return value;
  if (from === 'celsius' && to === 'fahrenheit') return (value * 9) / 5 + 32;
  return ((value - 32) * 5) / 9;
}

/** Converts a weight between the two weight units (1 lb = 0.45359237 kg). */
export function convertWeight(value: number, from: WeightUnit, to: WeightUnit): number {
  if (from === to) return value;
  if (from === 'kg' && to === 'lb') return value / 0.45359237;
  return value * 0.45359237;
}

/** Whether [value], denominated in [unit], falls within the BBT sanity range. */
export function isValidBbt(value: number, unit: BbtUnit): boolean {
  const celsius = convertTemperature(value, unit, 'celsius');
  return celsius >= MIN_BBT_CELSIUS && celsius <= MAX_BBT_CELSIUS;
}

/** Whether [value], denominated in [unit], falls within the weight sanity range. */
export function isValidWeight(value: number, unit: WeightUnit): boolean {
  const kg = convertWeight(value, unit, 'kg');
  return kg >= MIN_WEIGHT_KG && kg <= MAX_WEIGHT_KG;
}

/**
 * Formats a BBT/weight value for display in a day editor input (issue
 * #1339) — the web port of the app's `formatMeasurementValue`
 * (lib/ui/logging/day_sheet.dart:174, issue #457): up to two decimal
 * places, trailing zeros trimmed, so a converted seed (36.6 °C reads back
 * as 97.88000000000001 °F in IEEE doubles) never shows more spurious
 * precision than a person would type by hand. Display only: callers keep
 * the unrounded double as the edit state, so the save plan's
 * untouched-field comparison (payloads.ts's `storedMeasurementEquals`)
 * stays bit-exact and saving emits no write for an untouched field.
 */
export function formatMeasurementValue(value: number): string {
  // `(value * 100).roundToDouble() / 100` — Dart's roundToDouble breaks
  // exact-half ties away from zero, so mirror that instead of Math.round's
  // toward-+infinity tie-break.
  const scaled = value * 100;
  const rounded = (scaled < 0 ? -Math.round(-scaled) : Math.round(scaled)) / 100;
  const fixed = rounded.toFixed(2);
  if (fixed.endsWith('.00')) {
    return rounded.toFixed(0);
  }
  if (fixed.endsWith('0')) {
    return rounded.toFixed(1);
  }
  return fixed;
}

/** The BBT sanity range rendered in [unit], for the field's error message. */
export function bbtRangeIn(unit: BbtUnit): { min: number; max: number } {
  return {
    min: convertTemperature(MIN_BBT_CELSIUS, 'celsius', unit),
    max: convertTemperature(MAX_BBT_CELSIUS, 'celsius', unit),
  };
}

/** The weight sanity range rendered in [unit], same contract as [bbtRangeIn]. */
export function weightRangeIn(unit: WeightUnit): { min: number; max: number } {
  return {
    min: convertWeight(MIN_WEIGHT_KG, 'kg', unit),
    max: convertWeight(MAX_WEIGHT_KG, 'kg', unit),
  };
}
