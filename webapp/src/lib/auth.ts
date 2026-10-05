// The web client's half of the auth contract (issue #1250): every call the
// browser makes against the same-origin /auth/* Worker routes, and the one
// credential the browser keeps — the access token, in page memory, never in
// any storage a script reads back from disk.
//
// The refresh token never passes through here: it lives in the Worker's
// HttpOnly cookie, and `getToken` renews the access token through
// GET /auth/session (which rotates the cookie) when the current one is near
// expiry. That getter is what supabase-js's `accessToken` client option
// consumes, so the library's own session storage stays out of the picture
// entirely (src/lib/supabase.ts).
//
// Every POST carries the `x-lunarlog-csrf` custom header the Worker's CSRF
// gate demands, alongside the same-origin Origin header the browser adds.
//
// Issue #1256 adds the account-settings half: the linked sign-in methods
// (list, link, unlink — never the email identity), the Apple web ceremony
// that satisfies the delete-account Edge Function's `apple_code_required`
// precondition, and the deletion call itself (the one request that goes
// straight to the Supabase project instead of the Worker — the CSP's
// connect-src already names it).

import { supabasePublishableKey, supabaseUrl } from './config';
import { safeNextPath, withNext } from './next-path';

export type OAuthProvider = 'google' | 'apple';

export type VerifyType = 'email' | 'magiclink' | 'signup' | 'recovery';

export type SignOutScope = 'local' | 'global';

/** The user profile the auth routes echo back (already public to the user). */
export interface WebAuthUser {
  id: string;
  email: string | null;
}

/** What the Worker returns: the session minus the refresh token. */
export interface ClientSession {
  access_token: string;
  expires_in: number;
  expires_at: number;
  user: WebAuthUser | null;
}

/** A failed /auth/* call: the Worker's machine code, for copy mapping. */
export class AuthError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, status: number) {
    super(`auth request failed: ${status} ${code}`);
    this.name = 'AuthError';
    this.code = code;
    this.status = status;
  }
}

/**
 * A failed delete-account call: the Edge Function's own stable `code`
 * (`apple_code_required`, `apple_revoke_failed`, …), for the deletion copy
 * table. Distinct from AuthError so a copy mapping can never conflate the
 * Worker's codes with the Edge Function's.
 */
export class DeletionError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, status: number) {
    super(`account deletion failed: ${status} ${code}`);
    this.name = 'DeletionError';
    this.code = code;
    this.status = status;
  }
}

/** The caller's linked sign-in methods (GET /auth/identities). The email
 * identity is part of every account and is never unlinkable. */
export interface WebIdentities {
  email: string | null;
  providers: string[];
}

/** Which Sign in with Apple client minted a deletion code — on the web,
 * always the Services ID (`'web'`). */
export type AppleCodeClient = 'app' | 'web';

/** How long before expiry getToken stops trusting the cached token. */
const EXPIRY_SKEW_SECONDS = 30;

const CSRF_HEADER = 'x-lunarlog-csrf';

/** [body] with the return path added when there is one (issue #1456). */
function withReturnPath(
  body: Record<string, unknown>,
  next: string | null,
): Record<string, unknown> {
  const safe = safeNextPath(next);
  return safe === null ? body : { ...body, next: safe };
}

function csrfHeaders(): HeadersInit {
  return { 'content-type': 'application/json', [CSRF_HEADER]: '1' };
}

function parseSessionBody(raw: Record<string, unknown>): ClientSession {
  return {
    access_token: String(raw.access_token ?? ''),
    expires_in: typeof raw.expires_in === 'number' ? raw.expires_in : 3600,
    expires_at: typeof raw.expires_at === 'number' ? raw.expires_at : 0,
    user: typeof raw.user === 'object' && raw.user !== null ? (raw.user as WebAuthUser) : null,
  };
}

async function parseSession(response: Response): Promise<ClientSession> {
  return parseSessionBody((await response.json()) as Record<string, unknown>);
}

async function raiseForError(response: Response): Promise<void> {
  if (response.ok) return;
  let code = 'unknown';
  try {
    const raw = (await response.json()) as Record<string, unknown>;
    if (typeof raw.error === 'string' && raw.error !== '') code = raw.error;
  } catch {
    // A non-JSON failure (network edge, offline): the generic code stands.
  }
  throw new AuthError(code, response.status);
}

/**
 * The in-memory session holder and /auth/* client. One instance per page
 * (the exported `webAuth`); a module reload is a page reload, and the
 * session dies with the page by design.
 */
export class WebAuthClient {
  private accessToken: string | null = null;
  private expiresAtSeconds = 0;
  private user: WebAuthUser | null = null;
  private refreshInFlight: Promise<string | null> | null = null;

  /** The signed-in user, when the client holds a session. */
  getUser(): WebAuthUser | null {
    return this.user;
  }

  /**
   * The supabase-js `accessToken` option's getter: the cached token while
   * it stays fresh (past the expiry skew), otherwise one renewal through
   * /auth/session. Concurrent callers share one renewal — two tabs each
   * single-flight their own, and the shared cookie plus GoTrue's rotation
   * reuse window absorb the cross-tab race.
   */
  async getToken(): Promise<string | null> {
    const nowSeconds = Math.floor(Date.now() / 1000);
    if (
      this.accessToken !== null &&
      this.accessToken !== '' &&
      nowSeconds < this.expiresAtSeconds - EXPIRY_SKEW_SECONDS
    ) {
      return this.accessToken;
    }
    this.refreshInFlight ??= this.restoreSession().finally(() => {
      this.refreshInFlight = null;
    });
    return this.refreshInFlight;
  }

  /** True while a renewal is in flight (test seam). */
  isRefreshing(): boolean {
    return this.refreshInFlight !== null;
  }

  /** Forces the next getToken to renew (test seam). */
  expireTokenForTests(): void {
    this.accessToken = null;
    this.expiresAtSeconds = 0;
  }

  /**
   * Renews the access token from the refresh cookie via GET /auth/session.
   * Returns the token, or null when signed out — a 401 is a normal
   * signed-out state here, not an error.
   */
  async restoreSession(): Promise<string | null> {
    const response = await fetch('/auth/session', { credentials: 'same-origin' });
    if (response.status === 401) {
      this.forgetSession();
      return null;
    }
    await raiseForError(response);
    const session = await parseSession(response);
    this.adoptSession(session);
    return session.access_token;
  }

  async signInWithPassword(email: string, password: string): Promise<void> {
    const response = await fetch('/auth/password/sign-in', {
      method: 'POST',
      headers: csrfHeaders(),
      credentials: 'same-origin',
      body: JSON.stringify({ email, password }),
    });
    await raiseForError(response);
    this.adoptSession(await parseSession(response));
  }

  /**
   * Creates the account. Returns 'confirmation_required' when the project
   * confirms emails (its posture): no session exists until the emailed
   * link or 8-digit code completes sign-in.
   */
  async signUp(
    email: string,
    password: string,
    next: string | null = null,
  ): Promise<'signed_in' | 'confirmation_required'> {
    const response = await fetch('/auth/password/sign-up', {
      method: 'POST',
      headers: csrfHeaders(),
      credentials: 'same-origin',
      body: JSON.stringify(withReturnPath({ email, password }, next)),
    });
    await raiseForError(response);
    const raw = (await response.json()) as Record<string, unknown>;
    if (raw.session === false) return 'confirmation_required';
    // The body is already read: a second read of the same response throws,
    // which turned a sign-up that needs no confirmation into an error.
    this.adoptSession(parseSessionBody(raw));
    return 'signed_in';
  }

  /** Sends the email carrying the sign-in link and the 8-digit code. */
  async sendOtp(email: string, createUser: boolean, next: string | null = null): Promise<void> {
    const response = await fetch('/auth/otp/send', {
      method: 'POST',
      headers: csrfHeaders(),
      credentials: 'same-origin',
      body: JSON.stringify(withReturnPath({ email, create_user: createUser }, next)),
    });
    await raiseForError(response);
  }

  /** Verifies the emailed code and establishes the session. */
  async verifyOtp(email: string, token: string, type: VerifyType): Promise<void> {
    const response = await fetch('/auth/otp/verify', {
      method: 'POST',
      headers: csrfHeaders(),
      credentials: 'same-origin',
      body: JSON.stringify({ email, token, type }),
    });
    await raiseForError(response);
    this.adoptSession(await parseSession(response));
  }

  /** Sends the password-reset email (its link lands on /auth/callback). */
  async sendPasswordReset(email: string): Promise<void> {
    const response = await fetch('/auth/password/reset', {
      method: 'POST',
      headers: csrfHeaders(),
      credentials: 'same-origin',
      body: JSON.stringify({ email }),
    });
    await raiseForError(response);
  }

  /** Sets a new password against the in-memory access token. */
  async updatePassword(password: string): Promise<void> {
    const token = await this.getToken();
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      [CSRF_HEADER]: '1',
    };
    if (token !== null) headers.authorization = `Bearer ${token}`;
    const response = await fetch('/auth/password/update', {
      method: 'POST',
      headers,
      credentials: 'same-origin',
      body: JSON.stringify({ password }),
    });
    await raiseForError(response);
  }

  /**
   * Exchanges the PKCE `code` the emailed/OAuth link landed with for the
   * session. The verifier travels in its HttpOnly cookie — a link opened in
   * another browser arrives with none and surfaces `verifier_missing`.
   *
   * Returns whether the exchanged link was the password-recovery email
   * (issue #1293): the Worker marks its PKCE cookie for the recover flow
   * and echoes the marker here, because GoTrue's redirect back to the
   * callback carries only `?code=`, never `?type=recovery`.
   */
  async exchangeCallback(code: string): Promise<{ recovery: boolean; next: string | null }> {
    const response = await fetch('/auth/callback', {
      method: 'POST',
      headers: csrfHeaders(),
      credentials: 'same-origin',
      body: JSON.stringify({ code }),
    });
    await raiseForError(response);
    const raw = (await response.json()) as Record<string, unknown>;
    this.adoptSession(parseSessionBody(raw));
    // The return path the Worker carried through the sign-in (issue #1456).
    // It is checked here too: the page navigates to it, so the page decides.
    const next = typeof raw.next === 'string' ? safeNextPath(raw.next) : null;
    return { recovery: raw.recovery === true, next };
  }

  /**
   * Signs out this device's session, or every device's on 'global'. The
   * pre-POST renewal is best-effort (issue #1325): on an idle tab a failed
   * /auth/session renewal must not stop the sign-out POST, because the
   * Worker's bearer-less sign-out refreshes from the cookie itself and
   * clears it regardless. The in-memory token dies in a `finally` (issue
   * #1292): the Worker clears the refresh cookie on its side even when its
   * upstream calls fail, and a POST that never lands or fails must not
   * leave the page holding a live access token. The error still propagates
   * so the UI can show it.
   */
  async signOut(scope: SignOutScope): Promise<void> {
    const token = await this.getToken().catch(() => null);
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      [CSRF_HEADER]: '1',
    };
    if (token !== null) headers.authorization = `Bearer ${token}`;
    try {
      const response = await fetch('/auth/sign-out', {
        method: 'POST',
        headers,
        credentials: 'same-origin',
        body: JSON.stringify({ scope }),
      });
      await raiseForError(response);
    } finally {
      this.forgetSession();
    }
  }

  /**
   * The signed-in caller's linked sign-in methods, resolved by the Worker
   * from the caller's own GoTrue user — never anything request-supplied.
   */
  async getIdentities(): Promise<WebIdentities> {
    const response = await this.authedFetch('/auth/identities', 'GET');
    await raiseForError(response);
    const raw = (await response.json()) as Record<string, unknown>;
    return {
      email: typeof raw.email === 'string' ? raw.email : null,
      providers: Array.isArray(raw.providers)
        ? raw.providers.filter((p): p is string => typeof p === 'string')
        : [],
    };
  }

  /**
   * Starts linking one of the OAuth providers to this account: the Worker's
   * fetch-then-redirect shape (the link authorize needs the caller's bearer,
   * which a browser navigation cannot carry). Returns the provider URL the
   * caller assigns the browser to; the landed code completes through the
   * ordinary callback exchange, because GoTrue's link-mode flow state links
   * the identity instead of starting a session.
   */
  async startIdentityLink(provider: OAuthProvider): Promise<string> {
    const response = await this.authedFetch('/auth/identities/link', 'POST', { provider });
    await raiseForError(response);
    const raw = (await response.json()) as Record<string, unknown>;
    if (typeof raw.url !== 'string' || raw.url === '') {
      throw new AuthError('upstream_authorize_shape', 502);
    }
    return raw.url;
  }

  /**
   * Unlinks one of the OAuth providers. The email identity is never a valid
   * argument here (the Worker refuses it too): it is the account's only
   * recovery path. A successful unlink renews the session once, so the
   * page's cached user no longer lists the removed identity — the same
   * refreshSession the app's `AuthService.unlinkProvider` follows.
   */
  async unlinkIdentity(provider: OAuthProvider): Promise<void> {
    const response = await this.authedFetch('/auth/identities/unlink', 'POST', { provider });
    await raiseForError(response);
    await this.restoreSession();
  }

  /**
   * The Apple half of web account deletion (issue #1256): a top-level
   * navigation out to Apple's authorize endpoint under the Services ID,
   * with the Worker holding the ceremony's state in its HttpOnly cookie.
   * Apple redirects back to /account?code=…&state=…, where
   * `completeAppleDelete` consumes the check and the page calls
   * `deleteAccount` with the fresh code.
   */
  startAppleDelete(): void {
    window.location.assign('/auth/apple/delete/start');
  }

  /** Consumes the Apple ceremony: proves to the Worker that this browser
   * asked for it (the state cookie), before any deletion call carries the
   * code. */
  async completeAppleDelete(code: string, state: string): Promise<void> {
    const response = await fetch('/auth/apple/delete/complete', {
      method: 'POST',
      headers: csrfHeaders(),
      credentials: 'same-origin',
      body: JSON.stringify({ code, state }),
    });
    await raiseForError(response);
  }

  /**
   * The account-deletion call (issue #1256) — the one browser request that
   * bypasses the Worker and goes straight to the Supabase project's
   * delete-account Edge Function (same-origin API routes end at the Worker;
   * the CSP's connect-src already names the project). [appleCode] is the
   * fresh Apple web code after the ceremony, omitted (null) for the first
   * attempt — an Apple-linked account then fails closed with
   * `apple_code_required` having touched nothing, which is the page's cue
   * to run the ceremony. Bounded like the app's call (20 s) so a hung Edge
   * Function resolves to a typed failure instead of hanging the page.
   */
  async deleteAccount(
    appleCode: string | null,
    appleCodeClient: AppleCodeClient,
  ): Promise<void> {
    const token = await this.requiredToken();
    let response: Response;
    try {
      response = await fetch(`${supabaseUrl}/functions/v1/delete-account`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          authorization: `Bearer ${token}`,
          apikey: supabasePublishableKey,
        },
        body: JSON.stringify({
          ...(appleCode === null ? {} : { appleAuthorizationCode: appleCode }),
          appleCodeClient,
        }),
        signal: AbortSignal.timeout(20_000),
      });
    } catch (error: unknown) {
      throw new DeletionError(
        error instanceof Error && error.name === 'TimeoutError' ? 'timeout' : 'network',
        0,
      );
    }
    if (!response.ok) {
      let code = 'unknown';
      try {
        const raw = (await response.json()) as Record<string, unknown>;
        if (typeof raw.code === 'string' && raw.code !== '') code = raw.code;
      } catch {
        // A non-JSON failure (network edge, gateway): the generic code stands.
      }
      throw new DeletionError(code, response.status);
    }
  }

  /** Navigates the browser to the OAuth provider through the Worker. */
  startOAuth(provider: OAuthProvider, next: string | null = null): void {
    const start = `/auth/oauth/start?provider=${encodeURIComponent(provider)}`;
    window.location.assign(withNext(start, safeNextPath(next)));
  }

  /** Drops the in-memory session (the cookie is the Worker's to clear). */
  forgetSession(): void {
    this.accessToken = null;
    this.expiresAtSeconds = 0;
    this.user = null;
  }

  private adoptSession(session: ClientSession): void {
    this.accessToken = session.access_token;
    this.expiresAtSeconds = session.expires_at;
    this.user = session.user;
  }

  /**
   * The signed-in-only counterpart of `getToken`: the account routes act on
   * the caller's own identity, so a call with no live session fails here
   * rather than going out bearer-less to be refused by the Worker.
   */
  private async requiredToken(): Promise<string> {
    const token = await this.getToken();
    if (token === null) throw new AuthError('unauthorized', 401);
    return token;
  }

  /**
   * One same-origin Worker call with the bearer the Worker forwards
   * upstream (the routes that act on the caller's own GoTrue user) plus the
   * CSRF header the Worker's gate demands on every state-changing POST.
   */
  private async authedFetch(
    path: string,
    method: 'GET' | 'POST',
    body?: unknown,
  ): Promise<Response> {
    const token = await this.requiredToken();
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      [CSRF_HEADER]: '1',
      authorization: `Bearer ${token}`,
    };
    return fetch(path, {
      method,
      headers,
      credentials: 'same-origin',
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
  }
}

/** The page's one auth client. */
export const webAuth = new WebAuthClient();
