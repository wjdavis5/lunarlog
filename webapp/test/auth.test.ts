import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { WebAuthClient, webAuth } from '../src/lib/auth';

/**
 * The web auth client's contract (issue #1250), against a stubbed fetch:
 * every POST carries the CSRF header; the access token is held in memory
 * and renewed through /auth/session with a single in-flight renewal; a 401
 * restore is a normal signed-out; upstream error codes surface as
 * AuthError.code for the copy mapping.
 */

type FetchCall = { url: string; init: RequestInit | undefined };

const originalFetch = globalThis.fetch;

function stubFetch(handler: (call: FetchCall) => Promise<Response>): {
  calls: FetchCall[];
} {
  const calls: FetchCall[] = [];
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const call: FetchCall = { url: String(input), init };
    calls.push(call);
    return handler(call);
  }) as typeof fetch;
  return { calls };
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

const SESSION_BODY = {
  access_token: 'access-1',
  refresh_token: 'refresh-never-in-body',
  expires_in: 3600,
  expires_at: Math.floor(Date.now() / 1000) + 3600,
  user: { id: 'u1', email: 'a@example.com' },
};

describe('WebAuthClient (issue #1250)', () => {
  let client: WebAuthClient;

  beforeEach(() => {
    client = new WebAuthClient();
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
  });

  it('renews the access token through GET /auth/session and caches it', async () => {
    const { calls } = stubFetch(() => Promise.resolve(jsonResponse(SESSION_BODY)));

    const token = await client.getToken();
    expect(token).toBe('access-1');
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe('/auth/session');

    // Fresh token: the next getToken does not hit the network again.
    expect(await client.getToken()).toBe('access-1');
    expect(calls).toHaveLength(1);
    expect(client.getUser()?.email).toBe('a@example.com');
  });

  it('single-flights concurrent renewals into one /auth/session call', async () => {
    let resolveFetch: ((response: Response) => void) | null = null;
    const { calls } = stubFetch(
      () =>
        new Promise<Response>((resolve) => {
          resolveFetch = resolve;
        }),
    );

    const first = client.getToken();
    const second = client.getToken();
    expect(client.isRefreshing()).toBe(true);
    resolveFetch!(jsonResponse(SESSION_BODY));
    expect(await first).toBe('access-1');
    expect(await second).toBe('access-1');
    expect(calls).toHaveLength(1);
  });

  it('treats a 401 restore as a normal signed-out (null, no throw)', async () => {
    stubFetch(() => Promise.resolve(jsonResponse({ error: 'no_session' }, 401)));
    expect(await client.getToken()).toBeNull();
  });

  it('throws AuthError with the upstream code for a failed sign-in', async () => {
    stubFetch(() => Promise.resolve(jsonResponse({ error: 'invalid_credentials' }, 400)));
    await expect(client.signInWithPassword('a@b.co', 'nope')).rejects.toMatchObject({
      code: 'invalid_credentials',
      status: 400,
    });
  });

  it('sends the CSRF custom header on every POST', async () => {
    const { calls } = stubFetch(() => Promise.resolve(jsonResponse(SESSION_BODY)));
    await client.signInWithPassword('a@b.co', 'long enough password');
    const headers = new Headers(calls[0].init?.headers);
    expect(headers.get('x-lunarlog-csrf')).toBe('1');
    expect(JSON.parse(String(calls[0].init?.body))).toEqual({
      email: 'a@b.co',
      password: 'long enough password',
    });
  });

  it('signUp reports confirmation_required without adopting a session', async () => {
    stubFetch((call) => {
      if (call.url === '/auth/session') {
        return Promise.resolve(jsonResponse({ error: 'no_session' }, 401));
      }
      return Promise.resolve(
        jsonResponse({
          session: false,
          user: { id: 'u2', email: 'new@example.com' },
        }),
      );
    });
    expect(await client.signUp('new@example.com', 'long enough password')).toBe(
      'confirmation_required',
    );
    // No session arrived, so the next getToken renews from the (empty)
    // cookie and comes back signed out.
    expect(await client.getToken()).toBeNull();
  });

  // Where email confirmation is off the sign-up answers with a session.
  // The client read the response body once to look for `session: false`
  // and then a second time to parse the session, and a body can only be
  // read once: the sign-up succeeded on the server and threw in the page.
  it('signUp adopts the session when the sign-up needs no confirmation', async () => {
    const { calls } = stubFetch(() => Promise.resolve(jsonResponse(SESSION_BODY)));

    expect(await client.signUp('new@example.com', 'long enough password')).toBe('signed_in');
    expect(client.getUser()).toEqual({ id: 'u1', email: 'a@example.com' });
    // The adopted token is used as it stands: no renewal round trip.
    expect(await client.getToken()).toBe('access-1');
    expect(calls.map((call) => call.url)).toEqual(['/auth/password/sign-up']);
  });

  it('exchanges the callback code and forgets on sign-out', async () => {
    const { calls } = stubFetch((call) => {
      if (call.url === '/auth/session') {
        // After sign-out the cookie is gone: a renewal is a signed-out.
        return Promise.resolve(jsonResponse({ error: 'no_session' }, 401));
      }
      return Promise.resolve(jsonResponse(SESSION_BODY));
    });

    // An unmarked callback (sign-up, magic link, OAuth) is not recovery.
    expect(await client.exchangeCallback('pkce-code')).toEqual({
      recovery: false,
      next: null,
    });
    expect(JSON.parse(String(calls[0].init?.body))).toEqual({ code: 'pkce-code' });
    expect(client.getUser()?.id).toBe('u1');

    await client.signOut('global');
    const signOutCall = calls[1];
    expect(signOutCall.url).toBe('/auth/sign-out');
    expect(JSON.parse(String(signOutCall.init?.body))).toEqual({ scope: 'global' });
    const headers = new Headers(signOutCall.init?.headers);
    expect(headers.get('authorization')).toBe('Bearer access-1');
    expect(client.getUser()).toBeNull();
    expect(await client.getToken()).toBeNull();
  });

  it('surfaces the recovery marker from the callback exchange (issue #1293)', async () => {
    stubFetch((call) => {
      if (call.url === '/auth/session') {
        return Promise.resolve(jsonResponse({ error: 'no_session' }, 401));
      }
      // The Worker echoes its PKCE cookie's recovery marker in the body.
      return Promise.resolve(jsonResponse({ ...SESSION_BODY, recovery: true }));
    });

    expect(await client.exchangeCallback('pkce-code')).toEqual({
      recovery: true,
      next: null,
    });
    expect(client.getUser()?.id).toBe('u1');
  });

  it('forgets the in-memory session even when the sign-out POST fails (issue #1292)', async () => {
    let signedOut = false;
    stubFetch((call) => {
      if (call.url === '/auth/session') {
        // A live session first; after the failed sign-out, a renewal is a
        // signed-out — the Worker cleared the cookie even on this path.
        return Promise.resolve(
          signedOut ? jsonResponse({ error: 'no_session' }, 401) : jsonResponse(SESSION_BODY),
        );
      }
      // The POST /auth/sign-out fails the way an unreachable Worker
      // surfaces: a 500 instead of the cleared-cookie 200.
      signedOut = true;
      return Promise.resolve(jsonResponse({ error: 'unknown' }, 500));
    });

    await client.getToken();
    expect(client.getUser()?.id).toBe('u1');

    await expect(client.signOut('local')).rejects.toMatchObject({ status: 500 });
    // The POST failed, but the in-memory token died with it: getUser is
    // null and the next renewal comes back signed-out.
    expect(client.getUser()).toBeNull();
    expect(await client.getToken()).toBeNull();
  });

  it('still sends the sign-out POST when the token renewal fails (issue #1325)', async () => {
    let sessionCalls = 0;
    const { calls } = stubFetch((call) => {
      if (call.url === '/auth/session') {
        sessionCalls += 1;
        if (sessionCalls === 1) return Promise.resolve(jsonResponse(SESSION_BODY));
        // The idle-tab failure: the renewal signOut needs has expired and
        // dies with a non-401 error the way an unreachable GoTrue surfaces
        // through the Worker.
        return Promise.resolve(jsonResponse({ error: 'unknown' }, 500));
      }
      return Promise.resolve(jsonResponse({ ok: true }));
    });

    // A live session first; then the tab idles past the token's expiry.
    await client.getToken();
    expect(client.getUser()?.id).toBe('u1');
    client.expireTokenForTests();

    // The failed renewal must not stop the POST: the Worker's bearer-less
    // sign-out refreshes from the cookie itself and clears it regardless.
    await client.signOut('local');

    const signOutCall = calls[2]; // calls[1] is the failed renewal itself.
    expect(signOutCall.url).toBe('/auth/sign-out');
    expect(JSON.parse(String(signOutCall.init?.body))).toEqual({ scope: 'local' });
    const headers = new Headers(signOutCall.init?.headers);
    expect(headers.get('authorization')).toBeNull();
    // The in-memory session died in the finally even though the renewal
    // threw before the try.
    expect(client.getUser()).toBeNull();
  });

  it('surfaces verifier_missing from the callback exchange', async () => {
    stubFetch(() => Promise.resolve(jsonResponse({ error: 'verifier_missing' }, 401)));
    await expect(client.exchangeCallback('code')).rejects.toMatchObject({
      code: 'verifier_missing',
    });
  });

  it('navigates the whole browser to the OAuth start route', () => {
    const assigned: string[] = [];
    const originalLocation = window.location;
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: { assign: (url: string) => assigned.push(url) },
    });
    try {
      webAuth.startOAuth('google');
      expect(assigned).toEqual(['/auth/oauth/start?provider=google']);
    } finally {
      Object.defineProperty(window, 'location', {
        configurable: true,
        value: originalLocation,
      });
    }
  });

  // Issue #1456: a sign-in that leaves the site takes the return path with
  // it, so an invited visitor comes back to the invitation.
  describe('the return path through a sign-in that leaves the site', () => {
    const INVITE = '/invite?code=ABC123&kind=claim';

    function assignedBy(run: () => void): string[] {
      const assigned: string[] = [];
      const originalLocation = window.location;
      Object.defineProperty(window, 'location', {
        configurable: true,
        value: { assign: (url: string) => assigned.push(url) },
      });
      try {
        run();
      } finally {
        Object.defineProperty(window, 'location', {
          configurable: true,
          value: originalLocation,
        });
      }
      return assigned;
    }

    function bodyOf(call: FetchCall | undefined): Record<string, unknown> {
      return JSON.parse(String(call?.init?.body ?? '{}')) as Record<string, unknown>;
    }

    it('OAuth start carries it, encoded', () => {
      expect(assignedBy(() => webAuth.startOAuth('google', INVITE))).toEqual([
        `/auth/oauth/start?provider=google&next=${encodeURIComponent(INVITE)}`,
      ]);
    });

    it('OAuth start drops one that is not a page on this site', () => {
      for (const hostile of [
        '//evil.example',
        '/.//evil.example',
        'https://evil.example',
        '/sign-in',
      ]) {
        expect(assignedBy(() => webAuth.startOAuth('apple', hostile))).toEqual([
          '/auth/oauth/start?provider=apple',
        ]);
      }
    });

    it('the emailed link request carries it, and says nothing when there is none', async () => {
      const { calls } = stubFetch(() => Promise.resolve(jsonResponse({ ok: true })));
      await client.sendOtp('a@example.com', false, INVITE);
      await client.sendOtp('a@example.com', false);
      await client.sendOtp('a@example.com', false, '//evil.example');
      expect(bodyOf(calls[0])).toEqual({
        email: 'a@example.com',
        create_user: false,
        next: INVITE,
      });
      expect(bodyOf(calls[1])).toEqual({ email: 'a@example.com', create_user: false });
      expect(bodyOf(calls[2])).toEqual({ email: 'a@example.com', create_user: false });
    });

    it('a sign-up carries it for the confirmation link', async () => {
      const { calls } = stubFetch(() => Promise.resolve(jsonResponse({ session: false })));
      await client.signUp('new@example.com', 'long enough password', INVITE);
      expect(bodyOf(calls[0])).toEqual({
        email: 'new@example.com',
        password: 'long enough password',
        next: INVITE,
      });
    });

    it('the callback reports the path the Worker carried', async () => {
      stubFetch(() => Promise.resolve(jsonResponse({ ...SESSION_BODY, next: INVITE })));
      expect(await client.exchangeCallback('pkce-code')).toEqual({
        recovery: false,
        next: INVITE,
      });
    });

    it('the callback checks it again: a path off this site is not reported', async () => {
      for (const hostile of [
        '//evil.example/x',
        '/.//evil.example',
        '/%2Fevil.example',
        '/sign-in',
        42,
        {},
      ]) {
        stubFetch(() => Promise.resolve(jsonResponse({ ...SESSION_BODY, next: hostile })));
        expect((await client.exchangeCallback('pkce-code')).next).toBeNull();
      }
    });
  });
});

describe('WebAuthClient account surfaces (issue #1256)', () => {
  let client: WebAuthClient;

  beforeEach(() => {
    client = new WebAuthClient();
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
  });

  /** Signs the client in through the ordinary session restore so the
   * account routes have a bearer to carry. */
  async function signIn() {
    stubFetch((call) =>
      call.url === '/auth/session'
        ? Promise.resolve(jsonResponse(SESSION_BODY))
        : Promise.resolve(jsonResponse({})),
    );
    await client.getToken();
  }

  it('getIdentities reads the linked providers off the Worker with the bearer and CSRF header', async () => {
    await signIn();
    const { calls } = stubFetch((call) =>
      call.url === '/auth/session'
        ? Promise.resolve(jsonResponse(SESSION_BODY))
        : Promise.resolve(
            jsonResponse({ email: 'a@example.com', providers: ['email', 'apple'] }),
          ),
    );

    const identities = await client.getIdentities();

    expect(identities).toEqual({ email: 'a@example.com', providers: ['email', 'apple'] });
    const identityCall = calls.find((call) => call.url === '/auth/identities');
    expect(identityCall).toBeDefined();
    expect(identityCall?.init?.method).toBe('GET');
    const headers = new Headers(identityCall?.init?.headers);
    expect(headers.get('authorization')).toBe('Bearer access-1');
    expect(headers.get('x-lunarlog-csrf')).toBe('1');
  });

  it('getIdentities signed out fails locally as unauthorized, without a request', async () => {
    const { calls } = stubFetch(() => Promise.resolve(jsonResponse({}, 401)));
    await expect(client.getIdentities()).rejects.toMatchObject({ code: 'unauthorized' });
    expect(calls.filter((call) => call.url === '/auth/identities')).toHaveLength(0);
  });

  it('startIdentityLink returns the provider URL the link authorize returned', async () => {
    await signIn();
    const { calls } = stubFetch((call) =>
      call.url === '/auth/session'
        ? Promise.resolve(jsonResponse(SESSION_BODY))
        : Promise.resolve(
            jsonResponse({ url: 'https://appleid.apple.com/auth/authorize?x=1' }),
          ),
    );

    const url = await client.startIdentityLink('apple');

    expect(url).toBe('https://appleid.apple.com/auth/authorize?x=1');
    const linkCall = calls.find((call) => call.url === '/auth/identities/link');
    expect(linkCall?.init?.method).toBe('POST');
    expect(JSON.parse(String(linkCall?.init?.body))).toEqual({ provider: 'apple' });
    const headers = new Headers(linkCall?.init?.headers);
    expect(headers.get('authorization')).toBe('Bearer access-1');
    expect(headers.get('x-lunarlog-csrf')).toBe('1');
  });

  it('unlinkIdentity renews the session after the unlink so the cached user drops the identity', async () => {
    await signIn();
    const { calls } = stubFetch((call) =>
      call.url === '/auth/session'
        ? Promise.resolve(jsonResponse(SESSION_BODY))
        : Promise.resolve(jsonResponse({ ok: true })),
    );

    await client.unlinkIdentity('google');

    const order = calls.map((call) => call.url);
    expect(order.indexOf('/auth/identities/unlink')).toBeGreaterThanOrEqual(0);
    expect(order.indexOf('/auth/session')).toBeGreaterThan(
      order.indexOf('/auth/identities/unlink'),
    );
    expect(
      JSON.parse(
        String(calls.find((call) => call.url === '/auth/identities/unlink')?.init?.body),
      ),
    ).toEqual({
      provider: 'google',
    });
  });

  it('completeAppleDelete posts the landed code and state through the CSRF gate', async () => {
    const { calls } = stubFetch(() => Promise.resolve(jsonResponse({ ok: true })));

    await client.completeAppleDelete('one-time-code', 'state-nonce');

    const call = calls[0];
    expect(call.url).toBe('/auth/apple/delete/complete');
    expect(call.init?.method).toBe('POST');
    expect(JSON.parse(String(call.init?.body))).toEqual({
      code: 'one-time-code',
      state: 'state-nonce',
    });
    expect(new Headers(call.init?.headers).get('x-lunarlog-csrf')).toBe('1');
  });

  it('completeAppleDelete surfaces the Worker state codes as AuthError', async () => {
    stubFetch(() => Promise.resolve(jsonResponse({ error: 'state_mismatch' }, 403)));

    await expect(client.completeAppleDelete('c', 'wrong')).rejects.toMatchObject({
      code: 'state_mismatch',
      status: 403,
    });
  });

  it('deleteAccount posts to the Edge Function with the web client declaration and the fresh code', async () => {
    await signIn();
    const { calls } = stubFetch((call) =>
      call.url === '/auth/session'
        ? Promise.resolve(jsonResponse(SESSION_BODY))
        : Promise.resolve(jsonResponse({ ok: true })),
    );

    await client.deleteAccount('fresh-web-code', 'web');

    const deleteCall = calls.find((call) => call.url.endsWith('/functions/v1/delete-account'));
    expect(deleteCall).toBeDefined();
    const headers = new Headers(deleteCall?.init?.headers);
    expect(headers.get('authorization')).toBe('Bearer access-1');
    expect(headers.get('apikey')).toBeDefined();
    expect(JSON.parse(String(deleteCall?.init?.body))).toEqual({
      appleAuthorizationCode: 'fresh-web-code',
      appleCodeClient: 'web',
    });
  });

  it('deleteAccount omits the code entirely on the first (server-asks) attempt', async () => {
    await signIn();
    const { calls } = stubFetch((call) =>
      call.url === '/auth/session'
        ? Promise.resolve(jsonResponse(SESSION_BODY))
        : Promise.resolve(jsonResponse({ ok: false, code: 'apple_code_required' }, 400)),
    );

    await expect(client.deleteAccount(null, 'web')).rejects.toMatchObject({
      code: 'apple_code_required',
      status: 400,
      name: 'DeletionError',
    });

    const deleteCall = calls.find((call) => call.url.endsWith('/functions/v1/delete-account'));
    expect(JSON.parse(String(deleteCall?.init?.body))).toEqual({ appleCodeClient: 'web' });
  });

  it('deleteAccount signed out fails locally without touching the Edge Function', async () => {
    const { calls } = stubFetch(() => Promise.resolve(jsonResponse({}, 401)));

    await expect(client.deleteAccount(null, 'web')).rejects.toMatchObject({
      code: 'unauthorized',
    });
    expect(calls.filter((call) => call.url.includes('/functions/'))).toHaveLength(0);
  });

  it('deleteAccount maps a non-JSON failure and a rejection onto typed deletion errors', async () => {
    await signIn();
    stubFetch((call) =>
      call.url === '/auth/session'
        ? Promise.resolve(jsonResponse(SESSION_BODY))
        : Promise.reject(new TypeError('network down')),
    );

    await expect(client.deleteAccount(null, 'web')).rejects.toMatchObject({
      code: 'network',
      name: 'DeletionError',
    });
  });
});
