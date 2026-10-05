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

/** Pages a return path must never point at: it would loop back to sign-in. */
function isAuthScreen(pathname: string): boolean {
  return (
    pathname === '/sign-in' ||
    pathname.startsWith('/sign-in/') ||
    pathname === '/sign-up' ||
    pathname === '/forgot-password' ||
    pathname === '/reset-password' ||
    pathname.startsWith('/auth/')
  );
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
    url = new URL(raw, 'https://same-origin.invalid');
  } catch {
    return null;
  }
  if (url.origin !== 'https://same-origin.invalid') return null;
  if (isAuthScreen(url.pathname)) return null;
  return `${url.pathname}${url.search}${url.hash}`;
}

/** [path] carrying [next] as its `next` parameter, or [path] alone. */
export function withNext(path: string, next: string | null): string {
  if (next === null) return path;
  const separator = path.includes('?') ? '&' : '?';
  return `${path}${separator}next=${encodeURIComponent(next)}`;
}
