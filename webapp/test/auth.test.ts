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
    stubFetch(() =>
      Promise.resolve(jsonResponse({ error: 'invalid_credentials' }, 400)),
    );
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

  it('exchanges the callback code and forgets on sign-out', async () => {
    const { calls } = stubFetch((call) => {
      if (call.url === '/auth/session') {
        // After sign-out the cookie is gone: a renewal is a signed-out.
        return Promise.resolve(jsonResponse({ error: 'no_session' }, 401));
      }
      return Promise.resolve(jsonResponse(SESSION_BODY));
    });

    await client.exchangeCallback('pkce-code');
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
});
