import { Link } from 'react-router';

import { useT } from '../i18n/t';

/**
 * First-run orientation (issue #1795): what lunarlog is, who it is for, and
 * where the data lives, shown by the home page once per browser session to a
 * signed-in account with no profiles. Create a profile goes to the profile
 * picker, where a profile is created; Continue dismisses to the compact
 * empty state the page has always carried.
 */
export function FirstRunCard(props: { onContinue: () => void }) {
  const t = useT();
  return (
    <section className="card">
      <p className="card-title">{t('webFirstRunTitle')}</p>
      <p className="card-body">{t('webFirstRunBody')}</p>
      <p className="card-body">{t('webFirstRunDataLine')}</p>
      <p className="card-body">
        <Link className="btn btn-primary" to="/profiles">
          {t('webFirstRunCreateAction')}
        </Link>{' '}
        <button className="btn" type="button" onClick={props.onContinue}>
          {t('webFirstRunContinueAction')}
        </button>
      </p>
    </section>
  );
}
