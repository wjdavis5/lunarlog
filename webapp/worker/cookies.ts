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
 * /auth/apple/delete/start next to the 302 out to Apple's authorize
 * endpoint, and consumed once by /auth/apple/delete/complete when the
 * redirect back lands with `?code=&state=`. The nonce is the only thing
 * binding "this code came from a delete ceremony this browser asked for" —
 * the web app holds nothing at rest, so the Worker holds the check.
 * SameSite=Lax so Apple's top-level redirect back still carries it, exactly
 * like the PKCE cookie.
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

/** What the PKCE cookie's value decodes back into. */
export interface PkceValue {
  /** The PKCE code verifier — exactly what the challenge was issued with. */
  verifier: string;
  /** True when the outstanding link was the password-recovery email. */
  recovery: boolean;
}

/** The PKCE verifier cookie: short-lived, SameSite=Lax, optionally marked. */
export function buildPkceCookie(value: string, recovery = false): string {
  return buildCookie(
    PKCE_COOKIE,
    recovery ? `${PKCE_RECOVERY_PREFIX}${value}` : value,
    PKCE_MAX_AGE_SECONDS,
    'Lax',
  );
}

/** The Apple delete-ceremony state cookie: short-lived, SameSite=Lax (see
 * its own doc comment above). */
export function buildAppleDeleteCookie(value: string): string {
  return buildCookie(APPLE_DELETE_COOKIE, value, APPLE_DELETE_MAX_AGE_SECONDS, 'Lax');
}

/**
 * Decodes the PKCE cookie's value; null when it carries no verifier (an
 * empty value, or a bare marker with nothing after it). The marker cannot
 * collide with a real verifier: the base64url alphabet has no colon.
 */
export function parsePkceValue(value: string): PkceValue | null {
  if (value.startsWith(PKCE_RECOVERY_PREFIX)) {
    const verifier = value.slice(PKCE_RECOVERY_PREFIX.length);
    return verifier === '' ? null : { verifier, recovery: true };
  }
  return value === '' ? null : { verifier: value, recovery: false };
}

/** Expires one of this module's cookies (sign-out, consumed verifier, spent
 * Apple delete state). */
export function buildClearedCookie(
  name: typeof REFRESH_COOKIE | typeof PKCE_COOKIE | typeof APPLE_DELETE_COOKIE,
): string {
  return `${name}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`;
}

/** Reads one cookie from a Request's Cookie header, or null. */
export function readCookie(request: Request, name: string): string | null {
  const header = request.headers.get('cookie');
  if (header === null) return null;
  for (const part of header.split(';')) {
    const separator = part.indexOf('=');
    if (separator === -1) continue;
    if (part.slice(0, separator).trim() === name) {
      return part.slice(separator + 1).trim();
    }
  }
  return null;
}
