import { QueryClient, useQuery } from '@tanstack/react-query';

import { profileListSchema, type ProfileRow } from './schemas';
import {
  currentUserId,
  fetchActiveTransfer,
  fetchCareNotes,
  fetchGuardianNotesForDate,
  fetchGuardians,
  fetchPendingInvites,
  type ActiveTransferRow,
  type CareNoteRow,
  type GuardianNoteRow,
  type GuardianRow,
  type PendingInviteRow,
} from './sharing';
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

// --- Sharing and notes queries (issue #1255). Same shape as `useProfiles`:
//     enabled only on a configured build; the SharingError a wrapper throws
//     lands on the query as the typed failure the pages render. ------------

export const guardiansQueryKey = (profileId: string) => ['guardians', profileId] as const;
export const pendingInvitesQueryKey = (profileId: string) =>
  ['pendingInvites', profileId] as const;
export const activeTransferQueryKey = (profileId: string) =>
  ['activeTransfer', profileId] as const;
export const guardianNotesQueryKey = (profileId: string, localDate: string) =>
  ['guardianNotes', profileId, localDate] as const;
export const careNotesQueryKey = (profileId: string) => ['careNotes', profileId] as const;

function useSharingQuery<T>(
  key: readonly unknown[],
  fetch: (client: AppSupabaseClient) => Promise<T>,
  enabled: boolean,
) {
  return useQuery({
    queryKey: key,
    queryFn: () => {
      const client = getSupabaseClient();
      if (client === null) {
        throw new Error('Supabase is not configured in this build');
      }
      return fetch(client);
    },
    enabled,
  });
}

export function useGuardians(profileId: string | undefined, enabled = true) {
  const configured = getSupabaseClient() !== null;
  return useSharingQuery<GuardianRow[]>(
    guardiansQueryKey(profileId ?? ''),
    (client) => fetchGuardians(client, profileId ?? ''),
    configured && enabled && profileId !== undefined,
  );
}

export function usePendingInvites(profileId: string | undefined, enabled = true) {
  const configured = getSupabaseClient() !== null;
  return useSharingQuery<PendingInviteRow[]>(
    pendingInvitesQueryKey(profileId ?? ''),
    (client) => fetchPendingInvites(client, profileId ?? ''),
    configured && enabled && profileId !== undefined,
  );
}

export function useActiveTransfer(profileId: string | undefined, enabled = true) {
  const configured = getSupabaseClient() !== null;
  return useSharingQuery<ActiveTransferRow | null>(
    activeTransferQueryKey(profileId ?? ''),
    (client) => fetchActiveTransfer(client, profileId ?? ''),
    configured && enabled && profileId !== undefined,
  );
}

export function useGuardianNotes(
  profileId: string | undefined,
  localDate: string,
  enabled = true,
) {
  const configured = getSupabaseClient() !== null;
  return useSharingQuery<GuardianNoteRow[]>(
    guardianNotesQueryKey(profileId ?? '', localDate),
    (client) => fetchGuardianNotesForDate(client, profileId ?? '', localDate),
    configured && enabled && profileId !== undefined,
  );
}

export function useCareNotes(profileId: string | undefined, enabled = true) {
  const configured = getSupabaseClient() !== null;
  return useSharingQuery<CareNoteRow[]>(
    careNotesQueryKey(profileId ?? ''),
    (client) => fetchCareNotes(client, profileId ?? ''),
    configured && enabled && profileId !== undefined,
  );
}

/**
 * The signed-in account's id, or null. A stable read of the in-memory
 * session, so "you" markers and the author rules render once it resolves.
 */
export function useCurrentUserId(enabled = true) {
  const configured = getSupabaseClient() !== null;
  return useQuery({
    queryKey: ['currentUserId'],
    queryFn: () => {
      const client = getSupabaseClient();
      if (client === null) return Promise.resolve(null);
      return currentUserId(client);
    },
    enabled: configured && enabled,
    staleTime: Infinity,
  });
}
