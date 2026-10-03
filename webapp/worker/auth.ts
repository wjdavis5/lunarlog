// The same-origin auth Worker routes (issue #1250, epic #831 decision D3).
//
// A signed-in web browser holds exactly one credential: the Supabase
// *access* token, in page memory, delivered in a JSON body. The refresh
// token never reaches a place scripts can read — it lives in the rotating
// `__Host-ll_refresh` HttpOnly cookie this module sets and rotates, and
// only this same origin can present it. Every state-changing route demands
// the app's own `Origin` plus the `x-lunarlog-csrf` custom header (a
// cross-site form can supply neither: forms cannot set custom headers, and
// a cross-site fetch cannot without a CORS preflight this Worker never
// answers), on top of the SameSite=Strict cookie itself.
//
// Upstream is Supabase Auth over plain HTTP — the same GoTrue endpoints and
// body shapes supabase-js sends (verified against the installed
// @supabase/auth-js source: grants at /auth/v1/token?grant_type=…, the
// `redirect_to` target as a *query* parameter, `code_challenge` in the
// body with `code_challenge_method=s256`). The Worker is a thin proxy:
//
//   password sign-in / sign-up, the emailed code + magic-link send and
//   verify, Google/Apple PKCE start and the /auth/callback exchange,
//   password reset + update, session refresh (which rotates the cookie),
//   and sign-out on this device or everywhere.
//
// Deno-tested like the rest of worker/ (the webapp CI job runs
// `deno check` + `deno test` here); every upstream call goes through the
// injectable `supabaseFetch` seam, so the tests run against fakes — the
// real-provider runs are #1258's checklist. Live Google/Apple/email-link
// sign-in additionally needs the console steps in #1093.

import {
  APPLE_DELETE_COOKIE,
  PKCE_COOKIE,
  REFRESH_COOKIE,
  buildAppleDeleteCookie,
  buildClearedCookie,
  buildPkceCookie,
  buildRefreshCookie,
  parsePkceValue,
  readCookie,
} from './cookies.ts';
import { APPLE_WEB_SERVICES_ID, SUPABASE_URL } from './headers.ts';

/** The subset of `Env` the auth routes need (see index.ts). */
export interface AuthEnv {
  /** The Supabase publishable key, set as a Wrangler secret at deploy. */
  SUPABASE_PUBLISHABLE_KEY?: string;
}

/**
 * The upstream Supabase Auth call seam. `path` carries the GoTrue path and
 * query (`/auth/v1/token?grant_type=password`); everything else is a plain
 * fetch init. Injectable so the tests never touch the network.
 */
export type SupabaseAuthFetch = (path: string, init: RequestInit) => Promise<Response>;

/** The `x-lunarlog-csrf` header name; the client sends the value `1`. */
export const CSRF_HEADER = 'x-lunarlog-csrf';
const CSRF_HEADER_VALUE = '1';

/** PKCE providers the start route allows — the same two the app links. */
const OAUTH_PROVIDERS = ['google', 'apple'] as const;
type OAuthProvider = (typeof OAUTH_PROVIDERS)[number];

/** Emailed-token verify types the verify route allows (GoTrue's set). */
const VERIFY_TYPES = ['email', 'magiclink', 'signup', 'recovery'] as const;
type VerifyType = (typeof VERIFY_TYPES)[number];

/** Sign-out scopes: this device's session, or every device's. */
const SIGN_OUT_SCOPES = ['local', 'global'] as const;
type SignOutScope = (typeof SIGN_OUT_SCOPES)[number];

/** One dependency bundle; tests substitute every member. */
export interface AuthDeps {
  supabaseUrl: string;
  publishableKey: string;
  supabaseFetch: SupabaseAuthFetch;
  /** URL-safe random string — the PKCE code verifier. */
  randomVerifier: () => string;
  /** base64url(SHA-256(input)) — the matching code challenge. */
  codeChallenge: (verifier: string) => Promise<string>;
}

function defaultDeps(publishableKey: string): AuthDeps {
  return {
    supabaseUrl: SUPABASE_URL,
    publishableKey,
    supabaseFetch: (path, init) => fetch(`${SUPABASE_URL}${path}`, init),
    randomVerifier: () => {
      // 48 bytes → 64 base64url characters, comfortably inside the PKCE
      // verifier range (43–128) GoTrue validates.
      const bytes = new Uint8Array(48);
      crypto.getRandomValues(bytes);
      return base64Url(bytes);
    },
    codeChallenge: async (verifier) => {
      const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
      return base64Url(new Uint8Array(digest));
    },
  };
}

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

/** The JSON the client is allowed to see: everything but the refresh token. */
interface ClientSession {
  access_token: string;
  expires_in: number;
  expires_at: number;
  user: unknown;
}

function toClientSession(raw: Record<string, unknown>): ClientSession {
  const expires_in = typeof raw.expires_in === 'number' ? raw.expires_in : 3600;
  return {
    access_token: String(raw.access_token),
    expires_in,
    expires_at: typeof raw.expires_at === 'number' ? raw.expires_at : unixNow() + expires_in,
    user: raw.user ?? null,
  };
}

function unixNow(): number {
  return Math.floor(Date.now() / 1000);
}

function jsonResponse(
  body: unknown,
  extraHeaders: Record<string, string> = {},
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ...extraHeaders },
  });
}

function errorResponse(
  status: number,
  code: string,
  extraHeaders: Record<string, string> = {},
): Response {
  return jsonResponse(
    { error: code },
    { 'cache-control': 'no-store', ...extraHeaders },
    status,
  );
}

/**
 * The upstream error body's machine-readable code — GoTrue's `error_code`
 * (`invalid_credentials`, `bad_jwt`, `session_not_found`, …), falling back
 * to `code`, then `error`, then `unknown`. Besides the catalogue-copy
 * mapping below, the sign-out route branches on it (issue #1343).
 */
async function upstreamErrorCode(response: Response): Promise<string> {
  try {
    const raw = (await response.json()) as Record<string, unknown>;
    if (typeof raw.error_code === 'string' && raw.error_code !== '') {
      return raw.error_code;
    } else if (typeof raw.code === 'string' && raw.code !== '') {
      return raw.code;
    } else if (typeof raw.error === 'string' && raw.error !== '') {
      return raw.error;
    }
  } catch {
    // A non-JSON upstream error body: the generic code stands.
  }
  return 'unknown';
}

/**
 * Forwards Supabase Auth's own error code so the client can map it to
 * catalogue copy the way the app maps `AuthException.code` (the same
 * strings: `invalid_credentials`, `weak_password`, `over_request_rate_limit`,
 * `otp_expired`, …). A body without a code collapses to `unknown`.
 */
async function upstreamError(response: Response): Promise<Response> {
  return errorResponse(response.status, await upstreamErrorCode(response));
}

/**
 * The CSRF gate. A state-changing route needs both:
 *
 *   1. the app's own `Origin` (a cross-site request carries the attacker's
 *      origin, or none at all from a classic form post), and
 *   2. the `x-lunarlog-csrf: 1` custom header (a cross-site form cannot
 *      set custom headers at all, and a cross-site `fetch` cannot without
 *      a CORS preflight this Worker never answers).
 *
 * SameSite=Strict on the refresh cookie is the third, passive layer.
 * GET routes only reject a *present-and-foreign* Origin: browsers omit
 * Origin on same-origin GETs (top-level navigations especially), but never
 * send a foreign one quietly.
 */
export function csrfCheck(request: Request, requireCustomHeader: boolean): boolean {
  const origin = request.headers.get('origin');
  const sameOrigin =
    origin === null ? request.method === 'GET' : origin === new URL(request.url).origin;
  if (!sameOrigin) return false;
  if (!requireCustomHeader) return true;
  return request.headers.get(CSRF_HEADER) === CSRF_HEADER_VALUE;
}

/** Headers every upstream Supabase Auth call carries (mirrors auth-js). */
function upstreamHeaders(
  request: Request,
  key: string,
  extra: Record<string, string> = {},
): HeadersInit {
  const headers: Record<string, string> = {
    apikey: key,
    authorization: `Bearer ${key}`,
    'content-type': 'application/json',
    ...extra,
  };
  // Supabase Auth rate-limits per client IP; every web user reaches it
  // through the Worker's shared egress IPs, so forward the real client IP
  // Cloudflare hands us (issue #1250's rate-limit acceptance bullet —
  // whether GoTrue honours it is recorded in the PR and re-checked live in
  // #1258).
  const clientIp = request.headers.get('cf-connecting-ip');
  if (clientIp !== null) headers['x-forwarded-for'] = clientIp;
  return headers;
}

function sessionResponse(
  raw: Record<string, unknown>,
  extraHeaders: Record<string, string>,
  extraBody: Record<string, unknown> = {},
): Response {
  const session = toClientSession(raw);
  return new Response(JSON.stringify({ ...session, ...extraBody }), {
    status: 200,
    headers: {
      'content-type': 'application/json',
      'cache-control': 'no-store',
      'set-cookie': buildRefreshCookie(String(raw.refresh_token)),
      ...extraHeaders,
    },
  });
}

async function readJsonBody(request: Request): Promise<Record<string, unknown>> {
  try {
    const raw = (await request.json()) as unknown;
    return typeof raw === 'object' && raw !== null ? (raw as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

function bearerOf(request: Request): string | null {
  const header = request.headers.get('authorization');
  if (header === null) return null;
  const match = /^Bearer (.+)$/i.exec(header.trim());
  return match === null ? null : match[1];
}

/**
 * The email-sender half of the PKCE flows (magic link, confirmation
 * email, recovery email): sets the verifier cookie and points the emailed
 * link back at this origin's /auth/callback, exactly the way supabase-js
 * wires it — challenge in the body, redirect target in the query string.
 * The recovery email's cookie is marked as such (issue #1293): the marker
 * is what tells the callback page to show the new-password step, because
 * GoTrue's redirect back carries only `?code=`, never `?type=recovery`.
 */
async function startPkceEmailFlow(
  request: Request,
  deps: AuthDeps,
  upstreamPath: string,
  body: Record<string, unknown>,
  recovery = false,
): Promise<Response> {
  const verifier = deps.randomVerifier();
  body.code_challenge = await deps.codeChallenge(verifier);
  body.code_challenge_method = 's256';
  const target = new URL(`${deps.supabaseUrl}${upstreamPath}`);
  target.searchParams.set('redirect_to', `${new URL(request.url).origin}/auth/callback`);
  const response = await deps.supabaseFetch(`${target.pathname}${target.search}`, {
    method: 'POST',
    headers: upstreamHeaders(request, deps.publishableKey),
    body: JSON.stringify(body),
  });
  if (!response.ok) return upstreamError(response);
  return jsonResponse(
    { ok: true },
    { 'cache-control': 'no-store', 'set-cookie': buildPkceCookie(verifier, recovery) },
  );
}

/** The three grant shapes that return a fresh session (and rotate the cookie). */
async function grantSession(
  request: Request,
  deps: AuthDeps,
  grant: 'password' | 'refresh_token' | 'pkce',
  body: Record<string, unknown>,
  extraBody: Record<string, unknown> = {},
): Promise<Response> {
  const response = await deps.supabaseFetch(`/auth/v1/token?grant_type=${grant}`, {
    method: 'POST',
    headers: upstreamHeaders(request, deps.publishableKey),
    body: JSON.stringify(body),
  });
  if (!response.ok) return upstreamError(response);
  const raw = (await response.json()) as Record<string, unknown>;
  if (typeof raw.refresh_token !== 'string' || typeof raw.access_token !== 'string') {
    return errorResponse(502, 'upstream_session_shape');
  }
  return sessionResponse(raw, { 'cache-control': 'no-store' }, extraBody);
}

async function handlePasswordSignIn(request: Request, deps: AuthDeps): Promise<Response> {
  const body = await readJsonBody(request);
  if (typeof body.email !== 'string' || typeof body.password !== 'string') {
    return errorResponse(400, 'email_and_password_required');
  }
  return grantSession(request, deps, 'password', {
    email: body.email,
    password: body.password,
  });
}

async function handlePasswordSignUp(request: Request, deps: AuthDeps): Promise<Response> {
  const body = await readJsonBody(request);
  if (typeof body.email !== 'string' || typeof body.password !== 'string') {
    return errorResponse(400, 'email_and_password_required');
  }
  // Email confirmation on (the project's posture): GoTrue returns the user
  // with no session, and the confirmation email's link carries a PKCE code
  // that lands on /auth/callback — so sign-up starts a PKCE flow too, the
  // way supabase-js's signUp does.
  const verifier = deps.randomVerifier();
  const challenge = await deps.codeChallenge(verifier);
  const target = new URL(`${deps.supabaseUrl}/auth/v1/signup`);
  target.searchParams.set('redirect_to', `${new URL(request.url).origin}/auth/callback`);
  const response = await deps.supabaseFetch(`${target.pathname}${target.search}`, {
    method: 'POST',
    headers: upstreamHeaders(request, deps.publishableKey),
    body: JSON.stringify({
      email: body.email,
      password: body.password,
      code_challenge: challenge,
      code_challenge_method: 's256',
    }),
  });
  if (!response.ok) return upstreamError(response);
  const raw = (await response.json()) as Record<string, unknown>;
  if (typeof raw.access_token === 'string' && typeof raw.refresh_token === 'string') {
    // An auto-confirm posture would return a session here; set the cookie
    // for that shape too.
    return sessionResponse(raw, { 'cache-control': 'no-store' });
  }
  return jsonResponse(
    { session: false, user: raw.user ?? null },
    { 'cache-control': 'no-store', 'set-cookie': buildPkceCookie(verifier) },
  );
}

async function handleOtpSend(request: Request, deps: AuthDeps): Promise<Response> {
  const body = await readJsonBody(request);
  if (typeof body.email !== 'string') return errorResponse(400, 'email_required');
  return startPkceEmailFlow(request, deps, '/auth/v1/otp', {
    email: body.email,
    create_user: body.create_user === true,
  });
}

/** The verify endpoint returns the session directly (no grant_type URL). */
async function handleOtpVerify(request: Request, deps: AuthDeps): Promise<Response> {
  const body = await readJsonBody(request);
  const type = body.type;
  if (
    typeof body.email !== 'string' ||
    typeof body.token !== 'string' ||
    typeof type !== 'string' ||
    !VERIFY_TYPES.includes(type as VerifyType)
  ) {
    return errorResponse(400, 'email_token_type_required');
  }
  const response = await deps.supabaseFetch('/auth/v1/verify', {
    method: 'POST',
    headers: upstreamHeaders(request, deps.publishableKey),
    body: JSON.stringify({
      email: body.email,
      token: (body.token as string).replace(/\s+/g, ''),
      type,
    }),
  });
  if (!response.ok) return upstreamError(response);
  const raw = (await response.json()) as Record<string, unknown>;
  if (typeof raw.refresh_token !== 'string' || typeof raw.access_token !== 'string') {
    return errorResponse(502, 'upstream_session_shape');
  }
  return sessionResponse(raw, { 'cache-control': 'no-store' });
}

async function handlePasswordReset(request: Request, deps: AuthDeps): Promise<Response> {
  const body = await readJsonBody(request);
  if (typeof body.email !== 'string') return errorResponse(400, 'email_required');
  // The recovery marker rides in the PKCE cookie (issue #1293) so the
  // callback can report it — see startPkceEmailFlow.
  return startPkceEmailFlow(request, deps, '/auth/v1/recover', { email: body.email }, true);
}

async function handlePasswordUpdate(request: Request, deps: AuthDeps): Promise<Response> {
  const body = await readJsonBody(request);
  if (typeof body.password !== 'string') return errorResponse(400, 'password_required');
  const bearer = bearerOf(request);
  if (bearer === null) return errorResponse(401, 'access_token_required');
  const response = await deps.supabaseFetch('/auth/v1/user', {
    method: 'PUT',
    headers: upstreamHeaders(request, deps.publishableKey, {
      authorization: `Bearer ${bearer}`,
    }),
    body: JSON.stringify({ password: body.password }),
  });
  if (!response.ok) return upstreamError(response);
  const raw = (await response.json()) as Record<string, unknown>;
  return jsonResponse({ ok: true, user: raw }, { 'cache-control': 'no-store' });
}

async function handleCallback(request: Request, deps: AuthDeps): Promise<Response> {
  const body = await readJsonBody(request);
  if (typeof body.code !== 'string' || body.code === '') {
    return errorResponse(400, 'code_required');
  }
  // The cookie's value decodes to verifier + recovery marker (issue #1293);
  // the marker is how a recovery link is recognised, since GoTrue's
  // redirect back here carries only `?code=`, never `?type=recovery`.
  const pkce = readCookie(request, PKCE_COOKIE);
  const value = pkce === null ? null : parsePkceValue(pkce);
  // The PKCE link opened in a different browser (or the verifier expired):
  // no usable verifier cookie. The UI renders the issue's dedicated copy for
  // this exact code — open the link where you asked for it, or use the code.
  if (value === null) return errorResponse(401, 'verifier_missing');
  const response = await grantSession(
    request,
    deps,
    'pkce',
    {
      auth_code: body.code,
      code_verifier: value.verifier,
    },
    { recovery: value.recovery },
  );
  if (response.status === 200) {
    // The verifier is single-use: consumed on success, marker and all —
    // the page has already received the flag in the response body.
    response.headers.append('set-cookie', buildClearedCookie(PKCE_COOKIE));
  }
  return response;
}

async function handleSession(request: Request, deps: AuthDeps): Promise<Response> {
  const refreshToken = readCookie(request, REFRESH_COOKIE);
  if (refreshToken === null) return errorResponse(401, 'no_session');
  const response = await grantSession(request, deps, 'refresh_token', {
    refresh_token: refreshToken,
  });
  if (response.status === 400 || response.status === 401) {
    // The rotation family is revoked or dead: drop the cookie so the next
    // call is a clean signed-out, not a retry of a dead token.
    response.headers.append('set-cookie', buildClearedCookie(REFRESH_COOKIE));
  }
  return response;
}

async function handleOAuthStart(request: Request, deps: AuthDeps): Promise<Response> {
  if (!csrfCheck(request, false)) return errorResponse(403, 'csrf_rejected');
  const provider = new URL(request.url).searchParams.get('provider');
  if (provider === null || !OAUTH_PROVIDERS.includes(provider as OAuthProvider)) {
    return errorResponse(400, 'unknown_provider');
  }
  const verifier = deps.randomVerifier();
  const challenge = await deps.codeChallenge(verifier);
  const target = new URL(`${deps.supabaseUrl}/auth/v1/authorize`);
  target.searchParams.set('provider', provider);
  target.searchParams.set('redirect_to', `${new URL(request.url).origin}/auth/callback`);
  target.searchParams.set('code_challenge', challenge);
  target.searchParams.set('code_challenge_method', 's256');
  return new Response(null, {
    status: 302,
    headers: {
      location: target.toString(),
      'cache-control': 'no-store',
      'set-cookie': buildPkceCookie(verifier),
    },
  });
}

// ---------------------------------------------------------------------------
// Identity linking and the Apple delete ceremony (issue #1256): the account
// page's sign-in-method surface and its Apple re-authentication step.
// ---------------------------------------------------------------------------

/** The signed-in caller's bearer, or null (every route below requires one:
 * linking, unlinking, and listing identities all act on the caller's own
 * GoTrue user, never a body-supplied one). */
function requireBearer(request: Request): string | null {
  return bearerOf(request);
}

/**
 * The caller's linked sign-in methods, resolved from their own GoTrue user
 * (GET /auth/v1/user with the caller's bearer). The email identity is part
 * of the answer: the account page renders it as the one method that can
 * never be removed.
 */
async function handleIdentities(request: Request, deps: AuthDeps): Promise<Response> {
  const bearer = requireBearer(request);
  if (bearer === null) return errorResponse(401, 'access_token_required');
  const response = await deps.supabaseFetch('/auth/v1/user', {
    method: 'GET',
    headers: upstreamHeaders(request, deps.publishableKey, {
      authorization: `Bearer ${bearer}`,
    }),
  });
  if (!response.ok) return upstreamError(response);
  const raw = (await response.json()) as Record<string, unknown>;
  const identities = Array.isArray(raw.identities) ? raw.identities : [];
  const providers = identities
    .map((identity) =>
      typeof identity === 'object' &&
      identity !== null &&
      typeof (identity as Record<string, unknown>).provider === 'string'
        ? ((identity as Record<string, unknown>).provider as string)
        : null,
    )
    .filter((provider): provider is string => provider !== null);
  return jsonResponse(
    { email: typeof raw.email === 'string' ? raw.email : null, providers },
    { 'cache-control': 'no-store' },
  );
}

/**
 * Starts linking one of the two OAuth providers to the caller's account.
 * Same PKCE shape as /auth/oauth/start (verifier in the short-lived cookie,
 * challenge upstream), but against GoTrue's *link* authorize endpoint with
 * the caller's own bearer — the header a browser navigation cannot carry,
 * which is why this is a fetch-then-redirect (the client assigns the
 * returned provider URL) instead of a 302 out. `skip_http_redirect=true`
 * makes GoTrue answer {"url": …} instead of 302ing the Worker's fetch
 * straight to the provider. The landed code completes through the existing
 * POST /auth/callback exchange: the flow state GoTrue created in link mode
 * links the identity instead of starting a session.
 */
async function handleIdentityLink(request: Request, deps: AuthDeps): Promise<Response> {
  const bearer = requireBearer(request);
  if (bearer === null) return errorResponse(401, 'access_token_required');
  const body = await readJsonBody(request);
  const provider = body.provider;
  if (typeof provider !== 'string' || !OAUTH_PROVIDERS.includes(provider as OAuthProvider)) {
    return errorResponse(400, 'unknown_provider');
  }
  const verifier = deps.randomVerifier();
  const challenge = await deps.codeChallenge(verifier);
  const target = new URL(`${deps.supabaseUrl}/auth/v1/user/identities/authorize`);
  target.searchParams.set('provider', provider);
  target.searchParams.set('redirect_to', `${new URL(request.url).origin}/auth/callback`);
  target.searchParams.set('code_challenge', challenge);
  target.searchParams.set('code_challenge_method', 's256');
  target.searchParams.set('skip_http_redirect', 'true');
  const response = await deps.supabaseFetch(`${target.pathname}${target.search}`, {
    method: 'GET',
    headers: upstreamHeaders(request, deps.publishableKey, {
      authorization: `Bearer ${bearer}`,
    }),
  });
  if (!response.ok) return upstreamError(response);
  const raw = (await response.json()) as Record<string, unknown>;
  if (typeof raw.url !== 'string' || raw.url === '') {
    return errorResponse(502, 'upstream_authorize_shape');
  }
  return jsonResponse(
    { url: raw.url },
    { 'cache-control': 'no-store', 'set-cookie': buildPkceCookie(verifier) },
  );
}

/**
 * Unlinks one of the two OAuth providers from the caller's account: resolve
 * the provider's identity id from the caller's own GoTrue user (never a
 * body-supplied id — that would let a caller unlink someone else's), then
 * DELETE it upstream with the caller's bearer. Only the two OAuth providers
 * are ever unlinkable here — the email identity is the account's recovery
 * path and is not offered, matching the app (`AuthService.unlinkProvider`).
 */
async function handleIdentityUnlink(request: Request, deps: AuthDeps): Promise<Response> {
  const bearer = requireBearer(request);
  if (bearer === null) return errorResponse(401, 'access_token_required');
  const body = await readJsonBody(request);
  const provider = body.provider;
  if (typeof provider !== 'string' || !OAUTH_PROVIDERS.includes(provider as OAuthProvider)) {
    return errorResponse(400, 'unknown_provider');
  }
  const userResponse = await deps.supabaseFetch('/auth/v1/user', {
    method: 'GET',
    headers: upstreamHeaders(request, deps.publishableKey, {
      authorization: `Bearer ${bearer}`,
    }),
  });
  if (!userResponse.ok) return upstreamError(userResponse);
  const raw = (await userResponse.json()) as Record<string, unknown>;
  const identities = Array.isArray(raw.identities) ? raw.identities : [];
  const identityId = identities
    .map((identity) => (typeof identity === 'object' && identity !== null ? identity : null))
    .map((identity) => identity as Record<string, unknown> | null)
    .find(
      (identity) =>
        identity !== null &&
        identity.provider === provider &&
        typeof identity.id === 'string' &&
        identity.id !== '',
    )?.id;
  if (typeof identityId !== 'string') return errorResponse(404, 'identity_not_found');
  const response = await deps.supabaseFetch(
    `/auth/v1/user/identities/${encodeURIComponent(identityId)}`,
    {
      method: 'DELETE',
      headers: upstreamHeaders(request, deps.publishableKey, {
        authorization: `Bearer ${bearer}`,
      }),
    },
  );
  if (!response.ok) return upstreamError(response);
  return jsonResponse({ ok: true }, { 'cache-control': 'no-store' });
}

/**
 * The Apple half of web account deletion (issue #1256): the delete-account
 * Edge Function refuses an Apple-linked account without a fresh
 * authorization code (`apple_code_required`), and on the web that code can
 * only come from a direct Sign in with Apple web ceremony under the
 * Services ID — GoTrue's own authorize consumes the code into a session
 * instead of exposing it.
 *
 * `GET /auth/apple/delete/start` is the top-level navigation out: a 302 to
 * Apple's authorize endpoint (no scope, so `response_mode=query` is Apple's
 * contract) with a random `state`, mirrored into the short-lived HttpOnly
 * cookie — the web app holds nothing at rest, so the Worker holds the
 * check. Apple redirects back to `/account?code=…&state=…` on top of this
 * same origin.
 */
async function handleAppleDeleteStart(request: Request, deps: AuthDeps): Promise<Response> {
  const state = deps.randomVerifier();
  const target = new URL('https://appleid.apple.com/auth/authorize');
  target.searchParams.set('response_type', 'code');
  target.searchParams.set('response_mode', 'query');
  target.searchParams.set('client_id', APPLE_WEB_SERVICES_ID);
  target.searchParams.set('redirect_uri', `${new URL(request.url).origin}/account`);
  target.searchParams.set('state', state);
  return new Response(null, {
    status: 302,
    headers: {
      location: target.toString(),
      'cache-control': 'no-store',
      'set-cookie': buildAppleDeleteCookie(state),
    },
  });
}

/**
 * Consumes the ceremony: the page POSTs the landed `code` and the `state`
 * Apple echoed; the Worker checks the state against its HttpOnly cookie
 * (constant-shape compare on a 64-char random value) and clears the cookie
 * on every settled outcome — the state is single-use. Success here only
 * means "this browser really asked for a delete ceremony"; the deletion
 * itself stays the page's call to the Edge Function, carrying the code and
 * `appleCodeClient: "web"`.
 */
async function handleAppleDeleteComplete(request: Request, _deps: AuthDeps): Promise<Response> {
  const body = await readJsonBody(request);
  if (
    typeof body.code !== 'string' ||
    body.code === '' ||
    typeof body.state !== 'string' ||
    body.state === ''
  ) {
    return errorResponse(400, 'code_and_state_required');
  }
  const expected = readCookie(request, APPLE_DELETE_COOKIE);
  if (expected === null) {
    return errorResponse(401, 'state_missing');
  }
  const clearedCookie = buildClearedCookie(APPLE_DELETE_COOKIE);
  if (expected !== body.state) {
    return errorResponse(403, 'state_mismatch', { 'set-cookie': clearedCookie });
  }
  return jsonResponse(
    { ok: true },
    { 'cache-control': 'no-store', 'set-cookie': clearedCookie },
  );
}

/**
 * The upstream revocation call for one scope and bearer.
 */
function logoutUpstream(
  request: Request,
  deps: AuthDeps,
  scope: string,
  bearer: string,
): Promise<Response> {
  return deps.supabaseFetch(`/auth/v1/logout?scope=${scope}`, {
    method: 'POST',
    headers: upstreamHeaders(request, deps.publishableKey, {
      authorization: `Bearer ${bearer}`,
    }),
    body: '{}',
  });
}

/**
 * One best-effort cookie refresh: the fresh access token, or null when
 * there is no cookie or GoTrue rejected or dropped the leg. Shared by the
 * sign-out's no-bearer path and its stale-bearer retry (issue #1343).
 */
async function refreshBearerFromCookie(
  request: Request,
  deps: AuthDeps,
): Promise<string | null> {
  const refreshToken = readCookie(request, REFRESH_COOKIE);
  if (refreshToken === null) return null;
  try {
    const refreshed = await deps.supabaseFetch('/auth/v1/token?grant_type=refresh_token', {
      method: 'POST',
      headers: upstreamHeaders(request, deps.publishableKey),
      body: JSON.stringify({ refresh_token: refreshToken }),
    });
    if (refreshed.ok) {
      const raw = (await refreshed.json()) as Record<string, unknown>;
      if (typeof raw.access_token === 'string') return raw.access_token;
    }
  } catch {
    // GoTrue unreachable: the caller proceeds without a bearer.
  }
  return null;
}

/**
 * One cookie-refresh leg plus a single logout retry (issue #1364): the
 * retry's own 2xx is the only answer that counts as a landed revocation —
 * a retried 403 `session_not_found` still means the Logout handler never
 * ran, so "everywhere" was not revoked. `false` also covers "no cookie to
 * refresh from". Shared by the stale-bearer (`bad_jwt`) retry and the
 * global `session_not_found` retry; runs inside handleSignOut's try, so a
 * rejecting retry fetch lands in its catch.
 */
async function retryLogoutFromCookie(
  request: Request,
  deps: AuthDeps,
  scope: string,
): Promise<boolean> {
  const fresh = await refreshBearerFromCookie(request, deps);
  if (fresh === null) return false;
  const retried = await logoutUpstream(request, deps, scope, fresh);
  return retried.ok;
}

async function handleSignOut(request: Request, deps: AuthDeps): Promise<Response> {
  const body = await readJsonBody(request);
  const scope = body.scope === undefined ? 'local' : body.scope;
  if (typeof scope !== 'string' || !SIGN_OUT_SCOPES.includes(scope as SignOutScope)) {
    return errorResponse(400, 'invalid_scope');
  }
  // Every path below ends the browser's session with this cookie (issue
  // #1292) — success and failure responses alike.
  const clearedCookie = buildClearedCookie(REFRESH_COOKIE);
  let bearer = bearerOf(request);
  if (bearer === null) {
    // No live access token (expired while idle): refresh once so the
    // sign-out can still reach GoTrue with a valid JWT. Best-effort: a
    // rejected fetch only means the revocation below goes out without a
    // bearer — it must not stop the cookie from being cleared (issue
    // #1292). For `global` the missing bearer is reported as a failure
    // below: with no way to reach GoTrue, "everywhere" was not signed out.
    bearer = await refreshBearerFromCookie(request, deps);
  }
  // The upstream revocation landed only when GoTrue's Logout handler
  // actually ran and answered 2xx. A 403 is GoTrue's requireAuthentication
  // rejecting the call *before* that: `bad_jwt` (the bearer no longer
  // verifies) and `session_not_found` (the bearer verifies but the session
  // its session_id claim names no longer exists) are both recoverable by
  // refreshing once from the HttpOnly cookie and retrying a single time.
  // A bare 401 or 404 is NOT recoverable or evaluated — the API gateway
  // rejecting the publishable key or a misrouted base URL answers those
  // without GoTrue ever seeing the request (issue #1343) — and neither is
  // anything else, so only a verifiable upstream answer sets `revoked`.
  // `local` signs this browser out by clearing the cookie below, so it is
  // always done (its own session_not_found needs no retry — issue #1343);
  // `global`'s whole point is the revocation itself, and session_not_found
  // alone never proves the account's other sessions were revoked (issue
  // #1364).
  let revoked = scope === 'local';
  if (bearer !== null) {
    // A rejected fetch — GoTrue timing out or resetting the connection —
    // must not turn the sign-out into a thrown 500 that leaves the refresh
    // cookie alive on a shared computer (issue #1292). The browser's
    // session still ends below; for `global` the failure is reported
    // instead of swallowed (issue #1324).
    try {
      const logout = await logoutUpstream(request, deps, scope, bearer);
      if (logout.status === 403) {
        const code = await upstreamErrorCode(logout);
        if (code === 'session_not_found') {
          if (scope === 'local') {
            // The bearer's own session is gone, and `local` ends this
            // browser's session by clearing the cookie below: done
            // (issue #1343).
            revoked = true;
          } else {
            // For `global`, session_not_found only proves the *caller's*
            // own session is gone — the Logout handler never ran, so no
            // revocation of the account's other sessions was attempted
            // (issue #1364). The session may have died to a local
            // sign-out in another tab, an inactivity or time-box limit,
            // or a refresh-token-reuse revoke, none of which touched the
            // phone's still-live session. Refresh once from the cookie
            // and retry; only the retry's own 2xx proves the global
            // revocation landed, and no cookie (or a rejected refresh)
            // leaves `revoked` false — revocation_failed below.
            revoked = await retryLogoutFromCookie(request, deps, scope);
          }
        } else if (code === 'bad_jwt') {
          // The in-memory access token no longer verifies (client clock
          // skew, or expiry between page load and this call): refresh once
          // from the HttpOnly cookie — the leg the no-bearer path above
          // takes — and retry a single time (issue #1343). The retried
          // answer must itself be a landed revocation; a second 403 (or
          // anything else) stays a failure.
          revoked = await retryLogoutFromCookie(request, deps, scope);
        }
      } else if (logout.ok) {
        revoked = true;
      }
    } catch {
      // The revocation did not land; the cookie still gets cleared below.
    }
  }
  // The cookie clears on every path (issue #1292): this browser's session
  // ends regardless of what happened upstream. But a `global` revocation
  // that never reached GoTrue must not read as success (issue #1324) —
  // the client's raiseForError throws on this status (its `finally` still
  // forgets the in-memory token), so "Sign out everywhere" surfaces the
  // failure and the user knows the other devices may still be signed in.
  if (scope === 'global' && !revoked) {
    return errorResponse(502, 'revocation_failed', { 'set-cookie': clearedCookie });
  }
  return jsonResponse(
    { ok: true },
    { 'cache-control': 'no-store', 'set-cookie': clearedCookie },
  );
}

/**
 * Handles one request if it is an /auth/* API route; `null` means "not
 * mine" and the caller falls through to the static assets (the SPA).
 */
export async function handleAuthRequest(
  request: Request,
  env: AuthEnv,
  deps?: AuthDeps,
): Promise<Response | null> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith('/auth/')) return null;
  const key = env.SUPABASE_PUBLISHABLE_KEY ?? '';
  if (key === '') return errorResponse(503, 'auth_not_configured');
  const authDeps = deps ?? defaultDeps(key);

  const route = `${request.method} ${url.pathname}`;
  switch (route) {
    case 'POST /auth/password/sign-in':
      if (!csrfCheck(request, true)) return errorResponse(403, 'csrf_rejected');
      return handlePasswordSignIn(request, authDeps);
    case 'POST /auth/password/sign-up':
      if (!csrfCheck(request, true)) return errorResponse(403, 'csrf_rejected');
      return handlePasswordSignUp(request, authDeps);
    case 'POST /auth/password/reset':
      if (!csrfCheck(request, true)) return errorResponse(403, 'csrf_rejected');
      return handlePasswordReset(request, authDeps);
    case 'POST /auth/password/update':
      if (!csrfCheck(request, true)) return errorResponse(403, 'csrf_rejected');
      return handlePasswordUpdate(request, authDeps);
    case 'POST /auth/otp/send':
      if (!csrfCheck(request, true)) return errorResponse(403, 'csrf_rejected');
      return handleOtpSend(request, authDeps);
    case 'POST /auth/otp/verify':
      if (!csrfCheck(request, true)) return errorResponse(403, 'csrf_rejected');
      return handleOtpVerify(request, authDeps);
    case 'POST /auth/callback':
      if (!csrfCheck(request, true)) return errorResponse(403, 'csrf_rejected');
      return handleCallback(request, authDeps);
    case 'POST /auth/sign-out':
      if (!csrfCheck(request, true)) return errorResponse(403, 'csrf_rejected');
      return handleSignOut(request, authDeps);
    case 'GET /auth/session':
      if (!csrfCheck(request, false)) return errorResponse(403, 'csrf_rejected');
      return handleSession(request, authDeps);
    case 'GET /auth/oauth/start':
      return handleOAuthStart(request, authDeps);
    case 'GET /auth/identities':
      if (!csrfCheck(request, false)) return errorResponse(403, 'csrf_rejected');
      return handleIdentities(request, authDeps);
    case 'POST /auth/identities/link':
      if (!csrfCheck(request, true)) return errorResponse(403, 'csrf_rejected');
      return handleIdentityLink(request, authDeps);
    case 'POST /auth/identities/unlink':
      if (!csrfCheck(request, true)) return errorResponse(403, 'csrf_rejected');
      return handleIdentityUnlink(request, authDeps);
    case 'GET /auth/apple/delete/start':
      if (!csrfCheck(request, false)) return errorResponse(403, 'csrf_rejected');
      return handleAppleDeleteStart(request, authDeps);
    case 'POST /auth/apple/delete/complete':
      if (!csrfCheck(request, true)) return errorResponse(403, 'csrf_rejected');
      return handleAppleDeleteComplete(request, authDeps);
    default:
      // Every other /auth/* path is the SPA's (the screens live outside
      // /auth/ in the router; /auth/callback itself is the SPA's page for
      // the GET the provider lands) — hand it to the assets pipeline.
      return null;
  }
}
