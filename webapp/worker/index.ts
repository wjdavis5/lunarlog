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

export default {
  // The third parameter is a test seam only (Workers passes request, env,
  // ctx): the Deno tests inject a stubbed Supabase Auth so the suite never
  // touches the network.
  async fetch(request: Request, env: Env, authDeps?: AuthDeps): Promise<Response> {
    const authResponse = await handleAuthRequest(request, env, authDeps);
    if (authResponse !== null) {
      return applySecurityHeaders(authResponse);
    }
    const assetResponse = await env.ASSETS.fetch(request);
    // Re-wrap so the headers below are *set* on a fresh response rather than
    // appended to whatever the asset layer chose. (The asset path never
    // carries Set-Cookie, so the rewrap is safe here and only here.)
    const response = new Response(assetResponse.body, assetResponse);
    for (const [name, value] of Object.entries(SECURITY_HEADERS)) {
      response.headers.set(name, value);
    }
    return response;
  },
};
