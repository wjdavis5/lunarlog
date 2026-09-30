/**
 * ULID generation and validation for client-created rows (issue #1255).
 *
 * Every synced content row the server accepts carries a 26-character
 * Crockford base32 ULID id — `profiles_id_ulid_check`,
 * `care_notes_id_ulid_check`, `guardian_notes_id_ulid_check` and friends all
 * pin `^[0-9A-HJKMNP-TV-Z]{26}$`, and the Flutter client generates ids from
 * the same spec (`lib/data/db/ulid.dart`). The web client creates
 * guardian-note and care-note rows through `sync_push`, so it must mint ids
 * in exactly that alphabet.
 *
 * Port of `lib/data/db/ulid.dart` (spec: https://github.com/ulid/spec):
 * 48 bits of millisecond timestamp + 80 bits of randomness. The web
 * generator is monotonic within one process instance like the Dart one, so
 * two notes written back-to-back still sort in creation order.
 */

const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const VALID_ULID = /^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$/;

/** Whether `id` is a syntactically valid ULID (26 Crockford base32 chars). */
export function isValidUlid(id: string): boolean {
  return VALID_ULID.test(id);
}

/** The millisecond timestamp encoded in a ULID, or null if `id` is invalid. */
export function ulidTimestampMs(id: string): number | null {
  if (!isValidUlid(id)) return null;
  let time = 0;
  for (let i = 0; i < 10; i++) {
    const value = CROCKFORD.indexOf(id[i] ?? '');
    if (value < 0) return null;
    time = time * 32 + value;
  }
  return time;
}

function encodeTime(timeMs: number): string {
  // 48-bit timestamp -> 10 characters (most significant first).
  const chars: string[] = new Array(10);
  let t = timeMs;
  for (let i = 9; i >= 0; i--) {
    chars[i] = CROCKFORD[t & 0x1f];
    t = Math.floor(t / 32);
  }
  return chars.join('');
}

function encodeRandomness(bytes: Uint8Array): string {
  // 80 bits of randomness -> exactly 16 characters of 5 bits each.
  let out = '';
  let bitBuffer = 0;
  let bitCount = 0;
  for (const byte of bytes) {
    bitBuffer = ((bitBuffer << 8) | byte) & 0xffff;
    bitCount += 8;
    while (bitCount >= 5) {
      bitCount -= 5;
      out += CROCKFORD[(bitBuffer >> bitCount) & 0x1f];
    }
  }
  return out;
}

function increment(bytes: Uint8Array): void {
  for (let i = bytes.length - 1; i >= 0; i--) {
    if ((bytes[i] ?? 0) < 255) {
      bytes[i] = (bytes[i] ?? 0) + 1;
      return;
    }
    bytes[i] = 0;
  }
  // Overflow of 80 bits of randomness within one millisecond (~10^24 ids)
  // is unreachable in practice.
  throw new Error('ULID randomness overflow within one millisecond');
}

/**
 * Generates monotonic ULIDs. Both seams are injectable so tests can pin the
 * clock and the randomness (the same seams `UlidGenerator` takes in Dart).
 */
export class UlidGenerator {
  private lastTimeMs: number | null = null;
  private lastRandomness: Uint8Array | null = null;
  private cspBuffer: Uint8Array = new Uint8Array(32);
  private cspCursor = 32;

  private readonly clock: () => number;
  private readonly randomByte: () => number;

  constructor(options: { clock?: () => number; randomByte?: () => number } = {}) {
    this.clock = options.clock ?? (() => Date.now());
    this.randomByte =
      options.randomByte ??
      (() => {
        // 32 random bytes at a time from the platform CSPRNG, consumed one
        // byte per call — the same shape as Dart's `Random.secure()`.
        if (this.cspCursor >= this.cspBuffer.length) {
          crypto.getRandomValues(this.cspBuffer);
          this.cspCursor = 0;
        }
        return this.cspBuffer[this.cspCursor++] ?? 0;
      });
  }

  /**
   * Returns the next ULID. Guaranteed to sort strictly greater than every
   * ULID previously returned by this generator.
   */
  next(): string {
    const nowMs = this.clock();

    let timeMs: number;
    let randomness: Uint8Array;
    const lastTime = this.lastTimeMs;
    if (lastTime !== null && nowMs <= lastTime) {
      // Same millisecond (or a clock regression): increment the previous
      // randomness to stay strictly monotonic.
      timeMs = lastTime;
      randomness = Uint8Array.from(this.lastRandomness ?? new Uint8Array(10));
      increment(randomness);
    } else {
      timeMs = nowMs;
      randomness = new Uint8Array(10);
      for (let i = 0; i < 10; i++) {
        randomness[i] = this.randomByte();
      }
    }

    this.lastTimeMs = timeMs;
    this.lastRandomness = randomness;

    return encodeTime(timeMs) + encodeRandomness(randomness);
  }
}
