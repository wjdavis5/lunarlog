import {
  QueryClientProvider,
  useMutation,
  useQuery,
  type QueryClient,
} from '@tanstack/react-query';
import { act, renderHook, waitFor } from '@testing-library/react';
import { createElement, type ReactNode } from 'react';
import { describe, expect, it, vi } from 'vitest';

import {
  createAppQueryClient,
  repullMembershipData,
  resetWebData,
  SYNCED_DATA_QUERY_KEY,
  useHasSyncSession,
  useLiveProfiles,
} from '../src/lib/queries';
import { hasSupabase } from '../src/lib/config';

describe('createAppQueryClient (issue #1249)', () => {
  it('has no persister — the cache is in-memory only', () => {
    const client = createAppQueryClient();
    expect(client.getDefaultOptions().queries?.persister).toBeUndefined();
  });

  it('exposes the stable synced-data query key the realtime hook and the sharing mutations invalidate', () => {
    expect(SYNCED_DATA_QUERY_KEY).toEqual(['synced-data']);
  });
});

describe('the session-gated hooks (issue #1252)', () => {
  // The vitest env sets no VITE_SUPABASE_* defines, so hasSupabase is false
  // and there is no client — the unconfigured-build contract: the synced
  // queries stay idle and the profile list is empty, never an error.
  it('reports no sync session on an unconfigured build', () => {
    expect(hasSupabase).toBe(false);
    const hook = renderHook(() => useHasSyncSession(), {
      wrapper: createWrapper(),
    });
    expect(hook.result.current).toBe(false);
  });

  it('useLiveProfiles is an empty list while the synced query is idle', async () => {
    const hook = renderHook(() => useLiveProfiles(), { wrapper: createWrapper() });
    await waitFor(() => expect(hook.result.current).toEqual([]));
  });

  it('resetWebData removes a query nothing is reading (the sign-out path)', () => {
    const client = createAppQueryClient();
    client.setQueryData(['synced-data'], { profiles: [1] });
    resetWebData(client);
    expect(client.getQueryData(['synced-data'])).toBeUndefined();
    expect(client.getQueryCache().getAll()).toEqual([]);
  });

  // A query on screen is reset in place, not removed: its hook would
  // otherwise go on showing the old session's data and never hear of the
  // new one. Removing it is what left the header saying "Sign in" after a
  // sign-in until the page was reloaded.
  it('resetWebData empties a query on screen before the new answer arrives', async () => {
    const client = createAppQueryClient();
    // The second read is held open, so the test can look at the page in
    // between: after the old account's answer has gone, before the new one.
    let releaseSecond: (value: string) => void = () => {};
    const second = new Promise<string>((resolve) => {
      releaseSecond = resolve;
    });
    const queryFn = vi
      .fn<() => Promise<string>>()
      .mockResolvedValueOnce('first')
      .mockReturnValueOnce(second);
    const hook = renderHook(() => useQuery({ queryKey: ['who'], queryFn }), {
      wrapper: wrapperFor(client),
    });
    await waitFor(() => expect(hook.result.current.data).toBe('first'));

    act(() => resetWebData(client));
    // Gone from memory in the same step, and still on the cache's books.
    expect(client.getQueryData(['who'])).toBeUndefined();
    expect(client.getQueryCache().getAll()).toHaveLength(1);
    // Gone from the screen while the new read is still out.
    await waitFor(() => expect(hook.result.current.data).toBeUndefined());
    expect(hook.result.current.isPending).toBe(true);
    expect(queryFn).toHaveBeenCalledTimes(2);

    await act(async () => releaseSecond('second'));
    await waitFor(() => expect(hook.result.current.data).toBe('second'));
  });

  it('resetWebData leaves a hook on screen reachable by a later invalidation', async () => {
    const client = createAppQueryClient();
    let reads = 0;
    const hook = renderHook(
      () =>
        useQuery({
          queryKey: ['reads'],
          queryFn: () => {
            reads += 1;
            return Promise.resolve(reads);
          },
        }),
      { wrapper: wrapperFor(client) },
    );
    await waitFor(() => expect(hook.result.current.data).toBe(1));

    act(() => resetWebData(client));
    await waitFor(() => expect(hook.result.current.data).toBe(2));
    await act(() => client.invalidateQueries({ queryKey: ['reads'] }));
    await waitFor(() => expect(hook.result.current.data).toBe(3));
  });

  it('resetWebData resets a switched-off query on screen without fetching it', async () => {
    const client = createAppQueryClient();
    const queryFn = vi.fn(() => Promise.resolve('fetched'));
    client.setQueryData(['off'], 'old session');
    const hook = renderHook(() => useQuery({ queryKey: ['off'], queryFn, enabled: false }), {
      wrapper: wrapperFor(client),
    });
    expect(hook.result.current.data).toBe('old session');

    act(() => resetWebData(client));
    expect(client.getQueryData(['off'])).toBeUndefined();
    await waitFor(() => expect(hook.result.current.data).toBeUndefined());
    expect(queryFn).not.toHaveBeenCalled();
  });

  it('resetWebData drops finished mutations, which still hold what they were given', async () => {
    const client = createAppQueryClient();
    const hook = renderHook(
      () => useMutation({ mutationFn: (secret: string) => Promise.resolve(secret.length) }),
      { wrapper: wrapperFor(client) },
    );
    await act(() => hook.result.current.mutateAsync('a password'));
    expect(client.getMutationCache().getAll()).toHaveLength(1);

    resetWebData(client);
    expect(client.getMutationCache().getAll()).toEqual([]);
  });

  it('repullMembershipData is a no-op on an unconfigured build — no pull, no invalidation', async () => {
    // hasSupabase is false in the vitest env: there is no client to pull
    // with, so the helper resolves without touching the query at all (the
    // configured path is exercised by the invite/manage-guardians page
    // tests through their mocked seams).
    const queryClient = createAppQueryClient();
    const seeded = { profiles: [] };
    queryClient.setQueryData(SYNCED_DATA_QUERY_KEY, seeded);
    await expect(repullMembershipData(queryClient)).resolves.toBeUndefined();
    expect(queryClient.getQueryData(SYNCED_DATA_QUERY_KEY)).toBe(seeded);
  });
});

function wrapperFor(client: QueryClient) {
  return function Wrapper({ children }: { children: ReactNode }) {
    return createElement(QueryClientProvider, { client }, children);
  };
}

function createWrapper() {
  return wrapperFor(createAppQueryClient());
}
