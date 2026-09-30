import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { webAuth, type OAuthProvider, type SignOutScope } from './auth';

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
}

export function useAuthSession() {
  return useQuery<AuthStatus>({
    queryKey: AUTH_SESSION_QUERY_KEY,
    queryFn: async () => {
      const token = await webAuth.getToken();
      return { signedIn: token !== null, email: webAuth.getUser()?.email ?? null };
    },
  });
}

function useInvalidateSession(): () => void {
  const queryClient = useQueryClient();
  return () => {
    void queryClient.invalidateQueries({ queryKey: AUTH_SESSION_QUERY_KEY });
  };
}

/** A single /auth/* round trip, with the session query refreshed after. */
function useAuthMutation<TVariables>(action: (variables: TVariables) => Promise<void>) {
  const invalidate = useInvalidateSession();
  return useMutation<void, Error, TVariables>({
    mutationFn: action,
    onSuccess: invalidate,
  });
}

/** Password sign-in. */
export function useSignIn() {
  return useAuthMutation((variables: { email: string; password: string }) =>
    webAuth.signInWithPassword(variables.email, variables.password),
  );
}

/** Account creation (returns 'confirmation_required' on the email-confirm posture). */
export function useSignUpMutation() {
  const invalidate = useInvalidateSession();
  return useMutation<
    'signed_in' | 'confirmation_required',
    Error,
    { email: string; password: string }
  >({
    mutationFn: (variables) => webAuth.signUp(variables.email, variables.password),
    onSuccess: invalidate,
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
  return useAuthMutation(
    (variables: { email: string; token: string; type: 'email' | 'recovery' }) =>
      webAuth.verifyOtp(variables.email, variables.token, variables.type),
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

/** Sign-out (this device or everywhere). */
export function useSignOut() {
  return useAuthMutation((scope: SignOutScope) => webAuth.signOut(scope));
}

/**
 * OAuth start is a navigation, not a fetch (the browser must land on the
 * provider); exposed for the tests' seam symmetry.
 */
export function startOAuth(provider: OAuthProvider): void {
  webAuth.startOAuth(provider);
}
