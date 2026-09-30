import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import type { AppSupabaseClient } from '../supabase';
import { fetchDayView, saveDay, type SaveDayResult } from './day-data';
import type { DayEdit, LoadedDayView } from './payloads';

/**
 * React Query hooks for the day editor (issue #1254). Same in-memory-only
 * discipline as `queries.ts` (issue #1249): no persister, the cache dies
 * with the page — the Playwright storage-empty guard keeps proving it.
 */

export function dayQueryKey(profileId: string, dateIso: string): readonly unknown[] {
  return ['day', profileId, dateIso] as const;
}

export function useDayView(
  client: AppSupabaseClient | null,
  profileId: string,
  dateIso: string,
) {
  const configured = client !== null;
  return useQuery({
    queryKey: dayQueryKey(profileId, dateIso),
    queryFn: () => {
      if (client === null) {
        throw new Error('Supabase is not configured in this build');
      }
      return fetchDayView(client, { profileId, dateIso });
    },
    enabled: configured,
    retry: false,
  });
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
      // Refetch the day so the editor converges on the server's stored
      // state — the same-date merge result included ("the web shows the
      // result").
      void queryClient.invalidateQueries({ queryKey: ['day', profileId] });
    },
  });
}
