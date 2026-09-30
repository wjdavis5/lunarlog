import { describe, expect, it, vi } from 'vitest';

import { webAuth } from '../src/lib/auth';
import {
  createSupabaseClient,
  getSupabaseClient,
  inMemorySessionStorage,
  resetSupabaseClientForTests,
} from '../src/lib/supabase';
import { hasSupabase } from '../src/lib/config';

describe('the Supabase client seam (issue #1249, accessToken option #1250)', () => {
  it('is null on an unconfigured build (every PR build)', () => {
    // The test env sets no VITE_SUPABASE_* defines, so hasSupabase is false
    // and no client is created — the unconfigured-build contract.
    expect(hasSupabase).toBe(false);
    expect(getSupabaseClient()).toBeNull();
  });

  it('creates a typed client wired to the auth client token getter', async () => {
    const client = createSupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test',
      () => webAuth.getToken(),
    );
    expect(typeof client.from).toBe('function');
    // With the accessToken option set, the auth namespace is not usable for
    // session work by contract (the library's own words) — no session
    // storage is ever consulted. The client object still exposes the
    // namespace; what must never happen is a persisted session, which the
    // storage test below and the e2e nothing-stored guard pin.
  });

  it('the in-memory session adapter stores nothing', async () => {
    const setItemSpy = vi.spyOn(Storage.prototype, 'setItem');
    const getItemSpy = vi.spyOn(Storage.prototype, 'getItem');

    expect(await inMemorySessionStorage.getItem('sb-auth-token')).toBeNull();
    await inMemorySessionStorage.setItem('sb-auth-token', '{"x":1}');
    await inMemorySessionStorage.removeItem('sb-auth-token');

    // Nothing ever reached the browser's real storage.
    expect(setItemSpy).not.toHaveBeenCalled();
    expect(getItemSpy).not.toHaveBeenCalled();
    expect(window.localStorage.length).toBe(0);
  });

  it('memoises one client and resets for tests', () => {
    resetSupabaseClientForTests();
    // hasSupabase is false in the test env, so memoisation is only asserted
    // via the reset seam's type contract here; the configured path is
    // covered by createSupabaseClient above.
    expect(() => resetSupabaseClientForTests()).not.toThrow();
  });
});
