import { Link, useNavigate } from 'react-router';
import { useState, type FormEvent } from 'react';

import { useT } from '../i18n/t';
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
  const signUp = useSignUpMutation();
  const sendOtp = useSendOtp();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [emailError, setEmailError] = useState<string | null>(null);
  const [passwordError, setPasswordError] = useState<string | null>(null);
  const [confirmationSent, setConfirmationSent] = useState(false);

  const mutationError = (signUp.error ?? sendOtp.error) as AuthError | null;

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
    signUp.mutate(
      { email: email.trim(), password },
      { onSuccess: (result) => setConfirmationSent(result === 'confirmation_required') },
    );
  };

  const sendCreateLink = () => {
    if (email.trim() === '' || !EMAIL_SHAPE.test(email.trim())) {
      setEmailError(t('accountSignInEmailRequired'));
      return;
    }
    setEmailError(null);
    sendOtp.mutate({ email: email.trim(), createUser: true });
    navigate(`/sign-in/code?email=${encodeURIComponent(email.trim())}&mode=signup`);
  };

  return (
    <main className="page">
      <h1 className="headline">{t('accountSignInTitleCreate')}</h1>
      {confirmationSent ? (
        <div className="auth-info">
          <p className="body">{t('accountSignInConfirmEmailInfo')}</p>
          <div className="auth-links">
            <Link to={`/sign-in/code?email=${encodeURIComponent(email.trim())}&mode=signup`}>
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
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
            <p className="body">
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
          {mutationError !== null ? (
            <p className="auth-error">{t(authCopyFor(mutationError).id)}</p>
          ) : null}
        </form>
      )}
      <div className="auth-links">
        <Link to="/sign-in">{t('accountSignInToggleHaveAccount')}</Link>
        <Link to="/">{t('calendarTodayTooltip')}</Link>
      </div>
    </main>
  );
}
