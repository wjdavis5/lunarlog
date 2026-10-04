// The staging deployment's response headers (issue #1249) — the one source
// of truth for the security posture, consumed by two servers:
//
//   * worker/index.ts (Cloudflare Workers, the deployed staging origin)
//   * vite.config.ts's `preview.headers` (so `npm run e2e` runs Playwright
//     against the *same* policy locally and in CI — the CSP-violation and
//     Trusted Types assertions in e2e/ are only meaningful when the headers
//     are actually served)
//
// Deno-compatible by design: no Node/Deno-specific imports, pure constants.
// `.github/scripts/check-webapp-staging.sh` re-asserts the important
// directives against the live origin after every deploy.

/**
 * The production Supabase project the staging client talks to (issue #1249:
 * staging is used only with the fabricated accounts from #710). The project
 * URL is public (it ships inside every client); only service-role material
 * is secret.
 */
export const SUPABASE_URL = 'https://dleexnnevuuddcgcpztq.supabase.co';

/**
 * The Sign in with Apple Services ID the web client's Apple ceremonies run
 * under (issue #1256). Public by design — it rides in the browser-visible
 * authorize redirect, exactly like the bundle id rides in the app's — so it
 * is a named constant here, not a secret; the delete-account Edge Function
 * carries the same constant (supabase/functions/_shared/apple_revoke.ts)
 * for the matching token exchange.
 */
export const APPLE_WEB_SERVICES_ID = 'com.wjdavis5.lunarlog.web';

/**
 * The content security policy. Strict by construction:
 *
 *   * `script-src 'self'` — no `unsafe-inline`, `unsafe-eval`, or
 *     `wasm-unsafe-eval`; the Vite build emits only external module scripts
 *     (e2e/smoke.spec.ts fails on any violation, including the
 *     Cloudflare-injected analytics beacon case check-webapp-staging.sh
 *     guards against at the edge).
 *   * `connect-src` allows self plus the Supabase project over `https` and
 *     `wss` — nothing else, no third-party analytics endpoints.
 *   * `frame-ancestors 'none'` + `X-Frame-Options: DENY` — not framable.
 *   * `require-trusted-types-for 'script'` — the stack passes with it
 *     (proven by e2e/smoke.spec.ts under real Chromium enforcement; if a
 *     future dependency violates it, that test goes red and this directive
 *     is the thing to revisit deliberately, not silently).
 *   * No CSS-in-JS: `style-src 'self'` and the scaffold uses plain CSS
 *     files only (see src/styles/global.css).
 */
export const CSP = [
  "default-src 'self'",
  "base-uri 'self'",
  `connect-src 'self' ${SUPABASE_URL} ${SUPABASE_URL.replace(/^https/, 'wss')}`,
  "font-src 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
  "img-src 'self'",
  "manifest-src 'self'",
  "object-src 'none'",
  "script-src 'self'",
  "style-src 'self'",
  'upgrade-insecure-requests',
  "require-trusted-types-for 'script'",
].join('; ');

/**
 * Every response the staging origin serves carries these, set (overriding
 * whatever the asset layer guessed) by worker/index.ts.
 */
export const SECURITY_HEADERS: Record<string, string> = {
  'content-security-policy': CSP,
  'strict-transport-security': 'max-age=63072000; includeSubDomains; preload',
  'cross-origin-opener-policy': 'same-origin',
  'x-frame-options': 'DENY',
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'x-robots-tag': 'noindex',
  'permissions-policy':
    'accelerometer=(), autoplay=(), camera=(), display-capture=(), encrypted-media=(), fullscreen=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), payment=(), picture-in-picture=(), publickey-credentials-get=(), screen-wake-lock=(), sync-xhr=(), usb=(), xr-spatial-tracking=()',
};
