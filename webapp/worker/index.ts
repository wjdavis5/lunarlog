// The staging Worker (issue #1249): serves the Vite build's static assets
// with the security headers from headers.ts applied to every response —
// including the SPA fallback for `/auth/*` (#1250's reserved entry).
//
// `run_worker_first: ["/*"]` in wrangler.jsonc routes every request through
// here first, so the asset layer's best-effort headers can never race the
// declared policy: this Worker owns the headers, unconditionally, on every
// response. Deno-tested like site/worker (the edge-functions-equivalent step
// of the webapp CI job runs `deno check` + `deno test` here).

import { SECURITY_HEADERS } from './headers.ts';

/** The subset of the Workers `Fetcher` type this handler uses. */
export interface AssetsFetcher {
  fetch: (request: Request) => Promise<Response>;
}

export interface Env {
  ASSETS: AssetsFetcher;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const assetResponse = await env.ASSETS.fetch(request);
    // Re-wrap so the headers below are *set* on a fresh response rather than
    // appended to whatever the asset layer chose.
    const response = new Response(assetResponse.body, assetResponse);
    for (const [name, value] of Object.entries(SECURITY_HEADERS)) {
      response.headers.set(name, value);
    }
    return response;
  },
};
