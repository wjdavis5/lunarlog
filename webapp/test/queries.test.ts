import { QueryClientProvider } from '@tanstack/react-query';
import { renderHook, waitFor } from '@testing-library/react';
import { createElement, type ReactNode } from 'react';
import { describe, expect, it, vi } from 'vitest';

import { fetchProfiles, createAppQueryClient, PROFILES_QUERY_KEY } from '../src/lib/queries';
import type { AppSupabaseClient } from '../src/lib/supabase';

function fakeClient(result: { data: unknown; error: { message: string } | null }) {
  const order = vi.fn().mockResolvedValue(result);
  const select = vi.fn().mockReturnValue({ order });
  const from = vi.fn().mockReturnValue({ select });
  return { client: { from } as unknown as AppSupabaseClient, from, select, order };
}

const validRow = {
  id: '01ARZ3NDEKTSV4RRFFQ69G5FAV',
  display_name: 'Maya',
  is_minor: false,
  mode: 'cycle',
  relationship: 'self',
  birth_year: 1990,
  sort_order: 0,
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
};
import {
  createAppQueryClient,
  PROFILES_QUERY_KEY,
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

  it('exposes the stable profiles query key', () => {
    expect(PROFILES_QUERY_KEY).toEqual(['profiles']);
  });

  it('exposes the stable synced-data query key the realtime hook invalidates', () => {
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
});

function createWrapper() {
  const client = createAppQueryClient();
  return function Wrapper({ children }: { children: ReactNode }) {
    return createElement(QueryClientProvider, { client }, children);
  };
}
