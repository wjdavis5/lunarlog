import { assertEquals } from 'jsr:@std/assert';

import worker, { type AssetsFetcher, type Env } from './index.ts';
import { CSP, SECURITY_HEADERS, SUPABASE_URL } from './headers.ts';
import { REFRESH_COOKIE, REFRESH_MAX_AGE_SECONDS } from './cookies.ts';

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

Deno.test('every asset response carries the full security posture', async () => {
  const env: Env = { ASSETS: fakeAssets() };
  const res = await worker.fetch(new Request('https://staging.test/'), env);

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
  const res = await worker.fetch(new Request('https://staging.test/no/such/route'), env);

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
  const res = await worker.fetch(new Request('https://staging.test/assets/index.js'), env);

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
    // is stubbed (the third parameter is the test seam).
    const env: Env = {
      ASSETS: fakeAssets(),
      SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test',
    };
    const res = await worker.fetch(
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
      {
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
        codeChallenge: async (verifier) => `challenge-${verifier}`,
      },
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
    const res = await worker.fetch(
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
