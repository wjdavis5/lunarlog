import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useRef } from 'react';

import { webAuth, type OAuthProvider, type SignOutScope } from './auth';
import { resetWebData } from './queries';

/**
 * The session query (issue #1250): the web app's signed-in state, held in
 * TanStack Query's in-memory cache like every other read. The queryFn runs
 * the auth client's renewal — on a fresh page load that is a GET
 * /auth/session, which is how a reload restores the session from the
 * HttpOnly refresh cookie without any user action.
 */
export const AUTH_SESSION_QUERY_KEY = ['auth', 'session'] as const;

export interface AuthStatus {
  signedIn: boolean;
  email: string | null;
  /**
   * The account the in-memory session belongs to (issue #1281) — the
   * identity the synced-data cache must be dropped when it changes.
   */
  userId: string | null;
}

export function useAuthSession() {
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
  });
}

function useInvalidateSession(): () => void {
  const queryClient = useQueryClient();
  return () => {
    void queryClient.invalidateQueries({ queryKey: AUTH_SESSION_QUERY_KEY });
  };
}

/** The identity-boundary reset (issue #1281): the synced-data snapshot, the
 * pull cursors, and every cached query — the whole session's page memory. */
function useResetWebData(): () => void {
  const queryClient = useQueryClient();
  return () => resetWebData(queryClient);
}

/**
 * A single /auth/* round trip, with the session query refreshed after.
 * `afterSuccess` runs before the refresh on the paths that adopt an
 * identity (issue #1281): they drop the synced-data cache first, so a
 * session that replaces another never merges its snapshot or pulls from
 * its cursors.
 */
function useAuthMutation<TResult, TVariables>(
  action: (variables: TVariables) => Promise<TResult>,
  afterSuccess?: (result: TResult) => void,
) {
  const invalidate = useInvalidateSession();
  return useMutation<TResult, Error, TVariables>({
    mutationFn: action,
    onSuccess: (result) => {
      afterSuccess?.(result);
      invalidate();
    },
  });
}

/** Password sign-in. */
export function useSignIn() {
  const resetWebData = useResetWebData();
  return useAuthMutation(
    (variables: { email: string; password: string }) =>
      webAuth.signInWithPassword(variables.email, variables.password),
    resetWebData,
  );
}

/** Account creation (returns 'confirmation_required' on the email-confirm posture). */
export function useSignUpMutation() {
  const invalidate = useInvalidateSession();
  const resetWebData = useResetWebData();
  return useMutation<
    'signed_in' | 'confirmation_required',
    Error,
    { email: string; password: string }
  >({
    mutationFn: (variables) => webAuth.signUp(variables.email, variables.password),
    onSuccess: (result) => {
      // Only a session adoption is an identity boundary; a pending email
      // confirmation signs nobody in (issue #1281).
      if (result === 'signed_in') {
        resetWebData();
      }
      invalidate();
    },
  });
}

/** Emailed-code / magic-link send. */
export function useSendOtp() {
  return useAuthMutation((variables: { email: string; createUser: boolean }) =>
    webAuth.sendOtp(variables.email, variables.createUser),
  );
}

/** Emailed-code verify. */
export function useVerifyOtp() {
  const resetWebData = useResetWebData();
  return useAuthMutation(
    (variables: { email: string; token: string; type: 'email' | 'recovery' }) =>
      webAuth.verifyOtp(variables.email, variables.token, variables.type),
    resetWebData,
  );
}

/** Password-reset email send. */
export function useSendPasswordReset() {
  return useAuthMutation((email: string) => webAuth.sendPasswordReset(email));
}

/** New-password save. */
export function useUpdatePassword() {
  return useAuthMutation((password: string) => webAuth.updatePassword(password));
}

/**
 * Sign-out (this device or everywhere). The reset runs in a `finally`
 * (issue #1281): once the operator asked out, the synced-data snapshot, the
 * pull cursors, and every cached query go — even when the POST itself
 * fails, so no account's health data stays on screen to merge into the
 * next sign-in.
 */
export function useSignOut() {
  const invalidate = useInvalidateSession();
  const resetWebData = useResetWebData();
  return useMutation<void, Error, SignOutScope>({
    mutationFn: async (scope) => {
      try {
        await webAuth.signOut(scope);
      } finally {
        resetWebData();
      }
    },
    onSuccess: invalidate,
  });
}

/**
 * The belt behind the per-mutation resets (issue #1281): whenever the
 * page's session resolves to a different account than the one the
 * synced-data cache was built under, drop the cache. This catches identity
 * changes that bypass the auth mutations — a token renewal in a tab whose
 * refresh cookie another tab's sign-in replaced. Mount once, in the shell.
 */
export function useResetWebDataOnIdentityChange(): void {
  const queryClient = useQueryClient();
  const session = useAuthSession();
  const userId = session.data?.userId ?? null;
  const previousUserId = useRef<string | null>(null);
  useEffect(() => {
    if (previousUserId.current !== null && userId !== previousUserId.current) {
      resetWebData(queryClient);
    }
    previousUserId.current = userId;
  }, [userId, queryClient]);
}

/**
 * OAuth start is a navigation, not a fetch (the browser must land on the
 * provider); exposed for the tests' seam symmetry.
 */
export function startOAuth(provider: OAuthProvider): void {
  webAuth.startOAuth(provider);
}
