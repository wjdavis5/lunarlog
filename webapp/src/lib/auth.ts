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

/** How long before expiry getToken stops trusting the cached token. */
const EXPIRY_SKEW_SECONDS = 30;

const CSRF_HEADER = 'x-lunarlog-csrf';

function csrfHeaders(): HeadersInit {
  return { 'content-type': 'application/json', [CSRF_HEADER]: '1' };
}

async function parseSession(response: Response): Promise<ClientSession> {
  const raw = (await response.json()) as Record<string, unknown>;
  return {
    access_token: String(raw.access_token ?? ''),
    expires_in: typeof raw.expires_in === 'number' ? raw.expires_in : 3600,
    expires_at: typeof raw.expires_at === 'number' ? raw.expires_at : 0,
    user:
      typeof raw.user === 'object' && raw.user !== null
        ? (raw.user as WebAuthUser)
        : null,
  };
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
  async signUp(email: string, password: string): Promise<'signed_in' | 'confirmation_required'> {
    const response = await fetch('/auth/password/sign-up', {
      method: 'POST',
      headers: csrfHeaders(),
      credentials: 'same-origin',
      body: JSON.stringify({ email, password }),
    });
    await raiseForError(response);
    const raw = (await response.json()) as Record<string, unknown>;
    if (raw.session === false) return 'confirmation_required';
    this.adoptSession(await parseSession(response));
    return 'signed_in';
  }

  /** Sends the email carrying the sign-in link and the 8-digit code. */
  async sendOtp(email: string, createUser: boolean): Promise<void> {
    const response = await fetch('/auth/otp/send', {
      method: 'POST',
      headers: csrfHeaders(),
      credentials: 'same-origin',
      body: JSON.stringify({ email, create_user: createUser }),
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
   */
  async exchangeCallback(code: string): Promise<void> {
    const response = await fetch('/auth/callback', {
      method: 'POST',
      headers: csrfHeaders(),
      credentials: 'same-origin',
      body: JSON.stringify({ code }),
    });
    await raiseForError(response);
    this.adoptSession(await parseSession(response));
  }

  /** Signs out this device's session, or every device's on 'global'. */
  async signOut(scope: SignOutScope): Promise<void> {
    const token = await this.getToken();
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      [CSRF_HEADER]: '1',
    };
    if (token !== null) headers.authorization = `Bearer ${token}`;
    const response = await fetch('/auth/sign-out', {
      method: 'POST',
      headers,
      credentials: 'same-origin',
      body: JSON.stringify({ scope }),
    });
    await raiseForError(response);
    this.forgetSession();
  }

  /** Navigates the browser to the OAuth provider through the Worker. */
  startOAuth(provider: OAuthProvider): void {
    window.location.assign(
      `/auth/oauth/start?provider=${encodeURIComponent(provider)}`,
    );
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
}

/** The page's one auth client. */
export const webAuth = new WebAuthClient();
