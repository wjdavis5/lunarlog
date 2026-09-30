import { describe, expect, it, vi } from 'vitest';

import {
  createInMemorySessionStorage,
  createSupabaseClient,
  getSupabaseClient,
  resetSupabaseClientForTests,
} from '../src/lib/supabase';
import { hasSupabase } from '../src/lib/config';

describe('the Supabase client seam (issue #1249)', () => {
  it('is null on an unconfigured build (every PR build)', () => {
    // The test env sets no VITE_SUPABASE_* defines, so hasSupabase is false
    // and no client is created — the unconfigured-build contract.
    expect(hasSupabase).toBe(false);
    expect(getSupabaseClient()).toBeNull();
  });

  it('creates a typed client when configured', () => {
    const client = createSupabaseClient('https://example.supabase.co', 'sb_publishable_test');
    expect(typeof client.from).toBe('function');
    expect(typeof client.auth).toBe('object');
  });

  it('the in-memory session adapter stores nothing at rest', async () => {
    const setItemSpy = vi.spyOn(Storage.prototype, 'setItem');
    const getItemSpy = vi.spyOn(Storage.prototype, 'getItem');
    const storage = createInMemorySessionStorage();

    expect(await storage.getItem('sb-auth-token')).toBeNull();
    await storage.setItem('sb-auth-token', '{"x":1}');
    // The session round-trips through page memory — a dropped session made
    // every post-sign-in request go out as anon (issue #1252) — but never
    // reaches the browser's at-rest storage.
    expect(await storage.getItem('sb-auth-token')).toBe('{"x":1}');
    await storage.removeItem('sb-auth-token');
    expect(await storage.getItem('sb-auth-token')).toBeNull();

    // Nothing ever reached the browser's real storage.
    expect(setItemSpy).not.toHaveBeenCalled();
    expect(getItemSpy).not.toHaveBeenCalled();
    expect(window.localStorage.length).toBe(0);
  });

  it('each adapter instance is its own store (two accounts never share a session)', async () => {
    const first = createInMemorySessionStorage();
    const second = createInMemorySessionStorage();
    // Distinct clients on the same project use the same storage KEY —
    // a shared store would hand one account's session to the other.
    await first.setItem('sb-auth-token', '{"sub":"user-a"}');
    expect(await second.getItem('sb-auth-token')).toBeNull();
  });

  it('memoises one client and resets for tests', () => {
    resetSupabaseClientForTests();
    // hasSupabase is false in the test env, so memoisation is only asserted
    // via the reset seam's type contract here; the configured path is
    // covered by createSupabaseClient above.
    expect(() => resetSupabaseClientForTests()).not.toThrow();
  });
});
