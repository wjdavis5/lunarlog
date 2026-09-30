import { describe, expect, it } from 'vitest';

import {
  browserTimeZone,
  isIsoLocalDate,
  todayInBrowserZone,
  validateDayDate,
} from '../src/lib/day/day-entry-policy';

/**
 * The date-bounds policy (issue #1254) — the web port of the app's #848
 * `DayEntryPolicy.validateDate`, which is the same rule the server's
 * `sync_push` enforces (`20260919160000_day_entry_date_bounds.sql`).
 * Parity with the Dart original is the point: both cases, both edges.
 */
describe('validateDayDate (issue #848, web port)', () => {
  it('accepts today and yesterday', () => {
    expect(validateDayDate('2026-09-30', '2026-09-30', null).valid).toBe(true);
    expect(validateDayDate('2026-09-29', '2026-09-30', null).valid).toBe(true);
  });

  it('tolerates exactly one day ahead (time-zone travel)', () => {
    expect(validateDayDate('2026-10-01', '2026-09-30', null).valid).toBe(true);
  });

  it('rejects two days ahead', () => {
    const result = validateDayDate('2026-10-02', '2026-09-30', null);
    expect(result).toEqual({ valid: false, violation: 'futureDate' });
  });

  it('rejects a date before the birth year, by year only', () => {
    expect(validateDayDate('1989-12-31', '2026-09-30', 1990)).toEqual({
      valid: false,
      violation: 'beforeBirthYear',
    });
    // A date inside the birth year itself is left alone (birth_year has no
    // month or day).
    expect(validateDayDate('1990-01-01', '2026-09-30', 1990).valid).toBe(true);
  });

  it('skips the birth-year rule when the year is unknown', () => {
    expect(validateDayDate('1500-01-01', '2026-09-30', null).valid).toBe(true);
  });

  it('honours both rules together', () => {
    const result = validateDayDate('1980-05-05', '2026-09-30', 1990);
    expect(result.valid).toBe(false);
    // The earlier rule in the function wins, matching the Dart original.
    expect(validateDayDate('2099-05-05', '2026-09-30', 1990)).toEqual({
      valid: false,
      violation: 'futureDate',
    });
  });

  it('compares civil dates, never instants (month and year edges)', () => {
    expect(validateDayDate('2026-10-01', '2026-09-30', null).valid).toBe(true); // +1 across month
    expect(validateDayDate('2027-01-01', '2026-12-31', null).valid).toBe(true); // +1 across year
    expect(validateDayDate('2026-10-02', '2026-09-30', null).valid).toBe(false);
  });

  it('refuses non-ISO shapes loudly', () => {
    expect(() => validateDayDate('2026/09/30', '2026-09-30', null)).toThrow();
    expect(() => validateDayDate('2026-09-30', 'not-a-date', null)).toThrow();
  });

  it('recognises the stored ISO shape', () => {
    expect(isIsoLocalDate('2026-09-30')).toBe(true);
    expect(isIsoLocalDate('2026-9-30')).toBe(false);
    expect(isIsoLocalDate('')).toBe(false);
  });
});

describe('browser clock seam', () => {
  it('renders today in yyyy-MM-dd', () => {
    expect(todayInBrowserZone(new Date('2026-09-30T23:30:00Z'))).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it('reports an IANA zone identifier', () => {
    expect(browserTimeZone().length).toBeGreaterThan(0);
  });
});
