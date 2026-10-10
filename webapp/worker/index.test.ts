import { assertEquals, assertFalse, assertStringIncludes } from 'jsr:@std/assert';

import worker, { createWorker, type AssetsFetcher, type Env } from './index.ts';
import type { AuthDeps } from './auth.ts';
import { CSP, SECURITY_HEADERS, SUPABASE_URL } from './headers.ts';
import { PKCE_COOKIE, REFRESH_COOKIE, REFRESH_MAX_AGE_SECONDS } from './cookies.ts';

function fakeAssets(
  overrides: Partial<ResponseInit> = {},
  body = '<!doctype html><html><body><div id="root"></div></body></html>',
): AssetsFetcher {
  return {
    fetch: async () =>
      new Response(body, {
        status: 200,
        headers: { 'content-type': 'text/html' },
        ...overrides,
      }),
  };
}

function fakeAuthDeps(overrides: Partial<AuthDeps> = {}): AuthDeps {
  return {
    supabaseUrl: 'https://supabase.test',
    publishableKey: 'sb_publishable_test',
    supabaseFetch: () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            access_token: 'a',
            refresh_token: 'refresh-1',
            expires_in: 3600,
            user: null,
          }),
          { status: 200, headers: { 'content-type': 'application/json' } },
        ),
      ),
    randomVerifier: () => 'verifier',
    codeChallenge: async (verifier: string) => `challenge-${verifier}`,
    ...overrides,
  };
}

/**
 * The shape the Workers runtime actually passes as the entry's third
 * argument (issue #1280: the runtime contract is fetch(request, env, ctx),
 * with ctx always set).
 */
function fakeContext() {
  const waited: Promise<unknown>[] = [];
  return {
    ctx: {
      waitUntil: (promise: Promise<unknown>) => waited.push(promise),
      passThroughOnException: () => {},
    },
    waited,
  };
}

Deno.test('every asset response carries the full security posture', async () => {
  const env: Env = { ASSETS: fakeAssets() };
  const res = await createWorker().fetch(new Request('https://staging.test/'), env);

  assertEquals(res.status, 200);
  for (const [name, value] of Object.entries(SECURITY_HEADERS)) {
    assertEquals(res.headers.get(name), value, `header ${name}`);
  }
});

Deno.test(
  'the CSP is the strict policy: self-only scripts, supabase connect, no framables',
  () => {
    assertEquals(CSP.includes("script-src 'self'"), true);
    assertEquals(CSP.includes("'unsafe-inline'"), false);
    assertEquals(CSP.includes("'unsafe-eval'"), false);
    assertEquals(CSP.includes("'wasm-unsafe-eval'"), false);
    assertEquals(CSP.includes("frame-ancestors 'none'"), true);
    assertEquals(
      CSP.includes(`connect-src 'self' ${SUPABASE_URL} wss://dleexnnevuuddcgcpztq.supabase.co`),
      true,
    );
    assertEquals(CSP.includes("require-trusted-types-for 'script'"), true);
    assertEquals(CSP.includes("style-src 'self'"), true);
  },
);

Deno.test('headers are set even when the asset layer answered differently', async () => {
  const env: Env = {
    ASSETS: fakeAssets({
      status: 404,
      headers: { 'content-type': 'text/html', 'x-robots-tag': 'index' },
    }),
  };
  const res = await createWorker().fetch(
    new Request('https://staging.test/no/such/route'),
    env,
  );

  assertEquals(res.status, 404);
  assertEquals(res.headers.get('x-robots-tag'), 'noindex');
  assertEquals(res.headers.get('cross-origin-opener-policy'), 'same-origin');
  assertEquals(
    res.headers.get('strict-transport-security'),
    'max-age=63072000; includeSubDomains; preload',
  );
});

Deno.test('non-HTML assets get the headers too', async () => {
  const env: Env = {
    ASSETS: {
      fetch: async () =>
        new Response('console.log(1)', {
          status: 200,
          headers: { 'content-type': 'text/javascript' },
        }),
    },
  };
  const res = await createWorker().fetch(
    new Request('https://staging.test/assets/index.js'),
    env,
  );

  assertEquals(res.status, 200);
  assertEquals(await res.text(), 'console.log(1)');
  assertEquals(res.headers.get('x-content-type-options'), 'nosniff');
  assertEquals(res.headers.get('content-security-policy'), CSP);
});

Deno.test(
  'auth responses carry the security headers AND their Set-Cookie survives',
  async () => {
    // Issue #1250: the auth routes are answered before the asset pipeline,
    // and the headers are set in place — a rewrap would drop the rotating
    // refresh cookie exactly when it is being set. The Supabase Auth fetch
    // is stubbed through createWorker (issue #1280's test seam — the entry
    // itself no longer takes deps, see the runtime-entry tests below).
    const env: Env = {
      ASSETS: fakeAssets(),
      SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test',
    };
    const res = await createWorker(fakeAuthDeps()).fetch(
      new Request('https://staging.test/auth/password/sign-in', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          origin: 'https://staging.test',
          'x-lunarlog-csrf': '1',
        },
        body: JSON.stringify({ email: 'a@example.com', password: 'x' }),
      }),
      env,
    );

    assertEquals(res.status, 200);
    for (const [name, value] of Object.entries(SECURITY_HEADERS)) {
      assertEquals(res.headers.get(name), value, `header ${name}`);
    }
    assertEquals(
      res.headers.get('set-cookie'),
      `${REFRESH_COOKIE}=refresh-1; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=${REFRESH_MAX_AGE_SECONDS}`,
    );
  },
);

Deno.test(
  'the SPA lands on /auth/callback GETs; the Worker answers only the POST',
  async () => {
    const env: Env = {
      ASSETS: fakeAssets(),
      SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test',
    };
    const res = await createWorker().fetch(
      new Request('https://staging.test/auth/callback?code=from-provider'),
      env,
    );

    // The GET falls through to the SPA fallback with the full headers.
    assertEquals(res.status, 200);
    assertEquals(res.headers.get('content-security-policy'), CSP);
    assertEquals(
      await res.text(),
      '<!doctype html><html><body><div id="root"></div></body></html>',
    );
  },
);

Deno.test(
  'the runtime entry treats its third argument as the ExecutionContext, not test deps',
  async () => {
    // Issue #1280: the entry used to take `authDeps?` here, so the deployed
    // Worker handed the ExecutionContext to every /auth/* route as its deps
    // and the first `deps.*` call threw. GET /auth/oauth/start touches the
    // deps first (`randomVerifier`) and its happy path performs no network
    // call, so a 302 built from defaultDeps(key) — not from ctx — proves
    // the seam moved to createWorker.
    const env: Env = {
      ASSETS: fakeAssets(),
      SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test',
    };
    const { ctx, waited } = fakeContext();
    const res = await worker.fetch(
      new Request('https://staging.test/auth/oauth/start?provider=google', {
        headers: { origin: 'https://staging.test', 'x-lunarlog-csrf': '1' },
      }),
      env,
      ctx,
    );

    assertEquals(res.status, 302);
    const location = new URL(res.headers.get('location') ?? '');
    assertEquals(location.origin, SUPABASE_URL);
    assertEquals(location.pathname, '/auth/v1/authorize');
    assertEquals(location.searchParams.get('provider'), 'google');
    assertEquals(location.searchParams.get('code_challenge_method'), 's256');
    // The PKCE cookie carries a verifier generated by defaultDeps — 48
    // random bytes as 64 base64url characters — so the deps really were
    // built from env, not whatever object arrived as ctx.
    const setCookie = res.headers.get('set-cookie') ?? '';
    assertEquals(setCookie.startsWith(`${PKCE_COOKIE}=`), true);
    const verifier = setCookie.slice(`${PKCE_COOKIE}=`.length, setCookie.indexOf(';'));
    assertEquals(verifier.length, 64);
    assertEquals(/^[A-Za-z0-9_-]+$/.test(verifier), true);
    // A real runtime ctx is never invoked by this code path.
    assertEquals(waited.length, 0);
  },
);

Deno.test(
  'the runtime entry answers GET /auth/session with the signed-out 401 under a real ctx',
  async () => {
    // The route the post-deploy smoke check pins (issue #1280): a signed-out
    // session probe must be the 401 JSON answer with the full security
    // posture — never the uncaught TypeError the ctx-as-deps bug produced.
    const env: Env = {
      ASSETS: fakeAssets(),
      SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test',
    };
    const { ctx, waited } = fakeContext();
    const res = await worker.fetch(new Request('https://staging.test/auth/session'), env, ctx);

    assertEquals(res.status, 401);
    assertEquals(res.headers.get('content-type'), 'application/json');
    assertEquals(res.headers.get('content-security-policy'), CSP);
    assertEquals((await res.json()) as Record<string, string>, { error: 'no_session' });
    assertEquals(waited.length, 0);
  },
);

// --- The #1248/#1258 cutover retirement duties ------------------------------

Deno.test('/privacy.html 301s to the apex policy (#1248)', async () => {
  const env: Env = { ASSETS: fakeAssets() };
  const res = await createWorker().fetch(
    new Request('https://app.lunarlog.app/privacy.html'),
    env,
  );
  assertEquals(res.status, 301);
  assertEquals(res.headers.get('location'), 'https://lunarlog.app/privacy');
  // The security posture rides on the redirect too.
  assertEquals(res.headers.get('content-security-policy'), CSP);
});

Deno.test(
  '/flutter_service_worker.js serves the self-unregistering worker (#1248)',
  async () => {
    const env: Env = { ASSETS: fakeAssets() };
    const res = await createWorker().fetch(
      new Request('https://app.lunarlog.app/flutter_service_worker.js'),
      env,
    );
    assertEquals(res.status, 200);
    assertEquals(res.headers.get('content-type')?.split(';')[0], 'application/javascript');
    const body = await res.text();
    assertStringIncludes(body, 'self.registration.unregister()');
    assertStringIncludes(body, 'caches.delete');
  },
);

Deno.test(
  'HTML shells carry Clear-Site-Data storage, never cache or cookies (#1248, #1397)',
  async () => {
    const env: Env = { ASSETS: fakeAssets() };
    const res = await createWorker().fetch(new Request('https://app.lunarlog.app/'), env);
    const csd = res.headers.get('clear-site-data') ?? '';
    assertStringIncludes(csd, '"storage"');
    assertFalse(
      csd.includes('"cache"'),
      'cache would wipe the HTTP cache on every page load (issue #1397)',
    );
    assertFalse(
      csd.includes('cookies'),
      'cookies would clear the refresh cookie every page load',
    );

    // Non-HTML asset responses stay clean (only the app shell wipes).
    const asset = await createWorker().fetch(
      new Request('https://app.lunarlog.app/assets/index-abc.js'),
      { ASSETS: fakeAssets({ headers: { 'content-type': 'application/javascript' } }) },
    );
    assertEquals(asset.headers.get('clear-site-data'), null);
  },
);
