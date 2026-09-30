import { describe, expect, it } from 'vitest';

import {
  UlidGenerator,
  cryptoRandomBytes,
  isValidUlid,
  newUlid,
  ulidTimestampMs,
} from '../src/lib/ulid';

describe('ULID generation (issue #1252)', () => {
  it('produces 26-character Crockford base32 ids', () => {
    for (let i = 0; i < 100; i += 1) {
      const id = newUlid();
      expect(id).toMatch(/^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$/);
      expect(isValidUlid(id)).toBe(true);
    }
  });

  it('never produces I, L, O, or U (the server check excludes them)', () => {
    for (let i = 0; i < 100; i += 1) {
      const id = newUlid();
      expect(id).not.toMatch(/[ILOU]/);
    }
  });

  it('is monotonic within one generator, even in the same millisecond', () => {
    let now = 1_700_000_000_000;
    const generator = new UlidGenerator(
      () => now,
      (length) => cryptoRandomBytes(length),
    );
    const seen: string[] = [];
    for (let i = 0; i < 50; i += 1) {
      seen.push(generator.next()); // same clock reading every call
    }
    for (let i = 1; i < seen.length; i += 1) {
      expect(seen[i] > seen[i - 1]).toBe(true);
    }
    // A clock regression must not regress ids either.
    now -= 1_000;
    expect(generator.next() > seen[49]).toBe(true);
  });

  it('encodes the generation millisecond, decodable back', () => {
    const now = 1_700_000_123_456;
    const generator = new UlidGenerator(
      () => now,
      () => new Uint8Array(10),
    );
    const id = generator.next();
    expect(ulidTimestampMs(id)).toBe(now);
  });

  it('rejects malformed ids and returns no timestamp for them', () => {
    expect(isValidUlid('01ARZ3NDEKTSV4RRFFQ69G5FAV')).toBe(true);
    expect(isValidUlid('0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f')).toBe(false);
    expect(isValidUlid('01ARZ3NDEKTSV4RRFFQ69G5FA')).toBe(false); // 25 chars
    expect(isValidUlid('01ARZ3NDEKTSV4RRFFQ69G5FAVI')).toBe(false); // 27
    expect(isValidUlid('01ARZ3NDEKTSV4RRFFQ69G5FAU')).toBe(false); // U not in alphabet
    expect(ulidTimestampMs('not-a-ulid')).toBeNull();
  });

  it('randomness increments rather than regenerating on a frozen clock', () => {
    const generator = new UlidGenerator(
      () => 42,
      () => new Uint8Array(10).fill(1),
    );
    const first = generator.next();
    const second = generator.next();
    expect(second > first).toBe(true);
    // And the increment is deterministic: the second id is first + 1 in the
    // randomness bits (same 10-char timestamp prefix, 16-char suffix +1).
    expect(second.slice(0, 10)).toBe(first.slice(0, 10));
  });

  it('throws when 80 bits of randomness are exhausted within one millisecond', () => {
    const generator = new UlidGenerator(
      () => 42,
      () => new Uint8Array(10).fill(255),
    );
    generator.next();
    expect(() => generator.next()).toThrow('overflow');
  });
});
