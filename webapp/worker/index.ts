// The staging Worker (issues #1249 and #1250): serves the Vite build's
// static assets with the security headers from headers.ts applied to every
// response, and answers the same-origin /auth/* API routes (auth.ts) — the
// PKCE/OAuth/email/password ceremonies whose refresh token lives only in
// the rotating HttpOnly cookie auth.ts sets.
//
// `run_worker_first: ["/*"]` in wrangler.jsonc routes every request through
// here first, so the asset layer's best-effort headers can never race the
// declared policy: this Worker owns the headers, unconditionally, on every
// response — auth responses included, without rewrapping them (a fresh
// Response would drop the Set-Cookie pairs). Deno-tested like site/worker
// (the edge-functions-equivalent step of the webapp CI job runs
// `deno check` + `deno test` here).

import { handleAuthRequest, type AuthDeps, type AuthEnv } from './auth.ts';
import { SECURITY_HEADERS } from './headers.ts';

/** The subset of the Workers `Fetcher` type this handler uses. */
export interface AssetsFetcher {
  fetch: (request: Request) => Promise<Response>;
}

/**
 * The subset of the Workers `ExecutionContext` the entry receives as its
 * third argument. Declared here because `deno check` runs without
 * `@cloudflare/workers-types` — the same minimal-structural-type approach
 * as AssetsFetcher above.
 */
export interface WorkerContext {
  waitUntil(promise: Promise<unknown>): void;
  passThroughOnException(): void;
}

export interface Env extends AuthEnv {
  ASSETS: AssetsFetcher;
}

/**
 * Sets the declared security posture on an already-built response. Headers
 * are mutated in place (never a rewrap) so multi-valued Set-Cookie pairs —
 * the auth routes' rotating refresh cookie plus the cleared PKCE cookie —
 * survive untouched.
 */
export function applySecurityHeaders(response: Response): Response {
  for (const [name, value] of Object.entries(SECURITY_HEADERS)) {
    response.headers.set(name, value);
  }
  return response;
}

async function serve(request: Request, env: Env, authDeps?: AuthDeps): Promise<Response> {
  const authResponse = await handleAuthRequest(request, env, authDeps);
  if (authResponse !== null) {
    return applySecurityHeaders(authResponse);
  }

  // Issue #1248/#1258: the Flutter web build this Worker replaces kept an
  // unencrypted IndexedDB copy of synced data, a localStorage refresh token,
  // and (on some browsers) a registered flutter_service_worker.js on
  // app.lunarlog.app. This Worker answers the same origin now, so it performs
  // the retirement duties itself.
  const url = new URL(request.url);
  if (url.pathname === '/privacy.html') {
    // The Flutter build published a privacy.html at this path; keep the
    // permanent move to the apex policy (issue #1248's acceptance list).
    // Built by hand — Response.redirect()'s headers are immutable, and the
    // security posture must land on this response like every other.
    return applySecurityHeaders(
      new Response(null, {
        status: 301,
        headers: { location: 'https://lunarlog.app/privacy' },
      }),
    );
  }
  if (url.pathname === '/flutter_service_worker.js') {
    // A browser still holding the Flutter registration fetches scope updates
    // at exactly this path: hand it a worker that empties every cache,
    // unregisters itself, and reloads its clients (#1248).
    return applySecurityHeaders(
      new Response(FLUTTER_SW_RETIREMENT, {
        headers: { 'content-type': 'application/javascript', 'cache-control': 'no-store' },
      }),
    );
  }

  const assetResponse = await env.ASSETS.fetch(request);
  // Re-wrap so the headers below are *set* on a fresh response rather than
  // appended to whatever the asset layer chose. (The asset path never
  // carries Set-Cookie, so the rewrap is safe here and only here.)
  const response = new Response(assetResponse.body, assetResponse);
  for (const [name, value] of Object.entries(SECURITY_HEADERS)) {
    response.headers.set(name, value);
  }
  // On the app shell, wipe whatever the previous web client left at rest:
  // "storage" clears localStorage, IndexedDB, Cache Storage and service
  // worker registrations, which is everything the retired Flutter build
  // left (#1248). Deliberately NOT "cache" (issue #1397): the migration
  // does not need the browser's HTTP cache - the React client's assets are
  // content-hashed, so stale Flutter-era entries can never be served - and
  // "cache" would re-download every asset on every full page load. And
  // deliberately NOT "cookies": this client's only credential, the rotating
  // __Host- refresh cookie, must survive its own page loads (#1258).
  if ((response.headers.get('content-type') ?? '').includes('text/html')) {
    response.headers.set('clear-site-data', '"storage"');
  }
  return response;
}

/**
 * The self-retiring service worker served at the Flutter build's old
 * registration path (issue #1248): installs immediately, empties every
 * cache it can see, unregisters itself, and reloads any open windows so
 * the next navigation is served by this Worker, not the stale shell.
 */
const FLUTTER_SW_RETIREMENT = `// lunarlog: the Flutter web app this served is retired (#1248).
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map((key) => caches.delete(key)));
    await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: 'window' });
    for (const client of clients) {
      client.navigate(client.url);
    }
  })());
});
`;

/**
 * The test factory: pins the auth deps so the Deno suite substitutes a
 * stubbed Supabase Auth and never touches the network (issue #1280). The
 * returned fetch takes exactly (request, env) — there is no third-argument
 * seam to confuse with the runtime's ExecutionContext.
 */
export function createWorker(authDeps?: AuthDeps): {
  fetch(request: Request, env: Env): Promise<Response>;
} {
  return {
    fetch: (request, env) => serve(request, env, authDeps),
  };
}

// The Workers runtime entry. The runtime's contract is fetch(request, env,
// ctx) with ctx always set — the ExecutionContext below, never an auth-deps
// object. Issue #1280: the entry used to take `authDeps?` here, so on the
// deployed Worker every /auth/* route received the ctx as its deps and
// threw on the first `deps.*` call. The auth deps are built per request
// from env (defaultDeps in handleAuthRequest); tests inject stubs through
// createWorker instead.
export default {
  async fetch(request: Request, env: Env, _ctx?: WorkerContext): Promise<Response> {
    return serve(request, env);
  },
};
