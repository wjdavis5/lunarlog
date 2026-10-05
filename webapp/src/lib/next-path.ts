/**
 * "Come back here after signing in."
 *
 * A page that needs a session (the invitation page is the first) sends a
 * signed-out visitor to `/sign-in?next=<path>`, and the sign-in pages go to
 * that path once the visitor is signed in. The value arrives in the address
 * bar, so it is untrusted: an attacker can hand someone a sign-in link whose
 * `next` points anywhere. [safeNextPath] accepts only a path on this origin
 * and returns null for everything else, and callers fall back to the home
 * page.
 *
 * Nothing is stored. The path travels in the URL between the sign-in pages.
 * A sign-in that leaves the site (Google, Apple, an emailed link) comes back
 * through `/auth/callback` without it, and lands on the home page.
 */

const MAX_NEXT_LENGTH = 512;

const PLACEHOLDER_ORIGIN = 'https://same-origin.invalid';

/**
 * Pages a return path must never point at: it would loop back to sign-in.
 *
 * [decodedPathname] is the path as the router reads it. The router matches
 * without regard to letter case or a trailing slash, so this does too:
 * `/Sign-In` and `/sign-up/` are the same screens as their plain spellings.
 */
function isAuthScreen(decodedPathname: string): boolean {
  const path = decodedPathname.toLowerCase().replace(/\/+$/, '');
  return (
    path === '/sign-in' ||
    path.startsWith('/sign-in/') ||
    path === '/sign-up' ||
    path.startsWith('/sign-up/') ||
    path === '/forgot-password' ||
    path.startsWith('/forgot-password/') ||
    path === '/reset-password' ||
    path.startsWith('/reset-password/') ||
    path === '/auth' ||
    path.startsWith('/auth/')
  );
}

/** [pathname] percent-decoded once, or null when it is not valid encoding. */
function decodePathname(pathname: string): string | null {
  try {
    return decodeURIComponent(pathname);
  } catch {
    return null;
  }
}

function hasControlCharacter(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code < 0x20 || code === 0x7f) return true;
  }
  return false;
}

/**
 * The same-origin path in [raw], or null when [raw] is anything else:
 * absent, another origin, protocol-relative (`//host`), a backslash form
 * browsers read as one (`/\host`), a scheme, a control character, an auth
 * screen, or too long.
 *
 * The checks run twice, on purpose. What is typed is not what is returned:
 * resolving the value removes dot segments, so `/.//host` and `/a/..//host`
 * both become `//host`, a protocol-relative address that the first check
 * never saw. And what is returned is not what the router matches: it
 * decodes the path first, so `/%2Fhost` and `/sign%2Din` reach it as
 * `//host` and `/sign-in`. So the resolved path is checked as well as the
 * raw one, in both its encoded and its decoded form, and no path with an
 * empty segment is accepted at all (no page on this site has one).
 */
export function safeNextPath(raw: string | null | undefined): string | null {
  if (raw === null || raw === undefined) return null;
  if (raw.length === 0 || raw.length > MAX_NEXT_LENGTH) return null;
  if (!raw.startsWith('/') || raw.startsWith('//')) return null;
  if (raw.includes('\\') || hasControlCharacter(raw)) return null;
  let url: URL;
  try {
    // Resolved against a placeholder origin: a value that escapes it is not
    // a path on this site, however it was spelled.
    url = new URL(raw, PLACEHOLDER_ORIGIN);
  } catch {
    return null;
  }
  if (url.origin !== PLACEHOLDER_ORIGIN) return null;

  const decoded = decodePathname(url.pathname);
  if (decoded === null) return null;
  for (const path of [url.pathname, decoded]) {
    if (!path.startsWith('/') || path.includes('//')) return null;
    if (path.includes('\\') || hasControlCharacter(path)) return null;
  }
  if (isAuthScreen(decoded)) return null;

  const result = `${url.pathname}${url.search}${url.hash}`;
  // The last word: whatever the rules above let through, the value handed
  // back must itself resolve to this origin and to the same path.
  let again: URL;
  try {
    again = new URL(result, PLACEHOLDER_ORIGIN);
  } catch {
    return null;
  }
  if (again.origin !== PLACEHOLDER_ORIGIN) return null;
  if (`${again.pathname}${again.search}${again.hash}` !== result) return null;
  return result;
}

/** [path] carrying [next] as its `next` parameter, or [path] alone. */
export function withNext(path: string, next: string | null): string {
  if (next === null) return path;
  const separator = path.includes('?') ? '&' : '?';
  return `${path}${separator}next=${encodeURIComponent(next)}`;
}
