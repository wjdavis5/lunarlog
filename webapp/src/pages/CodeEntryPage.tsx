import { Link, useNavigate, useSearchParams } from 'react-router';
import { useState, type FormEvent } from 'react';

import { useT } from '../i18n/t';
import { safeNextPath, withNext } from '../lib/next-path';
import { AuthError } from '../lib/auth';
import { authCopyFor } from '../lib/authCopy';
import { useVerifyOtp } from '../lib/authQueries';

/**
 * The emailed-code entry screen (issue #1250): the 8-digit code the
 * sign-in, sign-up, or recovery email carries, verified against the same
 * address it was sent to. The mode query parameter picks the verify type:
 * sign-in and sign-up codes verify as `email` (GoTrue's merged type);
 * recovery codes as `recovery`, and land on the new-password screen.
 */
export function CodeEntryPage() {
  const t = useT();
  const navigate = useNavigate();
  const [searchParameters] = useSearchParams();
  const email = searchParameters.get('email') ?? '';
  // The return path carried over from the sign-in or sign-up page; validated.
  const next = safeNextPath(searchParameters.get('next'));
  const recovery = searchParameters.get('mode') === 'recovery';
  const verify = useVerifyOtp();

  const [code, setCode] = useState('');
  const [codeError, setCodeError] = useState<string | null>(null);
  const [resetDone, setResetDone] = useState(false);

  const mutationError = verify.error as AuthError | null;
  const mutationCopy = mutationError === null ? null : authCopyFor(mutationError);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (email === '') {
      setCodeError(t('accountSignInEmailRequired'));
      return;
    }
    if (code.trim() === '') {
      setCodeError(t('accountSignInEmailRequired'));
      return;
    }
    setCodeError(null);
    verify.mutate(
      { email, token: code.trim(), type: recovery ? 'recovery' : 'email' },
      {
        onSuccess: () => {
          if (recovery) {
            setResetDone(true);
          } else {
            navigate(next ?? '/');
          }
        },
      },
    );
  };

  return (
    <main className="page page-auth">
      <h1 className="display">{t('accountSignInTitle')}</h1>
      <p className="body">{t('accountSignInMagicLinkInfo')}</p>
      {resetDone ? (
        <div className="auth-info">
          <p className="body">{t('accountPasswordRecoveryIntro')}</p>
          <div className="auth-links">
            <Link to="/reset-password">{t('accountPasswordRecoverySave')}</Link>
          </div>
        </div>
      ) : (
        <form className="auth-form" onSubmit={submit} noValidate>
          <div className="auth-field">
            <label htmlFor="code-input">{t('accountSignInCodeLabel')}</label>
            <input
              id="code-input"
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              placeholder={t('accountSignInCodeHint')}
              value={code}
              onChange={(event) => setCode(event.target.value)}
            />
          </div>
          <div className="auth-actions">
            <button
              type="submit"
              className="auth-button"
              disabled={code.trim() === '' || verify.isPending}
            >
              {t('accountSignInVerifyCodeAction')}
            </button>
          </div>
          {codeError !== null ? <p className="auth-error">{codeError}</p> : null}
          {mutationCopy !== null ? (
            <p className="auth-error">{t(mutationCopy.id, mutationCopy.values)}</p>
          ) : null}
        </form>
      )}
      <div className="auth-links">
        <Link to={withNext('/sign-in', next)}>{t('accountSignInTitle')}</Link>
      </div>
    </main>
  );
}
