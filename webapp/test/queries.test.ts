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
  id: '0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f',
  display_name: 'Maya',
  is_minor: false,
  mode: 'cycle',
  relationship: 'self',
  birth_year: 1990,
  sort_order: 0,
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
};

describe('createAppQueryClient (issue #1249)', () => {
  it('has no persister — the cache is in-memory only', () => {
    const client = createAppQueryClient();
    expect(client.getDefaultOptions().queries?.persister).toBeUndefined();
  });

  it('exposes the stable profiles query key', () => {
    expect(PROFILES_QUERY_KEY).toEqual(['profiles']);
  });
});

describe('fetchProfiles (issue #1249)', () => {
  it('returns Zod-validated rows on success', async () => {
    const { client } = fakeClient({ data: [validRow], error: null });
    const rows = await fetchProfiles(client);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.display_name).toBe('Maya');
  });

  it('strips unknown keys (a new migration column is not a runtime failure)', async () => {
    const { client } = fakeClient({
      data: [{ ...validRow, some_future_column: 'x' }],
      error: null,
    });
    const rows = await fetchProfiles(client);
    expect(rows[0]).not.toHaveProperty('some_future_column');
  });

  it('throws on a PostgREST error', async () => {
    const { client } = fakeClient({ data: null, error: { message: 'permission denied' } });
    await expect(fetchProfiles(client)).rejects.toThrow('permission denied');
  });

  it('throws when a row fails validation', async () => {
    const { client } = fakeClient({
      data: [{ ...validRow, id: 'not-a-uuid' }],
      error: null,
    });
    await expect(fetchProfiles(client)).rejects.toThrow();
  });
});
