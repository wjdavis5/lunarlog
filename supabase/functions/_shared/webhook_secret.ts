/**
 * Constant-time comparison of a webhook shared secret (issue #1740).
 *
 * Both webhook functions compared with a plain `!==`, which short-circuits
 * on the first differing character — in principle a response-latency
 * prefix oracle for a caller with network access, letting the shared
 * secret be recovered and the function then called as an authorised
 * webhook. Both sides are hashed to fixed-length SHA-256 digests first (so
 * the comparison is always over the same 32 bytes and the secret's length
 * is not distinguishable from the comparison either), then the digests are
 * compared with a constant-time XOR accumulation. A missing expected
 * secret, an empty expected secret, and a missing header never match.
 */
export async function webhookSecretsMatch(
  expected: string | undefined,
  provided: string | null,
): Promise<boolean> {
  if (!expected || provided === null) return false;
  const encoder = new TextEncoder();
  const [expectedDigest, providedDigest] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
  ]);
  const expectedBytes = new Uint8Array(expectedDigest);
  const providedBytes = new Uint8Array(providedDigest);
  let difference = 0;
  for (let i = 0; i < expectedBytes.length; i++) {
    difference |= expectedBytes[i] ^ providedBytes[i];
  }
  return difference === 0;
}
