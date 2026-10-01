import { Link, useNavigate } from 'react-router';
import { useState, type FormEvent } from 'react';

import { useT } from '../i18n/t';
import { AuthError } from '../lib/auth';
import { authCopyFor } from '../lib/authCopy';
import {
  startOAuth,
  useAuthSession,
  useSendOtp,
  useSignOut,
  useSignIn,
} from '../lib/authQueries';

const EMAIL_SHAPE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * The web sign-in screen (issue #1250): password sign-in, the emailed
 * link/code sender, the Google and Apple PKCE starts, and — when a session
 * is already held — the signed-in state with sign-out on this device or
 * everywhere. Every string comes from the catalogue.
 */
export function SignInPage() {
  const t = useT();
  const navigate = useNavigate();
  const session = useAuthSession();
  const signIn = useSignIn();
  const sendOtp = useSendOtp();
  const signOut = useSignOut();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [emailError, setEmailError] = useState<string | null>(null);

  const mutationError = (signIn.error ?? sendOtp.error) as AuthError | null;
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
    signIn.mutate({ email: email.trim(), password });
  };

  const sendLink = () => {
    if (email.trim() === '' || !EMAIL_SHAPE.test(email.trim())) {
      setEmailError(t('accountSignInEmailRequired'));
      return;
    }
    setEmailError(null);
    // The navigation waits for the send to resolve (issue #1294): a
    // rejected send — rate limit, otp_disabled — must render the mapped
    // copy on this page, not strand the user on the code screen waiting
    // for an email that never comes.
    sendOtp.mutate(
      { email: email.trim(), createUser: false },
      {
        onSuccess: () => navigate(`/sign-in/code?email=${encodeURIComponent(email.trim())}`),
      },
    );
  };

  if (session.data?.signedIn === true) {
    return (
      <main className="page">
        <h1 className="headline">{t('accountSignInTitle')}</h1>
        <p className="body">
          {t('accountSectionSignedInAs', { email: session.data.email ?? '' })}
        </p>
        <div className="auth-actions">
          <button
            type="button"
            className="auth-button auth-button-secondary"
            disabled={signOut.isPending}
            onClick={() => signOut.mutate('local')}
          >
            {t('webAuthSignOutAction')}
          </button>
          <button
            type="button"
            className="auth-button auth-button-secondary"
            disabled={signOut.isPending}
            onClick={() => signOut.mutate('global')}
          >
            {t('webAuthSignOutEverywhereAction')}
          </button>
        </div>
        {signOut.error !== null ? (
          <p className="auth-error">{t('commonSomethingWentWrong')}</p>
        ) : null}
        <div className="auth-links">
          <Link to="/">{t('webAuthContinueAction')}</Link>
        </div>
      </main>
    );
  }

  return (
    <main className="page">
      <h1 className="headline">{t('accountSignInTitle')}</h1>
      <form className="auth-form" onSubmit={submit} noValidate>
        <div className="auth-field">
          <label htmlFor="sign-in-email">{t('accountSignInEmailLabel')}</label>
          <input
            id="sign-in-email"
            type="email"
            autoComplete="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
          />
          {emailError !== null ? <p className="auth-error">{emailError}</p> : null}
        </div>
        <div className="auth-field">
          <label htmlFor="sign-in-password">{t('accountSignInPasswordLabel')}</label>
          <input
            id="sign-in-password"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
          />
        </div>
        <div className="auth-actions">
          <button
            type="submit"
            className="auth-button"
            disabled={email.trim() === '' || password === '' || signIn.isPending}
          >
            {t('accountSignInAction')}
          </button>
          <button
            type="button"
            className="auth-button auth-button-secondary"
            disabled={email.trim() === '' || sendOtp.isPending}
            onClick={sendLink}
          >
            {t('accountSignInMagicLinkSignIn')}
          </button>
        </div>
        {mutationCopy !== null ? (
          <p className="auth-error">{t(mutationCopy.id, mutationCopy.values)}</p>
        ) : null}
      </form>
      <div className="auth-actions" style={{ marginTop: 'var(--ll-space-3)' }}>
        <button
          type="button"
          className="auth-button auth-button-secondary"
          onClick={() => startOAuth('google')}
        >
          {t('accountGoogleButtonLabel')}
        </button>
        <button
          type="button"
          className="auth-button auth-button-secondary"
          onClick={() => startOAuth('apple')}
        >
          {t('webAuthAppleButtonLabel')}
        </button>
      </div>
      <div className="auth-links">
        <Link to="/forgot-password">{t('accountSignInForgotPasswordAction')}</Link>
        <Link to="/sign-up">{t('accountSignInToggleCreateInstead')}</Link>
        <Link to="/">{t('calendarTodayTooltip')}</Link>
      </div>
    </main>
  );
}
