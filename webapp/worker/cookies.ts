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
 * How long the refresh cookie lives (180 days). Supabase refresh tokens
 * do not expire by default, so this — not the token — is the web session's
 * lifetime; the token itself rotates on every refresh.
 */
export const REFRESH_MAX_AGE_SECONDS = 15552000;

/** The PKCE verifier cookie's life: ten minutes, then the link is dead. */
export const PKCE_MAX_AGE_SECONDS = 600;

export type SameSite = 'Strict' | 'Lax';

/**
 * Serialises one `__Host-` cookie. Every cookie this module builds is
 * HttpOnly (invisible to `document.cookie`), Secure, Path=/, and without a
 * Domain attribute — the full `__Host-` contract, asserted by the tests.
 */
export function buildCookie(
  name: typeof REFRESH_COOKIE | typeof PKCE_COOKIE,
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

/** The PKCE verifier cookie: short-lived, SameSite=Lax. */
export function buildPkceCookie(value: string): string {
  return buildCookie(PKCE_COOKIE, value, PKCE_MAX_AGE_SECONDS, 'Lax');
}

/** Expires one of this module's cookies (sign-out, consumed verifier). */
export function buildClearedCookie(name: typeof REFRESH_COOKIE | typeof PKCE_COOKIE): string {
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
