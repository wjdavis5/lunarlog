import { useEffect } from 'react';
import { Link } from 'react-router';

import { useT } from '../i18n/t';
import { useProfiles } from '../lib/queries';

function longMonth(now: Date): string {
  return new Intl.DateTimeFormat('en', { month: 'long' }).format(now);
}

/**
 * The scaffold's one real screen: the catalogue-formatted month header and
 * the empty-state card, plus the profiles the operator can see once the
 * build is configured (idle otherwise) — each linking to its sharing (#1255)
 * surfaces.
 */
export function TodayPage() {
  const t = useT();
  const now = new Date();
  const profiles = useProfiles();

  useEffect(() => {
    document.title = t('gateLockScreenAppTitle');
  }, [t]);

  return (
    <main className="page">
      <h1 className="display">
        {t('calendarMonthYearLabel', { month: longMonth(now), year: now.getFullYear() })}
      </h1>
      <section className="card">
        <p className="card-title">{t('calendarNoEntriesTitle')}</p>
        <p className="card-body">{t('calendarNoEntriesBody')}</p>
      </section>
      {profiles.data !== undefined && profiles.data.length > 0 ? (
        <ul className="profile-list">
          {profiles.data.map((profile) => (
            <li key={profile.id}>
              {profile.display_name}
              <div className="actions">
                <Link
                  className="nav-link"
                  to={`/profile/${profile.id}/guardians`}
                  aria-label={t('profilePickerMenuGuardians')}
                >
                  {t('profilePickerMenuGuardians')}
                </Link>
                <Link
                  className="nav-link"
                  to={`/profile/${profile.id}/notes`}
                  aria-label={t('guardianNotesSectionTitle')}
                >
                  {t('guardianNotesSectionTitle')}
                </Link>
              </div>
            </li>
          ))}
        </ul>
      ) : null}
    </main>
  );
}
