import { assertEquals } from 'jsr:@std/assert';

import {
  CSRF_HEADER,
  handleAuthRequest,
  type AuthDeps,
  type AuthEnv,
  type SupabaseAuthFetch,
} from './auth.ts';
import { PKCE_COOKIE, REFRESH_COOKIE, REFRESH_MAX_AGE_SECONDS } from './cookies.ts';

/**
 * The /auth/* Worker routes against a stubbed Supabase Auth (issue #1250).
 * The cookie flags, the rotation, the CSRF gate, the callback's
 * different-browser error, and the OAuth start's PKCE wiring are the
 * point; the real-provider runs are #1258's checklist.
 */

const ORIGIN = 'https://app.test';

interface UpstreamCall {
  path: string;
  init: RequestInit;
}

function sessionBody(refresh: string): Record<string, unknown> {
  return {
    access_token: `access-for-${refresh}`,
    refresh_token: refresh,
    expires_in: 3600,
    expires_at: 1700000000,
    user: { id: 'u1', email: 'a@example.com' },
  };
}

/** Builds deps whose upstream is a recorder; refresh tokens tick up per call. */
function fakeDeps(responder?: (call: UpstreamCall) => Response): {
  deps: AuthDeps;
  calls: UpstreamCall[];
} {
  const calls: UpstreamCall[] = [];
  let refreshCounter = 0;
  const deps: AuthDeps = {
    supabaseUrl: 'https://supabase.test',
    publishableKey: 'sb_publishable_test',
    supabaseFetch: (async (path: string, init: RequestInit) => {
      calls.push({ path, init });
      if (responder !== undefined) return responder({ path, init });
      refreshCounter += 1;
      return new Response(JSON.stringify(sessionBody(`refresh-${refreshCounter}`)), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    }) as SupabaseAuthFetch,
    randomVerifier: () => 'verifier-abc',
    codeChallenge: async (verifier) => `challenge-${verifier}`,
  };
  return { deps, calls };
}

const ENV: AuthEnv = { SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test' };

function post(
  path: string,
  body: unknown,
  options: { origin?: string | null; csrf?: boolean; cookie?: string; bearer?: string } = {},
): Request {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (options.origin !== null) headers['origin'] = options.origin ?? ORIGIN;
  if (options.csrf !== false) headers[CSRF_HEADER] = '1';
  if (options.cookie !== undefined) headers['cookie'] = options.cookie;
  if (options.bearer !== undefined) headers['authorization'] = `Bearer ${options.bearer}`;
  return new Request(`${ORIGIN}${path}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
}

/** Reads the error code off a response that may not exist (assert helper). */
async function errorOf(response: Response | null | undefined): Promise<string> {
  return ((await response?.json()) as { error: string } | undefined)?.error ?? 'missing';
}

function get(
  path: string,
  options: { cookie?: string; origin?: string | null; bearer?: string } = {},
): Request {
  const headers: Record<string, string> = {};
  if (options.cookie !== undefined) headers['cookie'] = options.cookie;
  if (options.origin !== null && options.origin !== undefined) {
    headers['origin'] = options.origin;
  }
  if (options.bearer !== undefined) headers['authorization'] = `Bearer ${options.bearer}`;
  return new Request(`${ORIGIN}${path}`, { method: 'GET', headers });
}

Deno.test(
  'password sign-in proxies the grant and sets the __Host- refresh cookie',
  async () => {
    const { deps, calls } = fakeDeps();
    const response = await handleAuthRequest(
      post('/auth/password/sign-in', { email: 'a@example.com', password: 'secret' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    assertEquals(calls.length, 1);
    assertEquals(calls[0].path, '/auth/v1/token?grant_type=password');
    const body = JSON.parse(String(calls[0].init.body));
    assertEquals(body.email, 'a@example.com');
    const headers = new Headers(calls[0].init.headers);
    assertEquals(headers.get('apikey'), 'sb_publishable_test');

    const payload = await response?.json();
    assertEquals(payload.access_token, 'access-for-refresh-1');
    // The refresh token never rides in the body the browser reads.
    assertEquals(payload.refresh_token, undefined);

    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=refresh-1; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=${REFRESH_MAX_AGE_SECONDS}`,
    );
  },
);

Deno.test(
  'session refresh rotates the cookie: the response carries the new token',
  async () => {
    const { deps, calls } = fakeDeps(
      () =>
        new Response(JSON.stringify(sessionBody('rotated-token')), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        }),
    );
    const response = await handleAuthRequest(
      get('/auth/session', { cookie: `${REFRESH_COOKIE}=stale-token` }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    assertEquals(calls[0].path, '/auth/v1/token?grant_type=refresh_token');
    assertEquals(JSON.parse(String(calls[0].init.body)).refresh_token, 'stale-token');
    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=rotated-token; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=${REFRESH_MAX_AGE_SECONDS}`,
    );
    const payload = await response?.json();
    assertEquals(payload.refresh_token, undefined);
    assertEquals(payload.access_token, 'access-for-rotated-token');
    assertEquals(payload.user.email, 'a@example.com');
  },
);

Deno.test('session without the cookie is a plain signed-out', async () => {
  const { deps, calls } = fakeDeps();
  const response = await handleAuthRequest(get('/auth/session'), ENV, deps);

  assertEquals(response?.status, 401);
  assertEquals(await errorOf(response), 'no_session');
  assertEquals(calls.length, 0);
});

Deno.test(
  'a dead refresh family clears the cookie so the next call is a clean signed-out',
  async () => {
    const { deps } = fakeDeps(
      () => new Response(JSON.stringify({ error_code: 'invalid_grant' }), { status: 400 }),
    );
    const response = await handleAuthRequest(
      get('/auth/session', { cookie: `${REFRESH_COOKIE}=stale` }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 400);
    assertEquals(await errorOf(response), 'invalid_grant');
    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );
  },
);

Deno.test(
  'CSRF: a POST without the app Origin is rejected before any upstream call',
  async () => {
    const { deps, calls } = fakeDeps();

    const noOrigin = await handleAuthRequest(
      post(
        '/auth/password/sign-in',
        { email: 'a@example.com', password: 'x' },
        { origin: null },
      ),
      ENV,
      deps,
    );
    assertEquals(noOrigin?.status, 403);
    assertEquals(await errorOf(noOrigin), 'csrf_rejected');

    const foreign = await handleAuthRequest(
      post(
        '/auth/password/sign-in',
        { email: 'a@example.com', password: 'x' },
        { origin: 'https://attacker.test' },
      ),
      ENV,
      deps,
    );
    assertEquals(foreign?.status, 403);

    const noCustomHeader = await handleAuthRequest(
      post(
        '/auth/password/sign-in',
        { email: 'a@example.com', password: 'x' },
        { csrf: false },
      ),
      ENV,
      deps,
    );
    assertEquals(noCustomHeader?.status, 403);

    // A cross-site GET at the session route is rejected on a present foreign
    // Origin too, even though GETs carry no custom header.
    const foreignGet = await handleAuthRequest(
      get('/auth/session', { origin: 'https://attacker.test' }),
      ENV,
      deps,
    );
    assertEquals(foreignGet?.status, 403);

    assertEquals(calls.length, 0);
  },
);

Deno.test('CSRF: the same-origin POST with the custom header passes through', async () => {
  const { deps, calls } = fakeDeps();
  const response = await handleAuthRequest(
    post('/auth/password/sign-in', { email: 'a@example.com', password: 'x' }),
    ENV,
    deps,
  );
  assertEquals(response?.status, 200);
  assertEquals(calls.length, 1);
});

Deno.test(
  'the PKCE callback without a verifier cookie is the different-browser case',
  async () => {
    const { deps, calls } = fakeDeps();
    const response = await handleAuthRequest(
      post('/auth/callback', { code: 'auth-code' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 401);
    assertEquals(await errorOf(response), 'verifier_missing');
    assertEquals(calls.length, 0);
  },
);

Deno.test('the PKCE callback exchanges with the cookie verifier and consumes it', async () => {
  const { deps, calls } = fakeDeps();
  const response = await handleAuthRequest(
    post('/auth/callback', { code: 'auth-code' }, { cookie: `${PKCE_COOKIE}=verifier-abc` }),
    ENV,
    deps,
  );

  assertEquals(response?.status, 200);
  assertEquals(calls[0].path, '/auth/v1/token?grant_type=pkce');
  assertEquals(JSON.parse(String(calls[0].init.body)), {
    auth_code: 'auth-code',
    code_verifier: 'verifier-abc',
  });
  // An unmarked (sign-up / magic-link / OAuth) cookie is not recovery.
  assertEquals(
    ((await response?.json()) as { recovery: boolean } | undefined)?.recovery,
    false,
  );
  const setCookies = response?.headers.getSetCookie() ?? [];
  assertEquals(setCookies.length, 2);
  assertEquals(
    setCookies[0],
    `${REFRESH_COOKIE}=refresh-1; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=${REFRESH_MAX_AGE_SECONDS}`,
  );
  assertEquals(
    setCookies[1],
    `${PKCE_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
  );
});

Deno.test(
  'a failed callback exchange keeps the verifier (the code may simply be mistyped)',
  async () => {
    const { deps } = fakeDeps(
      () => new Response(JSON.stringify({ error_code: 'invalid_grant' }), { status: 400 }),
    );
    const response = await handleAuthRequest(
      post('/auth/callback', { code: 'spent' }, { cookie: `${PKCE_COOKIE}=verifier-abc` }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 400);
    assertEquals(await errorOf(response), 'invalid_grant');
    assertEquals(response?.headers.getSetCookie().length, 0);
  },
);

Deno.test(
  'OAuth start redirects to the provider with the S256 challenge and the verifier cookie',
  async () => {
    const { deps, calls } = fakeDeps();
    const response = await handleAuthRequest(
      get('/auth/oauth/start?provider=google'),
      ENV,
      deps,
    );

    assertEquals(response?.status, 302);
    const location = new URL(response?.headers.get('location') ?? '');
    assertEquals(
      location.origin + location.pathname,
      'https://supabase.test/auth/v1/authorize',
    );
    assertEquals(location.searchParams.get('provider'), 'google');
    assertEquals(location.searchParams.get('redirect_to'), `${ORIGIN}/auth/callback`);
    assertEquals(location.searchParams.get('code_challenge'), 'challenge-verifier-abc');
    assertEquals(location.searchParams.get('code_challenge_method'), 's256');
    assertEquals(
      response?.headers.get('set-cookie'),
      `${PKCE_COOKIE}=verifier-abc; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=600`,
    );
    // Starting OAuth is a pure redirect: no upstream HTTP call.
    assertEquals(calls.length, 0);
  },
);

Deno.test('OAuth start accepts apple and rejects unknown providers', async () => {
  const { deps } = fakeDeps();
  const apple = await handleAuthRequest(get('/auth/oauth/start?provider=apple'), ENV, deps);
  assertEquals(apple?.status, 302);
  assertEquals(
    new URL(apple?.headers.get('location') ?? '').searchParams.get('provider'),
    'apple',
  );

  const unknown = await handleAuthRequest(get('/auth/oauth/start?provider=blob'), ENV, deps);
  assertEquals(unknown?.status, 400);
  assertEquals(await errorOf(unknown), 'unknown_provider');
});

Deno.test(
  'otp send wires the PKCE challenge and redirects the emailed link to this origin',
  async () => {
    const { deps, calls } = fakeDeps();
    const response = await handleAuthRequest(
      post('/auth/otp/send', { email: 'a@example.com', create_user: false }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    const target = new URL(`https://supabase.test${calls[0].path}`);
    assertEquals(target.pathname, '/auth/v1/otp');
    assertEquals(target.searchParams.get('redirect_to'), `${ORIGIN}/auth/callback`);
    const body = JSON.parse(String(calls[0].init.body));
    assertEquals(body.email, 'a@example.com');
    assertEquals(body.create_user, false);
    assertEquals(body.code_challenge, 'challenge-verifier-abc');
    assertEquals(body.code_challenge_method, 's256');
    assertEquals(
      response?.headers.get('set-cookie'),
      `${PKCE_COOKIE}=verifier-abc; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=600`,
    );
  },
);

Deno.test('otp verify validates the type allowlist and returns the session', async () => {
  const { deps, calls } = fakeDeps();
  const ok = await handleAuthRequest(
    post('/auth/otp/verify', { email: 'a@example.com', token: ' 1234 5678 ', type: 'email' }),
    ENV,
    deps,
  );
  assertEquals(ok?.status, 200);
  assertEquals(calls[0].path, '/auth/v1/verify');
  assertEquals(JSON.parse(String(calls[0].init.body)), {
    email: 'a@example.com',
    token: '12345678',
    type: 'email',
  });

  const badType = await handleAuthRequest(
    post('/auth/otp/verify', { email: 'a@example.com', token: '1', type: 'sms' }),
    ENV,
    deps,
  );
  assertEquals(badType?.status, 400);
  assertEquals(await errorOf(badType), 'email_token_type_required');
});

Deno.test(
  'password reset points the emailed link at this origin and sets the verifier cookie',
  async () => {
    const { deps, calls } = fakeDeps();
    const response = await handleAuthRequest(
      post('/auth/password/reset', { email: 'a@example.com' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    const target = new URL(`https://supabase.test${calls[0].path}`);
    assertEquals(target.pathname, '/auth/v1/recover');
    assertEquals(target.searchParams.get('redirect_to'), `${ORIGIN}/auth/callback`);
    assertEquals(
      JSON.parse(String(calls[0].init.body)).code_challenge,
      'challenge-verifier-abc',
    );
    // The recover flow's cookie is the one carrying the recovery marker
    // (issue #1293); the otp send's cookie above stays unmarked.
    assertEquals(
      response?.headers.getSetCookie()[0],
      `${PKCE_COOKIE}=recovery:verifier-abc; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=600`,
    );
  },
);

Deno.test(
  'the recovery flow: the exchange echoes recovery from the marked cookie (issue #1293)',
  async () => {
    const { deps, calls } = fakeDeps();
    const send = await handleAuthRequest(
      post('/auth/password/reset', { email: 'a@example.com' }),
      ENV,
      deps,
    );
    assertEquals(send?.status, 200);

    // The marked cookie exchanges exactly like a plain one: the verifier
    // travels to GoTrue bare, and the marker only surfaces in the body.
    const exchange = await handleAuthRequest(
      post(
        '/auth/callback',
        { code: 'auth-code' },
        { cookie: `${PKCE_COOKIE}=recovery:verifier-abc` },
      ),
      ENV,
      deps,
    );

    assertEquals(exchange?.status, 200);
    assertEquals(calls[1].path, '/auth/v1/token?grant_type=pkce');
    assertEquals(JSON.parse(String(calls[1].init.body)), {
      auth_code: 'auth-code',
      code_verifier: 'verifier-abc',
    });
    const payload = await exchange?.json();
    assertEquals(payload.recovery, true);
    // The verifier is consumed on success, marker and all.
    assertEquals(
      exchange?.headers.getSetCookie()[1],
      `${PKCE_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );
  },
);

Deno.test(
  'a marked cookie with no verifier after the marker is the different-browser case (issue #1293)',
  async () => {
    const { deps, calls } = fakeDeps();
    const response = await handleAuthRequest(
      post('/auth/callback', { code: 'auth-code' }, { cookie: `${PKCE_COOKIE}=recovery:` }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 401);
    assertEquals(await errorOf(response), 'verifier_missing');
    assertEquals(calls.length, 0);
  },
);

Deno.test('password update forwards the in-memory access token as the bearer', async () => {
  const { deps, calls } = fakeDeps();

  const noToken = await handleAuthRequest(
    post('/auth/password/update', { password: 'new password' }),
    ENV,
    deps,
  );
  assertEquals(noToken?.status, 401);

  const ok = await handleAuthRequest(
    post('/auth/password/update', { password: 'new password' }, { bearer: 'access-1' }),
    ENV,
    deps,
  );
  assertEquals(ok?.status, 200);
  assertEquals(calls[0].path, '/auth/v1/user');
  const init = calls[0].init;
  assertEquals(init.method, 'PUT');
  assertEquals(new Headers(init.headers).get('authorization'), 'Bearer access-1');
  assertEquals(JSON.parse(String(init.body)).password, 'new password');
});

/** A GoTrue-shaped error response: the status in the body as well as the line. */
function gotrueError(status: number, errorCode: string): Response {
  return new Response(
    JSON.stringify({ code: status, error_code: errorCode, msg: 'for testing' }),
    { status, headers: { 'content-type': 'application/json' } },
  );
}

Deno.test(
  'sign-out global reports the failure on a bare gateway 401 (issue #1343)',
  async () => {
    // A 401 that is not GoTrue's own answer — the API gateway
    // rejecting a rotated publishable key, say — means GoTrue never
    // evaluated the request, so nothing was revoked and the response must
    // say so. GoTrue's own 403 `error_code`s no longer count as
    // already-revoked either: since #1364 they retry once from the cookie
    // instead (supabase-js's blind 401/403/404 tolerance is why the old
    // bare-401 shortcut looked plausible).
    const { deps, calls } = fakeDeps(() => new Response(null, { status: 401 }));
    const response = await handleAuthRequest(
      post('/auth/sign-out', { scope: 'global' }, { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 502);
    assertEquals(await errorOf(response), 'revocation_failed');
    assertEquals(calls[0].path, '/auth/v1/logout?scope=global');
    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );

    const badScope = await handleAuthRequest(
      post('/auth/sign-out', { scope: 'others' }, { bearer: 'access-1' }),
      ENV,
      deps,
    );
    assertEquals(badScope?.status, 400);
  },
);

Deno.test(
  'sign-out without a live access token refreshes once from the cookie first',
  async () => {
    const { deps, calls } = fakeDeps();
    const response = await handleAuthRequest(
      post('/auth/sign-out', { scope: 'local' }, { cookie: `${REFRESH_COOKIE}=refresh-1` }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    assertEquals(calls[0].path, '/auth/v1/token?grant_type=refresh_token');
    assertEquals(calls[1].path, '/auth/v1/logout?scope=local');
    assertEquals(
      new Headers(calls[1].init.headers).get('authorization'),
      'Bearer access-for-refresh-1',
    );
  },
);

Deno.test(
  'sign-out global reports the failure when the logout fetch rejects (issue #1324)',
  async () => {
    // GoTrue times out or resets the connection: the fetch rejects instead
    // of resolving to an error status. The revocation never landed, so the
    // response must say so — but the browser's session still ends, because
    // the cleared cookie rides on the failure response too (issue #1292).
    const { deps, calls } = fakeDeps(() => {
      throw new TypeError('fetch failed');
    });
    const response = await handleAuthRequest(
      post('/auth/sign-out', { scope: 'global' }, { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 502);
    assertEquals(await errorOf(response), 'revocation_failed');
    assertEquals(calls[0].path, '/auth/v1/logout?scope=global');
    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );
  },
);

Deno.test(
  'sign-out local stays a success when the logout fetch rejects (issue #1292)',
  async () => {
    // `local`'s goal is this browser's cookie, which clears below
    // regardless: the upstream revocation stays best-effort here even as
    // `global` now reports its own failures (issue #1324).
    const { deps, calls } = fakeDeps(() => {
      throw new TypeError('fetch failed');
    });
    const response = await handleAuthRequest(
      post('/auth/sign-out', { scope: 'local' }, { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    assertEquals(((await response?.json()) as { ok: boolean } | undefined)?.ok, true);
    assertEquals(calls[0].path, '/auth/v1/logout?scope=local');
    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );
  },
);

Deno.test(
  'sign-out without a bearer still clears the cookie when the refresh leg rejects (issue #1292)',
  async () => {
    // No live access token and the cookie-refresh fetch rejects: no bearer
    // ever exists, the logout leg is skipped, and the response is still
    // the cleared-cookie 200 — never a thrown 500.
    const { deps, calls } = fakeDeps(() => {
      throw new TypeError('fetch failed');
    });
    const response = await handleAuthRequest(
      post('/auth/sign-out', { scope: 'local' }, { cookie: `${REFRESH_COOKIE}=refresh-1` }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    assertEquals(calls.length, 1);
    assertEquals(calls[0].path, '/auth/v1/token?grant_type=refresh_token');
    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );
  },
);

Deno.test(
  'sign-out global without a bearer reports the failure when the refresh leg rejects (issue #1324)',
  async () => {
    // No live access token and the cookie-refresh fetch rejects: no bearer
    // ever exists, the logout leg never runs, and nothing was revoked —
    // "Sign out everywhere" must not read as success. The cookie still
    // clears (issue #1292).
    const { deps, calls } = fakeDeps(() => {
      throw new TypeError('fetch failed');
    });
    const response = await handleAuthRequest(
      post('/auth/sign-out', { scope: 'global' }, { cookie: `${REFRESH_COOKIE}=refresh-1` }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 502);
    assertEquals(await errorOf(response), 'revocation_failed');
    assertEquals(calls.length, 1);
    assertEquals(calls[0].path, '/auth/v1/token?grant_type=refresh_token');
    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );
  },
);

Deno.test(
  'sign-out global reports the failure when the logout returns a server error (issue #1324)',
  async () => {
    // GoTrue answered, but not with a revocation: a 500 means the other
    // devices' refresh-token families were not touched. The 403 retry leg
    // never applies to a non-403 answer (issue #1364), so the failure
    // stands.
    const { deps, calls } = fakeDeps(() => new Response(null, { status: 500 }));
    const response = await handleAuthRequest(
      post('/auth/sign-out', { scope: 'global' }, { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 502);
    assertEquals(await errorOf(response), 'revocation_failed');
    assertEquals(calls[0].path, '/auth/v1/logout?scope=global');
    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );
  },
);

Deno.test(
  'sign-out global succeeds on GoTrue revoking (204), not on a bare 404 (issue #1343)',
  async () => {
    // 204 is GoTrue's real revocation answer. A bare 404 used to count as
    // "already revoked" too, but it is just as likely a misrouted base
    // URL — GoTrue's own already-gone answer is 403 `session_not_found`
    // (issue #1343), so a bare 404 is now a reported failure like any
    // other answer GoTrue did not evaluate.
    const revoked = fakeDeps(() => new Response(null, { status: 204 }));
    const ok = await handleAuthRequest(
      post('/auth/sign-out', { scope: 'global' }, { bearer: 'access-1' }),
      ENV,
      revoked.deps,
    );
    assertEquals(ok?.status, 200);
    assertEquals(((await ok?.json()) as { ok: boolean } | undefined)?.ok, true);
    assertEquals(revoked.calls[0].path, '/auth/v1/logout?scope=global');
    assertEquals(
      ok?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );

    const misrouted = fakeDeps(() => new Response(null, { status: 404 }));
    const failed = await handleAuthRequest(
      post('/auth/sign-out', { scope: 'global' }, { bearer: 'access-1' }),
      ENV,
      misrouted.deps,
    );
    assertEquals(failed?.status, 502);
    assertEquals(await errorOf(failed), 'revocation_failed');
  },
);

Deno.test(
  'sign-out global reports revocation_failed on 403 session_not_found with no cookie (issue #1364)',
  async () => {
    // session_not_found only proves the *caller's* session is gone: the
    // Logout handler never ran, so the account's other sessions were not
    // revoked (issue #1364). The session may have died to a local sign-out
    // in another tab, an inactivity limit, or a refresh-token reuse, with
    // the phone's session still live. No refresh cookie to retry from:
    // the failure is reported, not the old blanket success (issue #1343).
    const { deps, calls } = fakeDeps(() => gotrueError(403, 'session_not_found'));
    const response = await handleAuthRequest(
      post('/auth/sign-out', { scope: 'global' }, { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 502);
    assertEquals(await errorOf(response), 'revocation_failed');
    assertEquals(calls.length, 1);
    assertEquals(calls[0].path, '/auth/v1/logout?scope=global');
    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );
  },
);

Deno.test(
  'sign-out global retries once from the cookie on 403 session_not_found (issue #1364)',
  async () => {
    // The bearer's session is gone, but the HttpOnly cookie still holds a
    // live refresh token: refresh once and retry, the bad_jwt leg's
    // mechanics. The retry's own 204 is the landed revocation the first
    // answer could not prove.
    let logouts = 0;
    const { deps, calls } = fakeDeps(({ path }) => {
      if (path === '/auth/v1/logout?scope=global') {
        logouts += 1;
        return logouts === 1
          ? gotrueError(403, 'session_not_found')
          : new Response(null, { status: 204 });
      }
      return new Response(JSON.stringify(sessionBody('refresh-2')), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    });
    const response = await handleAuthRequest(
      post(
        '/auth/sign-out',
        { scope: 'global' },
        { bearer: 'access-gone', cookie: `${REFRESH_COOKIE}=refresh-1` },
      ),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    assertEquals(((await response?.json()) as { ok: boolean } | undefined)?.ok, true);
    assertEquals(calls.length, 3);
    assertEquals(calls[0].path, '/auth/v1/logout?scope=global');
    assertEquals(calls[1].path, '/auth/v1/token?grant_type=refresh_token');
    assertEquals(JSON.parse(String(calls[1].init.body)).refresh_token, 'refresh-1');
    assertEquals(calls[2].path, '/auth/v1/logout?scope=global');
    assertEquals(
      new Headers(calls[2].init.headers).get('authorization'),
      'Bearer access-for-refresh-2',
    );
    // The browser's session ends on the retried sign-out too.
    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );
  },
);

Deno.test(
  'sign-out global fails closed when the retried logout also answers session_not_found (issue #1364)',
  async () => {
    // Even on the retry, session_not_found means the Logout handler never
    // ran (requireAuthentication rejected the fresh bearer first): it is
    // not a landed revocation, so the failure stands.
    const { deps, calls } = fakeDeps(({ path }) =>
      path === '/auth/v1/logout?scope=global'
        ? gotrueError(403, 'session_not_found')
        : new Response(JSON.stringify(sessionBody('refresh-2')), {
            status: 200,
            headers: { 'content-type': 'application/json' },
          }),
    );
    const response = await handleAuthRequest(
      post(
        '/auth/sign-out',
        { scope: 'global' },
        { bearer: 'access-gone', cookie: `${REFRESH_COOKIE}=refresh-1` },
      ),
      ENV,
      deps,
    );

    assertEquals(response?.status, 502);
    assertEquals(await errorOf(response), 'revocation_failed');
    assertEquals(calls.length, 3);
    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );
  },
);

Deno.test(
  'sign-out local still succeeds on 403 session_not_found without a retry (issue #1364)',
  async () => {
    // `local`'s goal is this browser's cookie, which clears below either
    // way, and the bearer's own session is already gone: success without
    // the cookie-refresh retry `global` needs (issue #1364).
    const { deps, calls } = fakeDeps(() => gotrueError(403, 'session_not_found'));
    const response = await handleAuthRequest(
      post('/auth/sign-out', { scope: 'local' }, { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    assertEquals(((await response?.json()) as { ok: boolean } | undefined)?.ok, true);
    assertEquals(calls.length, 1);
    assertEquals(calls[0].path, '/auth/v1/logout?scope=local');
    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );
  },
);

Deno.test(
  'sign-out global refreshes from the cookie and retries once on 403 bad_jwt (issue #1343)',
  async () => {
    // The in-memory access token no longer verifies (expiry under clock
    // skew): GoTrue answers 403 `bad_jwt`. The Worker refreshes once from
    // the HttpOnly cookie and retries with the fresh bearer — the
    // recoverable path a bearer-present sign-out never took before (the
    // cookie-refresh leg used to run only when the bearer was missing).
    let logouts = 0;
    const { deps, calls } = fakeDeps(({ path }) => {
      if (path === '/auth/v1/logout?scope=global') {
        logouts += 1;
        return logouts === 1
          ? gotrueError(403, 'bad_jwt')
          : new Response(null, { status: 204 });
      }
      return new Response(JSON.stringify(sessionBody('refresh-2')), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    });
    const response = await handleAuthRequest(
      post(
        '/auth/sign-out',
        { scope: 'global' },
        { bearer: 'access-stale', cookie: `${REFRESH_COOKIE}=refresh-1` },
      ),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    assertEquals(((await response?.json()) as { ok: boolean } | undefined)?.ok, true);
    assertEquals(calls.length, 3);
    assertEquals(calls[0].path, '/auth/v1/logout?scope=global');
    assertEquals(calls[1].path, '/auth/v1/token?grant_type=refresh_token');
    assertEquals(JSON.parse(String(calls[1].init.body)).refresh_token, 'refresh-1');
    assertEquals(calls[2].path, '/auth/v1/logout?scope=global');
    assertEquals(
      new Headers(calls[2].init.headers).get('authorization'),
      'Bearer access-for-refresh-2',
    );
    // The browser's session ends on the retried sign-out too.
    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );
  },
);

Deno.test(
  'sign-out global without a cookie stays a failure on 403 bad_jwt (issue #1343)',
  async () => {
    // No refresh cookie to refresh from: the retry leg cannot run, and the
    // stale bearer's rejection is reported instead of read as success.
    const { deps, calls } = fakeDeps(() => gotrueError(403, 'bad_jwt'));
    const response = await handleAuthRequest(
      post('/auth/sign-out', { scope: 'global' }, { bearer: 'access-stale' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 502);
    assertEquals(await errorOf(response), 'revocation_failed');
    assertEquals(calls.length, 1);
    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );
  },
);

Deno.test(
  'sign-out global fails closed when the bad_jwt retry answers session_not_found (issue #1364)',
  async () => {
    // The retried answer must itself be a landed revocation: a retried
    // session_not_found still means the Logout handler never ran, so the
    // old `ok || retried session_not_found` shortcut was the same false
    // success the first-attempt branch carried (issue #1364).
    let logouts = 0;
    const { deps, calls } = fakeDeps(({ path }) => {
      if (path === '/auth/v1/logout?scope=global') {
        logouts += 1;
        return logouts === 1
          ? gotrueError(403, 'bad_jwt')
          : gotrueError(403, 'session_not_found');
      }
      return new Response(JSON.stringify(sessionBody('refresh-2')), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    });
    const response = await handleAuthRequest(
      post(
        '/auth/sign-out',
        { scope: 'global' },
        { bearer: 'access-stale', cookie: `${REFRESH_COOKIE}=refresh-1` },
      ),
      ENV,
      deps,
    );

    assertEquals(response?.status, 502);
    assertEquals(await errorOf(response), 'revocation_failed');
    assertEquals(calls.length, 3);
    assertEquals(
      response?.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
    );
  },
);

Deno.test(
  'sign-out global fails closed on an unrecognised 403 error code (issue #1343)',
  async () => {
    // Only `session_not_found` and `bad_jwt` are the known 403s; any other
    // code — a future GoTrue addition, a different 403 — must not read as
    // a landed revocation.
    const { deps } = fakeDeps(() => gotrueError(403, 'insufficient_scope'));
    const response = await handleAuthRequest(
      post('/auth/sign-out', { scope: 'global' }, { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 502);
    assertEquals(await errorOf(response), 'revocation_failed');
  },
);

Deno.test(
  'sign-up with email confirmation on returns no session but starts the PKCE flow',
  async () => {
    const { deps, calls } = fakeDeps(
      () =>
        new Response(JSON.stringify({ user: { id: 'u2', email: 'new@example.com' } }), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        }),
    );
    const response = await handleAuthRequest(
      post('/auth/password/sign-up', { email: 'new@example.com', password: 'secret' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    const target = new URL(`https://supabase.test${calls[0].path}`);
    assertEquals(target.pathname, '/auth/v1/signup');
    assertEquals(target.searchParams.get('redirect_to'), `${ORIGIN}/auth/callback`);
    const payload = await response?.json();
    assertEquals(payload.session, false);
    assertEquals(payload.user.email, 'new@example.com');
    assertEquals(payload.refresh_token, undefined);
    // The confirmation link carries a PKCE code this browser can exchange.
    assertEquals(
      response?.headers.get('set-cookie')?.startsWith(`${PKCE_COOKIE}=verifier-abc`),
      true,
    );
  },
);

Deno.test('the real client IP rides to Supabase for its per-IP rate limiting', async () => {
  const { deps, calls } = fakeDeps();
  const request = new Request(`${ORIGIN}/auth/password/sign-in`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      origin: ORIGIN,
      [CSRF_HEADER]: '1',
      'cf-connecting-ip': '203.0.113.9',
    },
    body: JSON.stringify({ email: 'a@example.com', password: 'x' }),
  });
  await handleAuthRequest(request, ENV, deps);
  assertEquals(new Headers(calls[0].init.headers).get('x-forwarded-for'), '203.0.113.9');
});

Deno.test(
  'unconfigured builds get a 503, and non-auth paths fall through to the SPA',
  async () => {
    const { deps } = fakeDeps();
    const unconfigured = await handleAuthRequest(
      get('/auth/session'),
      { SUPABASE_PUBLISHABLE_KEY: '' },
      deps,
    );
    assertEquals(unconfigured?.status, 503);

    assertEquals(await handleAuthRequest(get('/'), ENV, deps), null);
    assertEquals(
      await handleAuthRequest(get('/auth/callback?code=from-provider'), ENV, deps),
      null,
    );
    assertEquals(await handleAuthRequest(get('/auth/somewhere'), ENV, deps), null);
    assertEquals(await handleAuthRequest(get('/sign-in'), ENV, deps), null);
  },
);

// ---------------------------------------------------------------------------
// Identity linking, unlinking, and the Apple delete ceremony (issue #1256)
// ---------------------------------------------------------------------------

const APPLE_SERVICES_ID = 'com.wjdavis5.lunarlog.web';

function upstreamUser(identities: Array<{ provider: string; id: string }>): Response {
  return new Response(JSON.stringify({ id: 'u1', email: 'a@example.com', identities }), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
}

Deno.test(
  "GET /auth/identities resolves the caller's linked providers from their own GoTrue user",
  async () => {
    const { deps, calls } = fakeDeps(({ path }) => {
      assertEquals(path, '/auth/v1/user');
      return upstreamUser([
        { provider: 'email', id: 'email-1' },
        { provider: 'apple', id: 'apple-1' },
      ]);
    });

    const response = await handleAuthRequest(
      get('/auth/identities', { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    assertEquals(new Headers(calls[0].init.headers).get('authorization'), 'Bearer access-1');
    const payload = (await response?.json()) as { email: string; providers: string[] };
    assertEquals(payload.email, 'a@example.com');
    assertEquals(payload.providers, ['email', 'apple']);
  },
);

Deno.test(
  'GET /auth/identities without a bearer is 401 (the caller is always their own subject)',
  async () => {
    const { deps, calls } = fakeDeps();

    const response = await handleAuthRequest(get('/auth/identities'), ENV, deps);

    assertEquals(response?.status, 401);
    assertEquals(calls.length, 0);
  },
);

Deno.test(
  "POST /auth/identities/link starts a PKCE link flow against GoTrue's link authorize endpoint",
  async () => {
    const { deps, calls } = fakeDeps(
      () =>
        new Response(JSON.stringify({ url: 'https://appleid.apple.com/auth/authorize?x=1' }), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        }),
    );

    const response = await handleAuthRequest(
      post('/auth/identities/link', { provider: 'apple' }, { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    assertEquals(calls.length, 1);
    assertEquals(
      calls[0].path,
      '/auth/v1/user/identities/authorize?provider=apple&redirect_to=https%3A%2F%2Fapp.test%2Fauth%2Fcallback&code_challenge=challenge-verifier-abc&code_challenge_method=s256&skip_http_redirect=true',
    );
    const headers = new Headers(calls[0].init.headers);
    assertEquals(headers.get('authorization'), 'Bearer access-1');
    const payload = (await response?.json()) as { url: string };
    assertEquals(payload.url, 'https://appleid.apple.com/auth/authorize?x=1');
    assertEquals(
      response?.headers.get('set-cookie'),
      `${PKCE_COOKIE}=verifier-abc; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=600`,
    );
  },
);

Deno.test(
  'POST /auth/identities/link refuses unknown providers and missing bearers',
  async () => {
    const { deps, calls } = fakeDeps();

    const noBearer = await handleAuthRequest(
      post('/auth/identities/link', { provider: 'apple' }),
      ENV,
      deps,
    );
    const badProvider = await handleAuthRequest(
      post('/auth/identities/link', { provider: 'email' }, { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(noBearer?.status, 401);
    assertEquals(badProvider?.status, 400);
    assertEquals(await errorOf(badProvider), 'unknown_provider');
    assertEquals(calls.length, 0);
  },
);

Deno.test(
  'POST /auth/identities/link forwards upstream failures with their codes',
  async () => {
    const { deps } = fakeDeps(
      () =>
        new Response(JSON.stringify({ error_code: 'identity_already_exists' }), {
          status: 422,
        }),
    );

    const response = await handleAuthRequest(
      post('/auth/identities/link', { provider: 'google' }, { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 422);
    assertEquals(await errorOf(response), 'identity_already_exists');
  },
);

Deno.test(
  'POST /auth/identities/link answers 502 when upstream omits the provider URL',
  async () => {
    const { deps } = fakeDeps(() => new Response(JSON.stringify({}), { status: 200 }));

    const response = await handleAuthRequest(
      post('/auth/identities/link', { provider: 'google' }, { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 502);
    assertEquals(await errorOf(response), 'upstream_authorize_shape');
  },
);

Deno.test(
  "POST /auth/identities/unlink resolves the identity id from the caller's own user and DELETEs it",
  async () => {
    const { deps, calls } = fakeDeps(({ path, init }) => {
      if (path === '/auth/v1/user') {
        return upstreamUser([
          { provider: 'email', id: 'email-1' },
          { provider: 'google', id: 'google-42' },
        ]);
      }
      assertEquals(path, '/auth/v1/user/identities/google-42');
      assertEquals(init.method, 'DELETE');
      assertEquals(new Headers(init.headers).get('authorization'), 'Bearer access-1');
      return new Response(JSON.stringify({ id: 'u1' }), { status: 200 });
    });

    const response = await handleAuthRequest(
      post('/auth/identities/unlink', { provider: 'google' }, { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    assertEquals(await response?.json(), { ok: true });
    assertEquals(calls.length, 2);
  },
);

Deno.test(
  'POST /auth/identities/unlink 404s a provider that is not linked, and never DELETEs',
  async () => {
    const { deps, calls } = fakeDeps(() =>
      upstreamUser([{ provider: 'email', id: 'email-1' }]),
    );

    const response = await handleAuthRequest(
      post('/auth/identities/unlink', { provider: 'google' }, { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 404);
    assertEquals(await errorOf(response), 'identity_not_found');
    assertEquals(calls.length, 1, 'only the user read runs; no identity DELETE');
  },
);

Deno.test(
  'POST /auth/identities/unlink only ever removes the two OAuth providers, never the email identity',
  async () => {
    const { deps, calls } = fakeDeps();

    const response = await handleAuthRequest(
      post('/auth/identities/unlink', { provider: 'email' }, { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 400);
    assertEquals(await errorOf(response), 'unknown_provider');
    assertEquals(calls.length, 0);
  },
);

// The Apple step of account deletion. Landing back on the account page with
// a state that matches the cookie is what lets the deletion go ahead, so
// the whole ceremony belongs to one signed-in account pressing a button on
// that page. These tests hold both ends to that.

const APPLE_USER = '11111111-2222-4333-8444-555555555555';
const OTHER_USER = '99999999-8888-4777-8666-555555555555';
const APPLE_DELETE_PENDING = `__Host-ll_apple_delete=verifier-abc.${APPLE_USER}`;

/** Upstream answers GET /auth/v1/user as [userId]; anything else is a bug. */
function userIs(userId: string): (call: UpstreamCall) => Response {
  return (call) => {
    if (call.path !== '/auth/v1/user') throw new Error(`unexpected upstream call ${call.path}`);
    return new Response(JSON.stringify({ id: userId, email: 'a@example.com' }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  };
}

Deno.test(
  'POST /auth/apple/delete/start answers with Apple under the Services ID and a state cookie',
  async () => {
    const { deps, calls } = fakeDeps(userIs(APPLE_USER));

    const response = await handleAuthRequest(
      post('/auth/apple/delete/start', {}, { bearer: 'access-1' }),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    assertEquals(response?.headers.get('cache-control'), 'no-store');
    // An answer for the page to act on, never a redirect a link could ride.
    assertEquals(response?.headers.get('location'), null);
    const body = (await response?.json()) as { url: string };
    const location = new URL(body.url);
    assertEquals(location.origin, 'https://appleid.apple.com');
    assertEquals(location.pathname, '/auth/authorize');
    assertEquals(location.searchParams.get('response_type'), 'code');
    assertEquals(location.searchParams.get('response_mode'), 'query');
    assertEquals(location.searchParams.get('client_id'), APPLE_SERVICES_ID);
    assertEquals(location.searchParams.get('redirect_uri'), 'https://app.test/account');
    assertEquals(location.searchParams.get('state'), 'verifier-abc');
    // The cookie names the account that asked, beside the nonce. Apple is
    // told only the nonce.
    assertEquals(
      response?.headers.get('set-cookie'),
      `__Host-ll_apple_delete=verifier-abc.${APPLE_USER}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=600`,
    );
    assertEquals(body.url.includes(APPLE_USER), false);
    // The account is read from GoTrue with the caller's own token.
    assertEquals(calls.length, 1);
    assertEquals(
      new Headers(calls[0].init.headers).get('authorization'),
      'Bearer access-1',
    );
  },
);

Deno.test('a link cannot start the Apple delete ceremony', async () => {
  // This is how it used to start: a plain GET that set the state cookie and
  // redirected out to Apple. A link can be followed from anywhere, so
  // another site could send a signed-in reader through it. A browser sends
  // no Origin on such a navigation, whatever site the link was on, and
  // would send the session along.
  for (const options of [
    {},
    { origin: ORIGIN },
    { bearer: 'access-1' },
    { cookie: '__Host-ll_refresh=refresh-1' },
  ]) {
    const { deps, calls } = fakeDeps(userIs(APPLE_USER));
    const response = await handleAuthRequest(
      get('/auth/apple/delete/start', options),
      ENV,
      deps,
    );
    // Not an auth route at all any more: no cookie, no way out to Apple.
    assertEquals(response, null, JSON.stringify(options));
    assertEquals(calls.length, 0);
  }
});

Deno.test('POST /auth/apple/delete/start is behind the whole CSRF gate', async () => {
  for (const options of [
    { origin: 'https://attacker.test', bearer: 'access-1' },
    { origin: null, bearer: 'access-1' },
    { csrf: false, bearer: 'access-1' },
  ]) {
    const { deps, calls } = fakeDeps(userIs(APPLE_USER));
    const response = await handleAuthRequest(
      post('/auth/apple/delete/start', {}, options),
      ENV,
      deps,
    );
    assertEquals(response?.status, 403, JSON.stringify(options));
    assertEquals(await errorOf(response), 'csrf_rejected');
    assertEquals(response?.headers.get('set-cookie'), null);
    assertEquals(calls.length, 0);
  }
});

Deno.test('POST /auth/apple/delete/start needs a signed-in caller GoTrue vouches for', async () => {
  const anonymous = fakeDeps(userIs(APPLE_USER));
  const noBearer = await handleAuthRequest(
    post('/auth/apple/delete/start', {}),
    ENV,
    anonymous.deps,
  );
  assertEquals(noBearer?.status, 401);
  assertEquals(await errorOf(noBearer), 'access_token_required');
  assertEquals(noBearer?.headers.get('set-cookie'), null);
  assertEquals(anonymous.calls.length, 0);

  // A token GoTrue refuses starts nothing either.
  const refused = fakeDeps(
    () =>
      new Response(JSON.stringify({ error_code: 'bad_jwt' }), {
        status: 403,
        headers: { 'content-type': 'application/json' },
      }),
  );
  const badToken = await handleAuthRequest(
    post('/auth/apple/delete/start', {}, { bearer: 'forged' }),
    ENV,
    refused.deps,
  );
  assertEquals(badToken?.status, 403);
  assertEquals(await errorOf(badToken), 'bad_jwt');
  assertEquals(badToken?.headers.get('set-cookie'), null);

  // Nor does an answer with no usable account id in it.
  for (const id of [undefined, '', 'not.a.uuid', 'a;b']) {
    const odd = fakeDeps(
      () =>
        new Response(JSON.stringify({ id }), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        }),
    );
    const response = await handleAuthRequest(
      post('/auth/apple/delete/start', {}, { bearer: 'access-1' }),
      ENV,
      odd.deps,
    );
    assertEquals(response?.status, 502, String(id));
    assertEquals(await errorOf(response), 'upstream_user_shape');
    assertEquals(response?.headers.get('set-cookie'), null);
  }
});

Deno.test(
  'POST /auth/apple/delete/complete accepts a matching state once and clears the cookie',
  async () => {
    const { deps } = fakeDeps(userIs(APPLE_USER));

    const response = await handleAuthRequest(
      post(
        '/auth/apple/delete/complete',
        { code: 'one-time-code', state: 'verifier-abc' },
        { cookie: APPLE_DELETE_PENDING, bearer: 'access-1' },
      ),
      ENV,
      deps,
    );

    assertEquals(response?.status, 200);
    assertEquals(await response?.json(), { ok: true });
    assertEquals(
      response?.headers.get('set-cookie')?.includes('Max-Age=0'),
      true,
      'the state is single-use: the cookie clears on success',
    );
  },
);

Deno.test(
  'POST /auth/apple/delete/complete 401s with no state cookie and 403s a mismatch',
  async () => {
    const { deps, calls } = fakeDeps(userIs(APPLE_USER));

    const noCookie = await handleAuthRequest(
      post(
        '/auth/apple/delete/complete',
        { code: 'c', state: 'verifier-abc' },
        { bearer: 'access-1' },
      ),
      ENV,
      deps,
    );
    const mismatch = await handleAuthRequest(
      post(
        '/auth/apple/delete/complete',
        { code: 'c', state: 'other-value' },
        { cookie: APPLE_DELETE_PENDING, bearer: 'access-1' },
      ),
      ENV,
      deps,
    );

    assertEquals(noCookie?.status, 401);
    assertEquals(await errorOf(noCookie), 'state_missing');
    assertEquals(mismatch?.status, 403);
    assertEquals(await errorOf(mismatch), 'state_mismatch');
    assertEquals(
      mismatch?.headers.get('set-cookie')?.includes('Max-Age=0'),
      true,
      'a failed guess still burns the outstanding state',
    );
    // Neither cost a call upstream: the state is checked first.
    assertEquals(calls.length, 0);
  },
);

Deno.test('only the account that started the Apple delete ceremony can finish it', async () => {
  // The right state, but someone else is signed in now.
  const other = fakeDeps(userIs(OTHER_USER));
  const wrongAccount = await handleAuthRequest(
    post(
      '/auth/apple/delete/complete',
      { code: 'one-time-code', state: 'verifier-abc' },
      { cookie: APPLE_DELETE_PENDING, bearer: 'access-2' },
    ),
    ENV,
    other.deps,
  );
  assertEquals(wrongAccount?.status, 403);
  assertEquals(await errorOf(wrongAccount), 'state_mismatch');
  assertEquals(wrongAccount?.headers.get('set-cookie')?.includes('Max-Age=0'), true);

  // The right state and nobody signed in.
  const anonymous = fakeDeps(userIs(APPLE_USER));
  const noBearer = await handleAuthRequest(
    post(
      '/auth/apple/delete/complete',
      { code: 'one-time-code', state: 'verifier-abc' },
      { cookie: APPLE_DELETE_PENDING },
    ),
    ENV,
    anonymous.deps,
  );
  assertEquals(noBearer?.status, 401);
  assertEquals(await errorOf(noBearer), 'access_token_required');
  assertEquals(noBearer?.headers.get('set-cookie')?.includes('Max-Age=0'), true);
  assertEquals(anonymous.calls.length, 0);

  // The right state and a token GoTrue refuses: the refusal is passed on,
  // and the state is spent all the same.
  const refused = fakeDeps(
    () =>
      new Response(JSON.stringify({ error_code: 'bad_jwt' }), {
        status: 403,
        headers: { 'content-type': 'application/json' },
      }),
  );
  const badToken = await handleAuthRequest(
    post(
      '/auth/apple/delete/complete',
      { code: 'one-time-code', state: 'verifier-abc' },
      { cookie: APPLE_DELETE_PENDING, bearer: 'forged' },
    ),
    ENV,
    refused.deps,
  );
  assertEquals(badToken?.status, 403);
  assertEquals(await errorOf(badToken), 'bad_jwt');
  assertEquals(badToken?.headers.get('set-cookie')?.includes('Max-Age=0'), true);
});

Deno.test('a state cookie that names no account finishes nothing', async () => {
  // The bare nonce is what the cookie held before the account rode along,
  // and what anyone could have planted through the old link.
  for (const stored of [
    'verifier-abc',
    'verifier-abc.',
    `.${APPLE_USER}`,
    `verifier-abc.${APPLE_USER}.extra`,
    `verifier-abc.${APPLE_USER}/x`,
  ]) {
    const { deps, calls } = fakeDeps(userIs(APPLE_USER));
    const response = await handleAuthRequest(
      post(
        '/auth/apple/delete/complete',
        { code: 'one-time-code', state: 'verifier-abc' },
        { cookie: `__Host-ll_apple_delete=${stored}`, bearer: 'access-1' },
      ),
      ENV,
      deps,
    );
    assertEquals(response?.status, 401, stored);
    assertEquals(await errorOf(response), 'state_missing', stored);
    assertEquals(response?.headers.get('set-cookie')?.includes('Max-Age=0'), true);
    assertEquals(calls.length, 0, stored);
  }
});

Deno.test('POST /auth/apple/delete/complete demands both a code and a state', async () => {
  const { deps } = fakeDeps(userIs(APPLE_USER));

  const missing = await handleAuthRequest(
    post(
      '/auth/apple/delete/complete',
      { state: 'verifier-abc' },
      { cookie: APPLE_DELETE_PENDING, bearer: 'access-1' },
    ),
    ENV,
    deps,
  );

  assertEquals(missing?.status, 400);
  assertEquals(await errorOf(missing), 'code_and_state_required');
});
