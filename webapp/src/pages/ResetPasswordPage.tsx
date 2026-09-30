import { Link } from 'react-router';
import { useState, type FormEvent } from 'react';

import { useT } from '../i18n/t';
import { AuthError } from '../lib/auth';
import { authCopyFor, kMinPasswordLength } from '../lib/authCopy';
import { useUpdatePassword } from '../lib/authQueries';

/**
 * The new-password screen (issue #1250): the endpoint of the recovery
 * flow, reached from the reset link's callback page or from the recovery
 * code path. Saves the new password against the in-memory access token the
 * recovery session established.
 */
export function ResetPasswordPage() {
  const t = useT();
  const update = useUpdatePassword();

  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [formError, setFormError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const mutationError = update.error as AuthError | null;

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (password.length < kMinPasswordLength) {
      setFormError(
        t('accountPasswordRecoveryLengthError', { length: kMinPasswordLength }),
      );
      return;
    }
    if (password !== confirm) {
      setFormError(t('accountPasswordRecoveryMismatchError'));
      return;
    }
    setFormError(null);
    update.mutate(password, { onSuccess: () => setSaved(true) });
  };

  return (
    <main className="page">
      <h1 className="headline">{t('accountPasswordRecoveryTitle')}</h1>
      <p className="body">{t('accountPasswordRecoveryIntro')}</p>
      {saved ? (
        <div className="auth-info">
          <p className="body">{t('accountPasswordRecoveryTitle')}</p>
          <div className="auth-links">
            <Link to="/">{t('webAuthContinueAction')}</Link>
          </div>
        </div>
      ) : (
        <form className="auth-form" onSubmit={submit} noValidate>
          <div className="auth-field">
            <label htmlFor="new-password">{t('accountPasswordRecoveryNewLabel')}</label>
            <input
              id="new-password"
              type="password"
              autoComplete="new-password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
            <p className="body">
              {t('accountPasswordRecoveryLengthHelper', { length: kMinPasswordLength })}
            </p>
          </div>
          <div className="auth-field">
            <label htmlFor="confirm-password">
              {t('accountPasswordRecoveryConfirmLabel')}
            </label>
            <input
              id="confirm-password"
              type="password"
              autoComplete="new-password"
              value={confirm}
              onChange={(event) => setConfirm(event.target.value)}
            />
          </div>
          <div className="auth-actions">
            <button
              type="submit"
              className="auth-button"
              disabled={password === '' || confirm === '' || update.isPending}
            >
              {t('accountPasswordRecoverySave')}
            </button>
          </div>
          {formError !== null ? <p className="auth-error">{formError}</p> : null}
          {mutationError !== null ? (
            <p className="auth-error">{t(authCopyFor(mutationError).id)}</p>
          ) : null}
        </form>
      )}
    </main>
  );
}
