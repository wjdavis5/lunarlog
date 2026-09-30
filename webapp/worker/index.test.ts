import { assertEquals } from 'jsr:@std/assert';

import worker, { type AssetsFetcher, type Env } from './index.ts';
import { CSP, SECURITY_HEADERS, SUPABASE_URL } from './headers.ts';

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
