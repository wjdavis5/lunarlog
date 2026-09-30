import { QueryClient, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useState } from 'react';

import { getSyncedDataCache, resetWebDataForSignOut, subscribeSyncSignals } from './domain';
import type { SyncedData } from './domain';
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
 * The whole synced dataset, one query: `sync_pull` (cursor-paginated) plus
 * the two direct selects, validated at the boundary and merged into the
 * page's in-memory snapshot. The realtime hook below invalidates this key
 * on every `sync_signals` wake.
 */
export const SYNCED_DATA_QUERY_KEY = ['synced-data'] as const;

/**
 * Whether the build is configured AND a session is in memory. The synced
 * queries stay idle until both hold — `sync_pull` requires an
 * authenticated caller, and on an unconfigured build (every PR build)
 * there is no client at all.
 */
export function useHasSyncSession(): boolean {
  const configured = getSupabaseClient() !== null;
  const [hasSession, setHasSession] = useState(false);

  useEffect(() => {
    const client = getSupabaseClient();
    if (client === null) {
      setHasSession(false);
      return;
    }
    let active = true;
    const evaluate = (): void => {
      void client.auth.getSession().then(({ data }) => {
        if (active) setHasSession(data.session !== null);
      });
    };
    evaluate();
    const {
      data: { subscription },
    } = client.auth.onAuthStateChange(() => {
      evaluate();
    });
    return () => {
      active = false;
      subscription.unsubscribe();
    };
  }, []);

  return configured && hasSession;
}

async function refreshSyncedData(): Promise<SyncedData> {
  const client = getSupabaseClient();
  if (client === null) {
    throw new Error('Supabase is not configured in this build');
  }
  return getSyncedDataCache().refresh(client);
}

/** The synced dataset (profiles, entries, guardians, notes), pulled live. */
export function useSyncedData() {
  const enabled = useHasSyncSession();
  return useQuery({
    queryKey: SYNCED_DATA_QUERY_KEY,
    queryFn: refreshSyncedData,
    enabled,
  });
}

/**
 * The live (non-deleted, non-archived) profiles the operator can see —
 * RLS-scoped server-side, sorted for display. The shell's profile list.
 */
export function useLiveProfiles(): ProfileRow[] {
  const query = useSyncedData();
  const rows = query.data?.profiles ?? [];
  return rows
    .filter((profile) => profile.deleted_at === null && profile.archived_at === null)
    .sort((a, b) => a.sort_order - b.sort_order || (a.id < b.id ? -1 : 1));
}

/**
 * Refetches the synced dataset whenever a `sync_signals` wake arrives for
 * any of the visible profiles. The signal is content-free — it only ever
 * means "go re-pull" — so the handler invalidates the one query key and
 * nothing else. No-op (idle subscription) while signed out.
 */
export function useSyncSignalsRefetch(profileIds: string[]): void {
  const queryClient = useQueryClient();
  const enabled = useHasSyncSession();
  // Stable dependency: the subscription re-wires when the id set changes,
  // not on every parent render that allocated a new array.
  const profileKey = profileIds.join(',');

  useEffect(() => {
    if (!enabled || profileKey === '') {
      return;
    }
    const client = getSupabaseClient();
    if (client === null) {
      return;
    }
    const subscription = subscribeSyncSignals(client, profileKey.split(','), () => {
      void queryClient.invalidateQueries({ queryKey: SYNCED_DATA_QUERY_KEY });
    });
    return () => {
      subscription.unsubscribe();
    };
  }, [enabled, queryClient, profileKey]);
}

/**
 * Sign-out: drops the synced-data snapshot/cursors and clears the TanStack
 * cache — the whole point of keeping them in memory. The auth flow calls
 * this on `SIGNED_OUT`.
 */
export function resetWebData(queryClient: QueryClient): void {
  resetWebDataForSignOut(queryClient);
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
