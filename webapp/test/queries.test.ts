import { QueryClientProvider } from '@tanstack/react-query';
import { renderHook, waitFor } from '@testing-library/react';
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

  it('resetWebData clears the query cache (the sign-out path)', () => {
    const client = createAppQueryClient();
    client.setQueryData(['synced-data'], { profiles: [1] });
    const clearSpy = vi.spyOn(client, 'clear');
    resetWebData(client);
    expect(clearSpy).toHaveBeenCalledTimes(1);
    expect(client.getQueryData(['synced-data'])).toBeUndefined();
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

function createWrapper() {
  const client = createAppQueryClient();
  return function Wrapper({ children }: { children: ReactNode }) {
    return createElement(QueryClientProvider, { client }, children);
  };
}
