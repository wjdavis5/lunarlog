/**
 * Monotonic-safe ULID generation for the web client (issue #1252).
 *
 * Every id the sync server accepts is a ULID — 26 characters of Crockford
 * base32 encoding a 128-bit value (48 bits of millisecond timestamp + 80
 * bits of randomness) — enforced server-side by the tables' own CHECK
 * constraints (`profiles_id_ulid_check`, `day_entries_id_ulid_check`, … in
 * 20260903014208_initial_sync_schema.sql) and by `sync_push`'s payload
 * validation. This module is a line-for-line port of the Dart client's
 * `lib/data/db/ulid.dart`, so a web-generated id is indistinguishable from
 * a phone-generated one. ULIDs from one generator sort strictly ascending
 * even when the clock stands still or regresses, which keeps
 * client-generated ids stable and sortable for sync.
 */

const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/** Whether [id] is a syntactically valid ULID (26 Crockford base32 chars). */
// The same shape the server's *_id_ulid_check constraints and sync_push's
// `c_ulid` pattern enforce; deliberately duplicated here so the client
// rejects a bad id before a round trip does.
export const ULID_PATTERN = /^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$/;

export function isValidUlid(id: string): boolean {
  return ULID_PATTERN.test(id);
}

/** The millisecond timestamp encoded in a ULID, or null if [id] is invalid. */
export function ulidTimestampMs(id: string): number | null {
  if (!isValidUlid(id)) return null;
  let time = 0;
  for (let i = 0; i < 10; i += 1) {
    const value = CROCKFORD.indexOf(id[i] as string);
    if (value < 0) return null;
    time = time * 32 + value;
  }
  return time;
}

/** Injected randomness source (80 bits = 10 bytes per ULID). */
export type RandomBytes = (length: number) => Uint8Array;

/** The browser's cryptographic random source, the default. */
export const cryptoRandomBytes: RandomBytes = (length) =>
  crypto.getRandomValues(new Uint8Array(length));

/**
 * Generates monotonic ULIDs. One instance per page load (the data layer
 * keeps a module singleton); tests may inject a clock and a randomness
 * source to pin both halves.
 */
export class UlidGenerator {
  constructor(clock: () => number = () => Date.now(), random: RandomBytes = cryptoRandomBytes) {
    this.clock = clock;
    this.random = random;
  }

  private readonly clock: () => number;
  private readonly random: RandomBytes;
  private lastTimeMs: number | null = null;
  private lastRandomness: Uint8Array | null = null;

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
      randomness = Uint8Array.of(...(this.lastRandomness as Uint8Array));
      increment(randomness);
    } else {
      timeMs = nowMs;
      randomness = this.random(10);
    }

    this.lastTimeMs = timeMs;
    this.lastRandomness = randomness;

    return encodeTime(timeMs) + encodeRandomness(randomness);
  }
}

function increment(bytes: Uint8Array): void {
  for (let i = bytes.length - 1; i >= 0; i -= 1) {
    if (bytes[i] < 255) {
      bytes[i] += 1;
      return;
    }
    bytes[i] = 0;
  }
  // Overflow of 80 bits of randomness within one millisecond (~10^24 ids)
  // is unreachable in practice.
  throw new Error('ULID randomness overflow within one millisecond');
}

/** 48-bit timestamp -> 10 characters (most significant first). */
function encodeTime(timeMs: number): string {
  let t = timeMs;
  const chars: string[] = new Array<string>(10);
  for (let i = 9; i >= 0; i -= 1) {
    chars[i] = CROCKFORD[t & 0x1f];
    t = Math.floor(t / 32);
  }
  return chars.join('');
}

/** 80 bits of randomness -> exactly 16 characters of 5 bits each. */
function encodeRandomness(bytes: Uint8Array): string {
  let out = '';
  let bitBuffer = 0;
  let bitCount = 0;
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

/** The page's one generator: monotonic within the page, nothing persisted. */
const sharedGenerator = new UlidGenerator();

/** Generates the next id for a client-created synced row. */
export function newUlid(): string {
  return sharedGenerator.next();
}
