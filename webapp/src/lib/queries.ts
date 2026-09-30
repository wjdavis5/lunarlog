import { QueryClient, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useState } from 'react';

import { getSyncedDataCache, resetWebDataForSignOut, subscribeSyncSignals } from './domain';
import type { SyncedData } from './domain';
import { webAuth } from './auth';
import type { ProfileRow } from './schemas';
import { getSupabaseClient } from './supabase';

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
    if (getSupabaseClient() === null) {
      setHasSession(false);
      return;
    }
    let active = true;
    // The app client carries supabase-js's `accessToken` option (issue
    // #1250), whose contract makes the `auth` namespace unusable — calling
    // `client.auth.getSession()` there throws and takes the React tree with
    // it (the e2e shell went blank exactly there). The session signal comes
    // from the in-memory web auth client instead: one `getToken()` probes
    // the Worker's `/auth/session` (single-flighted, rotates the refresh
    // cookie) and resolves null when no session exists — signed out, not
    // crashed.
    void webAuth
      .getToken()
      .then((token) => {
        if (active) setHasSession(token !== null);
      })
      .catch(() => {
        // A reachable-but-wrong /auth/session (the preview server has no
        // Worker, so it answers the SPA fallback) rejects the parse — a
        // signed-out page, not a crashed one.
        if (active) setHasSession(false);
      });
    return () => {
      active = false;
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
