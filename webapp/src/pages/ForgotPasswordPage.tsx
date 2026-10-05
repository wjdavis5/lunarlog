import { Link } from 'react-router';
import { useState, type FormEvent } from 'react';

import { useT } from '../i18n/t';
import { AuthError } from '../lib/auth';
import { authCopyFor } from '../lib/authCopy';
import { useSendPasswordReset } from '../lib/authQueries';

const EMAIL_SHAPE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * The forgot-password screen (issue #1250): requests the reset email. Its
 * link lands on /auth/callback; the emailed code can instead be entered on
 * the code screen with mode=recovery, which ends at the new-password
 * screen. The request's response is the same whatever the address is
 * (GoTrue's email-enumeration posture) — the copy already reads that way.
 */
export function ForgotPasswordPage() {
  const t = useT();
  const sendReset = useSendPasswordReset();

  const [email, setEmail] = useState('');
  const [emailError, setEmailError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);

  const mutationError = sendReset.error as AuthError | null;
  const mutationCopy = mutationError === null ? null : authCopyFor(mutationError);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (email.trim() === '') {
      setEmailError(t('accountSignInEmailRequired'));
      return;
    }
    if (!EMAIL_SHAPE.test(email.trim())) {
      setEmailError(t('accountSignInEmailInvalid'));
      return;
    }
    setEmailError(null);
    sendReset.mutate(email.trim(), { onSuccess: () => setSent(true) });
  };

  return (
    <main className="page page-auth">
      <h1 className="display">{t('accountSignInForgotPasswordAction')}</h1>
      {sent ? (
        <div className="auth-info">
          <p className="body">{t('webAuthResetInfo')}</p>
          <div className="auth-links">
            <Link to={`/sign-in/code?email=${encodeURIComponent(email.trim())}&mode=recovery`}>
              {t('accountSignInVerifyCodeAction')}
            </Link>
          </div>
        </div>
      ) : (
        <form className="auth-form" onSubmit={submit} noValidate>
          <div className="auth-field">
            <label htmlFor="forgot-email">{t('accountSignInEmailLabel')}</label>
            <input
              id="forgot-email"
              type="email"
              autoComplete="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
            />
            {emailError !== null ? <p className="auth-error">{emailError}</p> : null}
          </div>
          <div className="auth-actions">
            <button
              type="submit"
              className="auth-button"
              disabled={email.trim() === '' || sendReset.isPending}
            >
              {t('webAuthSendResetAction')}
            </button>
          </div>
          {mutationCopy !== null ? (
            <p className="auth-error">{t(mutationCopy.id, mutationCopy.values)}</p>
          ) : null}
        </form>
      )}
      <div className="auth-links">
        <Link to="/sign-in">{t('accountSignInTitle')}</Link>
      </div>
    </main>
  );
}
