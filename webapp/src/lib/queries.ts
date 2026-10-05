import { QueryClient, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useState } from 'react';

import { getSyncedDataCache, resetWebDataForSignOut, subscribeSyncSignals } from './domain';
import type { SyncedData } from './domain';
import { webAuth } from './auth';
import { type ProfileRow } from './schemas';
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

/**
 * The whole synced dataset, one query: `sync_pull` (cursor-paginated) plus
 * the two direct selects, validated at the boundary and merged into the
 * page's in-memory snapshot. The realtime hook below invalidates this key
 * on every `sync_signals` wake, and the sharing mutations invalidate it
 * after every membership change (issue #1282) — it is the only key any
 * screen reads.
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
  // The pull is tagged with the account it runs under (issue #1338): the
  // id is re-read inside refresh before the pull and again at resolution,
  // so a renewal that adopted a replaced refresh cookie's account discards
  // the pull instead of merging it onto the previous account's snapshot —
  // the session query re-resolving is no longer the only thing that can
  // notice.
  return getSyncedDataCache().refresh(client, () => webAuth.getUser()?.id ?? null);
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
 * The membership-change re-pull (issue #1282): after an invite accept, an
 * ownership-transfer claim, a leave, or a revoke, the sharing pages call
 * this — a full from-zero pull into a fresh snapshot (an incremental pull
 * cannot converge: the joined profile's history sits below the session's
 * cursors, and a left/revoked profile stops being returned with no
 * tombstone), then the synced-data invalidation so every mounted screen
 * refetches against it. Best-effort: a failed re-pull still invalidates
 * (the ordinary incremental refresh runs), and the promise never rejects,
 * so a caller's follow-on navigation always lands. No-op on an
 * unconfigured build.
 */
export async function repullMembershipData(queryClient: QueryClient): Promise<void> {
  const client = getSupabaseClient();
  if (client === null) {
    return;
  }
  try {
    await getSyncedDataCache().repullAll(client, () => webAuth.getUser()?.id ?? null);
  } catch {
    // The re-pull is convergence, not a gate — the sharing RPC itself
    // already succeeded, so its failure must not fail the mutation.
  } finally {
    await queryClient.invalidateQueries({ queryKey: SYNCED_DATA_QUERY_KEY });
  }
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
 * Empties the query cache at an identity boundary without stranding the
 * hooks that are on screen.
 *
 * `queryClient.clear()` removes every query, including the ones mounted
 * components are reading. Such a component keeps the result it last saw and
 * is told nothing more: the query it reads is no longer in the cache, so a
 * later invalidation finds nothing to refetch. Two things followed. The
 * header is never unmounted, so after a sign-in on the page it went on
 * showing the signed-out links, and after a sign-out the signed-in ones,
 * until a reload. And a page showing one account's data when the session
 * changed underneath it (the shell's identity watcher) kept that data on
 * screen, which is the opposite of what the reset is for.
 *
 * So a query nothing is reading is removed, as before, and a query on
 * screen is reset in place: its data is dropped at once, which empties the
 * page, and it is fetched again under whatever session now holds. Mutations
 * are dropped as `clear()` dropped them: a finished sign-in still holds the
 * password it was given.
 */
function dropQueriesAtIdentityBoundary(queryClient: QueryClient): void {
  queryClient.getMutationCache().clear();
  const cache = queryClient.getQueryCache();
  for (const query of cache.getAll()) {
    if (query.getObserversCount() === 0) cache.remove(query);
  }
  // Everything left is being read by something on screen.
  void queryClient.resetQueries();
}

/**
 * Sign-out: drops the synced-data snapshot/cursors and empties the TanStack
 * cache — the whole point of keeping them in memory. The auth mutations
 * call this at every identity boundary (issue #1281): the sign-out mutation
 * in a `finally`, the sign-in paths on session adoption, and the shell's
 * identity watcher whenever the signed-in user id changes.
 */
export function resetWebData(queryClient: QueryClient): void {
  resetWebDataForSignOut({ clear: () => dropQueriesAtIdentityBoundary(queryClient) });
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
