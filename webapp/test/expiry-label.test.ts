import { createIntl } from 'react-intl';
import { describe, expect, it } from 'vitest';

import messages from '../src/i18n/messages.en.json';
import type { TFunction } from '../src/i18n/t';
import { expiryLabel } from '../src/pages/ManageGuardiansPage';

/**
 * How long a pending invitation has left, as its row says it (issue #1465).
 * The real catalogue formats the strings, so the plural is exercised too.
 */
const intl = createIntl({ locale: 'en', messages });
const t: TFunction = (id, values) => intl.formatMessage({ id }, values);

const NOW = new Date('2026-10-05T12:00:00Z');
const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

function label(msFromNow: number): string {
  return expiryLabel(new Date(NOW.getTime() + msFromNow).toISOString(), NOW, t);
}

describe('expiryLabel', () => {
  it('tells an invitation that lasts days in days', () => {
    // The case from the issue: six days used to read "expires in 144h".
    expect(label(6 * DAY)).toBe('expires in 6 days');
    expect(label(7 * DAY)).toBe('expires in 7 days');
    expect(label(30 * DAY)).toBe('expires in 30 days');
  });

  it('starts counting days at two full days', () => {
    expect(label(48 * HOUR)).toBe('expires in 2 days');
    expect(label(48 * HOUR - MINUTE)).toBe('expires in 48h');
    expect(label(30 * HOUR)).toBe('expires in 30h');
  });

  it('rounds a day count down, never up', () => {
    expect(label(3 * DAY - MINUTE)).toBe('expires in 2 days');
    expect(label(3 * DAY)).toBe('expires in 3 days');
  });

  it('keeps hours and minutes below that', () => {
    expect(label(6 * HOUR)).toBe('expires in 6h');
    expect(label(91 * MINUTE)).toBe('expires in 2h');
    expect(label(90 * MINUTE)).toBe('expires in 90m');
    expect(label(20 * 1000)).toBe('expires in 1m');
  });

  it('says a lapsed invitation has expired', () => {
    expect(label(0)).toBe('expired');
    expect(label(-3 * DAY)).toBe('expired');
  });

  it('has a singular for one day', () => {
    // Not reachable through expiryLabel while days start at two, but the
    // plural must not read "1 days" if that threshold ever moves.
    expect(t('sharingManageGuardiansExpiryDays', { days: 1 })).toBe('expires in 1 day');
  });
});
