import { describe, expect, it } from 'vitest';

import { bbtUnitFromDb, weightUnitFromDb } from '../src/lib/day/measurements';

/**
 * The unit a stored measurement row is denominated in (#1287): the decode
 * degrades rather than throws — the same rule as the app's
 * `BbtUnit.fromDb`/`WeightUnit.fromDb` (lib/domain/models/measurement_unit.dart)
 * — because a row from an older client (unit null) or a future one (a unit
 * this build doesn't know) must still read back, at the default unit.
 */
describe('measurement unit decoding (#1287)', () => {
  it('bbtUnitFromDb maps the two CHECK-constrained units and degrades the rest to celsius', () => {
    expect(bbtUnitFromDb('fahrenheit')).toBe('fahrenheit');
    expect(bbtUnitFromDb('celsius')).toBe('celsius');
    expect(bbtUnitFromDb(null)).toBe('celsius');
    expect(bbtUnitFromDb('kelvin')).toBe('celsius');
  });

  it('weightUnitFromDb maps the two CHECK-constrained units and degrades the rest to kg', () => {
    expect(weightUnitFromDb('lb')).toBe('lb');
    expect(weightUnitFromDb('kg')).toBe('kg');
    expect(weightUnitFromDb(null)).toBe('kg');
    expect(weightUnitFromDb('stones')).toBe('kg');
  });
});
