// Cookie helpers for the /auth/* routes (issue #1250).
//
// The browser never holds a credential a script can read: the only
// long-lived secret, the Supabase refresh token, lives in a `__Host-`
// HttpOnly cookie this Worker sets and rotates (epic #831 decision D3).
// Deno-compatible by design: pure string functions, no imports.

/**
 * The refresh-token cookie. The `__Host-` prefix makes the browser refuse
 * the cookie unless it is Secure, Path=/, and carries no Domain attribute —
 * it cannot be shadowed by a sibling-domain response.
 */
export const REFRESH_COOKIE = '__Host-ll_refresh';

/**
 * The PKCE code-verifier cookie, set by /auth/oauth/start (and the email
 * senders) and consumed once by /auth/callback. SameSite=Lax so the OAuth
 * provider's top-level redirect back still carries it; short-lived because
 * a verifier is single-use material.
 */
export const PKCE_COOKIE = '__Host-ll_pkce';

/**
 * The Apple delete-ceremony state cookie (issue #1256): set by
 * POST /auth/apple/delete/start beside the address of Apple's authorize
 * endpoint, and consumed once by /auth/apple/delete/complete when the
 * redirect back lands with `?code=&state=`. Its value is the ceremony's
 * nonce and the id of the account that asked (see `buildAppleDeleteCookie`).
 * Together they are the only thing saying "this code came from a delete
 * ceremony this account asked for, in this browser" — the web app holds
 * nothing at rest, so the Worker holds the check. SameSite=Lax so Apple's
 * top-level redirect back still carries it, exactly like the PKCE cookie.
 */
export const APPLE_DELETE_COOKIE = '__Host-ll_apple_delete';

/**
 * How long the refresh cookie lives (180 days). Supabase refresh tokens
 * do not expire by default, so this — not the token — is the web session's
 * lifetime; the token itself rotates on every refresh.
 */
export const REFRESH_MAX_AGE_SECONDS = 15552000;

/** The PKCE verifier cookie's life: ten minutes, then the link is dead. */
export const PKCE_MAX_AGE_SECONDS = 600;

/** The Apple delete state cookie's life: also ten minutes — Apple
 * authorization codes themselves expire after five, so the ceremony is
 * dead shortly after the code is either way. */
export const APPLE_DELETE_MAX_AGE_SECONDS = 600;

export type SameSite = 'Strict' | 'Lax';

/**
 * Serialises one `__Host-` cookie. Every cookie this module builds is
 * HttpOnly (invisible to `document.cookie`), Secure, Path=/, and without a
 * Domain attribute — the full `__Host-` contract, asserted by the tests.
 */
export function buildCookie(
  name: typeof REFRESH_COOKIE | typeof PKCE_COOKIE | typeof APPLE_DELETE_COOKIE,
  value: string,
  maxAgeSeconds: number,
  sameSite: SameSite,
): string {
  return `${name}=${value}; HttpOnly; Secure; SameSite=${sameSite}; Path=/; Max-Age=${maxAgeSeconds}`;
}

/** The refresh cookie with its long Max-Age and SameSite=Strict. */
export function buildRefreshCookie(value: string): string {
  return buildCookie(REFRESH_COOKIE, value, REFRESH_MAX_AGE_SECONDS, 'Strict');
}

/**
 * The recovery marker prefixed onto the PKCE cookie's value by the
 * password-recovery flow (issue #1293): GoTrue's PKCE redirect back to
 * /auth/callback carries only `?code=`, never `?type=recovery`, so the
 * Worker records which kind of flow the cookie belongs to — beside the
 * verifier, the way supabase-js stores its PASSWORD_RECOVERY marker next
 * to its own verifier — and POST /auth/callback echoes it to the page.
 */
export const PKCE_RECOVERY_PREFIX = 'recovery:';

/**
 * The return-path marker (issue #1456): `next~<base64url path>:` ahead of
 * the verifier. A visitor who was headed somewhere when they were sent to
 * sign in (an invitation, so far) gets back there after a sign-in that
 * leaves the site and returns through /auth/callback: Google, Apple, an
 * emailed link. The page keeps nothing at rest, so the path rides with the
 * verifier, in the same short-lived HttpOnly cookie and for the same ten
 * minutes at most.
 *
 * Neither `~` nor `:` is in the base64url alphabet, so the marker cannot be
 * confused with a verifier or with the path it carries.
 */
export const PKCE_NEXT_PREFIX = 'next~';

/** What the PKCE cookie's value decodes back into. */
export interface PkceValue {
  /** The PKCE code verifier — exactly what the challenge was issued with. */
  verifier: string;
  /** True when the outstanding link was the password-recovery email. */
  recovery: boolean;
  /**
   * The path to return to after the sign-in, or null. Whatever is here was
   * validated before it was written and must be validated again by whoever
   * reads it: a cookie is not a trusted store.
   */
  next: string | null;
}

function encodeBase64Url(text: string): string {
  let binary = '';
  for (const byte of new TextEncoder().encode(text)) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function decodeBase64Url(encoded: string): string | null {
  if (!/^[A-Za-z0-9_-]*$/.test(encoded)) return null;
  try {
    const binary = atob(encoded.replace(/-/g, '+').replace(/_/g, '/'));
    const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    return null;
  }
}

/**
 * The PKCE verifier cookie: short-lived, SameSite=Lax, optionally marked.
 * A recovery link has its own destination (the new-password step), so it
 * never carries a return path.
 */
export function buildPkceCookie(
  value: string,
  recovery = false,
  next: string | null = null,
): string {
  const marker = recovery
    ? PKCE_RECOVERY_PREFIX
    : next === null || next === ''
      ? ''
      : `${PKCE_NEXT_PREFIX}${encodeBase64Url(next)}:`;
  return buildCookie(PKCE_COOKIE, `${marker}${value}`, PKCE_MAX_AGE_SECONDS, 'Lax');
}

/** What the Apple delete-ceremony cookie's value decodes back into. */
export interface AppleDeleteValue {
  /** The nonce Apple echoes back as `state`. */
  state: string;
  /** The id of the account that started the ceremony. */
  userId: string;
}

/** Neither half of the cookie's value may hold its separator, or anything a
 * cookie value cannot. */
const APPLE_DELETE_PART = /^[A-Za-z0-9_-]+$/;

/**
 * The Apple delete-ceremony state cookie: short-lived, SameSite=Lax (see
 * its own doc comment above). The value is `<state>.<user id>`: the account
 * that asked rides with the nonce, so the ceremony can only be finished by
 * the account that started it. Null when either half could not be written
 * safely, which a random nonce and a GoTrue user id never are.
 */
export function buildAppleDeleteCookie(state: string, userId: string): string | null {
  if (!APPLE_DELETE_PART.test(state) || !APPLE_DELETE_PART.test(userId)) return null;
  return buildCookie(
    APPLE_DELETE_COOKIE,
    `${state}.${userId}`,
    APPLE_DELETE_MAX_AGE_SECONDS,
    'Lax',
  );
}

/**
 * Decodes the Apple delete-ceremony cookie's value; null when it is not
 * `<state>.<user id>`. That includes a value written before the account id
 * rode along (the bare nonce): a ceremony in flight across that change is
 * simply started again.
 */
export function parseAppleDeleteValue(value: string): AppleDeleteValue | null {
  const parts = value.split('.');
  if (parts.length !== 2) return null;
  const [state, userId] = parts;
  if (!APPLE_DELETE_PART.test(state) || !APPLE_DELETE_PART.test(userId)) return null;
  return { state, userId };
}

/**
 * Decodes the PKCE cookie's value; null when it carries no verifier (an
 * empty value, or a bare marker with nothing after it). The marker cannot
 * collide with a real verifier: the base64url alphabet has no colon.
 */
export function parsePkceValue(value: string): PkceValue | null {
  if (value.startsWith(PKCE_RECOVERY_PREFIX)) {
    const verifier = value.slice(PKCE_RECOVERY_PREFIX.length);
    return verifier === '' ? null : { verifier, recovery: true, next: null };
  }
  if (value.startsWith(PKCE_NEXT_PREFIX)) {
    const end = value.indexOf(':', PKCE_NEXT_PREFIX.length);
    // A marker with no terminator is not a verifier either.
    if (end === -1) return null;
    const verifier = value.slice(end + 1);
    if (verifier === '') return null;
    // A path that does not decode is dropped; the sign-in still completes.
    const next = decodeBase64Url(value.slice(PKCE_NEXT_PREFIX.length, end));
    return { verifier, recovery: false, next: next === '' ? null : next };
  }
  return value === '' ? null : { verifier: value, recovery: false, next: null };
}

/** Expires one of this module's cookies (sign-out, consumed verifier, spent
 * Apple delete state). */
export function buildClearedCookie(
  name: typeof REFRESH_COOKIE | typeof PKCE_COOKIE | typeof APPLE_DELETE_COOKIE,
): string {
  return `${name}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`;
}

/** [text] without the spaces and tabs around it: all that pads a cookie pair. */
function trimCookiePadding(text: string): string {
  return text.replace(/^[ \t]+|[ \t]+$/g, '');
}

/**
 * Reads one cookie from a Request's Cookie header, or null.
 *
 * Only spaces and tabs are trimmed from around a name, which is what a
 * browser trims before it decides whether a cookie is entitled to the
 * `__Host-` prefix. `String.prototype.trim` strips more than that (a
 * no-break space, for one). A cookie named with such a character in front
 * of `__Host-…` is not a `__Host-` cookie to the browser, so anything on a
 * sibling domain may set it; trimmed too generously here, it would be read
 * as the real one. Every cookie this Worker trusts comes through this
 * function, so the name must match exactly.
 */
export function readCookie(request: Request, name: string): string | null {
  const header = request.headers.get('cookie');
  if (header === null) return null;
  for (const part of header.split(';')) {
    const separator = part.indexOf('=');
    if (separator === -1) continue;
    if (trimCookiePadding(part.slice(0, separator)) === name) {
      return trimCookiePadding(part.slice(separator + 1));
    }
  }
  return null;
}
