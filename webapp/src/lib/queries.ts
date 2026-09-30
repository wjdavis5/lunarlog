import { QueryClient, useQuery } from '@tanstack/react-query';

import { profileListSchema, type ProfileRow } from './schemas';
import { getSupabaseClient, type AppSupabaseClient } from './supabase';

/**
 * TanStack Query, in-memory only (issue #1249): deliberately no persister.
 * The query cache lives and dies with the page, like everything else this
 * client keeps — the Playwright storage-empty test (e2e/storage-empty) is
 * the end-to-end guard that nothing leaks to at-rest storage.
 */
export function createAppQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        retry: 1,
      },
    },
  });
}

export const PROFILES_QUERY_KEY = ['profiles'] as const;

/**
 * One network read, validated at the boundary: `select('*')` over `profiles`
 * (RLS scopes the rows to what the signed-in operator may see), then the
 * Zod parse before any component touches a row.
 */
export async function fetchProfiles(client: AppSupabaseClient): Promise<ProfileRow[]> {
  const { data, error } = await client.from('profiles').select('*').order('sort_order');
  if (error !== null) {
    throw new Error(`profiles select failed: ${error.message}`);
  }
  return profileListSchema.parse(data);
}

/**
 * The shell's first real query. Enabled only when the build is configured;
 * on an unconfigured build (every PR build) it stays idle and the page
 * renders the catalogue copy alone.
 */
export function useProfiles() {
  const configured = getSupabaseClient() !== null;
  return useQuery({
    queryKey: PROFILES_QUERY_KEY,
    queryFn: () => {
      const client = getSupabaseClient();
      if (client === null) {
        throw new Error('Supabase is not configured in this build');
      }
      return fetchProfiles(client);
    },
    enabled: configured,
  });
}
