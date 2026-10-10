import { QueryClientProvider } from '@tanstack/react-query';
import { act, cleanup, renderHook, waitFor } from '@testing-library/react';
import type { ReactNode } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const fakes = vi.hoisted(() => ({
  getToken: vi.fn<() => Promise<string | null>>(),
  getUser: vi.fn<() => { id: string; email: string | null } | null>(),
}));

vi.mock('../src/lib/auth', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../src/lib/auth')>();
  return { ...actual, webAuth: fakes };
});

// A configured build: the gate reads `getSupabaseClient() !== null` before
// it reads the session at all.
vi.mock('../src/lib/supabase', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../src/lib/supabase')>();
  return { ...actual, getSupabaseClient: () => ({}) };
});

import { AUTH_SESSION_QUERY_KEY } from '../src/lib/authSession';
import { createAppQueryClient, useHasSyncSession } from '../src/lib/queries';

/**
 * The synced-data session gate (issue #1826): `useHasSyncSession` must
 * follow the session query, not latch the mount-time answer. A session that
 * arrives without an auth mutation in this tab (a token renewal whose
 * refresh cookie another tab's sign-in replaced) refetches the query, and
 * the flag must flip with it.
 */
function renderGate() {
  const queryClient = createAppQueryClient();
  const view = renderHook(() => useHasSyncSession(), {
    wrapper: ({ children }: { children: ReactNode }) => (
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    ),
  });
  return { ...view, queryClient };
}

describe('useHasSyncSession (issue #1826)', () => {
  afterEach(cleanup);

  it('flips when a session arrives after the mount', async () => {
    fakes.getToken.mockResolvedValue(null);
    fakes.getUser.mockReturnValue(null);

    const { result, queryClient } = renderGate();
    await waitFor(() => expect(fakes.getToken).toHaveBeenCalled());
    expect(result.current).toBe(false);

    // The session arrives in this tab through the refresh cookie another
    // tab's sign-in replaced: no auth mutation runs here, so only the
    // session query's own refetch (focus, or this invalidation) sees it.
    fakes.getToken.mockResolvedValue('token');
    fakes.getUser.mockReturnValue({ id: 'u1', email: 'a@b.co' });
    await act(async () => {
      await queryClient.invalidateQueries({ queryKey: AUTH_SESSION_QUERY_KEY });
    });

    await waitFor(() => expect(result.current).toBe(true));
  });
});
