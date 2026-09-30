/**
 * Client-side ULID generation and validation (issue #1254), ported from the
 * app's `lib/data/db/ulid.dart` so the web editor writes rows the server
 * accepts: every synced id is 26 characters of Crockford base32 encoding a
 * 128-bit value — 48 bits of millisecond timestamp + 80 bits of randomness.
 * The server's `sync_push` rejects anything else ("id is not a ULID"), so a
 * bare `crypto.randomUUID()` is never an option here.
 *
 * Monotonic within one process (same-millisecond draws increment the previous
 * randomness), matching the app's generator, so ids this client mints sort
 * strictly after anything it minted before — the tiebreak the server's
 * same-date resolver applies when two writes land on the same LWW timestamp.
 */

const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const ULID_PATTERN = /^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$/;

/** Whether [id] is a syntactically valid ULID (26 Crockford base32 chars). */
export function isValidUlid(id: string): boolean {
  return ULID_PATTERN.test(id);
}

/** The millisecond timestamp encoded in a ULID, or null if [id] is invalid. */
export function ulidTimestampMs(id: string): number | null {
  if (!isValidUlid(id)) return null;
  let time = 0;
  for (let i = 0; i < 10; i++) {
    const value = CROCKFORD.indexOf(id[i]);
    if (value < 0) return null;
    time = time * 32 + value;
  }
  return time;
}

function encodeTime(timeMs: number): string {
  let t = timeMs;
  let chars = '';
  for (let i = 0; i < 10; i++) {
    chars = CROCKFORD[t & 0x1f] + chars;
    t = Math.floor(t / 32);
  }
  return chars;
}

function encodeRandomness(bytes: number[]): string {
  let bitBuffer = 0;
  let bitCount = 0;
  let out = '';
  for (const byte of bytes) {
    bitBuffer = (bitBuffer << 8) | byte;
    bitCount += 8;
    while (bitCount >= 5) {
      bitCount -= 5;
      out += CROCKFORD[(bitBuffer >> bitCount) & 0x1f];
    }
  }
  return out;
}

function increment(bytes: number[]): number[] {
  for (let i = bytes.length - 1; i >= 0; i--) {
    if (bytes[i] < 255) {
      bytes[i]++;
      return bytes;
    }
    bytes[i] = 0;
  }
  // Overflow of 80 bits of randomness within one millisecond (~10^24 ids)
  // is unreachable in practice.
  throw new Error('ULID randomness overflow within one millisecond');
}

let lastTimeMs: number | null = null;
let lastRandomness: number[] | null = null;

/**
 * Draws 10 random bytes. `crypto.getRandomValues` when the platform exposes
 * it (every browser and Node 19+), `Math.random` as the jsdom/test fallback —
 * tests pin only the format and monotonicity, never the entropy source.
 */
function drawRandomness(): number[] {
  const globalCrypto = typeof crypto !== 'undefined' ? crypto : undefined;
  if (globalCrypto?.getRandomValues !== undefined) {
    const bytes = new Uint8Array(10);
    globalCrypto.getRandomValues(bytes);
    return [...bytes];
  }
  return Array.from({ length: 10 }, () => Math.floor(Math.random() * 256));
}

/**
 * Generates a monotonic ULID: sorts strictly greater than every ULID this
 * module previously returned, even across a clock regression. Tests reset
 * the sequence via [resetUlidSequenceForTests].
 */
export function generateUlid(now: number = Date.now()): string {
  let timeMs: number;
  let randomness: number[];
  if (lastTimeMs !== null && now <= lastTimeMs) {
    timeMs = lastTimeMs;
    randomness = increment([...(lastRandomness as number[])]);
  } else {
    timeMs = now;
    randomness = drawRandomness();
  }
  lastTimeMs = timeMs;
  lastRandomness = randomness;
  return encodeTime(timeMs) + encodeRandomness(randomness);
}

/** Test seam: forget the monotonic sequence so a test starts clean. */
export function resetUlidSequenceForTests(): void {
  lastTimeMs = null;
  lastRandomness = null;
}
