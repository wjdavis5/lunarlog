import { assertEquals, assertNotEquals } from 'jsr:@std/assert';

import {
  CSRF_HEADER,
  handleAuthRequest,
  type AuthDeps,
  type AuthEnv,
  type SupabaseAuthFetch,
} from './auth.ts';
import { buildPkceCookie, parsePkceValue, PKCE_COOKIE, PKCE_NEXT_PREFIX } from './cookies.ts';

/**
 * The return path through a sign-in that leaves the site (issue #1456).
 *
 * A visitor sent to sign in on the way to an invitation comes back through
 * /auth/callback after Google, Apple or an emailed link. The page keeps
 * nothing at rest, so the Worker carries where they were headed in the
 * short-lived PKCE cookie, beside the verifier, and hands it back with the
 * session.
 *
 * The path is attacker-influenced twice: in the request that starts the
 * sign-in, and in principle in the cookie. These tests hold both ends to
 * the same rule: a path on this origin that is not a sign-in screen, or
 * nothing.
 */

const ORIGIN = 'https://app.test';
const ENV: AuthEnv = { SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test' };
const INVITE = '/invite?code=ABC123&kind=claim';

/** Inputs that must never come back out as a place to go. */
const HOSTILE = [
  'https://evil.example/invite',
  '//evil.example/invite',
  '/.//evil.example',
  '/a/..//evil.example',
  '/%2Fevil.example',
  '/\\evil.example',
  'javascript:alert(1)',
  'invite?code=A',
  '/sign-in',
  '/Sign-In/',
  '/sign%2Din',
  '/auth/callback?code=x',
  '',
];

function fakeDeps(responder?: (path: string) => Response): {
  deps: AuthDeps;
  paths: string[];
} {
  const paths: string[] = [];
  const deps: AuthDeps = {
    supabaseUrl: 'https://supabase.test',
    publishableKey: 'sb_publishable_test',
    supabaseFetch: (async (path: string) => {
      paths.push(path);
      if (responder !== undefined) return responder(path);
      return new Response(
        JSON.stringify({
          access_token: 'access-1',
          refresh_token: 'refresh-1',
          expires_in: 3600,
          expires_at: 1700000000,
          user: { id: 'u1', email: 'a@example.com' },
        }),
        { status: 200, headers: { 'content-type': 'application/json' } },
      );
    }) as SupabaseAuthFetch,
    randomVerifier: () => 'verifier-abc',
    codeChallenge: async (verifier) => `challenge-${verifier}`,
  };
  return { deps, paths };
}

function post(path: string, body: unknown, cookie?: string): Request {
  const headers: Record<string, string> = {
    'content-type': 'application/json',
    origin: ORIGIN,
    [CSRF_HEADER]: '1',
  };
  if (cookie !== undefined) headers['cookie'] = cookie;
  return new Request(`${ORIGIN}${path}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
}

function get(path: string, headers: Record<string, string> = {}): Request {
  return new Request(`${ORIGIN}${path}`, { method: 'GET', headers });
}

/** The PKCE cookie's value from a response's Set-Cookie headers. */
function pkceValueOf(response: Response | null | undefined): string {
  const cookie = (response?.headers.getSetCookie() ?? []).find((value) =>
    value.startsWith(`${PKCE_COOKIE}=`),
  );
  if (cookie === undefined) throw new Error('no PKCE cookie was set');
  return cookie.slice(PKCE_COOKIE.length + 1).split(';')[0];
}

/** The same value as the browser would send it back. */
function asRequestCookie(value: string): string {
  return `${PKCE_COOKIE}=${value}`;
}

/** An email sender's upstream answer: no session, the mail is on its way. */
function emailSent(): Response {
  return new Response(JSON.stringify({ user: { id: 'u1' } }), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
}

// --- the cookie's value ------------------------------------------------------

Deno.test('the cookie value round-trips a return path beside the verifier', () => {
  const cookie = buildPkceCookie('verifier-abc', false, INVITE);
  const value = cookie.slice(PKCE_COOKIE.length + 1).split(';')[0];
  assertEquals(value.startsWith(PKCE_NEXT_PREFIX), true);
  // Nothing readable in the cookie: the path is encoded, not written out.
  assertEquals(value.includes('invite'), false);
  assertEquals(parsePkceValue(value), {
    verifier: 'verifier-abc',
    recovery: false,
    next: INVITE,
  });
  // The cookie keeps every flag it had.
  assertEquals(cookie.endsWith('; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=600'), true);
});

Deno.test('the cookie value is unchanged when there is nowhere to return to', () => {
  assertEquals(
    buildPkceCookie('verifier-abc'),
    `${PKCE_COOKIE}=verifier-abc; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=600`,
  );
  assertEquals(buildPkceCookie('verifier-abc', false, null), buildPkceCookie('verifier-abc'));
  assertEquals(buildPkceCookie('verifier-abc', false, ''), buildPkceCookie('verifier-abc'));
  assertEquals(parsePkceValue('verifier-abc'), {
    verifier: 'verifier-abc',
    recovery: false,
    next: null,
  });
});

Deno.test('a recovery cookie never carries a return path', () => {
  const cookie = buildPkceCookie('verifier-abc', true, INVITE);
  assertEquals(cookie.startsWith(`${PKCE_COOKIE}=recovery:verifier-abc;`), true);
  assertEquals(parsePkceValue('recovery:verifier-abc'), {
    verifier: 'verifier-abc',
    recovery: true,
    next: null,
  });
});

Deno.test('a return path with characters outside ASCII survives the cookie', () => {
  const path = '/invite?code=A&note=café ✓';
  const value = buildPkceCookie('verifier-abc', false, path)
    .slice(PKCE_COOKIE.length + 1)
    .split(';')[0];
  // A cookie value may not hold a space, a semicolon or a comma.
  assertEquals(/^[A-Za-z0-9_~:-]+$/.test(value), true);
  assertEquals(parsePkceValue(value)?.next, path);
});

Deno.test('a damaged marker loses the path but never invents a verifier', () => {
  // Not base64url: the path is dropped, the verifier stands.
  assertEquals(parsePkceValue('next~***:verifier-abc'), {
    verifier: 'verifier-abc',
    recovery: false,
    next: null,
  });
  // Bytes that are not UTF-8.
  assertEquals(parsePkceValue('next~_w:verifier-abc')?.next, null);
  // Only the spelling this Worker writes is read back. `/i?~~~` in the
  // standard alphabet ("L2k/fn5+") decodes fine, and is still not ours.
  assertEquals(atob('L2k/fn5+'), '/i?~~~');
  assertEquals(parsePkceValue('next~L2k/fn5+:verifier-abc'), {
    verifier: 'verifier-abc',
    recovery: false,
    next: null,
  });
  assertEquals(parsePkceValue('next~L2k_fn5-:verifier-abc')?.next, '/i?~~~');
  // No terminator, or nothing after it: there is no verifier to use.
  assertEquals(parsePkceValue('next~L2ludml0ZQ'), null);
  assertEquals(parsePkceValue('next~L2ludml0ZQ:'), null);
});

// --- starting a sign-in ------------------------------------------------------

Deno.test('OAuth start carries the return path in the verifier cookie', async () => {
  const { deps } = fakeDeps();
  const response = await handleAuthRequest(
    get(`/auth/oauth/start?provider=google&next=${encodeURIComponent(INVITE)}`),
    ENV,
    deps,
  );
  assertEquals(response?.status, 302);
  assertEquals(parsePkceValue(pkceValueOf(response)), {
    verifier: 'verifier-abc',
    recovery: false,
    next: INVITE,
  });
  // The provider is never told where the visitor was headed.
  const location = new URL(response?.headers.get('location') ?? '');
  assertEquals(location.searchParams.get('redirect_to'), `${ORIGIN}/auth/callback`);
  assertEquals(location.toString().includes('invite'), false);
});

Deno.test('OAuth start ignores a return path that is not a page on this site', async () => {
  for (const hostile of HOSTILE) {
    const { deps } = fakeDeps();
    const response = await handleAuthRequest(
      get(`/auth/oauth/start?provider=google&next=${encodeURIComponent(hostile)}`),
      ENV,
      deps,
    );
    // The sign-in still starts; it just has nowhere special to return to.
    assertEquals(response?.status, 302, hostile);
    assertEquals(pkceValueOf(response), 'verifier-abc', hostile);
  }
});

Deno.test('OAuth start honours a return path only from the app itself', async () => {
  const start = `/auth/oauth/start?provider=google&next=${encodeURIComponent(INVITE)}`;
  // The app's own sign-in button, and a browser too old to say.
  const fromTheApp: Record<string, string>[] = [{ 'sec-fetch-site': 'same-origin' }, {}];
  for (const headers of fromTheApp) {
    const { deps } = fakeDeps();
    const response = await handleAuthRequest(get(start, headers), ENV, deps);
    assertEquals(parsePkceValue(pkceValueOf(response))?.next, INVITE);
  }
  // A link on another site, a sibling subdomain, and an address that was
  // typed, pasted or opened from a message: none of them picks the landing.
  for (const site of ['cross-site', 'same-site', 'none']) {
    const { deps } = fakeDeps();
    const response = await handleAuthRequest(get(start, { 'sec-fetch-site': site }), ENV, deps);
    // The sign-in still starts; it ends on the home page.
    assertEquals(response?.status, 302, site);
    assertEquals(pkceValueOf(response), 'verifier-abc', site);
  }
});

Deno.test(
  'a return path that would not fit is dropped, and the sign-in still starts',
  async () => {
    // 58 characters in, 514 out once percent-encoded: over the limit, so it
    // never reaches the cookie. It used to be written and then refused on the
    // way back. A few hundred of them made a cookie the browser threw away,
    // verifier and all, and the sign-in failed.
    for (const length of [57, 334, 335, 511]) {
      const { deps } = fakeDeps();
      const long = `/${'\u4e2d'.repeat(length)}`;
      const response = await handleAuthRequest(
        get(`/auth/oauth/start?provider=google&next=${encodeURIComponent(long)}`),
        ENV,
        deps,
      );
      assertEquals(response?.status, 302, String(length));
      assertEquals(pkceValueOf(response), 'verifier-abc', String(length));
    }
    // The longest path the app could ask for still fits a cookie with room to
    // spare: the value stays far under the 4096 bytes a browser keeps.
    const { deps } = fakeDeps();
    const longest = `/invite?code=${'A'.repeat(512 - '/invite?code='.length)}`;
    const response = await handleAuthRequest(
      get(`/auth/oauth/start?provider=google&next=${encodeURIComponent(longest)}`),
      ENV,
      deps,
    );
    const value = pkceValueOf(response);
    assertEquals(parsePkceValue(value)?.next, longest);
    assertEquals(value.length < 1024, true);
  },
);

Deno.test('the emailed link carries the return path in the verifier cookie', async () => {
  const { deps, paths } = fakeDeps(emailSent);
  const response = await handleAuthRequest(
    post('/auth/otp/send', { email: 'a@example.com', create_user: false, next: INVITE }),
    ENV,
    deps,
  );
  assertEquals(response?.status, 200);
  assertEquals(parsePkceValue(pkceValueOf(response))?.next, INVITE);
  // The emailed link still comes back to the callback, and only there.
  assertEquals(paths[0].includes(encodeURIComponent(`${ORIGIN}/auth/callback`)), true);
  assertEquals(paths[0].includes('invite'), false);
});

Deno.test('a new account that must confirm carries the return path too', async () => {
  const { deps } = fakeDeps(emailSent);
  const response = await handleAuthRequest(
    post('/auth/password/sign-up', {
      email: 'new@example.com',
      password: 'long enough password',
      next: INVITE,
    }),
    ENV,
    deps,
  );
  assertEquals(response?.status, 200);
  assertEquals(parsePkceValue(pkceValueOf(response))?.next, INVITE);
});

Deno.test('the email senders ignore a hostile or malformed return path', async () => {
  for (const hostile of [...HOSTILE, 42, null, { path: INVITE }, [INVITE]]) {
    const { deps } = fakeDeps(emailSent);
    const sent = await handleAuthRequest(
      post('/auth/otp/send', { email: 'a@example.com', create_user: false, next: hostile }),
      ENV,
      deps,
    );
    assertEquals(pkceValueOf(sent), 'verifier-abc', String(hostile));
    const signedUp = await handleAuthRequest(
      post('/auth/password/sign-up', {
        email: 'new@example.com',
        password: 'long enough password',
        next: hostile,
      }),
      ENV,
      deps,
    );
    assertEquals(pkceValueOf(signedUp), 'verifier-abc', String(hostile));
  }
});

Deno.test('the password-reset email never carries a return path', async () => {
  const { deps } = fakeDeps(emailSent);
  const response = await handleAuthRequest(
    post('/auth/password/reset', { email: 'a@example.com', next: INVITE }),
    ENV,
    deps,
  );
  assertEquals(pkceValueOf(response), 'recovery:verifier-abc');
});

// --- coming back -------------------------------------------------------------

async function callbackWith(cookieValue: string): Promise<{
  status: number;
  body: { next?: unknown; recovery?: unknown; access_token?: unknown };
  cleared: boolean;
  verifierSent: unknown;
}> {
  let verifierSent: unknown;
  const deps = fakeDeps().deps;
  const inner = deps.supabaseFetch;
  deps.supabaseFetch = (async (path: string, init: RequestInit) => {
    verifierSent = (JSON.parse(String(init.body)) as { code_verifier?: unknown }).code_verifier;
    return inner(path, init);
  }) as SupabaseAuthFetch;
  const response = await handleAuthRequest(
    post('/auth/callback', { code: 'auth-code' }, asRequestCookie(cookieValue)),
    ENV,
    deps,
  );
  const cleared = (response?.headers.getSetCookie() ?? []).some((value) =>
    value.startsWith(`${PKCE_COOKIE}=;`),
  );
  return {
    status: response?.status ?? 0,
    body: ((await response?.json()) ?? {}) as { next?: unknown; recovery?: unknown },
    cleared,
    verifierSent,
  };
}

Deno.test('the callback hands the return path back with the session', async () => {
  const value = pkceValueOf(
    await handleAuthRequest(
      get(`/auth/oauth/start?provider=apple&next=${encodeURIComponent(INVITE)}`),
      ENV,
      fakeDeps().deps,
    ),
  );
  const result = await callbackWith(value);
  assertEquals(result.status, 200);
  assertEquals(result.body.next, INVITE);
  assertEquals(result.body.recovery, false);
  // The exchange used the verifier, not the marker in front of it.
  assertEquals(result.verifierSent, 'verifier-abc');
  // Single use: the cookie, path and all, is gone.
  assertEquals(result.cleared, true);
});

Deno.test('the callback returns no path when none was carried', async () => {
  const result = await callbackWith('verifier-abc');
  assertEquals(result.status, 200);
  assertEquals(result.body.next, null);
});

Deno.test('the callback returns no path for a recovery link', async () => {
  const result = await callbackWith('recovery:verifier-abc');
  assertEquals(result.status, 200);
  assertEquals(result.body.recovery, true);
  assertEquals(result.body.next, null);
});

Deno.test('the callback checks the path again: a forged cookie gets nowhere', async () => {
  for (const hostile of HOSTILE) {
    if (hostile === '') continue;
    // Built the way the Worker builds it, but with a path the Worker would
    // never have written: as if the cookie had been set by something else.
    const forged = buildPkceCookie('verifier-abc', false, hostile)
      .slice(PKCE_COOKIE.length + 1)
      .split(';')[0];
    assertNotEquals(forged, 'verifier-abc', hostile);
    const result = await callbackWith(forged);
    // The sign-in itself is genuine and completes.
    assertEquals(result.status, 200, hostile);
    assertEquals(result.body.next, null, hostile);
  }
});

Deno.test('a damaged marker still signs in, with nowhere special to go', async () => {
  const result = await callbackWith('next~***:verifier-abc');
  assertEquals(result.status, 200);
  assertEquals(result.body.next, null);
  assertEquals(result.verifierSent, 'verifier-abc');
});
