/**
 * The day-entry date-bounds policy (issue #1254 on the web) — a faithful
 * port of `lib/domain/logging/day_entry_policy.dart` (issue #848), the
 * date-bounds rule every day-entry write path shares, including the
 * server's own `sync_push` checks (`20260919160000_day_entry_date_bounds.sql`).
 *
 * Until #1251 compiles `lib/domain` to JavaScript, this module is the web
 * client's validation stopgap; when the compiled module lands, the day
 * editor calls it through the same two-case result and this file is deleted
 * in favour of the real thing. The rules are deliberately identical:
 *
 *  - a date more than one calendar day after `today` fails (`futureDate`).
 *    The tolerated extra day absorbs time-zone travel: a user whose local
 *    calendar is one day ahead of this device's is still logging a real
 *    "today".
 *  - a date whose year is before the profile's `birth_year` fails
 *    (`beforeBirthYear`). Only the year is compared — the stored
 *    `birth_year` carries no month or day, so a date in the birth year
 *    itself is left alone. A null birth year leaves the rule unapplied.
 *
 * `today` is always passed in by the caller (clock-seam discipline, like
 * the Dart original) — never read here.
 */

/** A civil calendar date in the stored `yyyy-MM-dd` form. */
export type LocalDateIso = string;

const ISO_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

export type DayDateViolation = 'futureDate' | 'beforeBirthYear';
export type DayDateValidation = { valid: true } | { valid: false; violation: DayDateViolation };

/** Whether [iso] has the stored `yyyy-MM-dd` shape at all. */
export function isIsoLocalDate(iso: string): boolean {
  return ISO_DATE_PATTERN.test(iso);
}

/** The civil day-after arithmetic on ISO strings: no time zones involved. */
function addDays(iso: LocalDateIso, days: number): LocalDateIso {
  const [y, m, d] = iso.split('-').map(Number) as [number, number, number];
  const shifted = new Date(Date.UTC(y, m - 1, d + days));
  return shifted.toISOString().slice(0, 10);
}

/**
 * Validates [date] against [today] and, when known, the profile's
 * [birthYear]. Mirrors `DayEntryPolicy.validateDate` exactly.
 */
export function validateDayDate(
  date: LocalDateIso,
  today: LocalDateIso,
  birthYear: number | null,
): DayDateValidation {
  if (!isIsoLocalDate(date) || !isIsoLocalDate(today)) {
    throw new Error(`validateDayDate: dates must be yyyy-MM-dd (got "${date}", "${today}")`);
  }
  if (date > addDays(today, 1)) {
    return { valid: false, violation: 'futureDate' };
  }
  if (birthYear !== null && Number(date.slice(0, 4)) < birthYear) {
    return { valid: false, violation: 'beforeBirthYear' };
  }
  return { valid: true };
}

/** Today's civil date in the browser's own time zone, as `yyyy-MM-dd`. */
export function todayInBrowserZone(now: Date = new Date()): LocalDateIso {
  const year = String(now.getFullYear()).padStart(4, '0');
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/** The browser's IANA time zone identifier (the day row's `tz` column). */
export function browserTimeZone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
}
