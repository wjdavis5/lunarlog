import { Link } from 'react-router';

import { useT } from '../i18n/t';

/**
 * What a signed-out visitor sees at `/` and `/profiles`.
 *
 * The first thing anyone sees of the web client, so it says what this is,
 * offers the two ways in, and states the one thing that makes a browser
 * safe for a household's records: nothing is kept here but the sign-in
 * (PRIVACY.md section 6). All copy comes from the catalogue.
 */
export function SignedOutHome() {
  const t = useT();
  return (
    <main className="page welcome">
      <h1 className="welcome-title">{t('webWelcomeTitle')}</h1>
      <p className="welcome-lead">{t('webHomeNeedsSignIn')}</p>
      <div className="welcome-actions">
        <Link className="btn btn-primary" to="/sign-in">
          {t('accountSectionSignIn')}
        </Link>
        <Link className="nav-link" to="/sign-up">
          {t('accountSignInToggleCreateInstead')}
        </Link>
      </div>
      <p className="welcome-note">{t('webWelcomeStorageNote')}</p>
    </main>
  );
}
