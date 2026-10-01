import { Link, useSearchParams } from 'react-router';
import { useEffect, useRef, useState } from 'react';

import { useT } from '../i18n/t';
import type { MessageId } from '../i18n/message-ids';
import { AuthError, webAuth } from '../lib/auth';
import { authCopyFor } from '../lib/authCopy';
import { AUTH_SESSION_QUERY_KEY } from '../lib/authQueries';
import { useQueryClient } from '@tanstack/react-query';

type CallbackState =
  | { kind: 'pending' }
  | { kind: 'signedIn'; recovery: boolean }
  // The mapped copy and its FormatJS values (issue #1295): the render is
  // a state away from the failure, so the values ride along with the id —
  // otherwise the weak-password copy would show its raw `{minLength}`.
  | { kind: 'failed'; copyId: MessageId; values?: Record<string, string | number> }
  | { kind: 'idle' };

/**
 * The PKCE callback page (issue #1250): the page the emailed/OAuth links
 * land on, at this origin's /auth/callback. The Worker holds the PKCE
 * verifier in its HttpOnly cookie, so the page exchanges the landed `code`
 * through POST /auth/callback and renders the outcome:
 *
 *   - signed in (a recovery link additionally points at the new-password
 *     screen);
 *   - `verifier_missing` — the issue's dedicated different-browser copy:
 *     open the link in the browser where you asked for it, or use the
 *     8-digit code;
 *   - any other failure — the mapped auth-failure copy.
 *
 * In an environment without the Worker (vite preview in e2e) the exchange
 * fails generically and the same mapped-copy path renders; the heading is
 * the catalogue's sign-in title in every state, so a deep link always lands
 * on a real screen.
 */
export function AuthCallbackPage() {
  const t = useT();
  const [searchParameters] = useSearchParams();
  const queryClient = useQueryClient();
  const [state, setState] = useState<CallbackState>({ kind: 'pending' });
  const startedRef = useRef(false);

  const code = searchParameters.get('code');
  const providerError = searchParameters.get('error');
  const recovery = searchParameters.get('type') === 'recovery';

  useEffect(() => {
    if (startedRef.current) return; // StrictMode/loop guard: one exchange per landing.
    if (code === null && providerError === null) {
      setState({ kind: 'idle' });
      return;
    }
    startedRef.current = true;
    if (code === null) {
      // The provider bounced back with its own error: the same
      // expired-link copy the app renders for a rejected link.
      setState({ kind: 'failed', copyId: 'authFailureExpiredLink' });
      return;
    }
    webAuth
      .exchangeCallback(code)
      .then(() => {
        void queryClient.invalidateQueries({ queryKey: AUTH_SESSION_QUERY_KEY });
        setState({ kind: 'signedIn', recovery });
      })
      .catch((error: unknown) => {
        const copy =
          error instanceof AuthError
            ? authCopyFor(error)
            : { id: 'commonSomethingWentWrong' as const };
        setState({ kind: 'failed', copyId: copy.id, values: copy.values });
      });
  }, [code, providerError, recovery, queryClient]);

  return (
    <main className="page">
      <h1 className="headline">{t('accountSignInTitle')}</h1>
      {state.kind === 'signedIn' ? (
        <>
          <p className="body">
            {t('accountSectionSignedInAs', { email: webAuth.getUser()?.email ?? '' })}
          </p>
          {state.recovery ? (
            <div className="auth-info">
              <p className="body">{t('accountPasswordRecoveryIntro')}</p>
              <div className="auth-links">
                <Link to="/reset-password">{t('accountPasswordRecoverySave')}</Link>
              </div>
            </div>
          ) : null}
          <div className="auth-links">
            <Link to="/">{t('webAuthContinueAction')}</Link>
          </div>
        </>
      ) : null}
      {state.kind === 'failed' ? (
        <div className="auth-info">
          <p className="body">{t(state.copyId, state.values)}</p>
          <div className="auth-links">
            <Link to="/sign-in">{t('accountSignInTitle')}</Link>
          </div>
        </div>
      ) : null}
      {state.kind === 'idle' ? <p className="body">{t('accountSignInMagicLinkInfo')}</p> : null}
    </main>
  );
}
