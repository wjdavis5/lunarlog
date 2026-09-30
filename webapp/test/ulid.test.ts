import { describe, expect, it } from 'vitest';

import {
  generateUlid,
  isValidUlid,
  resetUlidSequenceForTests,
  ulidTimestampMs,
} from '../src/lib/ulid';

/**
 * The web ULID generator (issue #1254), ported from the app's
 * lib/data/db/ulid.dart — the server's sync_push rejects any id that is
 * not 26 characters of Crockford base32, so these are the acceptance
 * bounds the web writes live under.
 */
describe('generateUlid (issue #1254)', () => {
  it('generates syntactically valid ULIDs (26 Crockford base32 chars)', () => {
    resetUlidSequenceForTests();
    for (let i = 0; i < 50; i++) {
      expect(isValidUlid(generateUlid())).toBe(true);
    }
  });

  it('never produces characters outside the Crockford alphabet', () => {
    resetUlidSequenceForTests();
    const id = generateUlid();
    // I, L, O, U are excluded (Crockford base32).
    expect(id).toMatch(/^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$/);
  });

  it('encodes the supplied timestamp in the first 10 characters', () => {
    resetUlidSequenceForTests();
    const now = 1_783_040_000_000; // ~2026-07
    const id = generateUlid(now);
    expect(ulidTimestampMs(id)).toBe(now);
  });

  it('is strictly monotonic within one millisecond', () => {
    resetUlidSequenceForTests();
    const now = 1_783_040_000_000;
    const first = generateUlid(now);
    const second = generateUlid(now);
    const third = generateUlid(now);
    expect(second > first).toBe(true);
    expect(third > second).toBe(true);
  });

  it('survives a clock regression without regressing', () => {
    resetUlidSequenceForTests();
    const later = generateUlid(2_000_000_000_000);
    const earlier = generateUlid(1_000_000_000_000);
    expect(earlier > later).toBe(true);
  });

  it('rejects malformed ids', () => {
    expect(isValidUlid('')).toBe(false);
    expect(isValidUlid('0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f')).toBe(false);
    expect(isValidUlid('Oooooooooooooooooooooooooo')).toBe(false); // 26 chars, I/L/O/U banned
    expect(isValidUlid('01ARZ3NDEKTSV4RRFFQ69G5FAV')).toBe(true); // the spec's example
  });
});
