import { describe, expect, it } from 'vitest';

import { UlidGenerator, isValidUlid, ulidTimestampMs } from '../src/lib/ulid';

describe('UlidGenerator (issue #1255)', () => {
  it('generates ids in the server ULID alphabet', () => {
    const generator = new UlidGenerator();
    const id = generator.next();
    expect(id).toHaveLength(26);
    expect(isValidUlid(id)).toBe(true);
  });

  it('encodes the clock into the first 10 characters (deterministic seams)', () => {
    let tick = 1_700_000_000_000;
    let byte = 0;
    const generator = new UlidGenerator({
      clock: () => tick,
      randomByte: () => (byte = (byte + 7) % 256),
    });
    const id = generator.next();
    expect(ulidTimestampMs(id)).toBe(tick);
    tick += 5;
    const second = generator.next();
    expect(ulidTimestampMs(second)).toBe(tick);
    expect(second > id).toBe(true);
  });

  it('stays monotonic within the same millisecond', () => {
    const generator = new UlidGenerator({ clock: () => 1000, randomByte: () => 3 });
    const first = generator.next();
    const second = generator.next();
    expect(ulidTimestampMs(first)).toBe(1000);
    expect(ulidTimestampMs(second)).toBe(1000);
    expect(second > first).toBe(true);
  });

  it('survives a clock regression without regressing ids', () => {
    let now = 2000;
    const generator = new UlidGenerator({ clock: () => now, randomByte: () => 9 });
    const at2000 = generator.next();
    now = 1000;
    const afterRegression = generator.next();
    expect(afterRegression > at2000).toBe(true);
    expect(ulidTimestampMs(afterRegression)).toBe(2000);
  });

  it('rejects non-ULID strings and hex-incompatible letters', () => {
    expect(isValidUlid('01ARZ3NDEKTSV4RRFFQ69G5FAV')).toBe(true);
    expect(isValidUlid('0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f')).toBe(false);
    expect(isValidUlid('01ARZ3NDEKTSV4RRFFQ69G5FA')).toBe(false);
    expect(isValidUlid('0IARZ3NDEKTSV4RRFFQ69G5FAV')).toBe(false);
    expect(ulidTimestampMs('nope')).toBeNull();
  });
});
