import { useQuery } from '@tanstack/react-query';

import { webAuth } from './auth';

/**
 * The session query (issue #1250): the web app's signed-in state, held in
 * TanStack Query's in-memory cache like every other read. The queryFn runs
 * the auth client's renewal - on a fresh page load that is a GET
 * /auth/session, which is how a reload restores the session from the
 * HttpOnly refresh cookie without any user action.
 *
 * Lives in its own module (issue #1826) so the synced-data gate
 * (`queries.ts`) and the day view (`day/use-day.ts`) can read it without
 * importing `authQueries.ts`, which imports them back for the identity
 * reset.
 */
export const AUTH_SESSION_QUERY_KEY = ['auth', 'session'] as const;

export interface AuthStatus {
  signedIn: boolean;
  email: string | null;
  /**
   * The account the in-memory session belongs to (issue #1281) - the
   * identity the synced-data cache must be dropped when it changes.
   */
  userId: string | null;
}

export function useAuthSession(options: { enabled?: boolean } = {}) {
  return useQuery<AuthStatus>({
    queryKey: AUTH_SESSION_QUERY_KEY,
    queryFn: async () => {
      const token = await webAuth.getToken();
      const user = webAuth.getUser();
      return {
        signedIn: token !== null,
        email: user?.email ?? null,
        userId: user?.id ?? null,
      };
    },
    // Every existing caller reads the session unconditionally (default
    // true). The synced-data gate passes `enabled: configured` so an
    // unconfigured build (every PR build) makes no /auth/session request.
    enabled: options.enabled ?? true,
  });
}
