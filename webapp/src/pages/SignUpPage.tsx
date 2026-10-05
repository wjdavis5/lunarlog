import { Link, useNavigate, useSearchParams } from 'react-router';
import { useState, type FormEvent } from 'react';

import { useT } from '../i18n/t';
import { safeNextPath, withNext } from '../lib/next-path';
import { AuthError } from '../lib/auth';
import { authCopyFor, kMinPasswordLength } from '../lib/authCopy';
import { useSendOtp, useSignUpMutation } from '../lib/authQueries';

const EMAIL_SHAPE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * The web sign-up screen (issue #1250): email + password account creation.
 * With the project's email-confirmation posture the response carries no
 * session — the screen shows the confirmation copy and points at the code
 * entry screen, where the emailed 8-digit code completes sign-in. The
 * password length mirrors the server's rule (12, letters/digits/symbols
 * enforced server-side; AGENTS.md's dashboard prerequisites).
 */
export function SignUpPage() {
  const t = useT();
  const navigate = useNavigate();
  const [searchParameters] = useSearchParams();
  // The return path a page handed over (see SignInPage); validated.
  const next = safeNextPath(searchParameters.get('next'));
  const signUp = useSignUpMutation();
  const sendOtp = useSendOtp();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [emailError, setEmailError] = useState<string | null>(null);
  const [passwordError, setPasswordError] = useState<string | null>(null);
  const [confirmationSent, setConfirmationSent] = useState(false);

  const mutationError = (signUp.error ?? sendOtp.error) as AuthError | null;
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
    if (password.length < kMinPasswordLength) {
      setPasswordError(t('accountSignInUseAtLeast', { length: kMinPasswordLength }));
      return;
    }
    setEmailError(null);
    setPasswordError(null);
    // A failed send belongs to the send, not to the sign-up attempt that
    // preceded it (issue #1345): the stale send error must not mask this
    // attempt's own result.
    sendOtp.reset();
    signUp.mutate(
      { email: email.trim(), password },
      {
        onSuccess: (result) => {
          setConfirmationSent(result === 'confirmation_required');
          // An account that needs no confirmation is signed in already:
          // carry on to where the visitor was headed.
          if (result === 'signed_in' && next !== null) navigate(next, { replace: true });
        },
      },
    );
  };

  const sendCreateLink = () => {
    if (email.trim() === '' || !EMAIL_SHAPE.test(email.trim())) {
      setEmailError(t('accountSignInEmailRequired'));
      return;
    }
    setEmailError(null);
    // A failed sign-up belongs to the sign-up attempt, not to the send that
    // follows it (issue #1345): `signUp.error` sits ahead of
    // `sendOtp.error` in the `??`, so the stale sign-up failure would
    // permanently mask this send's own error without the reset.
    signUp.reset();
    // The navigation waits for the send to resolve (issue #1294): a
    // rejected send — rate limit, otp_disabled — must render the mapped
    // copy on this page, not strand the user on the code screen waiting
    // for an email that never comes.
    sendOtp.mutate(
      { email: email.trim(), createUser: true },
      {
        onSuccess: () =>
          navigate(
            withNext(
              `/sign-in/code?email=${encodeURIComponent(email.trim())}&mode=signup`,
              next,
            ),
          ),
      },
    );
  };

  return (
    <main className="page page-auth">
      <h1 className="display">{t('accountSignInTitleCreate')}</h1>
      {confirmationSent ? (
        <div className="auth-info">
          <p className="body">{t('accountSignInConfirmEmailInfo')}</p>
          <div className="auth-links">
            <Link
              to={withNext(
                `/sign-in/code?email=${encodeURIComponent(email.trim())}&mode=signup`,
                next,
              )}
            >
              {t('accountSignInVerifyCodeAction')}
            </Link>
          </div>
        </div>
      ) : (
        <form className="auth-form" onSubmit={submit} noValidate>
          <div className="auth-field">
            <label htmlFor="sign-up-email">{t('accountSignInEmailLabel')}</label>
            <input
              id="sign-up-email"
              type="email"
              autoComplete="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
            />
            {emailError !== null ? <p className="auth-error">{emailError}</p> : null}
          </div>
          <div className="auth-field">
            <label htmlFor="sign-up-password">{t('accountSignInPasswordLabel')}</label>
            <input
              id="sign-up-password"
              type="password"
              autoComplete="new-password"
              aria-describedby="sign-up-password-hint"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
            <p className="auth-hint" id="sign-up-password-hint">
              {t('accountSignInPasswordLengthHelper', { length: kMinPasswordLength })}
            </p>
            {passwordError !== null ? <p className="auth-error">{passwordError}</p> : null}
          </div>
          <div className="auth-actions">
            <button
              type="submit"
              className="auth-button"
              disabled={email.trim() === '' || password === '' || signUp.isPending}
            >
              {t('accountSignInCreateAccountAction')}
            </button>
            <button
              type="button"
              className="auth-button auth-button-secondary"
              disabled={email.trim() === '' || sendOtp.isPending}
              onClick={sendCreateLink}
            >
              {t('accountSignInMagicLinkCreate')}
            </button>
          </div>
          {mutationCopy !== null ? (
            <p className="auth-error">{t(mutationCopy.id, mutationCopy.values)}</p>
          ) : null}
        </form>
      )}
      <div className="auth-links">
        <Link to={withNext('/sign-in', next)}>{t('accountSignInToggleHaveAccount')}</Link>
      </div>
    </main>
  );
}
