import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useMemo, useState } from 'react';

import { SYNCED_DATA_QUERY_KEY } from '../queries';
import { getSyncedDataCache } from '../domain';
import type { AppSupabaseClient } from '../supabase';
import { DaySaveError, dayViewFromSyncedData, saveDay, type SaveDayResult } from './day-data';
import type { DayEdit, LoadedDayView } from './payloads';

/**
 * React Query hooks for the day editor (issue #1254). The day view derives
 * from the #1252 data layer's one synced-data query (same cache, same
 * query key, in-memory only — the Playwright storage-empty guard keeps
 * proving nothing leaks to at-rest storage); the save mutation pushes
 * through `sync_push` and invalidates that key so the editor converges on
 * the server's stored state — the same-date merge result included.
 */

/**
 * The synced-data query, shared with the shell's hooks by key: one
 * incremental `sync_pull` walk serves every screen this session. The day
 * view itself derives from the returned snapshot; a profile that is not
 * visible to the caller surfaces as the query's error.
 */
export function useDayView(
  client: AppSupabaseClient | null,
  profileId: string,
  dateIso: string,
) {
  // The membership lookup needs the session user's id; the session lives
  // in client memory, resolved once per client.
  const [uid, setUid] = useState('');
  useEffect(() => {
    if (client === null) return;
    let active = true;
    void client.auth.getSession().then(({ data }) => {
      if (active) setUid(data.session?.user.id ?? '');
    });
    return () => {
      active = false;
    };
  }, [client]);

  const query = useQuery({
    queryKey: SYNCED_DATA_QUERY_KEY,
    queryFn: () => {
      if (client === null) {
        throw new Error('Supabase is not configured in this build');
      }
      return getSyncedDataCache().refresh(client);
    },
    enabled: client !== null,
    retry: false,
  });

  const notFound = useMemo(
    () => query.data !== undefined && !query.data.profiles.some((row) => row.id === profileId),
    [query.data, profileId],
  );

  const view = useMemo(() => {
    const synced = query.data;
    if (synced === undefined || uid === '' || notFound) return undefined;
    try {
      return dayViewFromSyncedData(synced, profileId, dateIso, uid);
    } catch {
      // A derivation failure on an existing profile is a bug, not a state;
      // the notFound flag above covers the legitimate absence case.
      return undefined;
    }
  }, [query.data, uid, notFound, profileId, dateIso]);

  return {
    isPending: query.isPending || (query.isSuccess && uid === ''),
    isError: query.isError || notFound,
    error:
      (query.error as Error | null) ??
      (notFound ? new DaySaveError('profile not found (or not visible to you)') : null),
    view,
  };
}

export type SaveDayMutationArgs = {
  edit: DayEdit;
  view: LoadedDayView;
  dateIso: string;
  todayIso: string;
  tz: string;
};

/**
 * The save mutation. A failure (network, whole-batch rejection, permission)
 * lands in `mutation.error` and stays there until a retry succeeds — the
 * page keeps every entered value, exactly like the app's day sheet.
 */
export function useSaveDay(client: AppSupabaseClient | null, profileId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (args: SaveDayMutationArgs): Promise<SaveDayResult> => {
      if (client === null) {
        return Promise.reject(new Error('Supabase is not configured in this build'));
      }
      return saveDay(client, {
        profileId,
        dateIso: args.dateIso,
        todayIso: args.todayIso,
        tz: args.tz,
        edit: args.edit,
        view: args.view,
      });
    },
    onSuccess: () => {
      // Refetch the synced data so the editor converges on the server's
      // stored state — the same-date merge result included ("the web shows
      // the result"). saveDay already advanced the shared cache; this
      // re-derives every consumer of the key.
      void queryClient.invalidateQueries({ queryKey: SYNCED_DATA_QUERY_KEY });
    },
  });
}
